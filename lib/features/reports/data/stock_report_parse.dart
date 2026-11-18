import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

class ReportSession {
  const ReportSession({
    required this.scanBatchId,
    required this.branchId,
    required this.branchName,
    required this.startedOn,
    required this.endedOn,
    required this.totalQty,
    required this.matchQty,
    required this.unmatchQty,
  });

  final String scanBatchId;
  final int? branchId;
  final String branchName;
  final String startedOn;
  final String endedOn;
  final int totalQty;
  final int matchQty;
  final int unmatchQty;
}

class BranchSummary {
  const BranchSummary({
    required this.id,
    required this.name,
    required this.total,
    required this.matched,
    required this.unmatched,
  });

  final int id;
  final String name;
  final int total;
  final int matched;
  final int unmatched;
}

/// One level of the consolidated tree: branch, category, product, or design.
/// Child lists are counts only. Item rows stay out of this object.
class ReportTreeNode {
  const ReportTreeNode({
    required this.id,
    required this.name,
    required this.total,
    required this.matched,
    required this.unmatched,
    this.children = const [],
  });

  final int id;
  final String name;
  final int total;
  final int matched;
  final int unmatched;
  final List<ReportTreeNode> children;
}

class ItemRow {
  const ItemRow({
    required this.item,
    required this.rfid,
    required this.category,
    required this.product,
    required this.gross,
    required this.net,
    required this.status,
  });

  final String item;
  final String rfid;
  final String category;
  final String product;
  final String gross;
  final String net;
  final String status;
}

class BatchRow {
  const BatchRow({
    required this.item,
    required this.product,
    required this.branch,
    required this.category,
    required this.rfid,
  });

  final String item;
  final String product;
  final String branch;
  final String category;
  final String rfid;
}

class BatchDetails {
  const BatchDetails({
    required this.matched,
    required this.unmatched,
  });

  final List<BatchRow> matched;
  final List<BatchRow> unmatched;
}

/// Small replies are read on this isolate. Larger ones stay off the screen,
/// but still use the light scanner so item rows are not built up front.
Future<T> readReport<T>(String body, T Function(String) parse) {
  if (body.length <= 1800000) return Future<T>.value(parse(body));
  return compute(parse, body);
}

dynamic decodeReportBody(String body) {
  var trimmed = body.trim();
  if (trimmed.isEmpty) return null;
  if (trimmed.codeUnitAt(0) == 0xFEFF) trimmed = trimmed.substring(1).trim();
  final decoded = jsonDecode(trimmed);
  if (decoded is String) {
    final inner = decoded.trim();
    if (inner.isEmpty) return null;
    return jsonDecode(inner);
  }
  return decoded;
}

int reportInt(dynamic value) {
  if (value is int) return value;
  if (value is num) return value.round();
  return int.tryParse(value?.toString() ?? '') ?? 0;
}

String reportText(dynamic value) {
  if (value == null) return '';
  final text = value.toString().trim();
  return text == 'null' ? '' : text;
}

String reportWeight(dynamic value) {
  if (value == null) return '';
  final number = value is num ? value.toDouble() : double.tryParse(value.toString());
  if (number == null) return reportText(value);
  return number.toStringAsFixed(2);
}

Map<String, dynamic>? _map(dynamic value) {
  if (value is Map<String, dynamic>) return value;
  if (value is Map) return value.map((key, item) => MapEntry(key.toString(), item));
  return null;
}

dynamic _unwrap(dynamic value) {
  final map = _map(value);
  if (map == null) return value;
  return map[r'$values'] ?? map[r'$Values'] ?? value;
}

String reportDateKey(String startedOn) {
  final text = startedOn.trim();
  if (text.length >= 10 && text[4] == '-') return text.substring(0, 10);
  final match = RegExp(r'^(\d{2})[/-](\d{2})[/-](\d{4})').firstMatch(text);
  if (match != null) return '${match[3]}-${match[2]}-${match[1]}';
  final parsed = DateTime.tryParse(text);
  if (parsed != null) {
    final month = parsed.month.toString().padLeft(2, '0');
    final day = parsed.day.toString().padLeft(2, '0');
    return '${parsed.year}-$month-$day';
  }
  return text.length >= 10 ? text.substring(0, 10) : text;
}

