import '../../../../core/constants/app_constants.dart';
import '../domain/entities/quotation_summary.dart';
import '../domain/entities/stock_item.dart';
import 'datasources/quotation_remote_data_source.dart';

/// Keeps a large labelled-stock catalogue in memory.
///
/// The first page is shown immediately. The rest is appended without another
/// loading state, and later opens reuse the same rows.
class LabeledStockIndex {
  LabeledStockIndex(this._remote);

  final QuotationRemoteDataSource _remote;
  String clientCode = '';
  List<StockItem> rows = const [];
  Future<void>? _job;

  bool readyFor(String code) => clientCode == code && rows.isNotEmpty;

  List<StockItem> filter(String query) {
    final needle = query.trim().toLowerCase();
    if (needle.isEmpty) return rows;
    final matches = <StockItem>[];
    for (final item in rows) {
      final haystack = '${item.itemCode} ${item.name} ${item.rfid} ${item.design}'.toLowerCase();
      if (haystack.contains(needle)) {
        matches.add(item);
        if (matches.length == 80) break;
      }
    }
    return matches;
  }

  Future<void> warm(String code, void Function() onRows) {
    if (clientCode == code && rows.isNotEmpty && _job == null) {
      Future<void>.microtask(onRows);
      return Future<void>.value();
    }
    if (clientCode == code && _job != null) return _job!;
    clientCode = code;
    rows = const [];
    final job = _fill(code, onRows);
    _job = job;
    return job.whenComplete(() {
      if (identical(_job, job)) _job = null;
    });
  }

  Future<void> _fill(String code, void Function() onRows) async {
    final first = await _remote.labeledStockPage(
      clientCode: code,
      pageNumber: 1,
      pageSize: AppConstants.stockPageSize,
    );
    if (clientCode != code) return;
    rows = first;
    onRows();
    if (first.length < AppConstants.stockPageSize) return;

    List<StockItem> bulk = const [];
    try {
      bulk = await _remote.labeledStockPage(
        clientCode: code,
        pageNumber: 1,
        pageSize: AppConstants.stockBulkSize,
        bulk: true,
      );
    } catch (_) {}
    if (clientCode != code) return;
    if (bulk.length > rows.length) {
      rows = bulk;
      onRows();
      return;
    }

    final seen = rows.map((item) => item.identity).toSet();
    var page = 2;
    while (clientCode == code && page <= 80) {
      final next = await _remote.labeledStockPage(
        clientCode: code,
        pageNumber: page,
        pageSize: 200,
      );
      if (next.isEmpty) break;
      final added = <StockItem>[];
      for (final item in next) {
        if (seen.add(item.identity)) added.add(item);
      }
      if (added.isNotEmpty) {
        rows = [...rows, ...added];
        onRows();
      }
      if (next.length < 200) break;
      page++;
    }
  }
}

/// Same first-page-then-fill behaviour for the quotation list.
class QuotationListIndex {
  QuotationListIndex(this._remote);

  final QuotationRemoteDataSource _remote;
  String clientCode = '';
  List<QuotationSummary> rows = const [];
  final Map<String, String> _names = {};
  Future<void>? _job;

  bool readyFor(String code) => clientCode == code && rows.isNotEmpty;

  List<QuotationSummary> filter(String query) {
    final needle = query.trim().toLowerCase();
    if (needle.isEmpty) return rows.map(_named).toList();
    return [
      for (final row in rows)
        if (_named(row).searchText.contains(needle)) _named(row),
    ];
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

  QuotationSummary _named(QuotationSummary row) {
    if (row.customerName.trim().isNotEmpty) return row;
    final remembered = _names[row.number.trim()];
    if (remembered == null || remembered.isEmpty) return row;
    return QuotationSummary(
      id: row.id,
      number: row.number,
      customerName: remembered,
      amount: row.amount,
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
    final first = await _remote.quotationPage(
      clientCode: code,
      pageNumber: 1,
      pageSize: AppConstants.quotationListPageSize,
    );
    if (clientCode != code) return;
    rows = first.map(_named).toList();
    onRows();
    if (first.length < AppConstants.quotationListPageSize) return;

    List<QuotationSummary> bulk = const [];
    try {
      bulk = await _remote.quotationPage(
        clientCode: code,
        pageNumber: 1,
        pageSize: AppConstants.stockBulkSize,
        bulk: true,
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
      final next = await _remote.quotationPage(
        clientCode: code,
        pageNumber: page,
        pageSize: 200,
      );
      if (next.isEmpty) break;
      final added = <QuotationSummary>[];
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
