import '../../../core/constants/app_constants.dart';
import '../domain/entities/order_record.dart';
import 'datasources/order_remote_data_source.dart';

/// Shows the first order page immediately, then fills the rest quietly.
class OrderListIndex {
  OrderListIndex(this._remote);

  final OrderRemoteDataSource _remote;
  String clientCode = '';
  List<OrderRecord> rows = const [];
  final Map<String, String> _names = {};
  Future<void>? _job;

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
    if (!refresh && clientCode == code && rows.isNotEmpty && _job == null) {
      Future<void>.microtask(onRows);
      return Future<void>.value();
    }
    if (!refresh && clientCode == code && _job != null) return _job!;
    clientCode = code;
    final job = _fill(code, onRows);
    _job = job;
    return job.whenComplete(() {
      if (identical(_job, job)) _job = null;
    });
  }

  Future<void> _fill(String code, void Function() onRows) async {
    final first = await _remote.orderPage(
      clientCode: code,
      pageNumber: 1,
      pageSize: AppConstants.quotationListPageSize,
    );
    if (clientCode != code) return;
    rows = first.map(_named).toList();
    onRows();
    if (first.length != AppConstants.quotationListPageSize) return;

    List<OrderRecord> bulk = const [];
    try {
      bulk = await _remote.orderPage(
        clientCode: code,
        pageNumber: 1,
        pageSize: AppConstants.stockBulkSize,
      );
    } catch (_) {}
    if (clientCode != code) return;
    if (bulk.length > rows.length) {
      rows = bulk.map(_named).toList();
      onRows();
      return;
    }

    final seen = rows.map((row) => row.id).toSet();
    var page = 2;
    while (clientCode == code && page <= 80) {
      final next = await _remote.orderPage(
        clientCode: code,
        pageNumber: page,
        pageSize: 200,
      );
      if (next.isEmpty) break;
      final added = <OrderRecord>[];
      for (final row in next) {
        if (seen.add(row.id)) added.add(row);
      }
      if (added.isNotEmpty) {
        rows = [...rows, ...added].map(_named).toList();
        onRows();
      }
      if (next.length < 200) break;
      page++;
    }
  }
}