List<ReportSession> parseSessions(String body) {
  try {
    final scanned = _scanSessions(body);
    if (scanned.isNotEmpty) return scanned;
  } catch (_) {}
  final decoded = decodeReportBody(body);
  final raw = _sessionRows(decoded);
  if (raw == null) return const [];
  final sessions = <ReportSession>[];
  for (final entry in raw) {
    final map = _map(_unwrap(entry));
    if (map == null) continue;
    final branch = reportText(map['BranchName'] ?? map['branchName']);
    final batch = reportText(map['BatchName'] ?? map['batchName']);
    final branchId = map['BranchId'] ?? map['branchId'];
    sessions.add(
      ReportSession(
        scanBatchId: reportText(map['ScanBatchId'] ?? map['scanBatchId'] ?? map['ScanBatchID']),
        branchId: branchId == null ? null : reportInt(branchId),
        branchName: branch.isEmpty ? batch : branch,
        startedOn: reportText(map['StartedOn'] ?? map['startedOn']),
        endedOn: reportText(map['EndedOn'] ?? map['endedOn']),
        totalQty: reportInt(map['TotalQty'] ?? map['totalQty']),
        matchQty: reportInt(map['MatchQty'] ?? map['matchQty'] ?? map['MatchedQty']),
        unmatchQty: reportInt(map['UnmatchQty'] ?? map['unmatchQty'] ?? map['UnmatchedQty']),
      ),
    );
  }
  return sessions;
}

List<dynamic>? _sessionRows(dynamic node, [int depth = 0]) {
  if (node == null || depth > 4) return null;
  final unwrapped = _unwrap(node);
  if (unwrapped is List) {
    if (unwrapped.isEmpty) return unwrapped;
    final first = _map(unwrapped.first);
    if (first != null && _looksLikeSession(first)) return unwrapped;
    for (final item in unwrapped) {
      final found = _sessionRows(item, depth + 1);
      if (found != null && found.isNotEmpty) return found;
    }
    return null;
  }
  final map = _map(unwrapped);
  if (map == null) return null;
  for (final key in const ['Sessions', 'sessions', 'SessionList', 'sessionList', 'ScanBatches']) {
    final found = _sessionRows(map[key], depth + 1);
    if (found != null && found.isNotEmpty) return found;
  }
  if (_looksLikeSession(map)) return [map];
  return null;
}

bool _looksLikeSession(Map<String, dynamic> map) {
  for (final key in map.keys) {
    final lower = key.toLowerCase().replaceAll('_', '');
    if (lower == 'scanbatchid' || lower == 'sessionid' || lower == 'batchname' || lower == 'startedon') {
      return true;
    }
  }
  return false;
}

List<BranchSummary> parseBranchSummaries(String body) {
  try {
    final scanned = _scanBranchSummaries(body);
    if (scanned.isNotEmpty) return scanned;
  } catch (_) {}
  final decoded = decodeReportBody(body);
  final branches = _branchList(decoded);
  final summaries = <BranchSummary>[];
  for (final entry in branches) {
    final map = _map(entry);
    if (map == null) continue;
    summaries.add(
      BranchSummary(
        id: reportInt(map['BranchId'] ?? map['branchId']),
        name: reportText(map['BranchName'] ?? map['branchName']),
        total: reportInt(map['TotalInventoryItems'] ?? map['totalInventoryItems']),
        matched: reportInt(map['TotalScannedItems'] ?? map['totalScannedItems']),
        unmatched: reportInt(map['NotScannedItems'] ?? map['notScannedItems']),
      ),
    );
  }
  return summaries;
}

List<ReportTreeNode> parseReportTree(String body) {
  try {
    final scanned = _scanReportTree(body);
    if (scanned != null) return scanned;
  } catch (_) {}
  return _treeFromDecoded(decodeReportBody(body));
}

List<ReportTreeNode> _treeFromDecoded(dynamic decoded) {
  final nodes = <ReportTreeNode>[];
  for (final entry in _branchList(decoded)) {
    final map = _map(entry);
    if (map == null) continue;
    final node = _treeNode(map, 0);
    if (node != null) nodes.add(node);
  }
  return nodes;
}

