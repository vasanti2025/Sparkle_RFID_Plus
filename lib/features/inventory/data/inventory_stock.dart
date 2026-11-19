import 'dart:async';
import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import '../../../core/di/injection.dart';
import '../../products/domain/entities/stored_record.dart';
import '../domain/inventory_catalog.dart';

/// Labelled stock kept on the device, indexed for a fast RFID match.
class InventoryStock {
  InventoryStock._();

  static final InventoryStock instance = InventoryStock._();

  var ready = false;
  List<InventoryPiece> pieces = const [];
  List<String> categories = const [];
  List<String> products = const [];
  List<String> designs = const [];
  List<String> counters = const [];
  List<String> boxes = const [];
  List<String> branches = const [];
  List<String> packets = const [];
  List<String> exhibitions = const [];
  final Map<String, int> locationIds = {};

  final Map<String, InventoryPiece> _byId = {};
  final Map<String, String> _keyToId = {};

  Future<void> load() async {
    try {
      await _read();
    } finally {
      ready = true;
    }
  }

  Future<void> _read() async {
    final products = await _pages(StoredRecord.kindProduct);
    final tags = await _pages(StoredRecord.kindRfid);
    final pieces = <InventoryPiece>[];
    _byId.clear();
    _keyToId.clear();
    locationIds.clear();
    for (final record in products) {
      final piece = _piece(record);
      if (piece == null) continue;
      pieces.add(piece);
      _byId[piece.id] = piece;
      _index(piece.id, piece.id);
      _index(piece.id, piece.rfid);
      _index(piece.id, piece.epc);
      _index(piece.id, piece.tid);
      _index(piece.id, record.barcode);
    }
    for (final tag in tags) {
      final barcode = tag.barcode ?? tag.itemCode;
      final owner = barcode == null ? null : _keyToId[_norm(barcode)];
      if (owner == null) continue;
      _index(owner, tag.rfid);
      _index(owner, tag.itemCode);
    }
    this.pieces = pieces;
    categories = _distinct(pieces.map((item) => item.category));
    this.products = _distinct(pieces.map((item) => item.product));
    designs = _distinct(pieces.map((item) => item.design));
    counters = _distinct(pieces.map((item) => item.counter));
    boxes = _distinct(pieces.map((item) => item.box));
    packets = _distinct(pieces.map((item) => item.packet));
    branches = _distinct(
      pieces.where((item) => (item.branchType ?? '').toLowerCase() != 'exhibition').map((item) => item.branch),
    );
    exhibitions = _distinct(
      pieces.where((item) => (item.branchType ?? '').toLowerCase() == 'exhibition').map((item) => item.branch),
    );
  }

  List<String> places(String mode) {
    return switch (mode) {
      'Counter' => counters,
      'Box' => boxes,
      'Packet' => packets,
      'Branch' => branches,
      'Exhibition' => exhibitions,
      _ => const ['All labelled stock'],
    };
  }

  List<InventoryPiece> select({
    required String mode,
    required String scope,
    required Set<String> categoriesSelected,
    required Set<String> productsSelected,
    required Set<String> designsSelected,
  }) {
    bool allows(String? value, Set<String> selected, List<String> all) {
      if (all.isEmpty) return true;
      if (value == null || value.isEmpty) return selected.length == all.length;
      return selected.contains(value);
    }

    return pieces.where((item) {
      if (!_inPlace(item, mode, scope)) return false;
      return allows(item.category, categoriesSelected, categories) &&
          allows(item.product, productsSelected, products) &&
          allows(item.design, designsSelected, designs);
    }).toList();
  }

  InventoryPiece? byId(String id) => _byId[id];

  /// Returns the item id for a reader EPC or TID. Unknown tags return null.
  String? match(String raw) {
    final key = _norm(raw);
    if (key.isEmpty) return null;
    final direct = _lookup(key);
    if (direct != null) return direct;
    if (key.startsWith('0000') && key.length > 4) return _lookup(key.substring(4));
    return null;
  }

  String? _lookup(String key) {
    final direct = _keyToId[key];
    if (direct != null) return direct;
    final stripped = _strip(key);
    if (stripped != key) return _keyToId[stripped];
    return null;
  }

  bool known(String raw) => match(raw) != null;

  bool _inPlace(InventoryPiece item, String mode, String scope) {
    final value = switch (mode) {
      'Counter' => item.counter,
      'Box' => item.box,
      'Packet' => item.packet,
      'Branch' => item.branch,
      'Exhibition' => item.branch,
      _ => scope,
    };
    if (mode == 'Display') return true;
    return (value ?? '').toLowerCase() == scope.toLowerCase();
  }

  void _index(String id, String? raw) {
    final key = _norm(raw ?? '');
    if (key.isEmpty) return;
    _keyToId[key] = id;
    if (key.startsWith('0000') && key.length > 4) _keyToId[key.substring(4)] = id;
    final stripped = _strip(key);
    if (stripped.isNotEmpty && stripped != key) _keyToId[stripped] = id;
  }

