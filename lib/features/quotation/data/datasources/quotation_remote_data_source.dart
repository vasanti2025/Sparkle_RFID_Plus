import 'package:flutter/foundation.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/error/exceptions.dart';
import '../../../../core/network/api_client.dart';
import '../../../../core/session/app_session.dart';
import '../../domain/entities/customer_record.dart';
import '../../domain/entities/quotation_detail.dart';
import '../../domain/entities/quotation_field.dart';
import '../../domain/entities/quotation_summary.dart';
import '../../domain/quotation_math.dart';
import '../../domain/entities/stock_item.dart';
import 'json_row_parser.dart';

class QuotationRemoteDataSource {
  const QuotationRemoteDataSource(this._api);

  final ApiClient _api;

  Future<CustomerIndex> loadCustomers(String clientCode) async {
    final body = await _api.post(AppConstants.getAllCustomers, {
      'ClientCode': clientCode,
    });
    final rows = _maps(body);
    final records = <CustomerRecord>[];
    for (final row in rows) {
      final first = _text(row, const ['FirstName', 'CustomerName', 'Name']);
      final last = _text(row, const ['LastName']);
      final name = '$first $last'.trim();
      if (name.isEmpty) continue;
      records.add(
        CustomerRecord(
          id: _int(row['Id'] ?? row['CustomerId']),
          name: name,
          mobile: _text(row, const ['Mobile', 'Phone']),
          email: _text(row, const ['Email']),
        ),
      );
    }
    return CustomerIndex(records);
  }

  Future<CustomerRecord> addCustomer({
    required String clientCode,
    required String name,
    required String mobile,
    required String email,
    String pan = '',
    String gst = '',
    String street = '',
    String city = '',
    String state = '',
    String country = '',
  }) async {
    final parts = name.trim().split(RegExp(r'\s+'));
    final first = parts.first;
    final last = parts.length > 1 ? parts.sublist(1).join(' ') : '';
    final body = await _api.post(AppConstants.addCustomer, {
      'FirstName': first,
      'MiddleName': '',
      'LastName': last,
      'Email': email,
      'CustomerLoginId': email,
      'Password': '',
      'Gender': '',
      'CustomerSlabId': 0,
      'CreditPeriodId': 0,
      'RateOfInterestId': 0,
      'Mobile': mobile,
      'OnlineStatus': 'Active',
      'DateOfBirth': '',
      'AdvanceAmount': '0',
      'BalanceAmount': '0',
      'CurrAddStreet': street,
      'Area': '',
      'PerAddTown': '',
      'City': city,
      'CurrAddState': state,
      'CurrAddPincode': '',
      'PerAddStreet': '',
      'PerAddState': '',
      'PerAddPincode': '',
      'Country': country,
      'PerAddCountry': '',
      'AadharNo': '',
      'Discount': '0',
      'CreditPeriod': '0',
      'PanNo': pan,
      'FineGold': '0',
      'FineSilver': '0',
      'GstNo': gst,
      'ClientCode': clientCode,
      'VendorId': 0,
      'Remark': '',
      'AddToVendor': false,
      'Id': 0,
    });
    if (body is Map) {
      final message = '${body['Message'] ?? body['message'] ?? ''}'.trim();
      final lower = message.toLowerCase();
      if (lower.contains('error') || lower.contains('fail') || lower.contains('exist')) {
        throw ServerException(message);
      }
    }
    return CustomerRecord(id: 0, name: name.trim(), mobile: mobile, email: email);
  }

  Future<List<StockItem>> searchStock({
    required String clientCode,
    required String query,
    int pageNumber = 1,
  }) async {
    final body = await _api.post(AppConstants.getAllLabeledStock, {
      'BranchId': 1,
      'CategoryId': 0,
      'ClientCode': clientCode,
      'CounterId': 0,
      'DesignId': 0,
      'FromDate': null,
      'ListType': 'ascending',
      'PageNumber': pageNumber,
      'PageSize': AppConstants.stockPageSize,
      'ProductId': 0,
      'RFIDCode': '',
      'SearchQuery': query,
      'SortColumn': null,
      'Status': 'Active',
      'ToDate': null,
    });
    return _maps(body).map(_stockItem).where((item) => item.identity.isNotEmpty).toList();
  }