ReportTreeNode? _treeNode(Map<String, dynamic> map, int level) {
  const ids = ['BranchId', 'CategoryId', 'ProductId', 'DesignId'];
  const names = ['BranchName', 'CategoryName', 'ProductName', 'DesignName'];
  const childKeys = ['Categories', 'Products', 'Designs'];
  final id = reportInt(map[ids[level]] ?? map[ids[level].toLowerCase()]);
  final name = reportText(map[names[level]] ?? map[names[level].toLowerCase()]);
  final children = <ReportTreeNode>[];
  if (level < 3) {
    final raw = _unwrap(map[childKeys[level]] ?? map[childKeys[level].toLowerCase()]);
    if (raw is List) {
      for (final entry in raw) {
        final child = _map(entry);
        if (child == null) continue;
        final node = _treeNode(child, level + 1);
        if (node != null) children.add(node);
      }
    }
  }
  if (id == 0 && name.isEmpty && children.isEmpty && !map.containsKey('TotalInventoryItems') && !map.containsKey('totalInventoryItems')) {
    return null;
  }
  return ReportTreeNode(
    id: id,
    name: name,
    total: reportInt(map['TotalInventoryItems'] ?? map['totalInventoryItems']),
    matched: reportInt(map['TotalScannedItems'] ?? map['totalScannedItems']),
    unmatched: reportInt(map['NotScannedItems'] ?? map['notScannedItems']),
    children: children,
  );
}

List<dynamic> _branchList(dynamic decoded) {
  final map = _map(_unwrap(decoded));
  if (map == null) return const [];
  final direct = _unwrap(map['Branches'] ?? map['branches']);
  if (direct is List) return direct;
  for (final key in const ['Data', 'data', 'Result', 'result']) {
    final inner = _map(_unwrap(map[key]));
    final nested = inner == null ? null : _unwrap(inner['Branches'] ?? inner['branches']);
    if (nested is List) return nested;
  }
  return const [];
}

List<ItemRow> extractBranchItems(Map<String, Object?> args) {
  final body = args['body'] as String? ?? '';
  final branchId = args['branchId'] as int? ?? 0;
  final branchName = (args['branchName'] as String? ?? '').trim();
  final type = ((args['type'] as String?) ?? 'TOTAL').toUpperCase();
  final categoryId = args['categoryId'] as int? ?? 0;
  final productId = args['productId'] as int? ?? 0;
  final designId = args['designId'] as int? ?? 0;
  try {
    final scanned = _scanBranchItems(body, branchId, branchName, type, categoryId, productId, designId);
    if (scanned != null) return scanned;
  } catch (_) {}
  final decoded = decodeReportBody(body);
  final rows = <ItemRow>[];
  for (final entry in _branchList(decoded)) {
    final branch = _map(entry);
    if (branch == null || !_sameBranch(branch, branchId, branchName)) continue;
    final categories = _unwrap(branch['Categories'] ?? branch['categories']);
    if (categories is! List) continue;
    for (final categoryEntry in categories) {
      final category = _map(categoryEntry);
      if (category == null) continue;
      if (categoryId > 0 && reportInt(category['CategoryId'] ?? category['categoryId']) != categoryId) continue;
      final products = _unwrap(category['Products'] ?? category['products']);
      if (products is! List) continue;
      for (final productEntry in products) {
        final product = _map(productEntry);
        if (product == null) continue;
        if (productId > 0 && reportInt(product['ProductId'] ?? product['productId']) != productId) continue;
        final designs = _unwrap(product['Designs'] ?? product['designs']);
        if (designs is! List) continue;
        for (final designEntry in designs) {
          final design = _map(designEntry);
          if (design == null) continue;
          if (designId > 0 && reportInt(design['DesignId'] ?? design['designId']) != designId) continue;
          final items = _unwrap(design['Items'] ?? design['items']);
          if (items is! List) continue;
          for (final itemEntry in items) {
            final item = _map(itemEntry);
            if (item == null) continue;
            final status = reportText(item['Status'] ?? item['status']);
            final statusKey = status.toLowerCase();
            if (type == 'MATCHED' && statusKey != 'matched') continue;
            if (type == 'UNMATCHED' && statusKey != 'unmatched') continue;
            rows.add(
              ItemRow(
                item: reportText(item['ItemCode'] ?? item['itemCode'] ?? item['Item']),
                rfid: reportText(item['RFIDCode'] ?? item['rfidCode'] ?? item['EPC']),
                category: reportText(item['CategoryName'] ?? item['categoryName'] ?? category['CategoryName']),
                product: reportText(item['ProductName'] ?? item['productName'] ?? product['ProductName']),
                gross: reportWeight(item['GrossWeight'] ?? item['grossWeight'] ?? item['GrossWt'] ?? item['Gwt']),
                net: reportWeight(item['NetWeight'] ?? item['netWeight'] ?? item['NetWt'] ?? item['Nwt']),
                status: status,
              ),
            );
          }
        }
      }
    }
  }
  return rows;
}

