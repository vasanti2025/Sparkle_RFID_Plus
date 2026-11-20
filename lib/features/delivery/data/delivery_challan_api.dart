import '../../../core/constants/app_constants.dart';
import '../../../core/network/api_client.dart';
import '../../../core/session/app_session.dart';

class ChallanRecord {
  const ChallanRecord({
    required this.id,
    required this.number,
    required this.date,
    required this.customer,
    required this.fields,
    required this.items,
  });

  final int id;
  final String number;
  final String date;
  final String customer;
  final Map<String, String> fields;
  final List<Map<String, String>> items;
}

class DeliveryChallanApi {
  DeliveryChallanApi({ApiClient? client}) : _api = client ?? ApiClient();

  final ApiClient _api;

  Future<String> save({
    required bool editing,
    required int challanId,
    required int customerId,
    required String customerName,
    required bool gstOn,
    required String date,
    required String branchName,
    required String salesman,
    required String challanNo,
    required List<Map<String, String>> items,
  }) async {
    final clientCode = AppSession.clientCode;
    if (clientCode.isEmpty) throw StateError('Sign in to save this challan.');
    final branchId = AppSession.branchId > 0 ? AppSession.branchId : 1;
    final userId = int.tryParse(AppSession.userId) ?? 0;
    var number = challanNo;
    if (!editing) {
      final last = await _api.post(AppConstants.lastChallanNo, {
        'ClientCode': clientCode,
        'BranchId': branchId,
      });
      final raw = last is Map ? last['LastChallanNo'] ?? last['lastChallanNo'] : null;
      final nextNo = (int.tryParse('$raw') ?? 0) + 1;
      number = '$nextNo';
    }
    final base = _sum(items, const ['amount', 'Amount', 'totalitemamount']);
    final gst = gstOn ? base * 0.03 : 0;
    final total = base + gst;
    final lines = [
      for (final item in items) _linePayload(item, clientCode, customerId, customerName, userId, challanId),
    ];
    final payload = <String, dynamic>{
      if (editing) 'Id': challanId,
      'BranchId': branchId,
      'ClientCode': clientCode,
      'CustomerId': customerId.toString(),
      'CustomerName': customerName,
      'TransactionAmtType': 'CREDIT',
      'TransactionMetalType': 'GOLD',
      'MetalType': 'GOLD',
      'TransactionDetails': 'Delivery Challan Created',
      'Billedby': salesman,
      'Soldby': salesman,
      'SaleType': 'Challan',
      'BillType': 'Challan',
      'PaymentMode': 'Credit',
      'ChallanStatus': 'Sold',
      'Visibility': 'True',
      'GST': gstOn ? '3.00' : '0.00',
      'GSTApplied': gstOn ? 'True' : 'False',
      'TotalGSTAmount': gst.toStringAsFixed(2),
      'TotalAmount': total.toStringAsFixed(2),
      'TotalNetAmount': base.toStringAsFixed(2),
      'BalanceAmt': total.toStringAsFixed(2),
      'InvoiceDate': _isoDate(date),
      'InvoiceNo': number,
      'ChallanNo': number,
      'Qty': '${items.length}',
      'GrossWt': _sum(items, const ['grossWt', 'GrossWt', 'gross']).toStringAsFixed(3),
      'NetWt': _sum(items, const ['netWt', 'NetWt', 'net']).toStringAsFixed(3),
      'BranchName': branchName,
      'ChallanDetails': lines,
      'Payments': const [],
    };
    payload.removeWhere((_, value) => value == null);
    final path = editing ? AppConstants.updateDeliveryChallan : AppConstants.addDeliveryChallan;
    final body = await _api.post(path, payload);
    if (body is Map) {
      final message = '${body['Message'] ?? body['message'] ?? ''}'.trim();
      final lower = message.toLowerCase();
      if (lower.contains('error') || lower.contains('fail')) {
        throw StateError(message.isEmpty ? 'Challan could not be saved.' : message);
      }
      if (message.isNotEmpty) return message;
    }
    return editing ? 'Delivery challan updated' : 'Delivery challan saved';
  }

