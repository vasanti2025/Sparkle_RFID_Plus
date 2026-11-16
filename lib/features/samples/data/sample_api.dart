import '../../../core/constants/app_constants.dart';
import '../../../core/di/injection.dart';
import '../../../core/network/api_client.dart';
import '../../../core/session/app_session.dart';
import '../../inventory/data/inventory_stock.dart';
import '../../inventory/domain/inventory_catalog.dart';
import '../../products/domain/entities/stored_record.dart';

class SampleOutRecord {
  const SampleOutRecord({
    required this.id,
    required this.number,
    required this.customerId,
    required this.customerName,
    required this.date,
    required this.returnDate,
    required this.description,
    required this.status,
    required this.items,
  });

  final int id;
  final String number;
  final int customerId;
  final String customerName;
  final String date;
  final String returnDate;
  final String description;
  final String status;
  final List<Map<String, dynamic>> items;

  bool get open {
    final value = status.toLowerCase().replaceAll(' ', '');
    return value.isEmpty || value == 'sampleout';
  }
}

class SampleInRecord {
  const SampleInRecord({
    required this.itemCode,
    required this.name,
    required this.sampleOutNo,
    required this.customerName,
    required this.date,
    required this.gross,
  });

  final String itemCode;
  final String name;
  final String sampleOutNo;
  final String customerName;
  final String date;
  final String gross;
}

class SampleApi {
  SampleApi({ApiClient? client}) : _api = client ?? ApiClient();

  final ApiClient _api;

  int get _branch {
    if (AppSession.branchNo > 0) return AppSession.branchNo;
    if (AppSession.branchId > 0) return AppSession.branchId;
    return 1;
  }

  Future<List<SampleOutRecord>> sampleOuts() async {
    final body = await _api.post(AppConstants.allSampleOut, {
      'ClientCode': AppSession.clientCode,
      'SampleStatus': 'SampleOut',
    });
    return [
      for (final row in _rows(body)) _out(row),
    ].where((record) => record.number.isNotEmpty).toList();
  }

  Future<List<SampleInRecord>> sampleIns() async {
    final body = await _api.post(AppConstants.allSampleIn, {
      'ClientCode': AppSession.clientCode,
      'SampleStatus': 'SampleIn',
    });
    return [
      for (final row in _rows(body))
        SampleInRecord(
          itemCode: '${row['ItemCode'] ?? ''}'.trim(),
          name: '${row['ProductName'] ?? ''}'.trim(),
          sampleOutNo: '${row['SampleOutNo'] ?? ''}'.trim(),
          customerName: _customerName(row),
          date: '${row['SampleInDate'] ?? row['CreatedOn'] ?? ''}'.trim(),
          gross: '${row['GrossWt'] ?? row['TotalWt'] ?? ''}'.trim(),
        ),
    ];
  }

  Future<String?> saveOut({
    required int customerId,
    required String customerName,
    required String returnDate,
    required String description,
    required List<InventoryPiece> pieces,
  }) async {
    if (AppSession.clientCode.isEmpty) return 'Sign in to save a sample out.';
    if (customerId <= 0) return 'Choose a customer';
    if (pieces.isEmpty) return 'Select at least one piece.';
    final last = await _lastNumber();
    final number = _nextNumber(last);
    final today = _day(DateTime.now());
    final items = <Map<String, dynamic>>[];
    for (final piece in pieces) {
      items.add(await _issue(piece, number: number, customerId: customerId, customerName: customerName, status: 'SampleOut'));
    }
    final response = await _api.post(AppConstants.addSampleOut, {
      'ClientCode': AppSession.clientCode,
      'BranchId': _branch,
      'CustomerId': customerId,
      'SampleOutNo': number,
      'ReturnDate': returnDate.isEmpty ? today : returnDate,
      'Description': description,
      'Date': today,
      'SampleStatus': 'SampleOut',
      'Quantity': items.length,
      'TotalDiamondWeight': '0',
      'TotalGrossWt': _sum(pieces, (piece) => piece.milligrams),
      'TotalNetWt': _sum(pieces, (piece) => piece.netMilligrams ?? 0),
      'TotalStoneWeight': '0',
      'TotalWt': _sum(pieces, (piece) => piece.milligrams),
      'IssueItems': items,
    });
    if (response is Map && (response['success'] == false || response['Success'] == false)) {
      return 'Failed to save sample out';
    }
    await InventoryStock.instance.dropPieces(pieces.map((piece) => piece.id));
    return null;
  }

