import 'dart:convert';

import '../../../core/constants/app_constants.dart';
import '../../../core/network/api_client.dart';
import '../../../core/session/app_session.dart';

class PageControl {
  const PageControl({
    required this.id,
    required this.key,
    required this.label,
    required this.placeholder,
    required this.priority,
    required this.type,
    required this.visibility,
    required this.place,
    required this.options,
    this.suffix = '',
  });

  final int id;
  final String key;
  final String label;
  final String placeholder;
  final int priority;
  final String type;
  final String visibility;
  final String place;
  final List<String> options;
  final String suffix;

  bool get hidden {
    final value = visibility.toLowerCase();
    return value == 'hidden' || value == 'none' || value == 'false';
  }

  bool get readOnly {
    final value = visibility.toLowerCase().replaceAll(' ', '');
    if (value.contains('readwrite') || value.contains('write')) return false;
    return value.contains('read') || value == 'readonly';
  }

  String get kind => type.toLowerCase();

  bool get isAction {
    final slot = place.toLowerCase();
    if (kind.contains('button') || slot == 'button' || slot == 'action') return true;
    final token = key.toLowerCase().replaceAll(RegExp('[^a-z0-9]'), '');
    const actions = {'save', 'cancel', 'scan', 'submit', 'close', 'update', 'print'};
    if (actions.contains(token)) return true;
    final bare = token.startsWith('btn') ? token.substring(3) : token;
    return actions.contains(bare);
  }

}

class PageModule {
  const PageModule({
    required this.pageName,
    required this.displayName,
    required this.permission,
    required this.canCreate,
    required this.canEdit,
    required this.canDelete,
    required this.full,
    required this.controls,
  });

  final String pageName;
  final String displayName;
  final String permission;
  final bool canCreate;
  final bool canEdit;
  final bool canDelete;
  final bool full;
  final List<PageControl> controls;

  bool get enabled {
    final value = permission.toLowerCase();
    return value.isEmpty || value == 'enable' || value == 'enabled' || value == 'true';
  }
}

class PageLayoutApi {
  PageLayoutApi({ApiClient? client}) : _api = client ?? ApiClient();

  final ApiClient _api;

  Future<List<PageModule>> load({String pageName = AppConstants.deliveryPageName}) async {
    final clientCode = AppSession.clientCode;
    final userId = AppSession.userId;
    if (clientCode.isEmpty || userId.isEmpty) {
      throw StateError('Sign in to load this form.');
    }
    final parsedUser = int.tryParse(userId);
    final body = await _api.post(AppConstants.userPermissions, {
      'ClientCode': clientCode,
      'UserId': parsedUser ?? userId,
      'isMobView': true,
      'PageName': pageName,
    });
    return pageModulesFrom(body, pageName: pageName);
  }
}

List<PageModule> pageModulesFrom(dynamic body, {String pageName = AppConstants.deliveryPageName}) {
  return _modulesFor(body, pageName);
}

List<PageModule> _modulesFor(dynamic body, String pageName) {
  final modules = _modules(body);
  final wanted = pageName.toLowerCase();
  final named = modules.where((module) => module.pageName.toLowerCase() == wanted).toList();
  if (named.isNotEmpty) return named;
  if (modules.length == 1 && modules.first.pageName.isEmpty) return modules;
  return const [];
}

List<PageModule> _modules(dynamic body) {
  final rows = _moduleRows(body);
  return [
    for (final row in rows)
      PageModule(
        pageName: _text(row, const ['PageName', 'pageName']),
        displayName: _text(row, const ['PageDisplayName', 'pageDisplayName']),
        permission: _text(row, const ['PagePermission', 'pagePermission']),
        canCreate: _bool(row['Create'] ?? row['create']),
        canEdit: _bool(row['Edit'] ?? row['edit']),
        canDelete: _bool(row['Delete'] ?? row['delete']),
        full: _bool(row['Full'] ?? row['full'] ?? row['Ful1']),
        controls: _controls(_controlList(row)),
      ),
  ];
}

List<Map<String, dynamic>> _moduleRows(dynamic body) {
  if (body is List) {
    final rows = <Map<String, dynamic>>[];
    for (final entry in body) {
      if (entry is! Map) continue;
      final map = Map<String, dynamic>.from(entry);
      final nested = map['Modules'] ?? map['modules'];
      if (nested is List) {
        rows.addAll(_moduleRows(nested));
      } else if (_controlList(map) != null || map.containsKey('PageName') || map.containsKey('pageName')) {
        rows.add(map);
      }
    }
    return rows;
  }
  if (body is Map) {
    final map = Map<String, dynamic>.from(body);
    final rows = <Map<String, dynamic>>[];
    for (final entry in map.entries) {
      final key = entry.key.toString().toLowerCase();
      if (key != AppConstants.deliveryPageName && key.replaceAll('_', '') != 'mobdeliverychalan') {
        continue;
      }
      final value = entry.value;
      if (value is Map) {
        final module = Map<String, dynamic>.from(value);
        module.putIfAbsent('PageName', () => entry.key);
        rows.add(module);
      } else if (value is List) {
        rows.add({'PageName': entry.key, 'PageControls': value});
      }
    }
    if (rows.isNotEmpty) return rows;
    final nested = map['Modules'] ?? map['modules'] ?? map['data'] ?? map['Data'] ?? map['result'] ?? map['Result'];
    if (nested != null && nested != body) return _moduleRows(nested);
    if (_controlList(map) != null || map.containsKey('PageName') || map.containsKey('pageName')) {
      return [map];
    }
  }
  return const [];
}

