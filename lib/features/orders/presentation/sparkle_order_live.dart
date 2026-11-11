import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import '../../../core/di/injection.dart';
import '../../../core/session/app_session.dart';
import '../../../core/utils/result.dart';
import '../../quotation/domain/entities/customer_record.dart';
import '../../quotation/domain/entities/stock_item.dart';
import '../domain/entities/order_record.dart';
import 'demo/order_demo_session.dart';

/// Real order and customer data behind the Sparkle order screen.
class SparkleOrderLive {
  final Map<String, CustomerRecord> _customers = {};
  Database? _database;

  Future<void> open(OrderDemoSession session, void Function() onChanged) async {
    final code = AppSession.clientCode;
    if (code.isEmpty) return;
    final cached = await _readCache(code);
    session.replaceLive(cached);
    onChanged();
    final queued = await syncPending(code, session);
    try {
      await Injection.orders.warmOrders(code, () {
        final pending = queued;
        final live = [
          for (final row in Injection.orders.ordersMatching(code, '')) _fromRecord(row),
        ];
        final liveIds = live.map((order) => order.id).toSet();
        session.replaceLive([
          ...live,
          for (final order in pending)
            if (!liveIds.contains(order.id)) order,
        ]);
        onChanged();
      }, refresh: true);
      await _writeCache(code, session.orders.where((order) => !order.pending));
    } catch (_) {}
    final customers = await Injection.quotations.loadCustomers(code);
    if (customers case Success(:final data)) {
      _customers
        ..clear()
        ..addEntries(data.records.map((record) => MapEntry(record.name, record)));
      session.setCustomers(_customers.keys.toList());
      onChanged();
    }
    if (code.isNotEmpty) {
      await Injection.quotations.warmLabeledStock(code, () {});
    }
  }

  CustomerRecord? customerNamed(String name) => _customers[name];

  void remember(CustomerRecord record) {
    _customers[record.name] = record;
  }

  Future<List<DemoOrder>> syncPending(String code, OrderDemoSession session) async {
    final pending = await _readPending(code);
    if (pending.isEmpty) return const [];
    final stillPending = <DemoOrder>[];
    for (final order in pending) {
      final outcome = await _save(code, order);
      if (outcome.offline) {
        stillPending.add(order);
        continue;
      }
      if (outcome.error != null) {
        stillPending.add(order);
        continue;
      }
      await _dropPending(order.id ?? '');
    }
    session.orders.removeWhere((order) => order.pending && !stillPending.any((item) => item.id == order.id));
    return stillPending;
  }

  Future<String?> save(OrderDemoSession session, DemoOrder draft) async {
    final code = AppSession.clientCode;
    if (code.isEmpty) return 'Sign in to save orders.';
    final known = _customers[draft.customer];
    final customerId = (known?.id ?? 0) > 0 ? known!.id : draft.customerId;
    if (customerId <= 0) return 'Select a saved customer.';
    draft.customerId = customerId;
    final outcome = await _save(code, draft);
    if (outcome.offline) {
      draft.pending = true;
      draft.id ??= 'LOCAL-${DateTime.now().millisecondsSinceEpoch}';
      await _queue(code, draft);
      _upsert(session, draft);
      return 'Saved on this device. It will sync when you are online.';
    }
    if (outcome.error != null) return outcome.error;
    draft
      ..pending = false
      ..id = outcome.number ?? draft.id;
    _upsert(session, draft);
    await _dropPending(draft.id ?? '');
    return null;
  }

  Future<String?> remove(OrderDemoSession session, String id) async {
    final code = AppSession.clientCode;
    final order = session.orders.cast<DemoOrder?>().firstWhere(
      (item) => item?.id == id,
      orElse: () => null,
    );
    if (order == null) return 'Order could not be found.';
    if (order.pending || order.serverId <= 0) {
      await _dropPending(id);
      session.orders.removeWhere((item) => item.id == id);
      return null;
    }
    final result = await Injection.orders.deleteOrder(clientCode: code, id: order.serverId);
    if (result case Error(:final failure)) {
      if (_offline(failure.message)) {
        return 'Connect to the internet to delete this order.';
      }
      return failure.message;
    }
    session.orders.removeWhere((item) => item.id == id);
    return null;
  }