bool _sameBranch(Map<String, dynamic> branch, int branchId, String branchName) {
  final id = reportInt(branch['BranchId'] ?? branch['branchId']);
  if (branchId > 0 && id == branchId) return true;
  if (branchId <= 0 && branchName.isNotEmpty) {
    return reportText(branch['BranchName'] ?? branch['branchName']) == branchName;
  }
  return false;
}

BatchDetails parseBatchDetails(String body) {
  final decoded = decodeReportBody(body);
  final map = _detailMap(decoded);
  if (map == null) return const BatchDetails(matched: [], unmatched: []);
  return BatchDetails(
    matched: _batchRows(map['MatchedList'] ?? map['matchedList']),
    unmatched: _batchRows(map['UnmatchedList'] ?? map['unmatchedList']),
  );
}

Map<String, dynamic>? _detailMap(dynamic decoded) {
  final map = _map(_unwrap(decoded));
  if (map != null && (map.containsKey('MatchedList') || map.containsKey('matchedList'))) return map;
  final sessions = map == null ? null : _unwrap(map['Sessions'] ?? map['sessions']);
  if (sessions is List && sessions.isNotEmpty) {
    final first = _map(sessions.first);
    if (first != null) return first;
  }
  if (decoded is List && decoded.isNotEmpty) return _map(decoded.first);
  return map;
}

List<BatchRow> _batchRows(dynamic raw) {
  final list = _unwrap(raw);
  if (list is! List) return const [];
  final rows = <BatchRow>[];
  for (final entry in list) {
    final map = _map(entry);
    if (map == null) continue;
    rows.add(
      BatchRow(
        item: reportText(map['ItemCode'] ?? map['itemCode']),
        product: reportText(map['ProductName'] ?? map['productName']),
        branch: reportText(map['BranchName'] ?? map['branchName']),
        category: reportText(map['CategoryName'] ?? map['categoryName']),
        rfid: reportText(map['RFIDCode'] ?? map['rfidCode']),
      ),
    );
  }
  return rows;
}

String csvCell(String? value) {
  final text = value ?? '';
  if (text.contains(',') || text.contains('"') || text.contains('\n')) {
    return '"${text.replaceAll('"', '""')}"';
  }
  return text;
}

Future<int> writeConsolidatedCsv(Map<String, Object?> args) async {
  final body = args['body'] as String? ?? '';
  final path = args['path'] as String? ?? '';
  final branchId = args['branchId'] as int? ?? 0;
  final branchName = (args['branchName'] as String? ?? '').trim();
  final decoded = decodeReportBody(body);
  final sink = File(path).openWrite();
  sink.writeln('Branch,Item Code,RFID,TID,Category,Product,Design,Gross Weight,Net Weight,Status');
  var count = 0;
  for (final entry in _branchList(decoded)) {
    final branch = _map(entry);
    if (branch == null) continue;
    if ((branchId > 0 || branchName.isNotEmpty) && !_sameBranch(branch, branchId, branchName)) continue;
    final name = reportText(branch['BranchName'] ?? branch['branchName']);
    final categories = _unwrap(branch['Categories'] ?? branch['categories']);
    if (categories is! List) continue;
    for (final categoryEntry in categories) {
      final category = _map(categoryEntry);
      if (category == null) continue;
      final products = _unwrap(category['Products'] ?? category['products']);
      if (products is! List) continue;
      for (final productEntry in products) {
        final product = _map(productEntry);
        if (product == null) continue;
        final designs = _unwrap(product['Designs'] ?? product['designs']);
        if (designs is! List) continue;
        for (final designEntry in designs) {
          final design = _map(designEntry);
          if (design == null) continue;
          final items = _unwrap(design['Items'] ?? design['items']);
          if (items is! List) continue;
          for (final itemEntry in items) {
            final item = _map(itemEntry);
            if (item == null) continue;
            sink.writeln([
              csvCell(name),
              csvCell(reportText(item['ItemCode'] ?? item['itemCode'])),
              csvCell(reportText(item['RFIDCode'] ?? item['rfidCode'])),
              csvCell(reportText(item['TIDNumber'] ?? item['tidNumber'])),
              csvCell(reportText(item['CategoryName'] ?? category['CategoryName'])),
              csvCell(reportText(item['ProductName'] ?? product['ProductName'])),
              csvCell(reportText(item['DesignName'] ?? design['DesignName'])),
              csvCell(reportWeight(item['GrossWeight'] ?? item['grossWeight'])),
              csvCell(reportWeight(item['NetWeight'] ?? item['netWeight'])),
              csvCell(reportText(item['Status'] ?? item['status'])),
            ].join(','));
            count++;
          }
        }
      }
    }
  }
  await sink.flush();
  await sink.close();
  return count;
}

