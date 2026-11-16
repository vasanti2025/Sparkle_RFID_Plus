import 'dart:convert';

import '../../../core/constants/app_constants.dart';
import '../../../core/network/api_client.dart';
import '../../../core/session/app_session.dart';
import '../../inventory/data/inventory_stock.dart';
import '../../inventory/domain/inventory_catalog.dart';

class TransferTypeOption {
  const TransferTypeOption({required this.id, required this.name});

  final int id;
  final String name;

  (String, String)? get ends {
    final parts = name.split(RegExp(r'\s+to\s+', caseSensitive: false));
    if (parts.length < 2) return null;
    final from = parts[0].trim().toLowerCase();
    final to = parts[1].trim().toLowerCase();
    if (from.isEmpty || to.isEmpty) return null;
    return (from, to);
  }
}

class TransferEmployee {
  const TransferEmployee({required this.id, required this.name});

  final String id;
  final String name;
}

class TransferLine {
  const TransferLine({
    required this.approveId,
    required this.itemCode,
    required this.name,
    required this.status,
    required this.gross,
  });

  final int approveId;
  final String itemCode;
  final String name;
  final int? status;
  final String gross;
}

class TransferRecord {
  const TransferRecord({
    required this.id,
    required this.typeId,
    required this.typeName,
    required this.from,
    required this.to,
    required this.pending,
    required this.approved,
    required this.rejected,
    required this.lost,
    required this.requestType,
    required this.byEmployee,
    required this.toEmployee,
    required this.toBranch,
    required this.destinationId,
    required this.lines,
  });

  final int id;
  final int typeId;
  final String typeName;
  final String from;
  final String to;
  final int pending;
  final int approved;
  final int rejected;
  final int lost;
  final String requestType;
  final String byEmployee;
  final String toEmployee;
  final String toBranch;
  final int destinationId;
  final List<TransferLine> lines;

  bool get selfApproval {
    if (typeId == 15) {
      return byEmployee.isNotEmpty && byEmployee == toEmployee;
    }
    return true;
  }
}

class StockTransferApi {
  StockTransferApi({ApiClient? client}) : _api = client ?? ApiClient();

  final ApiClient _api;

  Future<List<TransferTypeOption>> types() async {
    final code = AppSession.clientCode;
    if (code.isEmpty) return const [];
    final body = await _api.post(AppConstants.stockTransferTypes, {'ClientCode': code});
    return [
      for (final row in _rows(body))
        if ((row['TransferType'] ?? row['transferType'] ?? '').toString().trim().isNotEmpty)
          TransferTypeOption(
            id: _int(row['Id'] ?? row['id']),
            name: (row['TransferType'] ?? row['transferType']).toString().trim(),
          ),
    ];
  }

  Future<List<TransferEmployee>> employees() async {
    final code = AppSession.clientCode;
    if (code.isEmpty) return const [];
    final body = await _api.post(AppConstants.userPermissions, {'ClientCode': code});
    final people = <TransferEmployee>[];
    for (final row in _rows(body)) {
      final id = _int(row['EmployeeId'] ?? row['employeeId']);
      final userId = _int(row['Id'] ?? row['UserId'] ?? row['id']);
      final chosen = id > 0 ? id : userId;
      if (chosen <= 0) continue;
      final name = '${row['FirstName'] ?? ''} ${row['LastName'] ?? ''}'.trim();
      people.add(TransferEmployee(id: '$chosen', name: name.isEmpty ? '$chosen' : name));
    }
    return people;
  }

