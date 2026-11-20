import '../../../core/constants/app_constants.dart';
import '../../../core/error/exceptions.dart';
import '../../../core/network/api_client.dart';
import '../../../core/session/app_session.dart';

/// One purity row with its current label rate. A row with [existing] false
/// has no saved rate yet; UpdateDailyRates still inserts it.
class DailyRateRow {
  DailyRateRow({
    required this.categoryId,
    required this.categoryName,
    required this.clientCode,
    required this.employeeCode,
    required this.finePercentage,
    required this.purityId,
    required this.purityName,
    required this.rate,
    required this.existing,
  });

  final int categoryId;
  final String categoryName;
  final String clientCode;
  final String employeeCode;
  final String finePercentage;
  final int purityId;
  final String purityName;
  String rate;
  final bool existing;

  Map<String, dynamic> toJson() {
    return {
      'CategoryId': categoryId,
      'CategoryName': categoryName,
      'ClientCode': clientCode,
      'EmployeeCode': employeeCode,
      'FinePercentage': finePercentage,
      'PurityId': purityId,
      'PurityName': purityName,
      'Rate': rate,
    };
  }
}

class DailyRateApi {
  DailyRateApi({ApiClient? client}) : _client = client ?? ApiClient();

  final ApiClient _client;

  /// Purity master merged with GetAllDailyRate, same as the old rate screen.
  Future<List<DailyRateRow>> load(String clientCode) async {
    final code = clientCode.trim();
    if (code.isEmpty) return const [];
    final body = {'ClientCode': code};
    final results = await Future.wait([
      _client.post(AppConstants.getAllPurity, body),
      _client.post(AppConstants.getAllDailyRate, body),
    ]);
    final purities = _rows(results[0]);
    final rates = _rows(results[1]);
    final employee = AppSession.employeeId > 0 ? '${AppSession.employeeId}' : '';
    if (purities.isNotEmpty) {
      return [
        for (final purity in purities)
          _fromPurity(purity, _matchRate(rates, purity), code, employee),
      ];
    }
    return [
      for (final rate in rates) _fromRate(rate, code, employee),
    ];
  }

  /// One call adds rows that have no rate yet and updates rows that do.
  Future<void> save(List<DailyRateRow> rows) async {
    if (rows.isEmpty) return;
    final body = await _client.postBody(
      AppConstants.updateDailyRates,
      rows.map((row) => row.toJson()).toList(),
    );
    if (body is Map && body['StatusType'] == false) {
      final message = _text(body['Message'] ?? body['message']);
      throw ServerException(message.isEmpty ? 'Failed to update rates' : message);
    }
  }

  DailyRateRow _fromPurity(
    Map<String, dynamic> purity,
    Map<String, dynamic>? rate,
    String clientCode,
    String employee,
  ) {
    return DailyRateRow(
      categoryId: _int(purity['CategoryId'] ?? rate?['CategoryId']),
      categoryName: _text(purity['CategoryName'] ?? rate?['CategoryName']),
      clientCode: _text(rate?['ClientCode']).isEmpty ? clientCode : _text(rate?['ClientCode']),
      employeeCode: _text(rate?['EmployeeCode']).isEmpty ? employee : _text(rate?['EmployeeCode']),
      finePercentage: _text(purity['FinePercentage'] ?? rate?['FinePercentage']).isEmpty
          ? '0'
          : _text(purity['FinePercentage'] ?? rate?['FinePercentage']),
      purityId: _int(purity['Id'] ?? purity['PurityId']),
      purityName: _text(purity['PurityName'] ?? rate?['PurityName']),
      rate: _text(rate?['Rate']).isEmpty ? '0.00' : _text(rate?['Rate']),
      existing: rate != null,
    );
  }

  DailyRateRow _fromRate(Map<String, dynamic> rate, String clientCode, String employee) {
    return DailyRateRow(
      categoryId: _int(rate['CategoryId']),
      categoryName: _text(rate['CategoryName']),
      clientCode: _text(rate['ClientCode']).isEmpty ? clientCode : _text(rate['ClientCode']),
      employeeCode: _text(rate['EmployeeCode']).isEmpty ? employee : _text(rate['EmployeeCode']),
      finePercentage: _text(rate['FinePercentage']).isEmpty ? '0' : _text(rate['FinePercentage']),
      purityId: _int(rate['PurityId'] ?? rate['Id']),
      purityName: _text(rate['PurityName']),
      rate: _text(rate['Rate']).isEmpty ? '0.00' : _text(rate['Rate']),
      existing: true,
    );
  }

  Map<String, dynamic>? _matchRate(List<Map<String, dynamic>> rates, Map<String, dynamic> purity) {
    final id = _int(purity['Id'] ?? purity['PurityId']);
    for (final rate in rates) {
      if (_int(rate['PurityId']) == id) return rate;
    }
    return null;
  }

  List<Map<String, dynamic>> _rows(dynamic body) {
    if (body is List) {
      return body.whereType<Map>().map(Map<String, dynamic>.from).toList();
    }
    if (body is Map) {
      for (final key in const ['data', 'Data', 'items', 'Items']) {
        final nested = body[key];
        if (nested is List) return _rows(nested);
      }
    }
    return const [];
  }

  static int _int(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  static String _text(Object? value) => value?.toString().trim() ?? '';
}
