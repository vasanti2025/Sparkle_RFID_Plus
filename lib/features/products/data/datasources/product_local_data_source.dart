import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import '../../../../core/constants/app_strings.dart';
import '../../domain/entities/product_sync_progress.dart';
import '../../domain/entities/stored_record.dart';
import '../product_csv.dart';
import '../sync_json_stream.dart';

abstract class ProductLocalDataSource {
  Future<Directory> syncDirectory();

  Stream<ProductSyncProgress> storeDownloaded(Directory directory);

  Future<List<StoredRecord>> search({
    String kind = StoredRecord.kindProduct,
    String query = '',
    int limit = 50,
    int offset = 0,
  });

  Future<int> count({String kind = StoredRecord.kindProduct});

  /// Writes synced products as CSV, one page at a time, so a large catalogue
  /// is not held in memory.
  Future<int> writeProductCsv(String path, {void Function(int written)? onProgress});

  Future<Map<String, String>> rfidMap();

  Future<int> upsertProducts(List<Map<String, dynamic>> items, {void Function(int written)? onProgress});
}

class ProductLocalDataSourceImpl implements ProductLocalDataSource {
  ProductLocalDataSourceImpl();

  Database? _database;

  @override
  Future<Directory> syncDirectory() async {
    final root = await getApplicationDocumentsDirectory();
    final directory = Directory('${root.path}/product_sync');
    if (!await directory.exists()) {
      await directory.create(recursive: true);
    }
    return directory;
  }

  @override
  Stream<ProductSyncProgress> storeDownloaded(Directory directory) {
    final controller = StreamController<ProductSyncProgress>();
    unawaited(_store(directory, controller));
    return controller.stream;
  }

  Future<void> _store(
    Directory directory,
    StreamController<ProductSyncProgress> controller,
  ) async {
    try {
      final database = await _open();
      final rfidFile = File('${directory.path}/rfid.json');
      if (await rfidFile.exists()) {
        await _replaceFile(
          database: database,
          file: rfidFile,
          kind: StoredRecord.kindRfid,
          controller: controller,
          message: AppStrings.savingRfid,
          start: 0.8,
          end: 0.9,
        );
        await rfidFile.delete();
      }
      final productFile = File('${directory.path}/labelled_stocks.json');
      if (!await productFile.exists()) {
        throw const FileSystemException('Product file missing');
      }
      await _replaceFile(
        database: database,
        file: productFile,
        kind: StoredRecord.kindProduct,
        controller: controller,
        message: AppStrings.savingProducts,
        start: 0.9,
        end: 1,
      );
      await productFile.delete();
      if (!controller.isClosed) {
        controller.add(
          const ProductSyncProgress(
            message: AppStrings.syncComplete,
            fraction: 1,
            completed: true,
          ),
        );
      }
    } catch (_) {
      if (!controller.isClosed) {
        controller.add(
          const ProductSyncProgress(
            message: AppStrings.syncFailed,
            fraction: 0,
            failed: true,
          ),
        );
      }
    } finally {
      await controller.close();
    }
  }

