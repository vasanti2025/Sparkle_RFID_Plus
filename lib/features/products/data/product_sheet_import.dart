import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:csv/csv.dart';
import 'package:flutter/foundation.dart';
import 'package:xml/xml.dart';

/// Same field keys and order as the reference Import Excel mapping.
const importFieldKeys = [
  'itemCode',
  'rfid',
  'grossWeight',
  'stoneWeight',
  'diamondWeight',
  'netWeight',
  'counterName',
  'category',
  'productName',
  'branchName',
  'design',
  'purity',
  'makingPerGram',
  'makingPercent',
  'fixMaking',
  'fixWastage',
  'stoneAmount',
  'diamondAmount',
  'sku',
  'vendor',
  'boxName',
];

const importFieldLabels = {
  'itemCode': 'Item Code',
  'rfid': 'RFID',
  'grossWeight': 'Gross Weight',
  'stoneWeight': 'Stone Weight',
  'diamondWeight': 'Diamond Weight',
  'netWeight': 'Net Weight',
  'counterName': 'Counter Name',
  'category': 'Category',
  'productName': 'Product Name',
  'branchName': 'Branch Name',
  'design': 'Design',
  'purity': 'Purity',
  'makingPerGram': 'Making/Gram',
  'makingPercent': 'Making %',
  'fixMaking': 'Fix Making',
  'fixWastage': 'Fix Wastage',
  'stoneAmount': 'Stone Amount',
  'diamondAmount': 'Diamond Amount',
  'sku': 'SKU',
  'vendor': 'Vendor',
  'boxName': 'Box Name',
};

class SheetTable {
  const SheetTable({required this.headers, required this.rows});

  final List<String> headers;
  final List<Map<String, String>> rows;
}

SheetTable parseExcelTable(List<int> bytes) {
  try {
    final archive = ZipDecoder().decodeBytes(bytes);
    final shared = _sharedStrings(archive);
    final sheetName = _firstSheetName(archive);
    if (sheetName == null) return const SheetTable(headers: [], rows: []);
    final sheet = _zipText(archive, sheetName);
    if (sheet == null || sheet.isEmpty) return const SheetTable(headers: [], rows: []);
    final grid = _sheetGrid(sheet, shared);
    if (grid.isEmpty) return const SheetTable(headers: [], rows: []);
    final headerColumns = grid.first.keys.toList()..sort();
    final headers = <String>[];
    final indexes = <int>[];
    for (final index in headerColumns) {
      final text = grid.first[index] ?? '';
      if (text.isEmpty) continue;
      headers.add(text);
      indexes.add(index);
    }
    final rows = <Map<String, String>>[];
    for (var r = 1; r < grid.length; r++) {
      final row = grid[r];
      final map = <String, String>{};
      var any = false;
      for (var c = 0; c < headers.length; c++) {
        final value = row[indexes[c]] ?? '';
        if (value.isNotEmpty) any = true;
        map[headers[c]] = value;
      }
      if (any) rows.add(map);
    }
    return SheetTable(headers: headers, rows: rows);
  } catch (_) {
    return const SheetTable(headers: [], rows: []);
  }
}

Future<SheetTable> parseExcelTableAsync(List<int> bytes) => compute(parseExcelTable, bytes);

SheetTable parseCsvTable(String text) {
  if (text.trim().isEmpty) return const SheetTable(headers: [], rows: []);
  final grid = const CsvToListConverter(shouldParseNumbers: false).convert(text);
  if (grid.isEmpty) return const SheetTable(headers: [], rows: []);
  final headers = grid.first.map((cell) => cell.toString().trim()).where((cell) => cell.isNotEmpty).toList();
  final rows = <Map<String, String>>[];
  for (var r = 1; r < grid.length; r++) {
    final row = grid[r];
    final map = <String, String>{};
    var any = false;
    for (var c = 0; c < headers.length; c++) {
      final value = c < row.length ? row[c].toString().trim() : '';
      if (value.isNotEmpty) any = true;
      map[headers[c]] = value;
    }
    if (any) rows.add(map);
  }
  return SheetTable(headers: headers, rows: rows);
}