List<ReportSession> _scanSessions(String body) {
  final scan = _Scan(body);
  final sessions = <ReportSession>[];
  scan.walk((key, read) {
    if (key != 'sessions' && key != 'sessionlist' && key != 'scanbatches') return false;
    scan.readArray(() {
      final row = scan.readScalars(const {
        'scanbatchid',
        'branchid',
        'branchname',
        'batchname',
        'startedon',
        'endedon',
        'totalqty',
        'matchqty',
        'matchedqty',
        'unmatchqty',
        'unmatchedqty',
      });
      if (row.isEmpty) return;
      final branch = row['branchname'] ?? '';
      final batch = row['batchname'] ?? '';
      final branchId = row['branchid'];
      sessions.add(
        ReportSession(
          scanBatchId: row['scanbatchid'] ?? '',
          branchId: branchId == null ? null : reportInt(branchId),
          branchName: branch.isEmpty ? batch : branch,
          startedOn: row['startedon'] ?? '',
          endedOn: row['endedon'] ?? '',
          totalQty: reportInt(row['totalqty']),
          matchQty: reportInt(row['matchqty'] ?? row['matchedqty']),
          unmatchQty: reportInt(row['unmatchqty'] ?? row['unmatchedqty']),
        ),
      );
    });
    return true;
  }, 0);
  return sessions;
}

List<BranchSummary> _scanBranchSummaries(String body) {
  final scan = _Scan(body);
  final branches = <BranchSummary>[];
  scan.walk((key, read) {
    if (key != 'branches') return false;
    scan.readArray(() {
      final row = scan.readScalars(const {
        'branchid',
        'branchname',
        'totalinventoryitems',
        'totalscanneditems',
        'notscanneditems',
      });
      if (row.isEmpty) return;
      branches.add(
        BranchSummary(
          id: reportInt(row['branchid']),
          name: row['branchname'] ?? '',
          total: reportInt(row['totalinventoryitems']),
          matched: reportInt(row['totalscanneditems']),
          unmatched: reportInt(row['notscanneditems']),
        ),
      );
    });
    return true;
  }, 0);
  return branches;
}

List<ReportTreeNode>? _scanReportTree(String body) {
  final scan = _Scan(body);
  final branches = <ReportTreeNode>[];
  var saw = false;
  scan.walk((key, read) {
    if (key != 'branches') return false;
    saw = true;
    scan.readArray(() {
      final node = scan.readLevel(0);
      if (node != null) branches.add(node);
    });
    return true;
  }, 0);
  return saw ? branches : null;
}

List<ItemRow>? _scanBranchItems(
  String body,
  int branchId,
  String branchName,
  String type,
  int categoryId,
  int productId,
  int designId,
) {
  final scan = _Scan(body);
  final rows = <ItemRow>[];
  var saw = false;
  scan.walk((key, read) {
    if (key != 'branches') return false;
    saw = true;
    scan.readArray(() => scan.readBranchItems(rows, branchId, branchName, type, categoryId, productId, designId));
    return true;
  }, 0);
  return saw ? rows : null;
}