  Future<String?> submit({
    required TransferTypeOption type,
    required String fromName,
    required String toName,
    required List<InventoryPiece> pieces,
    required String remarks,
    required String transferToEmployee,
  }) async {
    final code = AppSession.clientCode;
    final by = AppSession.employeeId > 0 ? '${AppSession.employeeId}' : AppSession.userId;
    final branch = AppSession.branchId;
    if (code.isEmpty || by.isEmpty) return 'Sign in to transfer stock.';
    if (type.id <= 0) return 'Choose a transfer type.';
    if (branch <= 0) return 'This account has no branch id for a transfer.';
    final ends = type.ends;
    final branchToBranch = type.id == 15 || (ends?.$1 == 'branch' && ends?.$2 == 'branch');
    final receiver = branchToBranch ? transferToEmployee.trim() : by;
    if (receiver.isEmpty) return 'Choose the employee who receives this stock.';

    final sourceId = branchToBranch
        ? _locationId('branch', fromName, branch)
        : _locationId(ends?.$1 ?? '', fromName, branch);
    final destinationId = branchToBranch
        ? _locationId('branch', toName, 0)
        : _locationId(ends?.$2 ?? '', toName, branch);
    if (branchToBranch && destinationId <= 0) return 'Could not resolve the destination branch.';

    final items = [
      for (final piece in pieces)
        if (piece.stockId > 0) {'stockId': piece.stockId},
    ];
    if (items.isEmpty) return 'Sync products again. These pieces have no stock id.';

    final now = DateTime.now();
    String two(int value) => value.toString().padLeft(2, '0');
    final body = await _api.post(AppConstants.addStockTransfer, {
      'ClientCode': code,
      'StockTransferItems': items,
      'StockType': 'labelled',
      'StockTransferTypeName': type.name,
      'TransferTypeId': type.id,
      'TransferByEmployee': by,
      'TransferedToBranch': branchToBranch ? '$destinationId' : '$branch',
      'TransferToEmployee': receiver,
      'TransferedBranch': branchToBranch ? '$sourceId' : '$branch',
      'Source': sourceId,
      'Destination': destinationId,
      'Remarks': remarks,
      'StockTransferDate': '${two(now.day)}-${two(now.month)}-${now.year}',
      'ReceivedByEmployee': '',
    });
    if (body is Map && (body['success'] == false || body['Success'] == false)) {
      return 'Transfer failed';
    }
    return null;
  }

  Future<List<TransferRecord>> list({
    required String requestType,
    int? typeId,
  }) async {
    final code = AppSession.clientCode;
    final userId = int.tryParse(AppSession.userId) ?? 0;
    if (code.isEmpty || userId <= 0) return const [];
    final seen = <int, TransferRecord>{};
    Future<void> pull(int branchId, int uid) async {
      final payload = <String, dynamic>{
        'ClientCode': code,
        'StockType': 'labelled',
        'BranchId': branchId,
        'UserID': uid,
        'RequestType': requestType,
      };
      if (typeId != null && typeId > 0) payload['TransferType'] = typeId;
      final body = await _api.post(AppConstants.allStockTransfers, payload);
      for (final row in _rows(body)) {
        final record = _record(row, requestType);
        if (record.id > 0) seen[record.id] = record;
      }
    }

    await pull(AppSession.branchNo, userId);
    if (AppSession.branchId > 0 && AppSession.branchId != AppSession.branchNo) {
      await pull(AppSession.branchId, userId);
    }
    if (seen.isEmpty && AppSession.employeeId > 0 && AppSession.employeeId != userId) {
      await pull(AppSession.branchNo, AppSession.employeeId);
    }
    final records = seen.values.toList()
      ..sort((a, b) => b.id.compareTo(a.id));
    return records;
  }

  Future<String?> cancel(int id) async {
    final body = await _api.post(AppConstants.cancelStockTransfer, {
      'Id': id,
      'ClientCode': AppSession.clientCode,
    });
    return _message(body) ?? 'Transfer cancelled';
  }

  Future<String?> decide({
    required List<TransferLine> lines,
    required String requestType,
    required int status,
  }) async {
    final items = [
      for (final line in lines)
        if (line.approveId > 0)
          {'Id': line.approveId, 'Approved': status == 1, 'Status': status},
    ];
    if (items.isEmpty) return 'Select at least one item.';
    final body = await _api.post(AppConstants.approveStockTransfer, {
      'StockTransferItems': items,
      'ClientCode': AppSession.clientCode,
      'UserID': AppSession.userId,
      'RequestTyp': requestType,
    });
    return _message(body) ?? 'Transfer updated';
  }