class ImportBuild {
  const ImportBuild({required this.items, required this.total, required this.failed});

  final List<Map<String, dynamic>> items;
  final int total;
  final List<String> failed;
}

ImportBuild buildImportedItems(Map<String, Object?> args) {
  final rows = (args['rows'] as List).cast<Map<String, String>>();
  final mapping = (args['mapping'] as Map).map((key, value) => MapEntry(key.toString(), value.toString()));
  final rfidMap = (args['rfid'] as Map).map((key, value) => MapEntry(key.toString(), value.toString()));
  final columns = <String, String>{};
  for (final entry in mapping.entries) {
    final field = entry.key.trim().toLowerCase();
    final column = entry.value.trim();
    if (field.isEmpty || column.isEmpty) continue;
    columns[field] = column;
  }

  String cell(Map<String, String> row, String field) {
    final column = columns[field];
    if (column == null || column.isEmpty) return '';
    return row[column]?.trim() ?? '';
  }

  final items = <Map<String, dynamic>>[];
  final failed = <String>[];
  for (var index = 0; index < rows.length; index++) {
    try {
      final row = rows[index];
      final itemCode = cell(row, 'itemcode');
      final rfid = cell(row, 'rfid');
      var epc = syncRfid(rfid, rfidMap);
      if (epc.isEmpty && rfid.isEmpty && itemCode.isNotEmpty) epc = stringToHex(itemCode);
      if (itemCode.isEmpty && epc.isEmpty) continue;
      items.add({
        'CategoryName': cell(row, 'category'),
        'ProductName': cell(row, 'productname'),
        'DesignName': cell(row, 'design'),
        'ItemCode': itemCode,
        'RFIDCode': rfid,
        'GrossWeight': cell(row, 'grossweight'),
        'TotalStoneWeight': cell(row, 'stoneweight'),
        'TotalDiamondWeight': cell(row, 'diamondweight'),
        'NetWeight': cell(row, 'netweight'),
        'PurityName': cell(row, 'purity'),
        'MakingPerGram': cell(row, 'makingpergram'),
        'MakingPercentage': cell(row, 'makingpercent'),
        'MakingFixedAmt': cell(row, 'fixmaking'),
        'MakingFixedWastage': cell(row, 'fixwastage'),
        'TotalStoneAmount': cell(row, 'stoneamount'),
        'TotalDiamondAmount': cell(row, 'diamondamount'),
        'SKU': cell(row, 'sku'),
        'EPC': epc,
        'VendorName': cell(row, 'vendor'),
        'TIDNumber': epc,
        'BoxName': cell(row, 'boxname'),
        'CounterName': cell(row, 'countername'),
        'BranchName': cell(row, 'branchname'),
      });
    } catch (_) {
      failed.add('Row ${index + 2}');
    }
  }
  return ImportBuild(items: items, total: rows.length, failed: failed);
}

String syncRfid(String rfid, Map<String, String> rfidMap) {
  final key = rfid.trim().toUpperCase();
  if (key.isEmpty) return '';
  return rfidMap[key] ?? '';
}

String stringToHex(String value) {
  final hex = utf8.encode(value.trim()).map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();
  final padded = ((hex.length + 3) ~/ 4) * 4;
  return hex.padLeft(padded, '0').toUpperCase();
}

String? sheetIdFrom(String input) {
  final text = input.trim();
  if (text.isEmpty) return null;
  final match = RegExp(r'/spreadsheets/d/([a-zA-Z0-9-_]+)').firstMatch(text);
  if (match != null) return match.group(1);
  if (!text.contains('/') && text.length > 20) return text;
  return null;
}

String sheetCsvUrl(String sheetId) => 'https://docs.google.com/spreadsheets/d/$sheetId/export?format=csv';

