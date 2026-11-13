import 'package:flutter/foundation.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/error/exceptions.dart';
import '../../../../core/network/api_client.dart';
import '../../../../core/session/app_session.dart';
import '../../../quotation/domain/entities/customer_record.dart';
import '../../../quotation/domain/entities/quotation_detail.dart';
import '../../../quotation/domain/entities/stock_item.dart';
import '../../../quotation/domain/quotation_math.dart';
import '../../domain/entities/order_record.dart';
import '../../domain/order_math.dart';
import 'order_rows.dart';

class OrderRemoteDataSource {
  OrderRemoteDataSource(this._api);

  final ApiClient _api;

  Future<Map<String, double>> dailyRates(String clientCode) async {
    try {
      final body = await _api.post(AppConstants.getAllDailyRate, {'ClientCode': clientCode});
      final rates = <String, double>{};
      for (final row in _rateRows(body)) {
        final name = _text(row, const ['PurityName', 'Purity', 'Name']).trim().toLowerCase();
        final rate = double.tryParse(_text(row, const ['Rate', 'TodaysRate', 'TodayRate']));
        if (name.isEmpty || rate == null) continue;
        rates[name] = rate;
      }
      return rates;
    } catch (_) {
      return const {};
    }
  }

  List<Map<String, dynamic>> _rateRows(dynamic body) {
    if (body is List) {
      return body.whereType<Map>().map(Map<String, dynamic>.from).toList();
    }
    if (body is Map) {
      for (final key in const ['data', 'Data', 'items', 'Items']) {
        final nested = body[key];
        if (nested is List) return _rateRows(nested);
      }
    }
    return const [];
  }

  Future<List<OrderRecord>> orderPage({
    required String clientCode,
    required int pageNumber,
    required int pageSize,
  }) async {
    final raw = await _api.postRaw(AppConstants.getAllOrders, {
      'ClientCode': clientCode,
      'PageNumber': pageNumber,
      'PageNo': pageNumber,
      'PageSize': pageSize,
      'PageCount': pageSize,
    });
    final rows = await compute(parseOrderRows, raw);
    return [
      for (final row in rows) _record(row),
    ].where((row) => row.id != 0 || row.number.isNotEmpty).toList();
  }

  OrderRecord _record(Map<String, dynamic> row) {
    final net = _text(row, const ['TotalNetAmount']);
    final total = _text(row, const ['TotalAmount']);
    return OrderRecord(
      id: _int(row['CustomOrderId'] ?? row['Id']),
      number: _text(row, const ['OrderNo', 'OrderNumber']),
      customerName: _customerName(row),
      amount: net.isNotEmpty ? net : total,
      source: row,
    );
  }

  QuotationDetail detailFrom(OrderRecord record) {
    final source = record.source;
    final itemRows = _itemRows(source);
    final items = <StockItem>[];
    for (var index = 0; index < itemRows.length; index++) {
      items.add(_stockItem(itemRows[index], index));
    }
    final named = record.customerName.isNotEmpty ? record.customerName : _customerName(source);
    return QuotationDetail(
      id: record.id,
      number: record.number,
      customer: CustomerRecord(
        id: _int(source['CustomerId']),
        name: named,
        mobile: _nestedText(source, const ['Mobile', 'MobileNo']),
        email: _nestedText(source, const ['Email']),
      ),
      items: items,
      gstApplied: _bool(source['GSTApplied'] ?? source['GstApplied'] ?? source['GstCheck']),
      source: source,
    );
  }

  Future<void> deleteOrder({
    required String clientCode,
    required int id,
  }) async {
    final body = await _api.post(AppConstants.deleteCustomOrder, {
      'clientCode': clientCode,
      'ClientCode': clientCode,
      'CustomOrderId': id,
    });
    _reject(body, 'Order could not be deleted');
  }