  Future<String?> saveIn({
    required SampleOutRecord record,
    required Set<String> returnedCodes,
  }) async {
    if (returnedCodes.isEmpty) return 'Scan or tick the pieces coming back.';
    final today = DateTime.now().toUtc().toIso8601String();
    final returned = returnedCodes.map(_norm).toSet();
    final items = [
      for (final issue in record.items)
        _returnedIssue(
          issue,
          record: record,
          status: returned.contains(_norm('${issue['ItemCode']}')) ? 'SampleIn' : 'SampleOut',
          sampleInDate: today,
        ),
    ];
    final allBack = items.isNotEmpty && items.every((item) => item['SampleStatus'] == 'SampleIn');
    final response = await _api.post(AppConstants.updateSampleOut, {
      'Id': record.id,
      'ClientCode': AppSession.clientCode,
      'BranchId': _branch,
      'CustomerId': record.customerId,
      'SampleOutNo': record.number,
      'ReturnDate': record.returnDate,
      'Description': record.description,
      'Date': record.date,
      'SampleStatus': allBack ? 'SampleIn' : 'SampleOut',
      'Quantity': items.length,
      'TotalGrossWt': _sumMaps(record.items, 'GrossWt'),
      'TotalNetWt': _sumMaps(record.items, 'NetWt'),
      'TotalStoneWeight': _sumMaps(record.items, 'StoneWeight'),
      'TotalDiamondWeight': _sumMaps(record.items, 'DiamondWeight'),
      'TotalWt': _sumMaps(record.items, 'TotalWt'),
      'StatusType': true,
      'SampleInDate': today,
      'IssueItems': items,
    });
    if (response is Map && (response['success'] == false || response['Success'] == false)) {
      return 'Failed to save sample in';
    }
    return null;
  }

  Future<String?> _lastNumber() async {
    final body = await _api.post(AppConstants.lastSampleOutNo, {
      'ClientCode': AppSession.clientCode,
      'BranchId': _branch,
    });
    if (body is String) return body;
    if (body is Map) {
      final value = body['SampleOutNo'] ?? body['sampleOutNo'] ?? body['data'] ?? body['Data'];
      if (value != null) return value.toString();
    }
    return body?.toString();
  }

