import 'dart:convert';

import '../../../../core/constants/app_strings.dart';
import '../../../../core/error/exceptions.dart';
import '../../domain/entities/user.dart';

class UserModel extends User {
  const UserModel({
    required super.id,
    required super.username,
    super.token,
    super.displayName,
    super.clientCode,
    super.branchId,
    super.roleId,
    super.branchName,
    super.organisationName,
    super.notice,
    this.sessionJson = '',
  });

  final String sessionJson;

  factory UserModel.fromLoginJson(Map<String, dynamic> json) {
    final employee = json['Employee'];
    if (employee is! Map) {
      throw ServerException(messageOf(json) ?? AppStrings.loginFailed);
    }
    final map = Map<String, dynamic>.from(employee);
    final clients = map['Clients'] is Map
        ? Map<String, dynamic>.from(map['Clients'] as Map)
        : const <String, dynamic>{};
    final firstName = _text(map['FirstName']);
    final lastName = _text(map['LastName']);
    final username = _text(map['Username'] ?? map['UserName']);
    final displayName = '$firstName $lastName'.trim();
    final expiry = _text(clients['PlanExpiryDate']);
    final daysRemaining = _daysRemaining(expiry);

    if (daysRemaining != null && daysRemaining < 0) {
      throw const ServerException(AppStrings.subscriptionExpired);
    }

    return UserModel(
      id: _text(map['Id']),
      username: username,
      token: _text(json['token']),
      displayName: displayName.isEmpty ? username : displayName,
      clientCode: _text(clients['ClientCode'] ?? map['ClientCode']),
      branchId: _int(map['DefaultBranchId']),
      roleId: _int(map['RoleId']),
      branchName: _text(map['DefaultBranch'] ?? map['BranchName']),
      organisationName: _text(
        clients['OrganisationName'] ?? clients['OrganizationName'],
      ),
      notice: daysRemaining != null && daysRemaining <= 15
          ? 'Your subscription will expire in $daysRemaining day(s). Please renew soon.'
          : null,
      sessionJson: jsonEncode(json),
    );
  }

  factory UserModel.fromJson(Map<String, dynamic> json) {
    return UserModel(
      id: _text(json['id']),
      username: _text(json['username']),
      token: _text(json['token']),
      displayName: _text(json['displayName']),
      clientCode: _text(json['clientCode']),
      branchId: _int(json['branchId']),
      roleId: _int(json['roleId']),
      branchName: _text(json['branchName']),
      organisationName: _text(json['organisationName']),
      sessionJson: _text(json['sessionJson']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'username': username,
      'token': token,
      'displayName': displayName,
      'clientCode': clientCode,
      'branchId': branchId,
      'roleId': roleId,
      'branchName': branchName,
      'organisationName': organisationName,
      'sessionJson': sessionJson,
    };
  }

  static String? messageOf(Map<String, dynamic> json) {
    for (final key in ['Message', 'message', 'error', 'Error']) {
      final value = json[key]?.toString().trim();
      if (value != null && value.isNotEmpty) return value;
    }
    return null;
  }

  static String _text(Object? value) => value?.toString().trim() ?? '';

  static int _int(Object? value) {
    if (value is num) return value.toInt();
    return int.tryParse('$value') ?? 0;
  }

  static int? _daysRemaining(String expiry) {
    final value = expiry.trim();
    if (value.length < 10) return null;
    try {
      final parsed = DateTime.parse(value.substring(0, 10));
      final today = DateTime.now();
      final todayStart = DateTime(today.year, today.month, today.day);
      final expiryStart = DateTime(parsed.year, parsed.month, parsed.day);
      return expiryStart.difference(todayStart).inDays;
    } on FormatException {
      return null;
    }
  }
}