  Future<String> saveOrder({
    required String clientCode,
    required CustomerRecord customer,
    required List<StockItem> items,
    required bool gstApplied,
    required double gstRate,
    double discount = 0,
    DateTime? orderDate,
    DateTime? deliveryDate,
    int id = 0,
    String number = '',
    Map<String, dynamic> source = const {},
  }) async {
    final orderNo = id > 0 && number.isNotEmpty ? number : await _nextOrderNo(clientCode);
    final payload = _payload(
      clientCode: clientCode,
      customer: customer,
      items: items,
      gstApplied: gstApplied,
      gstRate: gstRate,
      discount: discount,
      orderDate: orderDate,
      deliveryDate: deliveryDate,
      id: id,
      number: orderNo,
      source: source,
    );
    final path = id > 0 ? AppConstants.updateCustomOrder : AppConstants.addCustomOrder;
    final body = await _api.post(path, payload);
    _reject(body, 'Order could not be saved');
    if (body is Map) {
      final saved = _text(Map<String, dynamic>.from(body), const ['OrderNo', 'orderNo']);
      if (saved.isNotEmpty) return saved;
    }
    return orderNo;
  }

  Future<String> _nextOrderNo(String clientCode) async {
    final body = await _api.post(AppConstants.lastOrderNo, {'ClientCode': clientCode});
    var last = '';
    if (body is Map) {
      last = '${body['LastOrderNo'] ?? body['lastOrderNo'] ?? body['OrderNo'] ?? ''}'.trim();
    }
    return '${(int.tryParse(last) ?? 0) + 1}';
  }

  Map<String, dynamic> _payload({
    required String clientCode,
    required CustomerRecord customer,
    required List<StockItem> items,
    required bool gstApplied,
    required double gstRate,
    required double discount,
    DateTime? orderDate,
    DateTime? deliveryDate,
    required int id,
    required String number,
    required Map<String, dynamic> source,
  }) {
    final names = customer.name.trim().split(RegExp(r'\s+'));
    final first = names.isEmpty ? '' : names.first;
    final last = names.length > 1 ? names.sublist(1).join(' ') : '';
    final now = DateTime.now();
    final stamp = orderDate ?? now;
    final deliverOn = deliveryDate ?? stamp;
    final dated = isoOffset(stamp);
    final deliver = _dateOnly(deliverOn);
    final priced = items;
    final lines = [
      for (final item in priced)
        orderStoredLine(item, applyGst: gstApplied, gstFraction: gstRate),
    ];
    final rateBase = lines.where((line) => !line.mrp).fold<double>(0, (sum, line) => sum + line.item);
    final mrpBase = lines.where((line) => line.mrp).fold<double>(0, (sum, line) => sum + line.total);
    final base = rateBase + mrpBase;
    // RFID_Flutter create always sends GST off. Update keeps the form GST.
    final wantGst = id > 0 && gstApplied;
    final gst = wantGst ? lines.where((line) => !line.mrp).fold<double>(0, (sum, line) => sum + line.gst) : 0.0;
    final cut = discount < 0 ? 0.0 : discount;
    final net = base + gst - cut;
    final employeeId = int.tryParse(AppSession.userId) ?? 0;
    final status = _text(source, const ['OrderStatus']);
    final orderItems = <Map<String, dynamic>>[];
    for (final item in priced) {
      final line = orderStoredLine(item, applyGst: gstApplied, gstFraction: gstRate);
      orderItems.add(
        _orderItem(
          item: item,
          line: line,
          clientCode: clientCode,
          customer: customer,
          orderId: id,
          orderNo: number,
          orderDate: dated,
          deliver: deliver,
          employeeId: employeeId,
          status: status.isEmpty ? 'Order Received' : status,
          gst: wantGst ? line.gst : 0,
        ),
      );
    }
    final money = net.toStringAsFixed(2);
    final baseText = base.toStringAsFixed(2);
    return {
      'Id': 0,
      'CustomOrderId': id,
      'CustomerId': customer.id.toString(),
      'ClientCode': clientCode,
      'OrderId': 0,
      'TotalAmount': money,
      'PaymentMode': '',
      'Qty': '${priced.length}',
      'GST': wantGst ? 'true' : '0',
      'OrderStatus': status.isEmpty ? 'Order Received' : status,
      'GSTApplied': wantGst ? 'true' : 'false',
      'Discount': cut == 0 ? '0' : cut.toStringAsFixed(2),
      'TotalNetAmount': baseText,
      'TotalGSTAmount': gst.toStringAsFixed(2),
      'TotalPurchaseAmount': money,
      'ReceivedAmount': '0',
      'TotalBalanceMetal': '0',
      'BalanceAmount': money,
      'TotalFineMetal': '0',
      'OrderDate': dated,
      'OrderCount': '${priced.length}',
      'AdditionTaxApplied': wantGst ? 'true' : 'false',
      'OrderNo': number,
      'BillType': 'SampleOut',
      'BilledBy': '',
      'SoldBy': '',
      'BalanceAmt': money,
      'FinancialYear': _financialYear(now),
      'BaseCurrency': 'INR',
      'TotalStoneWeight': _sum(priced, const ['stonewt', 'stoneweight']).toString(),
      'TotalStoneAmount': lines.fold<double>(0, (sum, line) => sum + line.stone).toStringAsFixed(2),
      'TotalStonePieces': '0',
      'TotalDiamondWeight': _sum(priced, const ['diamondwt', 'diamondweight']).toString(),
      'TotalDiamondPieces': _sum(priced, const ['diamondpcs', 'diamondpieces']).toStringAsFixed(0),
      'TotalDiamondAmount': lines.fold<double>(0, (sum, line) => sum + line.diamond).toStringAsFixed(2),
      'FineSilver': '0',
      'FineGold': '0',
      'PaidMetal': '0',
      'PaidAmount': '0',
      'TaxableAmount': baseText,
      'CreatedOn': dated,
      'StatusType': true,
      'FineMetal': '0',
      'BalanceMetal': '0',
      'AdvanceAmt': '0',
      'PaidAmt': '0',
      'TaxableAmt': baseText,
      'GstAmount': gst.toStringAsFixed(2),
      'GstCheck': wantGst ? 'true' : 'false',
      'TDSCheck': 'false',
      'CustomOrderItem': orderItems,
      'Payments': const <dynamic>[],
      'Customer': {
        'FirstName': first,
        'LastName': last,
        'Mobile': customer.mobile,
        'Email': customer.email,
        'Password': '',
        'CustomerLoginId': customer.email,
        'MiddleName': '',
        'ClientCode': clientCode,
        'VendorId': 0,
        'AddToVendor': false,
        'CustomerSlabId': 0,
        'CreditPeriodId': 0,
        'RateOfInterestId': 0,
        'Id': customer.id,
        'StatusType': true,
      },
      'RfidCode': '',
      'TidNumber': '',
      'SKUId': 0,
      'BranchId': 1,
      'CompanyId': 1,
    };
  }

