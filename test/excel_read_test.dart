import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sparkle_rfid_plus/features/desktop/data/desktop_scan_excel.dart';
import 'package:sparkle_rfid_plus/features/products/data/product_sheet_import.dart';

void main() {
  test('reads inline xlsx cells and keeps blank RFID blank', () {
    final bytes = buildDesktopWorkbook([
      ['Item Code', 'RFID', 'Gross Weight'],
      ['A1', '', '1.5'],
    ]);
    final table = parseExcelTable(bytes);
    expect(table.headers, ['Item Code', 'RFID', 'Gross Weight']);
    expect(table.rows, [
      {'Item Code': 'A1', 'RFID': '', 'Gross Weight': '1.5'},
    ]);
  });

  test('reads shared strings and skips empty columns', () {
    final table = parseExcelTable(_sharedWorkbook());
    expect(table.headers, ['Item Code', 'Category']);
    expect(table.rows, [
      {'Item Code': 'RG1', 'Category': 'Ring'},
    ]);
  });
}

List<int> _sharedWorkbook() {
  final archive = Archive();
  void add(String name, String text) {
    final bytes = utf8.encode(text);
    archive.addFile(ArchiveFile(name, bytes.length, bytes));
  }

  add('xl/sharedStrings.xml', '''
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<sst xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">
  <si><t>Item Code</t></si>
  <si><t>Category</t></si>
  <si><t>RG1</t></si>
  <si><r><t>Ri</t></r><r><t>ng</t></r></si>
</sst>
''');
  add('xl/_rels/workbook.xml.rels', '''
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
  <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet1.xml"/>
</Relationships>
''');
  add('xl/worksheets/sheet1.xml', '''
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">
  <sheetData>
    <row r="1"><c r="A1" t="s"><v>0</v></c><c r="C1" t="s"><v>1</v></c></row>
    <row r="2"><c r="A2" t="s"><v>2</v></c><c r="C2" t="s"><v>3</v></c></row>
  </sheetData>
</worksheet>
''');
  return ZipEncoder().encode(archive);
}
