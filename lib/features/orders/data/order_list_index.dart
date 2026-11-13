import '../domain/entities/order_record.dart';
import 'datasources/order_remote_data_source.dart';

/// Loads the order list once and keeps the newest screen callback.
class OrderListIndex {
  OrderListIndex(this._remote);

  final OrderRemoteDataSource _remote;
  String clientCode = '';
  List<OrderRecord> rows = const [];
  final Map<String, String> _names = {};
  Future<void>? _job;
  void Function()? _listen;
  var _generation = 0;

  bool readyFor(String code) => clientCode == code && rows.isNotEmpty;

  List<OrderRecord> filter(String query) {
    final needle = query.trim().toLowerCase();
    if (needle.isEmpty) return rows.map(_named).toList();
    return [
      for (final row in rows)
        if (_named(row).searchText.contains(needle)) _named(row),
    ];
  }

  OrderRecord? find(int id) {
    for (final row in rows) {
      if (row.id == id) return _named(row);
    }
    return null;
  }

  void remember({required String number, required String customerName}) {
    final name = customerName.trim();
    if (number.trim().isEmpty || name.isEmpty) return;
    _names[number.trim()] = name;
    rows = [for (final row in rows) _named(row)];
  }

  void remove(int id) {
    rows = [for (final row in rows) if (row.id != id) row];
  }

  OrderRecord _named(OrderRecord row) {
    if (row.customerName.trim().isNotEmpty) return row;
    final remembered = _names[row.number.trim()];
    if (remembered == null || remembered.isEmpty) return row;
    return OrderRecord(
      id: row.id,
      number: row.number,
      customerName: remembered,
      amount: row.amount,
      source: row.source,
    );
  }

  Future<void> warm(String code, void Function() onRows, {bool refresh = false}) {
    _listen = onRows;
    if (!refresh && clientCode == code && rows.isNotEmpty && _job == null) {
      Future<void>.microtask(onRows);
      return Future<void>.value();
    }
    if (!refresh && clientCode == code && _job != null) {
      if (rows.isNotEmpty) Future<void>.microtask(onRows);
      return _job!;
    }
    clientCode = code;
    final generation = ++_generation;
    final job = _fill(code, generation);
    _job = job;
    return job.whenComplete(() {
      if (identical(_job, job)) _job = null;
    });
  }

  Future<void> _fill(String code, int generation) async {
    final loaded = await _remote.orderPage(clientCode: code);
    if (generation != _generation || clientCode != code) return;
    rows = loaded.map(_named).toList();
    _listen?.call();
  }
}