class _Scan {
  _Scan(String source) : s = source.trim() {
    if (s.isNotEmpty && s.codeUnitAt(0) == 0xFEFF) s = s.substring(1);
  }

  String s;
  int i = 0;

  int get n => s.length;

  void ws() {
    while (i < n) {
      final code = s.codeUnitAt(i);
      if (code > 32) break;
      i++;
    }
  }

  void walk(bool Function(String key, void Function()) onKey, int depth) {
    ws();
    if (i >= n || depth > 4) return;
    final code = s.codeUnitAt(i);
    if (code == 123) {
      i++;
      while (i < n) {
        ws();
        if (i < n && s.codeUnitAt(i) == 125) {
          i++;
          return;
        }
        final key = (readString() ?? '').toLowerCase();
        ws();
        if (i < n && s.codeUnitAt(i) == 58) i++;
        final taken = onKey(key, () {});
        if (!taken) {
          ws();
          if (depth < 3 && i < n && s.codeUnitAt(i) == 123) {
            walk(onKey, depth + 1);
          } else {
            skipValue();
          }
        }
        ws();
        if (i < n && s.codeUnitAt(i) == 44) i++;
      }
    }
  }

  void readArray(void Function() onItem) {
    ws();
    if (i >= n || s.codeUnitAt(i) != 91) {
      skipValue();
      return;
    }
    i++;
    while (i < n) {
      ws();
      if (i < n && s.codeUnitAt(i) == 93) {
        i++;
        return;
      }
      onItem();
      ws();
      if (i < n && s.codeUnitAt(i) == 44) i++;
    }
  }

  Map<String, String> readScalars(Set<String> keys) {
    ws();
    if (i >= n || s.codeUnitAt(i) != 123) {
      skipValue();
      return const {};
    }
    i++;
    final values = <String, String>{};
    while (i < n) {
      ws();
      if (i < n && s.codeUnitAt(i) == 125) {
        i++;
        break;
      }
      final key = (readString() ?? '').toLowerCase();
      ws();
      if (i < n && s.codeUnitAt(i) == 58) i++;
      if (keys.contains(key)) {
        values[key] = readScalar();
      } else {
        skipValue();
      }
      ws();
      if (i < n && s.codeUnitAt(i) == 44) i++;
    }
    return values;
  }

  ReportTreeNode? readLevel(int level) {
    ws();
    if (i >= n || s.codeUnitAt(i) != 123) {
      skipValue();
      return null;
    }
    i++;
    const idKeys = ['branchid', 'categoryid', 'productid', 'designid'];
    const nameKeys = ['branchname', 'categoryname', 'productname', 'designname'];
    const childKeys = ['categories', 'products', 'designs', ''];
    final idKey = idKeys[level];
    final nameKey = nameKeys[level];
    final childKey = childKeys[level];
    var id = 0;
    var name = '';
    var total = 0;
    var matched = 0;
    var unmatched = 0;
    var sawCount = false;
    final children = <ReportTreeNode>[];
    while (i < n) {
      ws();
      if (i < n && s.codeUnitAt(i) == 125) {
        i++;
        break;
      }
      final mark = i;
      final key = (readString() ?? '').toLowerCase();
      ws();
      if (i < n && s.codeUnitAt(i) == 58) i++;
      if (key == idKey) {
        id = reportInt(readScalar());
      } else if (key == nameKey) {
        name = readScalar();
      } else if (key == 'totalinventoryitems') {
        total = reportInt(readScalar());
        sawCount = true;
      } else if (key == 'totalscanneditems') {
        matched = reportInt(readScalar());
        sawCount = true;
      } else if (key == 'notscanneditems') {
        unmatched = reportInt(readScalar());
        sawCount = true;
      } else if (childKey.isNotEmpty && key == childKey) {
        readArray(() {
          final child = readLevel(level + 1);
          if (child != null) children.add(child);
        });
      } else {
        skipValue();
      }
      if (i == mark) i++;
      ws();
      if (i < n && s.codeUnitAt(i) == 44) i++;
    }
    if (id == 0 && name.isEmpty && children.isEmpty && !sawCount) return null;
    return ReportTreeNode(
      id: id,
      name: name,
      total: total,
      matched: matched,
      unmatched: unmatched,
      children: children,
    );
  }

