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
  int _stockGeneration = 0;
  int _indexedGeneration = -1;
  Map<String, StockItem> _tagMap = const {};

  bool readyFor(String code) => clientCode == code && rows.isNotEmpty;

  void _replaceRows(List<StockItem> next) {
    rows = next;
    _stockGeneration++;
  }

  Map<String, StockItem> _tagIndex() {
    if (_indexedGeneration == _stockGeneration) return _tagMap;
    final map = <String, StockItem>{};
    for (final item in rows) {
      _indexTag(map, item.rfid, item, tid: true);
      _indexTag(map, item.itemCode, item);
      _indexTag(map, item.extras['tidnumber'], item, tid: true);
      _indexTag(map, item.extras['tid'], item, tid: true);
      _indexTag(map, item.extras['rfidcode'], item, tid: true);
      _indexTag(map, item.extras['epc'], item, tid: true);
      _indexTag(map, item.extras['barcode'], item);
      _indexTag(map, item.extras['barcodenumber'], item);
    }
    _tagMap = map;
    _indexedGeneration = _stockGeneration;
    return map;
  }

  List<StockItem> findTags(Iterable<String> codes) {
    if (rows.isEmpty) return const [];
    final map = _tagIndex();
    final found = <String, StockItem>{};
    for (final raw in codes) {
      final item = _lookupTag(map, raw);
      if (item != null) found[item.identity] = item;
    }
    return found.values.toList();
  }

  bool matchesTag(StockItem item, String raw) {
    return _tagKeysMatch(item.rfid, raw, tid: true) ||
        _tagKeysMatch(item.itemCode, raw) ||
        _tagKeysMatch(item.extras['tidnumber'] ?? '', raw, tid: true) ||
        _tagKeysMatch(item.extras['tid'] ?? '', raw, tid: true) ||
        _tagKeysMatch(item.extras['rfidcode'] ?? '', raw, tid: true) ||
        _tagKeysMatch(item.extras['epc'] ?? '', raw, tid: true) ||
        _tagKeysMatch(item.extras['barcode'] ?? '', raw) ||
        _tagKeysMatch(item.extras['barcodenumber'] ?? '', raw);
  }

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
    _replaceRows(const []);
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
    _replaceRows(first);
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
      _replaceRows(bulk);
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
        _replaceRows([...rows, ...added]);
        onRows();
      }
      if (next.length < 200) break;
      page++;
    }
  }
}

void _indexTag(Map<String, StockItem> map, String? raw, StockItem item, {bool tid = false}) {
  final compact = _compactTag(raw);
  if (compact.isEmpty) return;
  _indexCompact(map, compact, item);
  for (final alias in _tagAliases(compact, tid: tid)) {
    _indexCompact(map, alias, item);
  }
}

void _indexCompact(Map<String, StockItem> map, String compact, StockItem item) {
  map.putIfAbsent(compact, () => item);
  if (compact.length > 12) {
    map.putIfAbsent(compact.substring(compact.length - 12), () => item);
  }
  if (compact.length > 16) {
    map.putIfAbsent(compact.substring(compact.length - 16), () => item);
  }
  if (compact.length > 24) {
    map.putIfAbsent(compact.substring(compact.length - 24), () => item);
  }
}

StockItem? _lookupTag(Map<String, StockItem> map, String raw) {
  final compact = _compactTag(raw);
  if (compact.isEmpty) return null;
  final direct = _lookupCompact(map, compact);
  if (direct != null) return direct;
  for (final alias in _tagAliases(compact, tid: true)) {
    final match = _lookupCompact(map, alias);
    if (match != null) return match;
  }
  return null;
}

StockItem? _lookupCompact(Map<String, StockItem> map, String compact) {
  final direct = map[compact];
  if (direct != null) return direct;
  if (compact.length > 12) {
    final tail = map[compact.substring(compact.length - 12)];
    if (tail != null) return tail;
  }
  if (compact.length > 16) {
    final tail = map[compact.substring(compact.length - 16)];
    if (tail != null) return tail;
  }
  if (compact.length > 24) {
    final tail = map[compact.substring(compact.length - 24)];
    if (tail != null) return tail;
  }
  return null;
}