  Future<Map<String, dynamic>> _issue(
    InventoryPiece piece, {
    required String number,
    required int customerId,
    required String customerName,
    required String status,
  }) async {
    final payload = await _payload(piece.id);
    String text(List<String> keys, [String fallback = '']) {
      for (final key in keys) {
        final value = payload[key]?.toString().trim();
        if (value != null && value.isNotEmpty && value.toLowerCase() != 'null') return value;
      }
      return fallback;
    }

    int numberOf(List<String> keys) => int.tryParse(text(keys)) ?? 0;
    final gross = text(const ['GrossWt', 'grossWt'], (piece.milligrams / 1000).toStringAsFixed(3));
    final net = text(const ['NetWt', 'netWt'], ((piece.netMilligrams ?? 0) / 1000).toStringAsFixed(3));
    final now = DateTime.now().toUtc().toIso8601String();
    return {
      'ItemCode': piece.id,
      'SKU': text(const ['SKU', 'Sku']),
      'SKUId': numberOf(const ['SKUId', 'SkuId']),
      'CategoryId': numberOf(const ['CategoryId']),
      'ProductId': numberOf(const ['ProductId']),
      'DesignId': numberOf(const ['DesignId']),
      'PurityId': numberOf(const ['PurityId']),
      'Quantity': 1,
      'GrossWt': gross,
      'NetWt': net,
      'TotalWt': text(const ['TotalWt'], gross),
      'FinePercentage': text(const ['FinePercentage'], '0'),
      'WastegePercentage': text(const ['WastegePercentage'], '0'),
      'StoneWeight': text(const ['StoneWeight'], '0'),
      'DiamondWeight': text(const ['DiamondWeight'], '0'),
      'FineWastageWt': text(const ['FineWastageWt'], '0'),
      'RatePerGram': text(const ['RatePerGram'], '0'),
      'MetalAmount': text(const ['MetalAmount'], '0'),
      'Description': text(const ['Description']),
      'SampleStatus': status,
      'ClientCode': AppSession.clientCode,
      'StoneAmount': text(const ['StoneAmount'], '0'),
      'SampleOutNo': number,
      'DiamondAmount': text(const ['DiamondAmount'], '0'),
      'Pieces': text(const ['Pieces'], '1'),
      'CategoryName': text(const ['CategoryName'], piece.category ?? ''),
      'ProductName': text(const ['ProductName'], piece.name),
      'PurityName': text(const ['PurityName'], piece.purity ?? ''),
      'DesignName': text(const ['DesignName'], piece.design ?? ''),
      'Id': 0,
      'CustomerId': customerId,
      'VendorId': 0,
      'BranchId': _branch,
      'LabelledStockId': piece.stockId,
      'CustomerName': customerName,
      'SampleInDate': now,
      'CreatedOn': now,
      'Customer': null,
      'RFIDCode': piece.rfid ?? '',
      'TIDNumber': piece.tid ?? '',
      'StatusType': true,
    };
  }

  Map<String, dynamic> _returnedIssue(
    Map<String, dynamic> issue, {
    required SampleOutRecord record,
    required String status,
    required String sampleInDate,
  }) {
    int asInt(Object? value) => value is num ? value.toInt() : int.tryParse('$value') ?? 0;
    return {
      'ItemCode': issue['ItemCode']?.toString() ?? '',
      'SKU': issue['SKU']?.toString() ?? '',
      'SKUId': asInt(issue['SKUId']),
      'CategoryId': asInt(issue['CategoryId']),
      'ProductId': asInt(issue['ProductId']),
      'DesignId': asInt(issue['DesignId']),
      'PurityId': asInt(issue['PurityId']),
      'Quantity': asInt(issue['Quantity']) <= 0 ? 1 : asInt(issue['Quantity']),
      'GrossWt': issue['GrossWt']?.toString() ?? '0',
      'NetWt': issue['NetWt']?.toString() ?? '0',
      'TotalWt': issue['TotalWt']?.toString() ?? issue['NetWt']?.toString() ?? '0',
      'FinePercentage': issue['FinePercentage']?.toString(),
      'WastegePercentage': issue['WastegePercentage']?.toString(),
      'StoneWeight': issue['StoneWeight']?.toString() ?? '0',
      'DiamondWeight': issue['DiamondWeight']?.toString() ?? '0',
      'FineWastageWt': issue['FineWastageWt']?.toString() ?? '0',
      'RatePerGram': issue['RatePerGram']?.toString(),
      'MetalAmount': issue['MetalAmount']?.toString(),
      'Description': issue['Description']?.toString() ?? '',
      'SampleStatus': status,
      'ClientCode': AppSession.clientCode,
      'StoneAmount': issue['StoneAmount']?.toString() ?? '0',
      'SampleOutNo': record.number,
      'DiamondAmount': issue['DiamondAmount']?.toString() ?? '0',
      'Pieces': issue['Pieces']?.toString() ?? '1',
      'CategoryName': issue['CategoryName']?.toString() ?? '',
      'ProductName': issue['ProductName']?.toString() ?? '',
      'PurityName': issue['PurityName']?.toString() ?? '',
      'DesignName': issue['DesignName']?.toString() ?? '',
      'Id': asInt(issue['Id']),
      'CustomerId': record.customerId,
      'VendorId': 0,
      'BranchId': _branch,
      'LabelledStockId': asInt(issue['LabelledStockId']),
      'CustomerName': record.customerName,
      'SampleInDate': sampleInDate,
      'CreatedOn': sampleInDate,
      'Customer': null,
      'RFIDCode': issue['RFIDCode']?.toString() ?? '',
      'TIDNumber': issue['TIDNumber']?.toString() ?? '',
      'StatusType': true,
    };
  }