dynamic _controlList(Map<String, dynamic> row) {
  for (final key in const [
    'PageControls',
    'pageControls',
    'PageControl',
    'pageControl',
    'pagecontrol',
    'Controls',
    'controls',
  ]) {
    final value = row[key];
    if (value is List) return value;
    if (value is String && value.trim().startsWith('[')) {
      return value;
    }
  }
  return null;
}

List<PageControl> _controls(dynamic raw) {
  if (raw is String) {
    try {
      raw = jsonDecode(raw);
    } catch (_) {
      return const [];
    }
  }
  if (raw is! List) return const [];
  final controls = <PageControl>[];
  for (final entry in raw) {
    if (entry is! Map) continue;
    final row = Map<String, dynamic>.from(entry);
    final key = _text(row, const [
      'key',
      'Key',
      'controlKey',
      'ControlKey',
      'fieldName',
      'FieldName',
      'controlName',
      'ControlName',
      'name',
      'Name',
    ]);
    if (key.isEmpty) continue;
    final visibility = _text(row, const ['visibility', 'Visibility']);
    final editable = '${row['isEditable'] ?? row['IsEditable'] ?? 'true'}'.toLowerCase();
    final flaggedReadOnly = _bool(row['readOnly'] ?? row['ReadOnly'] ?? row['isReadOnly']);
    final control = PageControl(
      id: _int(row['Id'] ?? row['id']),
      key: key,
      label: _text(row, const ['label', 'Label', 'displayName', 'DisplayName']).isEmpty
          ? key
          : _text(row, const ['label', 'Label', 'displayName', 'DisplayName']),
      placeholder: _text(row, const ['placeholder', 'Placeholder', 'hint', 'Hint']),
      priority: _int(row['priority'] ?? row['Priority'] ?? row['order'] ?? row['Order']),
      type: _text(row, const ['type', 'Type', 'controlType', 'ControlType']).isEmpty
          ? 'text'
          : _text(row, const ['type', 'Type', 'controlType', 'ControlType']),
      visibility: visibility.isEmpty ? 'ReadWrite' : visibility,
      place: _text(row, const ['place', 'Place', 'position', 'Position']).toLowerCase(),
      options: _options(row),
      suffix: _text(row, const ['suffix', 'Suffix', 'unit', 'Unit']),
    );
    if (control.hidden) continue;
    if (flaggedReadOnly || editable == 'false') {
      controls.add(
        PageControl(
          id: control.id,
          key: control.key,
          label: control.label,
          placeholder: control.placeholder,
          priority: control.priority,
          type: control.type,
          visibility: 'Read',
          place: control.place,
          options: control.options,
          suffix: control.suffix,
        ),
      );
      continue;
    }
    controls.add(control);
  }
  controls.sort((a, b) => a.priority.compareTo(b.priority));
  return controls;
}

List<String> _options(Map<String, dynamic> row) {
  for (final key in const ['options', 'Options', 'values', 'Values', 'items', 'Items', 'data', 'Data']) {
    final raw = row[key];
    if (raw is! List) continue;
    final values = <String>[];
    for (final entry in raw) {
      if (entry is Map) {
        final label = _text(Map<String, dynamic>.from(entry), const ['label', 'Label', 'name', 'Name', 'value', 'Value']);
        if (label.isNotEmpty) values.add(label);
      } else {
        final label = entry?.toString().trim() ?? '';
        if (label.isNotEmpty && label.toLowerCase() != 'null') values.add(label);
      }
    }
    if (values.isNotEmpty) return values;
  }
  return const [];
}

String _text(Map<String, dynamic> json, List<String> keys) {
  for (final key in keys) {
    final value = json[key]?.toString().trim() ?? '';
    if (value.isNotEmpty && value.toLowerCase() != 'null') return value;
  }
  return '';
}

int _int(Object? value) => value is num ? value.toInt() : int.tryParse('$value') ?? 0;

bool _bool(Object? value) {
  if (value is bool) return value;
  final text = '$value'.toLowerCase();
  return text == 'true' || text == '1' || text == 'yes';
}