  Future<List<ChallanRecord>> load() async {
    final clientCode = AppSession.clientCode;
    if (clientCode.isEmpty) {
      throw StateError('Sign in to load this form.');
    }
    final body = await _api.post(AppConstants.getAllDeliveryChallan, {
      'ClientCode': clientCode,
      'BranchId': AppSession.branchId,
    });
    return challansFrom(body);
  }
}

List<ChallanRecord> challansFrom(dynamic body) {
  final rows = _rows(body);
  return [for (final row in rows) _challan(row)];
}

List<Map<String, dynamic>> _rows(dynamic body) {
  if (body is List) {
    return [
      for (final entry in body)
        if (entry is Map) Map<String, dynamic>.from(entry),
    ];
  }
  if (body is Map) {
    final map = Map<String, dynamic>.from(body);
    for (final key in const ['data', 'Data', 'result', 'Result', 'challans', 'Challans']) {
      final nested = map[key];
      if (nested is List) return _rows(nested);
    }
  }
  return const [];
}

ChallanRecord _challan(Map<String, dynamic> row) {
  final fields = <String, String>{};
  row.forEach((key, value) {
    if (value is Map || value is List) return;
    _put(fields, key.toString(), value);
  });
  final number = _text(row, const ['ChallanNo', 'InvoiceNo', 'challanNo']);
  final customer = _text(row, const ['CustomerName', 'Name', 'customerName']);
  final date = _date(_text(row, const ['ChallanDate', 'CreatedOn', 'Date', 'challanDate']));
  if (number.isNotEmpty) fields.putIfAbsent('challanNo', () => number);
  if (customer.isNotEmpty) fields.putIfAbsent('customerName', () => customer);
  if (date.isNotEmpty) fields.putIfAbsent('date', () => date);
  final branch = _text(row, const ['BranchName', 'branch']);
  if (branch.isNotEmpty) fields.putIfAbsent('branch', () => branch);
  return ChallanRecord(
    id: int.tryParse(_text(row, const ['Id', 'id'])) ?? 0,
    number: number,
    date: date,
    customer: customer,
    fields: fields,
    items: _items(row),
  );
}

List<Map<String, String>> _items(Map<String, dynamic> row) {
  dynamic raw;
  for (final key in const ['items', 'Items', 'ChallanDetails', 'challanDetails']) {
    if (row[key] is List) {
      raw = row[key];
      break;
    }
  }
  if (raw is! List) return const [];
  final items = <Map<String, String>>[];
  for (final entry in raw) {
    if (entry is! Map) continue;
    final line = <String, String>{};
    entry.forEach((key, value) {
      if (value is Map || value is List) return;
      _put(line, key.toString(), value);
    });
    items.add(line);
  }
  return items;
}

void _put(Map<String, String> target, String key, Object? value) {
  final text = '$value'.trim();
  if (text.isEmpty || text.toLowerCase() == 'null') return;
  target[key] = text;
  final alias = _aliases[key];
  if (alias != null) target.putIfAbsent(alias, () => text);
}