bool _tagKeysMatch(String stored, String scanned, {bool tid = false}) {
  final left = _compactTag(stored);
  final right = _compactTag(scanned);
  if (left.isEmpty || right.isEmpty) return false;
  if (left == right) return true;
  final leftNames = {left, ..._tagAliases(left, tid: tid)};
  final rightNames = {right, ..._tagAliases(right, tid: true)};
  if (leftNames.intersection(rightNames).isNotEmpty) return true;
  if (left.length >= 12 && right.length >= 12) {
    final leftTail = left.substring(left.length - 12);
    final rightTail = right.substring(right.length - 12);
    return left.endsWith(rightTail) || right.endsWith(leftTail);
  }
  return false;
}

/// A tag may be stored or scanned with four leading zeros, such as 0000SP28
/// or hex 000053503238. Those zeros are ignored. The rest of the tag is unchanged.
Set<String> _tagAliases(String compact, {required bool tid}) {
  final aliases = <String>{};
  final trimmed = _withoutLeadingTidZeros(compact);
  if (trimmed != compact) aliases.add(trimmed);
  if (tid) {
    for (final source in {compact, trimmed}) {
      final text = _asciiFromHex(source);
      if (text == null) continue;
      aliases.add(text);
      final plain = _withoutLeadingTidZeros(text);
      if (plain != text) aliases.add(plain);
    }
  }
  for (final source in {compact, trimmed}) {
    final hex = _hexFromAscii(source);
    if (hex == null) continue;
    aliases.add(hex);
    aliases.add('0000$hex');
    final padded = _hexFromAscii('0000$source');
    if (padded != null) aliases.add(padded);
  }
  return aliases;
}

String? _asciiFromHex(String compact) {
  if (compact.length < 4 || compact.length > 40 || compact.length.isOdd) return null;
  if (!RegExp(r'^[0-9a-f]+$').hasMatch(compact)) return null;
  final chars = StringBuffer();
  for (var i = 0; i < compact.length; i += 2) {
    final byte = int.parse(compact.substring(i, i + 2), radix: 16);
    if (byte < 48 || byte > 122 || (byte > 57 && byte < 65) || (byte > 90 && byte < 97)) {
      return null;
    }
    chars.writeCharCode(byte);
  }
  final text = chars.toString().toLowerCase();
  if (text.length < 2 || !RegExp(r'[a-z]').hasMatch(text)) return null;
  return text;
}

String? _hexFromAscii(String compact) {
  if (compact.length < 2 || compact.length > 20) return null;
  if (!RegExp(r'^[a-z0-9]+$').hasMatch(compact) || !RegExp(r'[a-z]').hasMatch(compact)) {
    return null;
  }
  return compact.toUpperCase().codeUnits.map((unit) => unit.toRadixString(16).padLeft(2, '0')).join();
}

/// Labelled-stock TIDs are sometimes padded with four leading zeros.
String _withoutLeadingTidZeros(String compact) {
  if (compact.startsWith('0000') && compact.length > 4) {
    return compact.substring(4);
  }
  return compact;
}

/// Scan values plus readable item-code forms, such as 000053503238 and SP28.
List<String> scanLookupKeys(String raw) {
  final compact = _compactTag(raw);
  if (compact.isEmpty) return const [];
  final keys = <String>[raw.trim(), ..._tagAliases(compact, tid: true)];
  final seen = <String>{};
  return [for (final key in keys) if (key.isNotEmpty && seen.add(key.toLowerCase())) key];
}

String _compactTag(String? raw) {
  return (raw ?? '').trim().toLowerCase().replaceAll(RegExp(r'[\s\-:]'), '');
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