  Future<Map<String, dynamic>> _payload(String itemCode) async {
    final rows = await Injection.searchStoredRecords(query: itemCode, kind: StoredRecord.kindProduct, limit: 8);
    for (final row in rows) {
      if ((row.itemCode ?? '').toLowerCase() == itemCode.toLowerCase()) return row.payload;
    }
    return const {};
  }

  SampleOutRecord _out(Map<String, dynamic> json) {
    final customer = json['Customer'];
    final rawItems = json['IssueItems'];
    final items = <Map<String, dynamic>>[];
    if (rawItems is List) {
      for (final entry in rawItems.whereType<Map>()) {
        final row = Map<String, dynamic>.from(entry);
        final status = '${row['SampleStatus'] ?? ''}'.toLowerCase().replaceAll(' ', '');
        final active = row['StatusType'] != false && row['StatusType'] != 0 && row['StatusType'] != 'false';
        if (!active || status == 'samplein' || status == 'deleted' || status == 'cancelled') continue;
        items.add(row);
      }
    }
    return SampleOutRecord(
      id: _int(json['Id']),
      number: '${json['SampleOutNo'] ?? ''}'.trim(),
      customerId: _int(json['CustomerId']),
      customerName: customer is Map ? '${customer['FirstName'] ?? ''} ${customer['LastName'] ?? ''}'.trim() : _customerName(json),
      date: '${json['Date'] ?? ''}'.trim(),
      returnDate: '${json['ReturnDate'] ?? ''}'.trim(),
      description: '${json['Description'] ?? ''}'.trim(),
      status: '${json['SampleStatus'] ?? ''}'.trim(),
      items: items,
    );
  }
}

String _nextNumber(String? last) {
  final trimmed = last?.trim() ?? '';
  if (trimmed.isEmpty || trimmed.toLowerCase() == 'null') return 'C1';
  final match = RegExp(r'^(\D*)(\d+)$').firstMatch(trimmed);
  if (match == null) return '${trimmed}1';
  final current = int.tryParse(match.group(2)!) ?? 0;
  return '${match.group(1)}${current + 1}';
}

String _day(DateTime date) {
  String two(int value) => value.toString().padLeft(2, '0');
  return '${date.year}-${two(date.month)}-${two(date.day)}';
}

String _sum(List<InventoryPiece> pieces, int Function(InventoryPiece piece) read) {
  final grams = pieces.fold<int>(0, (sum, piece) => sum + read(piece)) / 1000;
  return grams.toStringAsFixed(3);
}

String _sumMaps(List<Map<String, dynamic>> items, String key) {
  var total = 0.0;
  for (final item in items) {
    total += double.tryParse('${item[key] ?? ''}') ?? 0;
  }
  return total.toStringAsFixed(3);
}

String _customerName(Map<String, dynamic> json) {
  final customer = json['Customer'];
  if (customer is Map) {
    final name = '${customer['FirstName'] ?? ''} ${customer['LastName'] ?? ''}'.trim();
    if (name.isNotEmpty) return name;
  }
  return '${json['CustomerName'] ?? ''}'.trim();
}

String _norm(String value) => value.trim().toUpperCase().replaceAll(' ', '').replaceAll('-', '');

List<Map<String, dynamic>> _rows(dynamic body) {
  if (body is List) {
    return [for (final row in body) if (row is Map) Map<String, dynamic>.from(row)];
  }
  if (body is Map) {
    for (final key in ['data', 'Data', 'result', 'Result', 'items', 'Items']) {
      if (body[key] is List) return _rows(body[key]);
    }
  }
  return const [];
}

int _int(Object? value) => value is num ? value.toInt() : int.tryParse('$value') ?? 0;