  Future<List<StoredRecord>> _pages(String kind) async {
    final all = <StoredRecord>[];
    const size = 800;
    for (var offset = 0; ; offset += size) {
      final page = await Injection.searchStoredRecords(
        kind: kind,
        limit: size,
        offset: offset,
      );
      all.addAll(page);
      if (page.length < size) break;
      await Future<void>.delayed(Duration.zero);
    }
    return all;
  }

  InventoryPiece? _piece(StoredRecord record) {
    final json = record.payload;
    final id = record.itemCode ?? _text(json, const ['ItemCode', 'itemCode']);
    if (id == null || id.isEmpty) return null;
    final gross = _grams(json, const ['GrossWt', 'grossWt', 'GrossWeight', 'grossWeight', 'TotalGwt']);
    final net = _grams(json, const ['NetWt', 'netWt', 'NetWeight', 'netWeight']);
    final piece = InventoryPiece(
      id: id,
      category: _text(json, const ['CategoryName', 'categoryName']) ?? 'Uncategorised',
      product: record.name ?? _text(json, const ['ProductName', 'productName']),
      design: _text(json, const ['DesignName', 'designName']),
      milligrams: gross,
      rfid: record.rfid ?? _text(json, const ['RFIDCode', 'Rfid', 'rfid']),
      epc: _text(json, const ['EPC', 'epc', 'Epc']),
      tid: _text(json, const ['TidValue', 'TIDNumber', 'TidNumber']),
      netMilligrams: net == 0 ? null : net,
      purity: _text(json, const ['PurityName', 'Purity', 'purity']),
      weightKnown: gross > 0,
      counter: _text(json, const ['CounterName', 'counterName']),
      box: _text(json, const ['BoxName', 'boxName']),
      branch: _text(json, const ['BranchName', 'branchName']),
      branchType: _text(json, const ['BranchType', 'branchType']),
      packet: _text(json, const ['PacketName', 'packetName']),
      stockId: _int(json, const ['LabelledStockId', 'BulkItemId', 'StockId', 'Id']),
      counterId: _int(json, const ['CounterId', 'counterId']),
      boxId: _int(json, const ['BoxId', 'boxId']),
      branchId: _int(json, const ['BranchId', 'branchId']),
      packetId: _int(json, const ['PacketId', 'packetId']),
    );
    _rememberLocation('counter', piece.counter, piece.counterId);
    _rememberLocation('box', piece.box, piece.boxId);
    _rememberLocation('branch', piece.branch, piece.branchId);
    _rememberLocation('packet', piece.packet, piece.packetId);
    return piece;
  }

  int locationId(String kind, String name) {
    return locationIds['${kind.toLowerCase()}|${name.trim().toLowerCase()}'] ?? 0;
  }

  void _rememberLocation(String kind, String? name, int id) {
    final label = name?.trim() ?? '';
    if (label.isEmpty || id <= 0) return;
    locationIds['${kind.toLowerCase()}|${label.toLowerCase()}'] = id;
  }

  /// After an approved transfer, keep the piece at its new location.
  Future<void> movePieces({
    required Iterable<String> itemCodes,
    required String toType,
    required String toName,
    required int destId,
  }) async {
    final keys = itemCodes.map((code) => code.trim().toLowerCase()).where((code) => code.isNotEmpty).toSet();
    if (keys.isEmpty || toName.trim().isEmpty) return;
    pieces = [
      for (final piece in pieces)
        keys.contains(piece.id.toLowerCase()) ? _moved(piece, toType, toName.trim(), destId) : piece,
    ];
    for (final piece in pieces) {
      if (keys.contains(piece.id.toLowerCase())) _byId[piece.id] = piece;
    }
    counters = _distinct(pieces.map((item) => item.counter));
    boxes = _distinct(pieces.map((item) => item.box));
    packets = _distinct(pieces.map((item) => item.packet));
    branches = _distinct(
      pieces.where((item) => (item.branchType ?? '').toLowerCase() != 'exhibition').map((item) => item.branch),
    );
    await _writeLocations(keys, toType, toName.trim(), destId);
  }

  Future<void> dropPieces(Iterable<String> itemCodes) async {
    final keys = itemCodes.map((code) => code.trim().toLowerCase()).where((code) => code.isNotEmpty).toSet();
    if (keys.isEmpty) return;
    pieces = pieces.where((piece) => !keys.contains(piece.id.toLowerCase())).toList();
    _byId.removeWhere((_, piece) => keys.contains(piece.id.toLowerCase()));
    _keyToId.removeWhere((_, id) => keys.contains(id.toLowerCase()));
    counters = _distinct(pieces.map((item) => item.counter));
    boxes = _distinct(pieces.map((item) => item.box));
    packets = _distinct(pieces.map((item) => item.packet));
    branches = _distinct(
      pieces.where((item) => (item.branchType ?? '').toLowerCase() != 'exhibition').map((item) => item.branch),
    );
    try {
      final database = await openDatabase('${await getDatabasesPath()}/sparkle_products.db');
      for (final code in keys) {
        await database.delete(
          'synced_records',
          where: 'kind = ? AND lower(item_code) = ?',
          whereArgs: [StoredRecord.kindProduct, code],
        );
      }
    } catch (_) {}
  }