  Map<String, dynamic> _orderItem({
    required StockItem item,
    required LinePrice line,
    required String clientCode,
    required CustomerRecord customer,
    required int orderId,
    required String orderNo,
    required String orderDate,
    required String deliver,
    required int employeeId,
    required String status,
    required double gst,
  }) {
    String pick(List<String> keys, [String fallback = '']) {
      for (final key in keys) {
        final value = item.extras[key];
        if (value != null && value.trim().isNotEmpty) return value.trim();
      }
      return fallback;
    }

    final qty = pick(const ['quantity', 'pieces', 'pcs'], '1');
    final count = double.tryParse(qty)?.toInt() ?? 0;
    return {
      'CustomOrderId': orderId,
      'RFIDCode': item.rfid,
      'TIDNumber': pick(const ['tidnumber', 'tid'], item.rfid),
      'OrderDate': orderDate,
      'DeliverDate': deliver,
      'SKUId': int.tryParse(pick(const ['skuid'])) ?? 0,
      'SKU': pick(const ['sku']),
      'VendorId': int.tryParse(pick(const ['vendorid'])) ?? 0,
      'CategoryId': int.tryParse(pick(const ['categoryid'])) ?? 0,
      'CategoryName': pick(const ['categoryname']),
      'ProductId': int.tryParse(pick(const ['productid'])) ?? 0,
      'ProductName': pick(const ['productname', 'name'], item.name),
      'DesignId': int.tryParse(pick(const ['designid'])) ?? 0,
      'DesignName': pick(const ['designname'], item.design),
      'PurityId': int.tryParse(pick(const ['purityid'])) ?? 0,
      'PurityName': pick(const ['purityname', 'purity']),
      'Purity': pick(const ['purity', 'purityname']),
      'GrossWt': pick(const ['grosswt', 'grossweight'], item.gross.isEmpty ? '0.0' : item.gross),
      'StoneWt': pick(const ['stonewt', 'stoneweight'], '0.0'),
      'DiamondWt': pick(const ['diamondwt', 'diamondweight'], '0.0'),
      'NetWt': line.weight(line.net),
      'Quantity': count <= 0 ? '1' : '$count',
      'RatePerGram': pick(const ['rate', 'metalrate', 'goldrate'], '0.0'),
      'MakingPerGram': pick(const ['makingpergram'], '0.0'),
      'MakingFixed': pick(const ['makingfixedamt', 'fixmaking'], '0.0'),
      'MakingPercentage': pick(const ['makingpercent', 'makingpercentage'], '0.0'),
      'MakingFixedWastage': pick(const ['makingfixedwastage', 'fixwastage'], '0.0'),
      'FixedWt': pick(const ['fixedwt', 'finewastagewt'], '0.0'),
      'FineWastageWt': pick(const ['finewastagewt', 'fixedwt'], '0.0'),
      'DiamondPieces': pick(const ['diamondpcs', 'diamondpieces'], '0'),
      'DiamondRate': pick(const ['diamondrate'], '0'),
      'DiamondAmount': line.diamond.toStringAsFixed(2),
      'StoneAmount': line.stone.toStringAsFixed(2),
      'MetalAmount': line.metal.toStringAsFixed(2),
      'TypesOdColors': pick(const ['typesodcolors', 'color', 'colour', 'typesofcolor', 'typeofcolor']),
      'ScrewType': pick(const ['screwtype', 'screw']),
      'Polish': pick(const ['polish', 'polishtype']),
      'ItemCode': item.itemCode,
      'CustomerId': customer.id,
      'CustomerName': customer.name,
      'MRP': pick(const ['mrp'], '0.0'),
      'HSNCode': pick(const ['hsncode', 'hsn']),
      'ProductCode': pick(const ['productcode']),
      'TotalWt': line.weight(line.net),
      'FinePercentage': pick(const ['finepercentage'], '0.0'),
      'PackingWeight': pick(const ['packingweight'], '0.0'),
      'BillType': 'SampleOut',
      'ClientCode': clientCode,
      'StatusType': true,
      'OldGoldPurchase': false,
      'Amount': line.item.toStringAsFixed(2),
      'totalGstAmount': gst.toStringAsFixed(2),
      'finalPrice': line.total.toStringAsFixed(2),
      'Description': pick(const ['description', 'productname'], item.name),
      'LabelledStockId': int.tryParse(pick(const ['labelledstockid', 'labeledstockid'])) ?? 0,
      'TotalStoneWeight': pick(const ['stonewt', 'stoneweight'], '0.0'),
      'CompanyId': int.tryParse(pick(const ['companyid'])) ?? 1,
      'BranchId': 1,
      'CounterId': pick(const ['counterid'], '0'),
      'EmployeeId': employeeId,
      'OrderNo': orderNo,
      'OrderStatus': status,
      'Stones': const <dynamic>[],
      'Diamond': const <dynamic>[],
    };
  }