  Future<({String? number, String? error, bool offline})> _save(String code, DemoOrder draft) async {
    final result = await Injection.orders.saveOrder(
      clientCode: code,
      customer: CustomerRecord(
        id: draft.customerId,
        name: draft.customer,
        mobile: '',
      ),
      items: [for (final piece in draft.items) _stock(piece)],
      gstApplied: draft.gst,
      gstRate: 0.03,
      id: draft.serverId,
      number: draft.serverId > 0 ? (draft.id ?? '') : '',
    );
    if (result case Success(:final data)) {
      return (number: data.isEmpty ? draft.id : data, error: null, offline: false);
    }
    if (result case Error(:final failure)) {
      if (_offline(failure.message)) return (number: null, error: null, offline: true);
      return (number: null, error: failure.message, offline: false);
    }
    return (number: null, error: 'Order could not be saved.', offline: false);
  }

  void _upsert(OrderDemoSession session, DemoOrder draft) {
    final saved = draft.copy()..dirty = false;
    final index = session.orders.indexWhere((order) => order.id == saved.id);
    if (index < 0) {
      session.orders.insert(0, saved);
    } else {
      session.orders[index] = saved;
    }
  }

  bool _offline(String message) {
    final text = message.toLowerCase();
    return text.contains('socket') ||
        text.contains('network') ||
        text.contains('host') ||
        text.contains('timed out') ||
        text.contains('connection') ||
        text.contains('internet');
  }

  DemoOrder _fromRecord(OrderRecord row) {
    final source = row.source;
    final items = <OrderPiece>[];
    final raw = source['CustomOrderItem'];
    if (raw is List) {
      for (final entry in raw.whereType<Map>()) {
        items.add(_piece(Map<String, dynamic>.from(entry)));
      }
    }
    return DemoOrder(
      id: row.number.isEmpty ? '${row.id}' : row.number,
      serverId: row.id,
      customerId: int.tryParse('${source['CustomerId']}') ?? 0,
      customer: row.customerName,
      items: items,
      gst: '${source['GSTApplied'] ?? ''}'.toLowerCase() == 'true',
      details: OrderDetails(
        orderDate: _day('${source['OrderDate'] ?? ''}'),
        deliveryDate: _day('${source['DeliverDate'] ?? source['DeliveryDate'] ?? ''}'),
        branch: '${source['BranchName'] ?? 'Branch'}',
        remark: '${source['Remark'] ?? ''}',
      ),
    );
  }

  OrderPiece _piece(Map<String, dynamic> row) {
    final extras = <String, String>{};
    row.forEach((key, value) {
      final text = '$value'.trim();
      if (text.isEmpty || text == 'null') return;
      extras[key.toLowerCase().replaceAll(RegExp('[^a-z0-9]'), '')] = text;
    });
    final code = '${row['ItemCode'] ?? row['SKU'] ?? row['RFIDCode'] ?? ''}'.trim();
    return OrderPiece(
      id: code.isEmpty ? '${row['RFIDCode'] ?? 'item'}' : code,
      name: '${row['ProductName'] ?? row['DesignName'] ?? 'Item'}',
      rfid: '${row['RFIDCode'] ?? ''}',
      grossMg: _mg('${row['GrossWt'] ?? ''}'),
      netMg: _mg('${row['NetWt'] ?? ''}'),
      extras: extras,
    );
  }

  StockItem _stock(OrderPiece piece) {
    String grams(int? milligrams) {
      if (milligrams == null) return '';
      return (milligrams / 1000).toStringAsFixed(3);
    }

    final extras = Map<String, String>.from(piece.extras);
    extras['itemcode'] = piece.id;
    extras['grosswt'] = grams(piece.grossMg);
    extras['netwt'] = grams(piece.netMg);
    return StockItem(
      itemCode: piece.id,
      name: piece.name,
      rfid: piece.rfid,
      gross: grams(piece.grossMg),
      net: grams(piece.netMg),
      extras: extras,
    );
  }

  int? _mg(String text) {
    final grams = double.tryParse(text.trim());
    if (grams == null) return null;
    return (grams * 1000).round();
  }

  String _day(String value) {
    final text = value.trim();
    if (text.length >= 10 && text[4] == '-') return text.substring(0, 10);
    return '';
  }