  InventoryPiece _moved(InventoryPiece piece, String toType, String toName, int destId) {
    final type = toType.toLowerCase();
    if (type == 'branch') {
      _rememberLocation('branch', toName, destId);
      return piece.copyWith(
        branch: toName,
        branchId: destId > 0 ? destId : piece.branchId,
        clearCounter: true,
        clearBox: true,
        clearPacket: true,
      );
    }
    if (type == 'counter') {
      _rememberLocation('counter', toName, destId);
      return piece.copyWith(counter: toName, counterId: destId > 0 ? destId : piece.counterId);
    }
    if (type == 'box') {
      _rememberLocation('box', toName, destId);
      return piece.copyWith(box: toName, boxId: destId > 0 ? destId : piece.boxId);
    }
    if (type == 'packet') {
      _rememberLocation('packet', toName, destId);
      return piece.copyWith(packet: toName, packetId: destId > 0 ? destId : piece.packetId);
    }
    return piece;
  }

  List<String> _distinct(Iterable<String?> values) {
    final set = <String>{};
    for (final value in values) {
      final text = value?.trim() ?? '';
      if (text.isNotEmpty) set.add(text);
    }
    final list = set.toList()..sort();
    return list;
  }

  String? _text(Map<String, dynamic> json, List<String> keys) {
    for (final key in keys) {
      final value = json[key]?.toString().trim();
      if (value != null && value.isNotEmpty && value.toLowerCase() != 'null') return value;
    }
    return null;
  }

  int _int(Map<String, dynamic> json, List<String> keys) {
    return int.tryParse(_text(json, keys) ?? '') ?? 0;
  }

  Future<void> _writeLocations(Set<String> itemCodes, String toType, String toName, int destId) async {
    try {
      final databasePath = '${await getDatabasesPath()}/sparkle_products.db';
      final database = await openDatabase(databasePath);
      final type = toType.toLowerCase();
      for (final code in itemCodes) {
        final rows = await database.query(
          'synced_records',
          columns: ['id', 'payload'],
          where: 'kind = ? AND lower(item_code) = ?',
          whereArgs: [StoredRecord.kindProduct, code],
          limit: 1,
        );
        if (rows.isEmpty) continue;
        final decoded = jsonDecode(rows.first['payload'] as String? ?? '{}');
        if (decoded is! Map) continue;
        final payload = Map<String, dynamic>.from(decoded);
        if (type == 'branch') {
          payload['BranchName'] = toName;
          if (destId > 0) payload['BranchId'] = destId;
          payload['CounterName'] = '';
          payload['CounterId'] = 0;
          payload['BoxName'] = '';
          payload['BoxId'] = 0;
          payload['PacketName'] = '';
          payload['PacketId'] = 0;
        } else if (type == 'counter') {
          payload['CounterName'] = toName;
          if (destId > 0) payload['CounterId'] = destId;
        } else if (type == 'box') {
          payload['BoxName'] = toName;
          if (destId > 0) payload['BoxId'] = destId;
        } else if (type == 'packet') {
          payload['PacketName'] = toName;
          if (destId > 0) payload['PacketId'] = destId;
        }
        await database.update(
          'synced_records',
          {'payload': jsonEncode(payload)},
          where: 'id = ?',
          whereArgs: [rows.first['id']],
        );
      }
    } catch (_) {
      // The transfer is already on the server. Local stock refreshes on the next sync.
    }
  }

  int _grams(Map<String, dynamic> json, List<String> keys) {
    final raw = _text(json, keys);
    final value = double.tryParse(raw ?? '');
    if (value == null || value <= 0) return 0;
    return (value * 1000).round();
  }

  String _norm(String raw) => raw.trim().toUpperCase().replaceAll(' ', '');

  String _strip(String key) {
    var text = key;
    if (text.length > 2 && text.startsWith('00')) text = text.substring(2);
    if (text.length > 2 && text.endsWith('00')) text = text.substring(0, text.length - 2);
    return text;
  }
}

int signalBars(String rssi) {
  final match = RegExp(r'-?\d+(?:\.\d+)?').firstMatch(rssi);
  if (match == null) return 3;
  final value = double.tryParse(match.group(0)!);
  if (value == null) return 3;
  if (value >= 0 && value <= 100) {
    return (value / 10).round().clamp(1, 10);
  }
  final clamped = value.clamp(-85, -35);
  return (((clamped + 85) / 5).round()).clamp(1, 10);
}
