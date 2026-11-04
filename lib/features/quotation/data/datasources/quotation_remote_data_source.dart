import '../../../../core/constants/app_constants.dart';
import '../../../../core/error/exceptions.dart';
import '../../../../core/network/api_client.dart';
import '../../domain/entities/customer_record.dart';
import '../../domain/entities/quotation_field.dart';
import '../../domain/entities/stock_item.dart';

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
  }) async {
    final parts = name.trim().split(RegExp(r'\s+'));
    final first = parts.first;
    final last = parts.length > 1 ? parts.sublist(1).join(' ') : '';
    await _api.post(AppConstants.addCustomer, {
      'FirstName': first,
      'LastName': last,
      'Mobile': mobile,
      'Email': email,
      'ClientCode': clientCode,
      'CurrAddState': '',
      'City': '',
      'CurrAddStreet': '',
      'Country': 'India',
      'GstNo': '',
    });
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
        fields.add(
          QuotationField(
            key: key,
            label: '${row['label'] ?? key}',
            placeholder: '${row['placeholder'] ?? ''}',
            place: '${row['place'] ?? 'middle'}'.toLowerCase(),
            priority: _int(row['priority']),
            type: '${row['type'] ?? 'text'}',
          ),
        );
      }
    }
    fields.sort((a, b) => a.priority.compareTo(b.priority));
    return fields;
  }

  StockItem _stockItem(Map<String, dynamic> row) {
    return StockItem(
      itemCode: _text(row, const ['ItemCode', 'itemCode']),
      name: _text(row, const ['ProductName', 'DesignName', 'ItemName', 'Name']),
      rfid: _text(row, const ['RFIDCode', 'TIDNumber', 'TidNumber']),
      gross: _text(row, const ['GrossWt', 'GrossWeight']),
      net: _text(row, const ['NetWt', 'NetWeight']),
      design: _text(row, const ['DesignName', 'Design']),
    );
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
