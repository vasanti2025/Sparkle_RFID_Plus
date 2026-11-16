import 'dart:io';

import 'package:flutter/services.dart';

/// Camera and location are asked on the login screen, not when a scan starts.
class ScanPermissions {
  ScanPermissions._();

  static const _channel = MethodChannel('com.loyalstring.sparkle_rfid_plus/permissions');

  static Future<void> request() async {
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod<bool>('requestScanPermissions');
    } on PlatformException {
      // Login can continue if the permission sheet is dismissed.
    }
  }
}