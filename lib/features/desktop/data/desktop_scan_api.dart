import '../../../core/constants/app_constants.dart';
import '../../../core/network/api_client.dart';

class DesktopScanRow {
  const DesktopScanRow({required this.epc, required this.rfid, required this.deviceId});

  final String epc;
  final String rfid;
  final String deviceId;
}

/// Same Scan to Desktop calls as the previous RFID app.
class DesktopScanApi {
  DesktopScanApi({ApiClient? client}) : _client = client ?? ApiClient();

  final ApiClient _client;

  Future<List<DesktopScanRow>> savedScans(String clientCode) async {
    final body = await _client.postBody(
      AppConstants.getAllRfidDetails,
      {'ClientCode': clientCode},
      timeout: const Duration(seconds: 40),
    );
    if (body is! Map) return const [];
    final map = Map<String, dynamic>.from(body);
    final success = map['success'] ?? map['Success'];
    if (success == false || success == 'false') return const [];
    final raw = map['data'] ?? map['Data'];
    if (raw is! List) return const [];
    final rows = <DesktopScanRow>[];
    for (final item in raw) {
      if (item is! Map) continue;
      final row = Map<String, dynamic>.from(item);
      final epc = '${row['TIDValue'] ?? row['EPC'] ?? ''}'.trim().toUpperCase();
      if (epc.isEmpty) continue;
      rows.add(
        DesktopScanRow(
          epc: epc,
          rfid: '${row['RFIDCode'] ?? ''}'.trim(),
          deviceId: '${row['DeviceId'] ?? ''}'.trim(),
        ),
      );
    }
    return rows;
  }

  Future<void> save(List<Map<String, dynamic>> rows) async {
    await _client.postBody(
      AppConstants.addRfidScans,
      rows,
      timeout: const Duration(seconds: 120),
    );
  }

  Future<int> clear({required String clientCode, required String deviceId}) async {
    final body = await _client.postBody(
      AppConstants.deleteRfidByDevice,
      {'ClientCode': clientCode, 'DeviceId': deviceId},
      timeout: const Duration(seconds: 40),
    );
    if (body is! Map) return -1;
    final map = Map<String, dynamic>.from(body);
    final success = map['success'] ?? map['Success'];
    if (success == false || success == 'false') return -1;
    return int.tryParse('${map['deletedRecords'] ?? map['DeletedRecords'] ?? 0}') ?? 0;
  }

  Future<void> registerDevice({required String clientCode, required String deviceId}) async {
    await _client.postBody(
      AppConstants.updateDeviceUsers,
      [
        {'id': clientCode, 'deviceId': deviceId},
      ],
      timeout: const Duration(seconds: 15),
    );
  }
}
