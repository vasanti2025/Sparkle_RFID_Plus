import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';

/// Plays the same scan tones as the Sparkle RFID handheld app.
class ScanSound {
  ScanSound._();

  static const _channel = MethodChannel('com.loyalstring.sparkle_rfid_plus/scan_sound');
  static var _lastBeepMs = 0;
  static var _lastSearchId = -1;
  static Timer? _quiet;

  static Future<void> prepare() => _call('prepare');

  static Future<void> startInventory() => _call('startInventorySound');

  static Future<void> stopInventory() => _call('stopInventorySound');

  static Future<void> stopAll() {
    _quiet?.cancel();
    _lastSearchId = -1;
    return _call('stopAll');
  }

  /// Short barcode beep. Inventory uses this on each newly matched tag.
  static Future<void> beep() async {
    final now = DateTime.now().millisecondsSinceEpoch;
    if (now - _lastBeepMs < 40) return;
    _lastBeepMs = now;
    await _call('playBeep');
  }

  /// Search tone for the current RSSI bucket. Loops until the range changes.
  static Future<void> playForRssi(String rssi) async {
    final id = soundIdForRssi(rssi);
    if (id < 0) return;
    if (id == _lastSearchId) {
      _armQuiet();
      return;
    }
    _lastSearchId = id;
    _armQuiet();
    await _call('playSound', {'id': id, 'loop': -1});
  }

  static void _armQuiet() {
    _quiet?.cancel();
    _quiet = Timer(const Duration(seconds: 1), () {
      _lastSearchId = -1;
      unawaited(_call('stopSound'));
    });
  }

  static Future<void> _call(String method, [Map<String, Object>? args]) async {
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod<void>(method, args);
    } on PlatformException {
      // Reader sound is optional if the channel is not ready.
    }
  }
}

/// Sparkle search buckets: under 50 fourty, under 60 sixty, under 70 found2, else beep.
int soundIdForRssi(String rssi) {
  final match = RegExp(r'-?\d+(?:\.\d+)?').firstMatch(rssi);
  final value = double.tryParse(match?.group(0) ?? '');
  if (value == null || value == 0) return -1;
  final magnitude = value.abs();
  if (magnitude < 50) return 4;
  if (magnitude < 60) return 2;
  if (magnitude < 70) return 5;
  return 1;
}