  Future<Database> _db() async {
    final existing = _database;
    if (existing != null) return existing;
    final file = '${await getDatabasesPath()}/sparkle_orders.db';
    final database = await openDatabase(
      file,
      version: 1,
      onCreate: (db, version) async {
        await db.execute(
          'CREATE TABLE order_cache (client TEXT, order_key TEXT, body TEXT, PRIMARY KEY (client, order_key))',
        );
        await db.execute(
          'CREATE TABLE order_pending (local_id TEXT PRIMARY KEY, client TEXT, body TEXT)',
        );
      },
    );
    _database = database;
    return database;
  }

  Future<List<DemoOrder>> _readCache(String code) async {
    final db = await _db();
    final rows = await db.query('order_cache', where: 'client = ?', whereArgs: [code]);
    return [for (final row in rows) _decode('${row['body']}')];
  }

  Future<void> _writeCache(String code, Iterable<DemoOrder> orders) async {
    final db = await _db();
    final batch = db.batch();
    batch.delete('order_cache', where: 'client = ?', whereArgs: [code]);
    for (final order in orders) {
      if ((order.id ?? '').isEmpty) continue;
      batch.insert('order_cache', {
        'client': code,
        'order_key': order.id,
        'body': jsonEncode(_encode(order)),
      });
    }
    await batch.commit(noResult: true);
  }

  Future<List<DemoOrder>> _readPending(String code) async {
    final db = await _db();
    final rows = await db.query('order_pending', where: 'client = ?', whereArgs: [code]);
    return [for (final row in rows) _decode('${row['body']}')];
  }

  Future<void> _queue(String code, DemoOrder order) async {
    final db = await _db();
    await db.insert('order_pending', {
      'local_id': order.id,
      'client': code,
      'body': jsonEncode(_encode(order..pending = true)),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> _dropPending(String id) async {
    if (id.isEmpty) return;
    final db = await _db();
    await db.delete('order_pending', where: 'local_id = ?', whereArgs: [id]);
  }

  Map<String, dynamic> _encode(DemoOrder order) {
    return {
      'id': order.id,
      'serverId': order.serverId,
      'customerId': order.customerId,
      'customer': order.customer,
      'gst': order.gst,
      'pending': order.pending,
      'orderDate': order.details.orderDate,
      'deliveryDate': order.details.deliveryDate,
      'branch': order.details.branch,
      'remark': order.details.remark,
      'items': [
        for (final item in order.items)
          {
            'id': item.id,
            'name': item.name,
            'rfid': item.rfid,
            'grossMg': item.grossMg,
            'netMg': item.netMg,
            'fwMg': item.fwMg,
            'extras': item.extras,
          },
      ],
    };
  }

  DemoOrder _decode(String raw) {
    final map = jsonDecode(raw);
    if (map is! Map) return DemoOrder();
    final items = <OrderPiece>[];
    final rawItems = map['items'];
    if (rawItems is List) {
      for (final entry in rawItems.whereType<Map>()) {
        final extras = <String, String>{};
        final stored = entry['extras'];
        if (stored is Map) {
          stored.forEach((key, value) => extras['$key'] = '$value');
        }
        items.add(
          OrderPiece(
            id: '${entry['id'] ?? ''}',
            name: '${entry['name'] ?? ''}',
            rfid: '${entry['rfid'] ?? ''}',
            grossMg: entry['grossMg'] as int?,
            netMg: entry['netMg'] as int?,
            fwMg: entry['fwMg'] as int?,
            extras: extras,
          ),
        );
      }
    }
    return DemoOrder(
      id: '${map['id'] ?? ''}',
      serverId: map['serverId'] as int? ?? 0,
      customerId: map['customerId'] as int? ?? 0,
      customer: '${map['customer'] ?? ''}',
      gst: map['gst'] == true,
      pending: map['pending'] == true,
      items: items,
      details: OrderDetails(
        orderDate: '${map['orderDate'] ?? ''}',
        deliveryDate: '${map['deliveryDate'] ?? ''}',
        branch: '${map['branch'] ?? ''}',
        remark: '${map['remark'] ?? ''}',
      ),
    );
  }
}

OrderPiece pieceFromStock(StockItem item) {
  int? mg(String text) {
    final grams = double.tryParse(text.trim());
    if (grams == null) return null;
    return (grams * 1000).round();
  }

  return OrderPiece(
    id: item.itemCode.isEmpty ? item.rfid : item.itemCode,
    name: item.name.isEmpty ? item.design : item.name,
    rfid: item.rfid,
    grossMg: mg(item.gross),
    netMg: mg(item.net),
    extras: item.extras,
  );
}
