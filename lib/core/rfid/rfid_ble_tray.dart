import 'dart:async';

import 'package:flutter/services.dart';
import 'package:rfid_flutter_android/rfid_flutter_android.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Bluetooth RFID tray on the same Chainway SDK as the handheld reader.
///
/// A tray is used only when Android already shows it connected, the same way
/// a headphone stays connected. Headphones and other accessories are ignored.
class RfidBleTray {
  RfidBleTray() {
    _events.receiveBroadcastStream().listen((event) {
      if (event is! Map || event['type'] != 'RFID_TAG') return;
      final tag = RfidTagInfo.fromMap(event);
      if (tag == null) return;
      if (tag.epc.trim().toUpperCase().startsWith('0000')) return;
      if (!_tags.isClosed) _tags.add([tag]);
    }, onError: (_) {});
  }

  static const _channel = MethodChannel('rfid_flutter_android/ble');
  static const _events = EventChannel('rfid_flutter_android/bleEvent');
  static const _addressKey = 'tray_bt_address';

  final _tags = StreamController<List<RfidTagInfo>>.broadcast();
  final _rejected = <String>{};

  Stream<List<RfidTagInfo>> get tags => _tags.stream;

  bool connected = false;
  String address = '';
  bool needsPermission = false;

  /// Tray Android already shows as connected. Headphones are ignored.
  Future<bool> attachIfConnected() async {
    needsPermission = false;
    if (await _stillConnected()) return true;
    final devices = await _invoke<List<dynamic>>('listConnected');
    if (devices == null) return false;
    final rows = _rows(devices);
    if (rows.isEmpty) {
      await _notePermission();
      return false;
    }
    final chosen = await _choose(rows, allowUnknown: true);
    if (chosen == null) return false;
    return _connect(chosen, 12000);
  }

  /// Paired tray on a phone, after the handheld UART reader is absent.
  Future<bool> attachPaired() async {
    needsPermission = false;
    if (await _stillConnected()) return true;
    final devices = await _invoke<List<dynamic>>('bondedDevices');
    if (devices == null) return false;
    final rows = _rows(devices);
    if (rows.isEmpty) {
      await _notePermission();
      return false;
    }
    final chosen = await _choose(rows, allowUnknown: rows.length == 1);
    if (chosen == null) return false;
    return _connect(chosen, 15000);
  }

  Future<bool> _stillConnected() async {
    if (!connected || address.isEmpty) return false;
    final still = await _invoke<bool>('isConnected') ?? false;
    if (still) return true;
    connected = false;
    return false;
  }

  List<Map<String, String>> _rows(List<dynamic> devices) {
    final rows = <Map<String, String>>[];
    for (final item in devices) {
      if (item is! Map) continue;
      final name = item['name']?.toString() ?? '';
      final mac = item['address']?.toString() ?? '';
      if (mac.isEmpty || _isAccessory(name)) continue;
      rows.add({'name': name, 'address': mac});
    }
    return rows;
  }

  Future<Map<String, String>?> _choose(List<Map<String, String>> rows, {required bool allowUnknown}) async {
    final prefs = await SharedPreferences.getInstance();
    final saved = (prefs.getString(_addressKey) ?? '').toUpperCase();
    if (saved.isNotEmpty && !_rejected.contains(saved)) {
      for (final row in rows) {
        if (row['address']!.toUpperCase() == saved) return row;
      }
    }
    for (final row in rows) {
      if (_looksLikeTray(row['name'] ?? '')) return row;
    }
    if (allowUnknown && rows.length == 1 && !_rejected.contains(rows.first['address']!.toUpperCase())) {
      return rows.first;
    }
    return null;
  }

  Future<bool> _connect(Map<String, String> chosen, int timeoutMs) async {
    final mac = chosen['address']!;
    final ok = await _invoke<bool>('connect', {'address': mac, 'timeoutMs': timeoutMs}) ?? false;
    if (!ok) {
      if (!_looksLikeTray(chosen['name'] ?? '')) _rejected.add(mac.toUpperCase());
      connected = false;
      return false;
    }
    address = mac;
    connected = true;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_addressKey, mac);
    return true;
  }

  Future<void> _notePermission() async {
    final allowed = await _invoke<bool>('hasPermission');
    if (allowed == false) {
      needsPermission = true;
      await _invoke<bool>('requestPermission');
    }
  }

  Future<bool> setInventoryMode(int bank) async {
    return await _invoke<bool>('setInventoryMode', {
          'inventoryBank': bank,
          'offset': 0,
          'length': 0,
        }) ??
        false;
  }

  Future<bool> setPower(int power) async {
    return await _invoke<bool>('setPower', {'value': power}) ?? false;
  }

  Future<bool> start() async {
    final ok = await _invoke<bool>('startInventory') ?? false;
    if (!ok) connected = false;
    return ok;
  }

  Future<void> stop() async {
    await _invoke<bool>('stopInventory');
  }

  Future<T?> _invoke<T>(String method, [Map<String, Object?>? args]) async {
    try {
      return await _channel.invokeMethod<T>(method, args);
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    }
  }

  bool _isAccessory(String name) {
    final value = name.toUpperCase().replaceAll(' ', '');
    return value.contains('HEADSET') ||
        value.contains('HEADPHONE') ||
        value.contains('AIRPOD') ||
        value.contains('WATCH') ||
        value.contains('SPEAKER') ||
        value.contains('PRINTER') ||
        value.contains('MOUSE') ||
        value.contains('KEYBOARD') ||
        value.contains('BUDS') ||
        value.contains('EARPHONE');
  }

  bool _looksLikeTray(String name) {
    final value = name.toUpperCase().replaceAll(' ', '');
    if (_isAccessory(name)) return false;
    return value.contains('TRAY') ||
        value.contains('UHF') ||
        value.contains('RFID') ||
        value.contains('R2000') ||
        value.contains('CHAINWAY') ||
        value.contains('IMINI') ||
        value.contains('RPAN') ||
        value.contains('R-PAN') ||
        value.contains('BLE') ||
        value.contains('READER') ||
        value.contains('R6') ||
        value.startsWith('UR') ||
        value.startsWith('CW');
  }
}