const _aliases = {
  'ChallanNo': 'challanNo',
  'CustomerName': 'customerName',
  'BranchName': 'branch',
  'FinePercentage': 'finePercent',
  'FinePercent': 'finePercent',
  'WastagePercentage': 'wastagePercent',
  'WastagePercent': 'wastagePercent',
  'SoldBy': 'salesman',
  'BilledBy': 'salesman',
  'Salesman': 'salesman',
  'ProductName': 'itemName',
  'DesignName': 'itemName',
  'ItemCode': 'itemCode',
  'Quantity': 'qty',
  'Qty': 'qty',
  'GrossWt': 'grossWt',
  'NetWt': 'netWt',
  'TotalStoneWeight': 'stoneWt',
  'StoneWt': 'stoneWt',
  'DiamondWeight': 'diamondWt',
  'TotalDiamondWeight': 'diamondWt',
  'MetalRate': 'rate',
  'RatePerGram': 'rate',
  'MakingCharg': 'makingChg',
  'StoneAmount': 'stoneAmt',
  'TotalStoneAmount': 'stoneAmt',
  'TotalDiamondAmount': 'diamondAmt',
  'FineWastageWt': 'fineWt',
  'GSTAmount': 'taxAmt',
  'ItemGSTAmount': 'taxAmt',
  'Amount': 'amount',
  'TotalItemAmount': 'amount',
  'RFIDCode': 'lineRfid',
  'Tid': 'lineRfid',
};

String _text(Map<String, dynamic> row, List<String> keys) {
  for (final key in keys) {
    final value = row[key]?.toString().trim() ?? '';
    if (value.isNotEmpty && value.toLowerCase() != 'null') return value;
  }
  return '';
}

Map<String, dynamic> _linePayload(
  Map<String, String> item,
  String clientCode,
  int customerId,
  String customerName,
  int userId,
  int challanId,
) {
  String pick(List<String> keys, [String fallback = '']) {
    for (final key in keys) {
      final value = item[key];
      if (value != null && value.isNotEmpty) return value;
    }
    return fallback;
  }

  return {
    'ClientCode': clientCode,
    'CustomerId': customerId,
    'CustomerName': customerName,
    'EmployeeId': userId,
    'ChallanId': challanId,
    'ProductName': pick(const ['itemName', 'ProductName', 'name']),
    'ItemCode': pick(const ['itemCode', 'ItemCode', 'code']),
    'Quantity': pick(const ['qty', 'Quantity'], '1'),
    'GrossWt': pick(const ['grossWt', 'GrossWt', 'gross'], '0'),
    'NetWt': pick(const ['netWt', 'NetWt', 'net'], '0'),
    'Amount': pick(const ['amount', 'Amount'], '0'),
    'ItemAmount': pick(const ['amount', 'Amount'], '0'),
    'TotalItemAmount': pick(const ['amount', 'Amount'], '0'),
    'MetalRate': pick(const ['rate', 'MetalRate'], '0'),
    'MakingCharg': pick(const ['makingChg', 'MakingCharg'], '0'),
    'TotalStoneWeight': pick(const ['stoneWt', 'TotalStoneWeight'], '0'),
    'TotalDiamondWeight': pick(const ['diamondWt', 'TotalDiamondWeight'], '0'),
    'TotalStoneAmount': pick(const ['stoneAmt', 'TotalStoneAmount'], '0'),
    'TotalDiamondAmount': pick(const ['diamondAmt', 'TotalDiamondAmount'], '0'),
    'RFIDCode': pick(const ['lineRfid', 'RFIDCode', 'rfid']),
    'ChallanStatus': 'Sold',
  };
}

double _sum(List<Map<String, String>> items, List<String> keys) {
  var total = 0.0;
  for (final item in items) {
    for (final key in keys) {
      final value = double.tryParse(item[key] ?? '');
      if (value != null) {
        total += value;
        break;
      }
    }
  }
  return total;
}

String _isoDate(String raw) {
  final parts = raw.split('-');
  if (parts.length == 3 && parts.first.length == 2) {
    return '${parts[2]}-${parts[1]}-${parts[0]}';
  }
  return raw.isEmpty ? DateTime.now().toIso8601String().split('T').first : raw;
}

String _date(String raw) {
  final parsed = DateTime.tryParse(raw);
  if (parsed == null) return raw;
  final day = parsed.day.toString().padLeft(2, '0');
  final month = parsed.month.toString().padLeft(2, '0');
  return '$day-$month-${parsed.year}';
}