String? _zipText(Archive archive, String name) {
  final want = name.replaceAll('\\', '/').toLowerCase();
  for (final file in archive.files) {
    if (file.name.replaceAll('\\', '/').toLowerCase() != want) continue;
    final data = file.readBytes();
    if (data == null || data.isEmpty) return '';
    return utf8.decode(data, allowMalformed: true);
  }
  return null;
}

String? _firstSheetName(Archive archive) {
  final rels = _zipText(archive, 'xl/_rels/workbook.xml.rels');
  if (rels != null && rels.isNotEmpty) {
    final document = XmlDocument.parse(rels);
    for (final node in document.descendants.whereType<XmlElement>()) {
      if (node.name.local != 'Relationship') continue;
      final type = node.getAttribute('Type') ?? '';
      if (!type.contains('/worksheet')) continue;
      final target = (node.getAttribute('Target') ?? '').replaceAll('\\', '/');
      if (target.isEmpty) continue;
      if (target.startsWith('/')) return target.substring(1);
      if (target.startsWith('xl/')) return target;
      return 'xl/${target.replaceFirst(RegExp(r'^\./'), '')}';
    }
  }
  final sheets = archive.files.map((file) => file.name.replaceAll('\\', '/')).where((name) => RegExp(r'^xl/worksheets/sheet\d+\.xml$', caseSensitive: false).hasMatch(name)).toList()..sort();
  return sheets.isEmpty ? null : sheets.first;
}

List<String> _sharedStrings(Archive archive) {
  final xml = _zipText(archive, 'xl/sharedStrings.xml');
  if (xml == null || xml.isEmpty) return const [];
  final document = XmlDocument.parse(xml);
  final values = <String>[];
  for (final node in document.descendants.whereType<XmlElement>()) {
    final parent = node.parent;
    if (node.name.local != 'si' || parent is! XmlElement || parent.name.local != 'sst') continue;
    values.add(_sharedText(node));
  }
  return values;
}

String _sharedText(XmlElement item) {
  final runs = item.childElements.where((node) => node.name.local == 'r');
  if (runs.isNotEmpty) {
    return runs.map((run) => run.childElements.where((node) => node.name.local == 't').map((node) => node.innerText).join()).join();
  }
  return item.childElements.where((node) => node.name.local == 't').map((node) => node.innerText).join();
}

List<Map<int, String>> _sheetGrid(String xml, List<String> shared) {
  final document = XmlDocument.parse(xml);
  final grid = <Map<int, String>>[];
  for (final row in document.descendants.whereType<XmlElement>()) {
    final parent = row.parent;
    if (row.name.local != 'row' || parent is! XmlElement || parent.name.local != 'sheetData') continue;
    final cells = <int, String>{};
    var next = 0;
    for (final cell in row.childElements) {
      if (cell.name.local != 'c') continue;
      final index = _columnIndex(cell.getAttribute('r'));
      final column = index < 0 ? next : index;
      next = column + 1;
      final value = _cellText(cell, shared).trim();
      if (value.isNotEmpty) cells[column] = value;
    }
    grid.add(cells);
  }
  return grid;
}

int _columnIndex(String? reference) {
  if (reference == null || reference.isEmpty) return -1;
  var number = 0;
  var seen = false;
  for (final code in reference.codeUnits) {
    final upper = code >= 97 && code <= 122 ? code - 32 : code;
    if (upper < 65 || upper > 90) break;
    seen = true;
    number = number * 26 + (upper - 64);
  }
  return seen ? number - 1 : -1;
}

String _cellText(XmlElement cell, List<String> shared) {
  final type = cell.getAttribute('t') ?? '';
  if (type == 'inlineStr') {
    final buffer = StringBuffer();
    for (final node in cell.descendants.whereType<XmlElement>()) {
      if (node.name.local == 't') buffer.write(node.innerText);
    }
    return buffer.toString();
  }
  var raw = '';
  for (final node in cell.childElements) {
    if (node.name.local == 'v') raw = node.innerText;
  }
  if (type == 's') {
    final index = int.tryParse(raw);
    if (index == null || index < 0 || index >= shared.length) return '';
    return shared[index];
  }
  return raw;
}