  List<Map<String, dynamic>> _itemRows(Map<String, dynamic> source) {
    for (final key in const ['CustomOrderItem', 'CustomOrderItems', 'OrderItem', 'Items']) {
      final value = source[key];
      if (value is List) {
        return value.whereType<Map>().map(Map<String, dynamic>.from).toList();
      }
    }
    return const [];
  }

  StockItem _stockItem(Map<String, dynamic> row, int index) {
    final extras = <String, String>{};
    row.forEach((key, value) {
      final text = '$value'.trim();
      if (text.isEmpty || text == 'null') return;
      extras[_token(key)] = text;
    });
    final itemCode = _text(row, const ['ItemCode', 'itemCode', 'SKU']);
    final design = _text(row, const ['DesignName', 'Design']);
    final gross = _text(row, const ['GrossWt', 'GrossWeight']);
    final net = _text(row, const ['NetWt', 'NetWeight']);
    final rfid = _text(row, const ['RFIDCode', 'TIDNumber', 'TidNumber']);
    final name = _text(row, const ['ProductName', 'DesignName', 'ItemName', 'Name']);
    extras.putIfAbsent('itemcode', () => itemCode);
    extras.putIfAbsent('designname', () => design);
    extras.putIfAbsent('grosswt', () => gross);
    extras.putIfAbsent('netwt', () => net);
    extras.putIfAbsent('rfid', () => rfid);
    _alias(extras, 'ratepergram', 'rate');
    _alias(extras, 'metalrate', 'rate');
    _alias(extras, 'makingfixed', 'makingfixedamt');
    _alias(extras, 'metalamount', 'metalamt');
    _alias(extras, 'makingpercentage', 'makingpercent');
    _alias(extras, 'stoneamount', 'stoneamt');
    _alias(extras, 'diamondamount', 'diamondamt');
    _alias(extras, 'amount', 'itemamt');
    _alias(extras, 'typesodcolors', 'color');
    _alias(extras, 'typesofcolor', 'color');
    _alias(extras, 'typeofcolor', 'color');
    _alias(extras, 'screwtype', 'screw');
    _alias(extras, 'polishtype', 'polish');
    final code = itemCode.isNotEmpty
        ? itemCode
        : (rfid.isNotEmpty ? rfid : 'line-${index + 1}');
    return StockItem(
      itemCode: code,
      name: name,
      rfid: rfid,
      gross: gross,
      net: net,
      design: design,
      extras: extras,
    );
  }