  Future<void> _replaceFile({
    required Database database,
    required File file,
    required String kind,
    required StreamController<ProductSyncProgress> controller,
    required String message,
    required double start,
    required double end,
  }) async {
    final head = await file
        .openRead(0, 1)
        .fold<List<int>>(<int>[], (previous, chunk) => previous..addAll(chunk));
    final topLevelArray = head.isNotEmpty && head.first == 0x5B;
    final parser = SyncJsonStream(topLevelArray: topLevelArray);
    final pending = <Map<String, dynamic>>[];
    var saved = 0;
    var total = 0;
    var lastEmit = 0;

    void emit({bool force = false}) {
      if (controller.isClosed) return;
      final now = DateTime.now().millisecondsSinceEpoch;
      if (!force && now - lastEmit < 160) return;
      lastEmit = now;
      final fraction = total > 0
          ? start + ((saved / total).clamp(0, 1)) * (end - start)
          : start;
      controller.add(
        ProductSyncProgress(
          message: total > 0 ? '$message $saved of $total' : '$message $saved',
          fraction: fraction,
          received: saved,
          total: total,
        ),
      );
    }

    emit(force: true);
    await database.transaction((txn) async {
      await txn.delete('synced_records', where: 'kind = ?', whereArgs: [kind]);
      Future<void> flush() async {
        if (pending.isEmpty) return;
        final batch = txn.batch();
        for (final item in pending) {
          batch.insert('synced_records', _row(kind, item));
        }
        await batch.commit(noResult: true);
        saved += pending.length;
        pending.clear();
        emit();
      }

      await for (final chunk in file.openRead().transform(utf8.decoder)) {
        await parser.addChunk(
          chunk,
          onTotal: (value) => total = value,
          onItem: (item) async {
            pending.add(item);
            if (pending.length >= 200) await flush();
          },
        );
      }
      await flush();
      await txn.insert('sync_meta', {
        'kind': kind,
        'saved_at': DateTime.now().toUtc().toIso8601String(),
        'record_count': saved,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    });
    emit(force: true);
  }

  Map<String, Object?> _row(String kind, Map<String, dynamic> item) {
    final fields = kind == StoredRecord.kindRfid
        ? (
            itemCode: _text(item, const ['BarcodeNumber', 'barcodeNumber']),
            rfid: _text(item, const [
              'TidValue',
              'TIDNumber',
              'TidNumber',
              'EPC',
            ]),
            barcode: _text(item, const [
              'BarcodeNumber',
              'barcodeNumber',
              'RFIDCode',
            ]),
            name: _text(item, const ['StatusType']),
          )
        : (
            itemCode: _text(item, const ['ItemCode', 'itemCode']),
            rfid: _text(item, const ['RFIDCode', 'Rfid', 'rfid', 'TIDNumber']),
            barcode: _text(item, const ['BarcodeNumber', 'Barcode', 'barcode']),
            name: _text(item, const [
              'ProductName',
              'productName',
              'ItemName',
              'itemName',
            ]),
          );
    return {
      'kind': kind,
      'item_code': fields.itemCode,
      'rfid': fields.rfid,
      'barcode': fields.barcode,
      'name': fields.name,
      'payload': jsonEncode(item),
    };
  }

  @override
  Future<List<StoredRecord>> search({
    String kind = StoredRecord.kindProduct,
    String query = '',
    int limit = 50,
    int offset = 0,
  }) async {
    final database = await _open();
    final trimmed = query.trim();
    final like = '%$trimmed%';
    final rows = await database.query(
      'synced_records',
      columns: ['kind', 'item_code', 'rfid', 'barcode', 'name', 'payload'],
      where: trimmed.isEmpty
          ? 'kind = ?'
          : 'kind = ? AND (item_code LIKE ? OR rfid LIKE ? OR barcode LIKE ? OR name LIKE ?)',
      whereArgs: trimmed.isEmpty ? [kind] : [kind, like, like, like, like],
      orderBy: 'id',
      limit: limit,
      offset: offset,
    );
    return rows.map(_record).toList();
  }

  @override
  Future<int> writeProductCsv(String path, {void Function(int written)? onProgress}) async {
    final database = await _open();
    final file = File(path);
    final sink = file.openWrite();
    var written = 0;
    try {
      sink.write('\uFEFF${productCsvHeader.join(',')}\r\n');
      var offset = 0;
      const page = 500;
      while (true) {
        final rows = await database.query(
          'synced_records',
          columns: ['item_code', 'rfid', 'name', 'payload'],
          where: 'kind = ?',
          whereArgs: [StoredRecord.kindProduct],
          orderBy: 'id',
          limit: page,
          offset: offset,
        );
        if (rows.isEmpty) break;
        final buffer = StringBuffer();
        for (final row in rows) {
          final decoded = jsonDecode(row['payload'] as String? ?? '{}');
          final payload = decoded is Map ? Map<String, dynamic>.from(decoded) : <String, dynamic>{};
          buffer
            ..write(
              productCsvFromPayload(
                payload,
                itemCode: row['item_code'] as String?,
                name: row['name'] as String?,
              ),
            )
            ..write('\r\n');
          written++;
        }
        sink.write(buffer);
        offset += rows.length;
        onProgress?.call(written);
        await Future<void>.delayed(Duration.zero);
        if (rows.length < page) break;
      }
      await sink.flush();
    } catch (_) {
      await sink.close();
      if (await file.exists()) await file.delete();
      rethrow;
    }
    await sink.close();
    return written;
  }

  @override
  Future<Map<String, String>> rfidMap() async {
    final database = await _open();
    final map = <String, String>{};
    var offset = 0;
    const page = 500;
    while (true) {
      final rows = await database.query(
        'synced_records',
        columns: ['barcode', 'rfid', 'payload'],
        where: 'kind = ?',
        whereArgs: [StoredRecord.kindRfid],
        orderBy: 'id',
        limit: page,
        offset: offset,
      );
      if (rows.isEmpty) break;
      for (final row in rows) {
        final barcode = (row['barcode'] as String? ?? '').trim().toUpperCase();
        final tid = (row['rfid'] as String? ?? '').trim();
        if (barcode.isEmpty || tid.isEmpty) continue;
        map[barcode] = tid;
      }
      offset += rows.length;
      if (rows.length < page) break;
    }
    return map;
  }

  @override
  Future<int> upsertProducts(List<Map<String, dynamic>> items, {void Function(int written)? onProgress}) async {
    if (items.isEmpty) return 0;
    final database = await _open();
    var written = 0;
    const page = 200;
    for (var start = 0; start < items.length; start += page) {
      final end = start + page > items.length ? items.length : start + page;
      final slice = items.sublist(start, end);
      await database.transaction((txn) async {
        for (final item in slice) {
          final code = _text(item, const ['ItemCode', 'itemCode']);
          if (code != null) {
            await txn.delete(
              'synced_records',
              where: 'kind = ? AND item_code = ?',
              whereArgs: [StoredRecord.kindProduct, code],
            );
          }
          await txn.insert('synced_records', _row(StoredRecord.kindProduct, item));
        }
      });
      written = end;
      onProgress?.call(written);
      await Future<void>.delayed(Duration.zero);
    }
    return written;
  }

  @override
  Future<int> count({String kind = StoredRecord.kindProduct}) async {
    final database = await _open();
    final rows = await database.rawQuery(
      'SELECT COUNT(*) AS total FROM synced_records WHERE kind = ?',
      [kind],
    );
    return (rows.first['total'] as num?)?.toInt() ?? 0;
  }

  StoredRecord _record(Map<String, Object?> row) {
    final decoded = jsonDecode(row['payload'] as String? ?? '{}');
    final payload = decoded is Map
        ? Map<String, dynamic>.from(decoded)
        : <String, dynamic>{};
    return StoredRecord(
      kind: row['kind'] as String? ?? StoredRecord.kindProduct,
      itemCode: row['item_code'] as String?,
      rfid: row['rfid'] as String?,
      barcode: row['barcode'] as String?,
      name: row['name'] as String?,
      payload: payload,
    );
  }

  String? _text(Map<String, dynamic> json, List<String> keys) {
    for (final key in keys) {
      final value = json[key]?.toString().trim();
      if (value != null && value.isNotEmpty) return value;
    }
    return null;
  }

  Future<Database> _open() async {
    final existing = _database;
    if (existing != null) return existing;
    final databasePath = '${await getDatabasesPath()}/sparkle_products.db';
    final database = await openDatabase(
      databasePath,
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE synced_records (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            kind TEXT NOT NULL,
            item_code TEXT,
            rfid TEXT,
            barcode TEXT,
            name TEXT,
            payload TEXT NOT NULL
          )
        ''');
        await db.execute(
          'CREATE INDEX idx_synced_kind ON synced_records(kind)',
        );
        await db.execute(
          'CREATE INDEX idx_synced_item_code ON synced_records(item_code)',
        );
        await db.execute(
          'CREATE INDEX idx_synced_rfid ON synced_records(rfid)',
        );
        await db.execute(
          'CREATE INDEX idx_synced_barcode ON synced_records(barcode)',
        );
        await db.execute('''
          CREATE TABLE sync_meta (
            kind TEXT PRIMARY KEY,
            saved_at TEXT NOT NULL,
            record_count INTEGER NOT NULL
          )
        ''');
      },
    );
    _database = database;
    return database;
  }
}