  void readBranchItems(
    List<ItemRow> rows,
    int branchId,
    String branchName,
    String type,
    int categoryId,
    int productId,
    int designId,
  ) {
    ws();
    if (i >= n || s.codeUnitAt(i) != 123) {
      skipValue();
      return;
    }
    i++;
    var id = 0;
    var name = '';
    var sawId = false;
    var sawName = false;
    final start = rows.length;
    while (i < n) {
      ws();
      if (i < n && s.codeUnitAt(i) == 125) {
        i++;
        break;
      }
      final mark = i;
      final key = (readString() ?? '').toLowerCase();
      ws();
      if (i < n && s.codeUnitAt(i) == 58) i++;
      final matches = (!sawId && branchId <= 0) || (sawId && id == branchId) || (branchId <= 0 && sawName && name == branchName);
      if (key == 'branchid') {
        id = reportInt(readScalar());
        sawId = true;
      } else if (key == 'branchname') {
        name = readScalar();
        sawName = true;
      } else if (key == 'categories' && matches) {
        _readCategories(rows, type, categoryId, productId, designId);
      } else {
        skipValue();
      }
      if (i == mark) i++;
      ws();
      if (i < n && s.codeUnitAt(i) == 44) i++;
    }
    final keep = branchId > 0 ? id == branchId : name == branchName;
    if (!keep && rows.length > start) rows.removeRange(start, rows.length);
  }

  void _readCategories(List<ItemRow> rows, String type, int categoryId, int productId, int designId) {
    readArray(() {
      ws();
      if (i >= n || s.codeUnitAt(i) != 123) {
        skipValue();
        return;
      }
      i++;
      var id = 0;
      var sawId = false;
      var category = '';
      final start = rows.length;
      while (i < n) {
        ws();
        if (i < n && s.codeUnitAt(i) == 125) {
          i++;
          break;
        }
        final mark = i;
        final key = (readString() ?? '').toLowerCase();
        ws();
        if (i < n && s.codeUnitAt(i) == 58) i++;
        final skip = categoryId > 0 && sawId && id != categoryId;
        if (key == 'categoryid') {
          id = reportInt(readScalar());
          sawId = true;
        } else if (key == 'categoryname') {
          category = readScalar();
        } else if (key == 'products' && !skip) {
          _readProducts(rows, category, type, productId, designId);
        } else {
          skipValue();
        }
        if (i == mark) i++;
        ws();
        if (i < n && s.codeUnitAt(i) == 44) i++;
      }
      if (categoryId > 0 && id != categoryId && rows.length > start) rows.removeRange(start, rows.length);
    });
  }

  void _readProducts(List<ItemRow> rows, String category, String type, int productId, int designId) {
    readArray(() {
      ws();
      if (i >= n || s.codeUnitAt(i) != 123) {
        skipValue();
        return;
      }
      i++;
      var id = 0;
      var sawId = false;
      var product = '';
      final start = rows.length;
      while (i < n) {
        ws();
        if (i < n && s.codeUnitAt(i) == 125) {
          i++;
          break;
        }
        final mark = i;
        final key = (readString() ?? '').toLowerCase();
        ws();
        if (i < n && s.codeUnitAt(i) == 58) i++;
        final skip = productId > 0 && sawId && id != productId;
        if (key == 'productid') {
          id = reportInt(readScalar());
          sawId = true;
        } else if (key == 'productname') {
          product = readScalar();
        } else if (key == 'designs' && !skip) {
          _readDesigns(rows, category, product, type, designId);
        } else {
          skipValue();
        }
        if (i == mark) i++;
        ws();
        if (i < n && s.codeUnitAt(i) == 44) i++;
      }
      if (productId > 0 && id != productId && rows.length > start) rows.removeRange(start, rows.length);
    });
  }

