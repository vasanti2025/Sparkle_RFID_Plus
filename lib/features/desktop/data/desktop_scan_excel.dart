import 'dart:convert';

import 'package:archive/archive.dart';

/// Builds a small xlsx without keeping a spreadsheet model in memory.
List<int> buildDesktopWorkbook(List<List<String>> rows) {
  final sheet = StringBuffer()
    ..write('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>')
    ..write('<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><sheetData>');
  for (var index = 0; index < rows.length; index++) {
    final rowNumber = index + 1;
    sheet.write('<row r="$rowNumber">');
    final cells = rows[index];
    for (var column = 0; column < cells.length; column++) {
      final letter = String.fromCharCode(65 + column);
      sheet
        ..write('<c r="$letter$rowNumber" t="inlineStr"><is><t xml:space="preserve">')
        ..write(_xml(cells[column]))
        ..write('</t></is></c>');
    }
    sheet.write('</row>');
  }
  sheet.write('</sheetData></worksheet>');

  final archive = Archive();
  _add(archive, '[Content_Types].xml', _contentTypes);
  _add(archive, '_rels/.rels', _rootRels);
  _add(archive, 'xl/workbook.xml', _workbook);
  _add(archive, 'xl/_rels/workbook.xml.rels', _workbookRels);
  _add(archive, 'xl/worksheets/sheet1.xml', sheet.toString());
  return ZipEncoder().encode(archive);
}

void _add(Archive archive, String name, String text) {
  final bytes = utf8.encode(text);
  archive.addFile(ArchiveFile(name, bytes.length, bytes));
}

String _xml(String value) {
  return value
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;');
}

const _contentTypes = '''
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
  <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
  <Default Extension="xml" ContentType="application/xml"/>
  <Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>
  <Override PartName="/xl/worksheets/sheet1.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>
</Types>
''';

const _rootRels = '''
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
  <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/>
</Relationships>
''';

const _workbook = '''
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">
  <sheets><sheet name="Scans" sheetId="1" r:id="rId1"/></sheets>
</workbook>
''';

const _workbookRels = '''
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
  <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet1.xml"/>
</Relationships>
''';
