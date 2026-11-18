import 'package:flutter_test/flutter_test.dart';
import 'package:sparkle_rfid_plus/features/reports/data/stock_report_parse.dart';

void main() {
  test('summary skips nested items', () {
    final body = '''
{"Branches":[{"BranchId":2,"BranchName":"Pune","TotalInventoryItems":797,"TotalScannedItems":0,"NotScannedItems":797,"Categories":[{"CategoryName":"Gold","Products":[{"ProductName":"Ring","Designs":[{"Items":[{"ItemCode":"A","RFIDCode":"E1","GrossWeight":1.2,"NetWeight":1,"Status":"Unmatched"}]}]}]}]}]}
''';
    final rows = parseBranchSummaries(body);
    expect(rows, hasLength(1));
    expect(rows.first.name, 'Pune');
    expect(rows.first.total, 797);
    expect(rows.first.matched, 0);
    expect(rows.first.unmatched, 797);
  });

  test('branch items keep only the opened branch', () {
    final body = '''
{"Branches":[
 {"BranchId":1,"BranchName":"Baner","Categories":[{"CategoryName":"Gold","Products":[{"ProductName":"Ring","Designs":[{"Items":[{"ItemCode":"B1","RFIDCode":"R1","GrossWeight":3,"NetWeight":2.5,"Status":"Matched"}]}]}]}]},
 {"BranchId":2,"BranchName":"Pune","Categories":[{"CategoryName":"Tops","Products":[{"ProductName":"Chain","Designs":[{"Items":[{"ItemCode":"P1","RFIDCode":"R2","GrossWeight":0.25,"NetWeight":0.2,"Status":"Unmatched"}]}]}]}]}
]}
''';
    final rows = extractBranchItems({'body': body, 'branchId': 2, 'branchName': 'Pune', 'type': 'TOTAL'});
    expect(rows, hasLength(1));
    expect(rows.first.item, 'P1');
    expect(rows.first.category, 'Tops');
    expect(rows.first.product, 'Chain');
    expect(rows.first.gross, '0.25');
    expect(rows.first.net, '0.20');
    expect(rows.first.status, 'Unmatched');
  });

  test('sessions skip embedded lists', () {
    final body = '''
{"Sessions":[{"ScanBatchId":"ab","BranchId":4,"BranchName":"Main Branch","StartedOn":"2026-11-10T09:15:00","EndedOn":"2026-11-10T09:16:00","TotalQty":865,"MatchQty":10,"UnmatchQty":20,"MatchedList":[{"ItemCode":"X"}]}]}
''';
    final rows = parseSessions(body);
    expect(rows, hasLength(1));
    expect(rows.first.scanBatchId, 'ab');
    expect(rows.first.branchName, 'Main Branch');
    expect(rows.first.totalQty, 865);
    expect(rows.first.matchQty, 10);
    expect(rows.first.unmatchQty, 20);
  });

  test('tree keeps category product design and skips items', () {
    final body = '''
{"Branches":[{"BranchId":2,"BranchName":"Pune","TotalInventoryItems":3,"TotalScannedItems":1,"NotScannedItems":2,"Categories":[
 {"CategoryId":8,"CategoryName":"Gold","TotalInventoryItems":2,"TotalScannedItems":1,"NotScannedItems":1,"Products":[
  {"ProductId":4,"ProductName":"Ring","TotalInventoryItems":2,"TotalScannedItems":1,"NotScannedItems":1,"Designs":[
   {"DesignId":6,"DesignName":"Classic","TotalInventoryItems":2,"TotalScannedItems":1,"NotScannedItems":1,"Items":[{"ItemCode":"A","Status":"Matched"},{"ItemCode":"B","Status":"Unmatched"}]}
  ]}
 ]},
 {"CategoryId":9,"CategoryName":"Tops","TotalInventoryItems":1,"TotalScannedItems":0,"NotScannedItems":1,"Products":[
  {"ProductId":5,"ProductName":"Chain","TotalInventoryItems":1,"TotalScannedItems":0,"NotScannedItems":1,"Designs":[
   {"DesignId":7,"DesignName":"Light","TotalInventoryItems":1,"TotalScannedItems":0,"NotScannedItems":1,"Items":[{"ItemCode":"C","Status":"Unmatched"}]}
  ]}
 ]}
]}]}
''';
    final tree = parseReportTree(body);
    expect(tree, hasLength(1));
    expect(tree.first.children, hasLength(2));
    expect(tree.first.children.first.name, 'Gold');
    expect(tree.first.children.first.children.single.name, 'Ring');
    expect(tree.first.children.first.children.single.children.single.name, 'Classic');
    final matched = extractBranchItems({
      'body': body,
      'branchId': 2,
      'branchName': 'Pune',
      'categoryId': 8,
      'productId': 4,
      'designId': 6,
      'type': 'MATCHED',
    });
    expect(matched, hasLength(1));
    expect(matched.single.item, 'A');
    final unmatched = extractBranchItems({
      'body': body,
      'branchId': 2,
      'branchName': 'Pune',
      'categoryId': 9,
      'type': 'UNMATCHED',
    });
    expect(unmatched, hasLength(1));
    expect(unmatched.single.item, 'C');
  });

  test('10k item scan stays quick', () {
    final items = StringBuffer();
    for (var i = 0; i < 10000; i++) {
      if (i > 0) items.write(',');
      items.write('{"ItemCode":"I$i","RFIDCode":"E$i","GrossWeight":1.25,"NetWeight":1,"Status":"Matched"}');
    }
    final body = '{"Branches":[{"BranchId":9,"BranchName":"Pune","TotalInventoryItems":10000,"TotalScannedItems":10000,"NotScannedItems":0,"Categories":[{"CategoryName":"Gold","Products":[{"ProductName":"Ring","Designs":[{"Items":[${items.toString()}]}]}]}]}]}';
    final watch = Stopwatch()..start();
    final summary = parseBranchSummaries(body);
    final listed = extractBranchItems({'body': body, 'branchId': 9, 'branchName': 'Pune', 'type': 'TOTAL'});
    watch.stop();
    expect(summary.single.total, 10000);
    expect(listed, hasLength(10000));
    expect(watch.elapsedMilliseconds, lessThan(1000));
  });
}