  Future<List<StockItem>> labeledStockPage({
    required String clientCode,
    required int pageNumber,
    required int pageSize,
    bool bulk = false,
  }) async {
    final body = _stockBody(clientCode, pageNumber, pageSize, '');
    if (!bulk) {
      return _maps(await _api.post(AppConstants.getAllLabeledStock, body))
          .map(_stockItem)
          .where((item) => item.identity.isNotEmpty)
          .toList();
    }
    final raw = await _api.postRaw(AppConstants.getAllLabeledStock, body);
    final rows = await compute(parseJsonRows, raw);
    return [for (final row in rows) _stockItem(row)].where((item) => item.identity.isNotEmpty).toList();
  }

  Map<String, dynamic> _stockBody(
    String clientCode,
    int pageNumber,
    int pageSize,
    String query,
  ) {
    return {
      'BranchId': 1,
      'CategoryId': 0,
      'ClientCode': clientCode,
      'CounterId': 0,
      'DesignId': 0,
      'FromDate': null,
      'ListType': 'ascending',
      'PageNumber': pageNumber,
      'PageNo': pageNumber,
      'PageSize': pageSize,
      'PageCount': pageSize,
      'ProductId': 0,
      'RFIDCode': '',
      'SearchQuery': query,
      'SortColumn': null,
      'Status': 'Active',
      'ToDate': null,
    };
  }

  Future<List<QuotationSummary>> quotationPage({
    required String clientCode,
    required int pageNumber,
    required int pageSize,
    bool bulk = false,
  }) async {
    final body = {
      'ClientCode': clientCode,
      'BranchId': 1,
      'SearchQuery': '',
      'PageNumber': pageNumber,
      'PageNo': pageNumber,
      'PageSize': pageSize,
      'PageCount': pageSize,
    };
    final rows = bulk
        ? await compute(parseJsonRows, await _api.postRaw(AppConstants.getAllQuotation, body))
        : _maps(await _api.post(AppConstants.getAllQuotation, body));
    return [for (final row in rows) _summary(row)].where((row) => row.id != 0 || row.number.isNotEmpty).toList();
  }

  QuotationSummary _summary(Map<String, dynamic> row) {
    final customer = _customerName(row);
    final net = _text(row, const ['TotalNetAmount']);
    final total = _text(row, const ['TotalAmount']);
    return QuotationSummary(
      id: _int(row['Id'] ?? row['QuotationId']),
      number: _text(row, const ['QuotationNo', 'QuotationNumber']),
      customerName: customer,
      amount: net.isNotEmpty ? net : total,
    );
  }

  String _nestedText(Map<String, dynamic> row, List<String> keys) {
    final direct = _clean(_text(row, keys));
    if (direct.isNotEmpty) return direct;
    for (final key in const ['Customer', 'customer', 'CustomerDetails']) {
      final nested = row[key];
      if (nested is! Map) continue;
      final value = _clean(_text(Map<String, dynamic>.from(nested), keys));
      if (value.isNotEmpty) return value;
    }
    return '';
  }

