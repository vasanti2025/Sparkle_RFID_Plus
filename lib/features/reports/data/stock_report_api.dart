import '../../../core/constants/app_constants.dart';
import '../../../core/network/api_client.dart';

class StockReportApi {
  StockReportApi({ApiClient? client}) : _client = client ?? ApiClient();

  final ApiClient _client;

  static const _timeout = Duration(minutes: 5);

  Future<String> sessions(String clientCode) {
    return _client.postRaw(
      AppConstants.stockVerificationSessions,
      {'ClientCode': clientCode.trim()},
      timeout: _timeout,
    );
  }

  Future<String> batchDetails({
    required String clientCode,
    required String scanBatchId,
  }) {
    return _client.postRaw(
      AppConstants.stockVerificationSessions,
      {
        'ClientCode': clientCode.trim(),
        'ScanBatchId': scanBatchId,
        'ReturnAllData': true,
      },
      timeout: _timeout,
    );
  }

  Future<String> consolidated({
    required String clientCode,
    required String reportDate,
  }) {
    return _client.postRaw(
      AppConstants.consolidatedStockReport,
      {
        'ClientCode': clientCode.trim(),
        'ReportDate': reportDate,
      },
      timeout: _timeout,
    );
  }

  Future<List<({int id, String name})>> branches(String clientCode) async {
    final body = await _client.post(
      AppConstants.getAllBranchMaster,
      {'ClientCode': clientCode.trim()},
      timeout: const Duration(seconds: 40),
    );
    final rows = <({int id, String name})>[];
    final list = body is List
        ? body
        : (body is Map ? (body['Branches'] ?? body['branches'] ?? body['Data']) : null);
    if (list is! List) return rows;
    for (final row in list) {
      if (row is! Map) continue;
      final id = _int(row['Id'] ?? row['BranchId'] ?? row['branchId']);
      final name = '${row['BranchName'] ?? row['Name'] ?? ''}'.trim();
      if (id <= 0 || name.isEmpty) continue;
      rows.add((id: id, name: name));
    }
    return rows;
  }

  int _int(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.round();
    return int.tryParse('$value') ?? 0;
  }
}