  Future<void> moveApproved({
    required TransferRecord record,
    required List<TransferLine> lines,
  }) async {
    final ends = record.typeName.split(RegExp(r'\s+to\s+', caseSensitive: false));
    final toType = ends.length >= 2 ? ends[1].trim().toLowerCase() : 'branch';
    final toName = record.to.trim().isNotEmpty ? record.to.trim() : record.toBranch.trim();
    if (toName.isEmpty) return;
    await InventoryStock.instance.movePieces(
      itemCodes: lines.map((line) => line.itemCode),
      toType: toType,
      toName: toName,
      destId: record.destinationId,
    );
  }

  int _locationId(String kind, String name, int fallback) {
    final id = InventoryStock.instance.locationId(kind, name);
    if (id > 0) return id;
    return fallback;
  }

  TransferRecord _record(Map<String, dynamic> json, String requestType) {
    final lines = <TransferLine>[];
    final rawLines = json['LabelledStockItems'] ?? json['StockTransferItems'];
    if (rawLines is List) {
      for (final entry in rawLines.whereType<Map>()) {
        final row = Map<String, dynamic>.from(entry);
        final lineId = _int(row['Id']);
        final approveId = _int(row['TransferItemId']) > 0 ? _int(row['TransferItemId']) : lineId;
        lines.add(
          TransferLine(
            approveId: approveId,
            itemCode: '${row['ItemCode'] ?? ''}'.trim(),
            name: '${row['ProductName'] ?? row['ProductTitle'] ?? ''}'.trim(),
            status: _status(row['RequestStatus'] ?? row['Status']),
            gross: '${row['GrossWt'] ?? row['GrossWeight'] ?? ''}'.trim(),
          ),
        );
      }
    }
    final from = '${json['SourceName'] ?? ''}'.trim();
    final to = '${json['DestinationName'] ?? ''}'.trim();
    return TransferRecord(
      id: _int(json['Id']),
      typeId: _int(json['TransferTypeId']),
      typeName: '${json['StockTransferTypeName'] ?? ''}'.trim(),
      from: from.isEmpty ? '${json['Source'] ?? ''}' : from,
      to: to.isEmpty ? '${json['DestinationName'] ?? json['TransferedToBranch'] ?? ''}' : to,
      pending: _int(json['Pending']),
      approved: _int(json['Approved']),
      rejected: _int(json['Rejected']),
      lost: _int(json['Lost']),
      requestType: '${json['RequestType'] ?? requestType}',
      byEmployee: '${json['TransferByEmployee'] ?? ''}'.trim(),
      toEmployee: '${json['TransferToEmployee'] ?? ''}'.trim(),
      toBranch: '${json['TransferedToBranch'] ?? ''}'.trim(),
      destinationId: _int(json['Destination']),
      lines: lines,
    );
  }
}

List<Map<String, dynamic>> _rows(dynamic body) {
  if (body is List) {
    return [for (final row in body) if (row is Map) Map<String, dynamic>.from(row)];
  }
  if (body is String && body.isNotEmpty) {
    try {
      return _rows(jsonDecode(body));
    } catch (_) {
      return const [];
    }
  }
  if (body is Map) {
    for (final key in ['data', 'Data', 'result', 'Result', 'StockTransfers', 'items', 'Items']) {
      final value = body[key];
      if (value is List || value is String) return _rows(value);
    }
  }
  return const [];
}

int _int(Object? value) {
  if (value is num) return value.toInt();
  return int.tryParse('$value') ?? 0;
}

int? _status(Object? value) {
  if (value == null) return null;
  if (value is num) return value.toInt();
  final text = value.toString().trim().toLowerCase();
  final parsed = int.tryParse(text);
  if (parsed != null) return parsed;
  if (text.contains('approv')) return 1;
  if (text.contains('reject')) return 2;
  if (text.contains('lost')) return 3;
  if (text.contains('pending')) return 0;
  return null;
}

String? _message(dynamic body) {
  if (body is Map) {
    for (final key in ['Message', 'message', 'StatusMessage']) {
      final value = body[key]?.toString().trim();
      if (value != null && value.isNotEmpty) return value;
    }
  }
  if (body is String && body.trim().isNotEmpty) return body.trim();
  return null;
}