  String _customerName(Map<String, dynamic> row) {
    final named = _clean(_text(row, const ['CustomerName', 'Name']));
    if (named.isNotEmpty) return named;
    final direct = _clean('${_text(row, const ['FirstName'])} ${_text(row, const ['LastName'])}');
    if (direct.isNotEmpty) return direct;
    for (final key in const ['Customer', 'customer', 'CustomerDetails']) {
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

  String _clean(String value) {
    final text = value.trim();
    if (text.isEmpty || text.toLowerCase() == 'null') return '';
    return text;
  }

  Future<QuotationDetail> quotationDetail({
    required String clientCode,
    required int id,
  }) async {
    final body = await _api.post(AppConstants.getQuotationById, {
      'clientCode': clientCode,
      'ClientCode': clientCode,
      'id': id,
      'Id': id,
      'BranchId': 1,
      'branchId': 1,
    });
    final source = _detailMap(body);
    final itemRows = _itemRows(source);
    final first = _text(source, const ['FirstName']);
    final last = _text(source, const ['LastName']);
    final named = _customerName(source);
    return QuotationDetail(
      id: _int(source['Id'] ?? id),
      number: _text(source, const ['QuotationNo']),
      customer: CustomerRecord(
        id: _int(source['CustomerId']),
        name: named.isNotEmpty ? named : '$first $last'.trim(),
        mobile: _nestedText(source, const ['MobileNo', 'Mobile']),
        email: _nestedText(source, const ['Email']),
      ),
      items: [
        for (final row in itemRows)
          if (_quotationStockItem(row).identity.isNotEmpty) _quotationStockItem(row),
      ],
      gstApplied: _bool(source['GSTApplied'] ?? source['GstApplied']),
      source: source,
    );
  }

  Map<String, dynamic> _detailMap(dynamic body) {
    if (body is Map) {
      final map = Map<String, dynamic>.from(body);
      for (final key in const ['data', 'Data', 'result', 'Result']) {
        final nested = map[key];
        if (nested is Map && (nested.containsKey('Id') || nested.containsKey('QuotationNo'))) {
          return Map<String, dynamic>.from(nested);
        }
      }
      return map;
    }
    throw const ServerException('Quotation could not be opened');
  }

  List<Map<String, dynamic>> _itemRows(Map<String, dynamic> source) {
    for (final key in const ['QuotationItem', 'QuotationItems', 'Items']) {
      final value = source[key];
      if (value is List) {
        return value.whereType<Map>().map(Map<String, dynamic>.from).toList();
      }
    }
    return const [];
  }

  Future<String> saveQuotation({
    required String clientCode,
    required CustomerRecord customer,
    required List<StockItem> items,
    required bool gstApplied,
    required double gstRate,
    int id = 0,
    String number = '',
    Map<String, dynamic> source = const {},
  }) async {
    final quotationNo = id > 0 && number.isNotEmpty ? number : await _nextQuotationNo(clientCode);
    final payload = _quotationPayload(
      clientCode: clientCode,
      customer: customer,
      items: items,
      gstApplied: gstApplied,
      gstRate: gstRate,
      id: id,
      number: quotationNo,
      source: source,
    );
    final path = id > 0 ? AppConstants.updateQuotation : AppConstants.addQuotation;
    final body = await _api.post(path, payload);
    if (body is Map) {
      final message = '${body['Message'] ?? body['message'] ?? ''}'.trim();
      final lower = message.toLowerCase();
      if (lower.contains('error') || lower.contains('fail') || lower.contains('required')) {
        throw ServerException(message);
      }
      final saved = _text(Map<String, dynamic>.from(body), const ['QuotationNo', 'quotationNo']);
      if (saved.isNotEmpty) return saved;
    }
    return quotationNo;
  }

  Future<void> deleteQuotation({
    required String clientCode,
    required int id,
  }) async {
    final body = await _api.post(AppConstants.deleteQuotation, {
      'Id': id,
      'ClientCode': clientCode,
      'BranchId': 1,
    });
    if (body is Map) {
      final message = '${body['Message'] ?? body['message'] ?? ''}'.trim();
      final lower = message.toLowerCase();
      if (lower.contains('error') || lower.contains('fail') || lower.contains('not found')) {
        throw ServerException(message.isEmpty ? 'Quotation could not be deleted' : message);
      }
    }
  }

  Future<({String name, String address, String gst})> companyProfile(String clientCode) async {
    final body = await _api.post(AppConstants.companyDetails, {'ClientCode': clientCode});
    final rows = _maps(body);
    if (rows.isEmpty) return (name: '', address: '', gst: '');
    final row = rows.first;
    final name = _text(row, const ['CompName', 'OrganisationName', 'OrganizationName']);
    final address = [
      _text(row, const ['CompRegisteredAddress', 'StreetAddress']),
      _text(row, const ['City']),
      _text(row, const ['State']),
      _text(row, const ['Country']),
    ].where((part) => part.isNotEmpty).join(', ');
    final gst = _text(row, const [
      'CompGSTINNo',
      'CompGstinNo',
      'GSTINNo',
      'GSTNo',
      'GstNo',
    ]);
    return (name: name, address: address, gst: gst);
  }

  Future<String> _nextQuotationNo(String clientCode) async {
    final body = await _api.post(AppConstants.lastQuotationNo, {
      'ClientCode': clientCode,
      'BranchId': 1,
    });
    var last = '';
    if (body is Map) {
      last = '${body['LastQuotationNo'] ?? body['lastQuotationNo'] ?? ''}'.trim();
    }
    final next = (int.tryParse(last) ?? 0) + 1;
    return '$next';
  }

  Map<String, dynamic> _quotationPayload({
    required String clientCode,
    required CustomerRecord customer,
    required List<StockItem> items,
    required bool gstApplied,
    required double gstRate,
    required int id,
    required String number,
    required Map<String, dynamic> source,
  }) {
    final names = customer.name.trim().split(RegExp(r'\s+'));
    final first = names.isEmpty ? '' : names.first;
    final last = names.length > 1 ? names.sublist(1).join(' ') : first;
    final now = DateTime.now();
    final date =
        '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    final priced = [
      for (final item in items) withLinePrice(item, priceLine(item, applyGst: gstApplied, gstFraction: gstRate)),
    ];
    final lines = [
      for (final item in priced) priceLine(item, applyGst: gstApplied, gstFraction: gstRate),
    ];
    final gross = _sum(priced, const ['grosswt', 'grossweight']);
    final stoneWeight = _sum(priced, const ['stonewt', 'stoneweight']);
    final stoneAmount = lines.fold<double>(0, (sum, line) => sum + line.stone);
    final diamondWeight = _sum(priced, const ['diamondwt', 'diamondweight']);
    final diamondAmount = lines.fold<double>(0, (sum, line) => sum + line.diamond);
    final diamondPieces = _sum(priced, const ['diamondpcs', 'diamondpieces']);
    final rateBase = lines.where((line) => !line.mrp).fold<double>(0, (sum, line) => sum + line.item);
    final mrpBase = lines.where((line) => line.mrp).fold<double>(0, (sum, line) => sum + line.total);
    final base = rateBase + mrpBase;
    final gst = lines.where((line) => !line.mrp).fold<double>(0, (sum, line) => sum + line.gst);
    final net = base + gst;
    final quotationItems = [
      for (final item in priced) _quotationItem(item, customer.id, id),
    ];
    final payload = source.isEmpty ? <String, dynamic>{} : Map<String, dynamic>.from(source);
    payload.addAll({
      'Id': id,
      'CustomerId': customer.id.toString(),
      'CustomerName': customer.name,
      'FirstName': first,
      'LastName': last,
      'MobileNo': customer.mobile,
      'Email': customer.email,
      'QuotationNo': number,
      'QuotationDate': date,
      'Date': date,
      'GrossWt': gross.toStringAsFixed(3),
      'TotalAmount': base.toStringAsFixed(2),
      'TotalStoneAmount': stoneAmount.toStringAsFixed(2),
      'TotalStoneWeight': stoneWeight.toStringAsFixed(3),
      'TotalStonePieces': '0',
      'TotalDiamondAmount': diamondAmount.toStringAsFixed(2),
      'TotalDiamondWeight': diamondWeight.toStringAsFixed(3),
      'TotalDiamondPieces': diamondPieces.toStringAsFixed(0),
      'GSTApplied': gstApplied ? '1' : '0',
      'TotalGSTAmount': gst.toStringAsFixed(2),
      'TotalNetAmount': net.toStringAsFixed(2),
      'PaymentMode': 'Cash',
      'QuotationItem': quotationItems,
      'ClientCode': clientCode,
      'CompanyId': 1,
      'BranchId': 1,
      'BaseCurrency': 'INR',
      'BillType': 'sale',
      'SaleType': 'quotation',
      'Visibility': 'private',
      'QuotationStatus': 'draft',
      'FinancialYear': '${now.year}',
      'Discount': '0',
      'TDS': '0',
      'CourierCharge': '0',
      'AdditionTaxApplied': '0',
      'AdvanceAmt': '0',
      'ReceivedAmount': '0',
      'BalanceAmount': net.toStringAsFixed(2),
      'CreditAmount': '0',
      'PurchaseStatus': 'pending',
      'CategoryId': 0,
      'CounterId': 1,
      'EmployeeId': int.tryParse(AppSession.userId) ?? 0,
      'VendorId': 0,
      'DeliveryAddress': '',
      'Qty': '${items.length}',
      'QuotationCount': '${items.length}',
      'MRP': net.toStringAsFixed(2),
      'Offer': '0',
    });
    return payload;
  }

  Map<String, dynamic> _quotationItem(StockItem item, int customerId, int quotationId) {
    String pick(List<String> keys, [String fallback = '0']) {
      for (final key in keys) {
        final value = item.extras[key];
        if (value != null && value.isNotEmpty) return value;
      }
      return fallback;
    }

    final parsedId = int.tryParse(item.extras['quotationitemid'] ?? '') ?? 0;
    final lineId = parsedId > 0 && parsedId < 1000000000 ? parsedId : 0;
    return {
      'Id': quotationId > 0 ? lineId : 0,
      'ItemCode': item.itemCode,
      'DesignName': pick(const ['designname', 'design'], item.design),
      'DesignId': pick(const ['designid']),
      'Purity': pick(const ['purity'], ''),
      'PurityId': int.tryParse(pick(const ['purityid'])) ?? 0,
      'GrossWt': pick(const ['grosswt', 'grossweight'], item.gross),
      'NetWt': pick(const ['netwt', 'netweight'], item.net),
      'StoneWt': pick(const ['stonewt', 'stoneweight']),
      'StonePieces': pick(const ['stonepcs', 'stonepieces']),
      'StoneAmount': pick(const ['stoneamt', 'stoneamount']),
      'TotalStoneAmount': pick(const ['stoneamt', 'stoneamount']),
      'DiamondWeight': pick(const ['diamondwt', 'diamondweight']),
      'DiamondPieces': pick(const ['diamondpcs', 'diamondpieces']),
      'DiamondAmount': pick(const ['diamondamt', 'diamondamount']),
      'TotalDiamondAmount': pick(const ['diamondamt', 'diamondamount']),
      'TotalDiamondPieces': pick(const ['diamondpcs', 'diamondpieces']),
      'DiamondClarity': pick(const ['diamondclarity'], ''),
      'DiamondColour': pick(const ['diamondcolour', 'diamondcolor'], ''),
      'Pieces': pick(const ['pieces', 'pcs'], '1'),
      'MetalRate': pick(const ['rate', 'metalrate']),
      'MetalAmount': pick(const ['metalamt', 'metalamount']),
      'MakingPerGram': pick(const ['makingpergram'], ''),
      'MakingPercentage': pick(const ['makingpercent', 'makingpercentage'], ''),
      'MakingFixedAmt': pick(const ['makingfixedamt', 'fixmaking'], ''),
      'MakingFixedWastage': pick(const ['makingfixedwastage', 'fixwastage'], ''),
      'MakingCharg': pick(const ['makingamt', 'makingamount', 'makingcharg']),
      'TotalItemAmount': pick(const ['itemamt', 'itemamount', 'totalitemamount', 'amount']),
      'Description': pick(const ['description', 'productname'], item.name),
      'BillType': 'sale',
      'CategoryId': int.tryParse(pick(const ['categoryid'])) ?? 0,
      'CategoryName': pick(const ['categoryname'], ''),
      'ProductId': int.tryParse(pick(const ['productid'])) ?? 0,
      'ProductName': pick(const ['productname', 'name'], item.name),
      'CustomerId': customerId,
      'QuotationItemId': lineId,
      'Quotationid': quotationId,
      'CreatedOn': DateTime.now().toIso8601String(),
      'Stones': const [],
      'MRP': pick(const ['mrp'], ''),
    };
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

  Future<List<QuotationField>> loadPosFields({
    required String clientCode,
    required String userId,
  }) async {
    final body = await _api.post(AppConstants.userPermissions, {
      'ClientCode': clientCode,
      'UserId': int.tryParse(userId) ?? userId,
      'isMobView': true,
      'PageName': AppConstants.quotationPageName,
      'visibility': 'Visible',
    });
    final modules = _modules(body);
    final fields = <QuotationField>[];
    for (final module in modules) {
      final page = '${module['PageName'] ?? ''}'.toLowerCase();
      if (page.isNotEmpty && page != AppConstants.quotationPageName) continue;
      final controls = module['PageControls'];
      if (controls is! List) continue;
      for (final raw in controls) {
        if (raw is! Map) continue;
        final row = Map<String, dynamic>.from(raw);
        final visibility = '${row['visibility'] ?? ''}'.toLowerCase();
        if (visibility == 'hidden' || visibility == 'none') continue;
        final key = '${row['key'] ?? ''}'.trim();
        if (key.isEmpty) continue;
        final editable = '${row['isEditable'] ?? row['IsEditable'] ?? 'true'}'
            .toLowerCase();
        fields.add(
          QuotationField(
            key: key,
            label: '${row['label'] ?? key}',
            placeholder: '${row['placeholder'] ?? ''}',
            place: '${row['place'] ?? 'middle'}'.toLowerCase(),
            priority: _int(row['priority']),
            type: '${row['type'] ?? 'text'}',
            readOnly: editable == 'false' ||
                _bool(row['readOnly'] ?? row['ReadOnly'] ?? row['isReadOnly']),
            suffix: _text(row, const ['suffix', 'Suffix', 'unit', 'Unit']),
          ),
        );
      }
    }
    fields.sort((a, b) => a.priority.compareTo(b.priority));
    return fields;
  }

  StockItem _quotationStockItem(Map<String, dynamic> row) {
    final item = _stockItem(row);
    final primary = _int(row['Id']);
    final lineId = primary > 0 ? primary : _int(row['QuotationItemId']);
    final extras = Map<String, String>.from(item.extras);
    if (lineId > 0) extras['quotationitemid'] = '$lineId';
    final code = item.itemCode.isNotEmpty
        ? item.itemCode
        : (item.rfid.isNotEmpty ? item.rfid : (lineId > 0 ? '$lineId' : ''));
    return StockItem(
      itemCode: code,
      name: item.name,
      rfid: item.rfid,
      gross: item.gross,
      net: item.net,
      design: item.design,
      extras: extras,
    );
  }

  StockItem _stockItem(Map<String, dynamic> row) {
    final extras = <String, String>{};
    row.forEach((key, value) {
      final text = '$value'.trim();
      if (text.isEmpty || text == 'null') return;
      extras[_token(key)] = text;
    });
    final itemCode = _text(row, const ['ItemCode', 'itemCode']);
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
    _copyAlias(extras, 'metalrate', 'rate');
    _copyAlias(extras, 'goldrate', 'rate');
    _copyAlias(extras, 'metalamount', 'metalamt');
    _copyAlias(extras, 'makingcharg', 'makingamt');
    _copyAlias(extras, 'makingamount', 'makingamt');
    _copyAlias(extras, 'makingpercentage', 'makingpercent');
    _copyAlias(extras, 'totalitemamount', 'itemamt');
    _copyAlias(extras, 'totalstoneamount', 'stoneamt');
    _copyAlias(extras, 'totaldiamondamount', 'diamondamt');
    extras.removeWhere((_, value) => value.isEmpty);
    return StockItem(
      itemCode: itemCode,
      name: name,
      rfid: rfid,
      gross: gross,
      net: net,
      design: design,
      extras: extras,
    );
  }

  void _copyAlias(Map<String, String> extras, String from, String to) {
    final value = extras[from];
    if (value != null && value.isNotEmpty) extras.putIfAbsent(to, () => value);
  }

  String _token(String value) =>
      value.toLowerCase().replaceAll(RegExp('[^a-z0-9]'), '');

  bool _bool(dynamic value) {
    final text = '$value'.toLowerCase();
    return text == 'true' || text == '1' || text == 'yes';
  }

  List<Map<String, dynamic>> _modules(dynamic body) {
    if (body is List) {
      return body.whereType<Map>().map((row) {
        final map = Map<String, dynamic>.from(row);
        final nested = map['Modules'];
        if (nested is List) {
          return nested.whereType<Map>().map(Map<String, dynamic>.from).toList();
        }
        return <Map<String, dynamic>>[map];
      }).expand((rows) => rows).toList();
    }
    if (body is Map) {
      final map = Map<String, dynamic>.from(body);
      final nested = map['Modules'] ?? map['data'] ?? map['Data'];
      if (nested != null) return _modules(nested);
    }
    return const [];
  }

  List<Map<String, dynamic>> _maps(dynamic body, [int depth = 0]) {
    if (depth > 4 || body == null) return const [];
    if (body is List) {
      return body.whereType<Map>().map(Map<String, dynamic>.from).toList();
    }
    if (body is Map) {
      final map = Map<String, dynamic>.from(body);
      for (final key in const [
        'data',
        'Data',
        'items',
        'Items',
        'result',
        'Result',
        'customers',
        'Customers',
      ]) {
        final nested = map[key];
        if (nested is List) return _maps(nested, depth + 1);
        if (nested is Map) {
          final inner = _maps(nested, depth + 1);
          if (inner.isNotEmpty) return inner;
        }
      }
    }
    throw const ServerException('Unexpected QA response');
  }

  String _text(Map<String, dynamic> row, List<String> keys) {
    for (final key in keys) {
      final value = row[key];
      if (value != null && '$value'.trim().isNotEmpty) return '$value'.trim();
    }
    return '';
  }

  int _int(dynamic value) {
    if (value is num) return value.toInt();
    return int.tryParse('$value') ?? 0;
  }
}