  void _alias(Map<String, String> extras, String from, String to) {
    final value = extras[from];
    if (value != null && value.isNotEmpty) extras.putIfAbsent(to, () => value);
  }

  void _reject(dynamic body, String fallback) {
    if (body is! Map) return;
    final message = '${body['Message'] ?? body['message'] ?? ''}'.trim();
    final lower = message.toLowerCase();
    if (lower.contains('error') || lower.contains('fail') || lower.contains('required')) {
      throw ServerException(message.isEmpty ? fallback : message);
    }
  }

  String _customerName(Map<String, dynamic> row) {
    final named = _clean(_text(row, const ['CustomerName', 'Name']));
    if (named.isNotEmpty) return named;
    final direct = _clean('${_text(row, const ['FirstName'])} ${_text(row, const ['LastName'])}');
    if (direct.isNotEmpty) return direct;
    for (final key in const ['Customer', 'customer']) {
      final nested = row[key];
      if (nested is! Map) continue;
      final map = Map<String, dynamic>.from(nested);
      final nestedName = _clean(_text(map, const ['CustomerName', 'Name']));
      if (nestedName.isNotEmpty) return nestedName;
      final person = _clean('${_text(map, const ['FirstName'])} ${_text(map, const ['LastName'])}');
      if (person.isNotEmpty) return person;
    }
    return '';
  }

  String _nestedText(Map<String, dynamic> row, List<String> keys) {
    final direct = _clean(_text(row, keys));
    if (direct.isNotEmpty) return direct;
    for (final key in const ['Customer', 'customer']) {
      final nested = row[key];
      if (nested is! Map) continue;
      final value = _clean(_text(Map<String, dynamic>.from(nested), keys));
      if (value.isNotEmpty) return value;
    }
    return '';
  }

  double _sum(List<StockItem> items, List<String> keys) {
    var total = 0.0;
    for (final item in items) {
      for (final key in keys) {
        final value = double.tryParse(item.extras[key] ?? '');
        if (value != null) {
          total += value;
          break;
        }
      }
    }
    return total;
  }

  String _text(Map<String, dynamic> row, List<String> keys) {
    for (final key in keys) {
      final value = row[key];
      if (value == null) continue;
      final text = '$value'.trim();
      if (text.isEmpty || text.toLowerCase() == 'null') continue;
      return text;
    }
    return '';
  }

  String _clean(String value) {
    final text = value.trim();
    if (text.isEmpty || text.toLowerCase() == 'null') return '';
    return text;
  }

  int _int(dynamic value) => int.tryParse('$value'.split('.').first) ?? 0;

  bool _bool(dynamic value) {
    final text = '$value'.toLowerCase();
    return text == 'true' || text == '1' || text == 'yes';
  }

  String _token(String value) => value.toLowerCase().replaceAll(RegExp('[^a-z0-9]'), '');

  String _financialYear(DateTime date) {
    final start = date.month >= 4 ? date.year : date.year - 1;
    final end = (start + 1).toString().substring(2);
    return '$start-$end';
  }

  String _dateOnly(DateTime date) {
    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');
    return '${date.year}-$month-$day';
  }
}

String isoOffset(DateTime now) {
  final offset = now.timeZoneOffset;
  final sign = offset.isNegative ? '-' : '+';
  final hours = offset.inHours.abs().toString().padLeft(2, '0');
  final minutes = (offset.inMinutes.abs() % 60).toString().padLeft(2, '0');
  String two(int value) => value.toString().padLeft(2, '0');
  return '${now.year}-${two(now.month)}-${two(now.day)}T${two(now.hour)}:${two(now.minute)}:${two(now.second)}$sign$hours:$minutes';
}