  void _readDesigns(List<ItemRow> rows, String category, String product, String type, int designId) {
    readArray(() {
      ws();
      if (i >= n || s.codeUnitAt(i) != 123) {
        skipValue();
        return;
      }
      i++;
      var id = 0;
      var sawId = false;
      final start = rows.length;
      while (i < n) {
        ws();
        if (i < n && s.codeUnitAt(i) == 125) {
          i++;
          break;
        }
        final mark = i;
        final key = (readString() ?? '').toLowerCase();
        ws();
        if (i < n && s.codeUnitAt(i) == 58) i++;
        final skip = designId > 0 && sawId && id != designId;
        if (key == 'designid') {
          id = reportInt(readScalar());
          sawId = true;
        } else if (key == 'items' && !skip) {
          _readItems(rows, category, product, type);
        } else {
          skipValue();
        }
        if (i == mark) i++;
        ws();
        if (i < n && s.codeUnitAt(i) == 44) i++;
      }
      if (designId > 0 && id != designId && rows.length > start) rows.removeRange(start, rows.length);
    });
  }

  void _readItems(List<ItemRow> rows, String category, String product, String type) {
    readArray(() {
      final row = readScalars(const {
        'itemcode',
        'item',
        'rfidcode',
        'epc',
        'categoryname',
        'productname',
        'grossweight',
        'grosswt',
        'gwt',
        'netweight',
        'netwt',
        'nwt',
        'status',
      });
      if (row.isEmpty) return;
      final status = row['status'] ?? '';
      final statusKey = status.toLowerCase();
      if (type == 'MATCHED' && statusKey != 'matched') return;
      if (type == 'UNMATCHED' && statusKey != 'unmatched') return;
      final ownCategory = row['categoryname'] ?? '';
      final ownProduct = row['productname'] ?? '';
      rows.add(
        ItemRow(
          item: row['itemcode'] ?? row['item'] ?? '',
          rfid: row['rfidcode'] ?? row['epc'] ?? '',
          category: ownCategory.isEmpty ? category : ownCategory,
          product: ownProduct.isEmpty ? product : ownProduct,
          gross: reportWeight(row['grossweight'] ?? row['grosswt'] ?? row['gwt']),
          net: reportWeight(row['netweight'] ?? row['netwt'] ?? row['nwt']),
          status: status,
        ),
      );
    });
  }

  String readScalar() {
    ws();
    if (i >= n) return '';
    final code = s.codeUnitAt(i);
    if (code == 34) return readString() ?? '';
    if (code == 123 || code == 91) {
      skipValue();
      return '';
    }
    final start = i;
    skipValue();
    return s.substring(start, i).trim();
  }

  String? readString() {
    ws();
    if (i >= n || s.codeUnitAt(i) != 34) return null;
    i++;
    final out = StringBuffer();
    while (i < n) {
      final code = s.codeUnitAt(i);
      if (code == 34) {
        i++;
        return out.toString();
      }
      if (code == 92 && i + 1 < n) {
        final next = s.codeUnitAt(++i);
        if (next == 117 && i + 4 < n) {
          out.writeCharCode(int.parse(s.substring(i + 1, i + 5), radix: 16));
          i += 5;
          continue;
        }
        out.writeCharCode(next == 110 ? 10 : next == 114 ? 13 : next == 116 ? 9 : next);
        i++;
        continue;
      }
      out.writeCharCode(code);
      i++;
    }
    return out.toString();
  }

  void skipValue() {
    ws();
    if (i >= n) return;
    final code = s.codeUnitAt(i);
    if (code == 34) {
      readString();
      return;
    }
    if (code == 123 || code == 91) {
      final open = code;
      final close = code == 123 ? 125 : 93;
      var depth = 0;
      var inString = false;
      var escaped = false;
      while (i < n) {
        final current = s.codeUnitAt(i);
        i++;
        if (inString) {
          if (escaped) {
            escaped = false;
          } else if (current == 92) {
            escaped = true;
          } else if (current == 34) {
            inString = false;
          }
          continue;
        }
        if (current == 34) {
          inString = true;
        } else if (current == open) {
          depth++;
        } else if (current == close) {
          depth--;
          if (depth == 0) return;
        }
      }
      return;
    }
    if (code == 116) {
      i += 4;
      return;
    }
    if (code == 102) {
      i += 5;
      return;
    }
    if (code == 110) {
      i += 4;
      return;
    }
    while (i < n) {
      final current = s.codeUnitAt(i);
      final number = (current >= 48 && current <= 57) || current == 45 || current == 43 || current == 46 || current == 101 || current == 69;
      if (!number) break;
      i++;
    }
  }
}
