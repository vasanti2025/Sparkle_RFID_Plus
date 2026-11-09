import 'dart:async';

import 'package:flutter/services.dart';
import 'package:rfid_flutter_core/rfid_flutter_core.dart';
import 'package:rfid_flutter_android/src/method_channel_helper.dart';

/// Barcode decoder interface implementation <br/>
/// 条码解码器接口实现 <br/>
///
/// ### English
///
/// Basic usage flow: [init] -> ... -> [free]
///
/// #### Note:
/// 1. BarcodeDecoder uses singleton pattern, please do not create instances, use BarcodeDecoder.instance to get the instance and call the various interfaces.
/// 2. Before calling other commands, please call the [init] method to initialize the plugin and open the scanner, and call the [free] method to release resources and close the scanner when not in use.
/// 3. After initialization is completed, scanning can be enabled through the [startScan] method, and the barcode data will be returned through the [barcodeStream]. You can use the [stopScan] method to stop scanning.
///
/// ### 中文
///
/// 基本使用流程：[init] -> ... -> [free]
///
/// #### 注意事项：
/// 1. BarcodeDecoder 使用了单例模式，请不要创建实例，使用 BarcodeDecoder.instance 获取实例调用各个接口即可
/// 2. 调用其他命令前，请先调用 [init] 方法初始化插件并打开扫描头，不再使用时调用 [free] 方法释放资源并关闭扫描头
/// 3. 完成初始化后，可通过 [startScan] 方法开启扫描，条码数据将通过 [barcodeStream] 流式返回。可以使用 [stopScan] 方法停止扫描
///
class BarcodeDecoder {
  static BarcodeDecoder? _instance;

  /// The instance of BarcodeDecoder <br/>
  /// 条码解码器实例
  static BarcodeDecoder get instance {
    _instance ??= BarcodeDecoder._();
    return _instance!;
  }

  late final MethodChannel _channel;
  late final MethodChannelHelper _methodChannelHelper;
  late final StreamController<RfidBarcodeInfo> _barcodeStreamController;

  BarcodeDecoder._() {
    _channel = const MethodChannel('rfid_flutter_android/barcode');
    _methodChannelHelper = MethodChannelHelper(_channel);

    // 使用广播流控制器以支持多个监听器
    _barcodeStreamController = StreamController<RfidBarcodeInfo>.broadcast();

    const eventChannel = EventChannel('rfid_flutter_android/barcodeEvent');
    eventChannel.receiveBroadcastStream().listen((event) {
      // print('barcodeEvent: $event');
      if (event['type'] == 'BARCODE_TAG') {
        final barcodeInfo = RfidBarcodeInfo.fromMap(event);
        if (barcodeInfo == null) return;

        _barcodeStreamController.add(barcodeInfo);
      }
    });
  }

  /// The stream of barcode data <br/>
  /// 条码数据流
  Stream<RfidBarcodeInfo> get barcodeStream => _barcodeStreamController.stream;

  /// Initialize the plugin and open the scanner <br/>
  /// 初始化插件并打开扫描头
  Future<RfidResult<bool>> init() async {
    return _methodChannelHelper.invokeBoolMethod('init');
  }

  /// Release resources and close the scanner <br/>
  /// 释放资源并关闭扫描头
  Future<RfidResult<bool>> free() async {
    return _methodChannelHelper.invokeBoolMethod('free');
  }

  /// Check if the plugin is initialized <br/>
  /// 检查插件是否已初始化
  Future<RfidResult<bool>> isInitialized() async {
    return _methodChannelHelper.invokeBoolMethod('isInitialized');
  }

  /// Start scanning <br/>
  /// 开启扫描
  Future<RfidResult<bool>> startScan() async {
    return _methodChannelHelper.invokeBoolMethod('startScan');
  }

  /// Stop scanning <br/>
  /// 停止扫描
  Future<RfidResult<bool>> stopScan() async {
    return _methodChannelHelper.invokeBoolMethod('stopScan');
  }

  /// Set the timeout for the scanner <br/>
  /// 设置扫描超时时间
  ///
  /// #### English
  /// [value] is the timeout for the scanner, in seconds
  ///
  /// #### 中文
  /// [value] 为扫描超时时间，单位为秒
  ///
  Future<RfidResult<bool>> setTimeout(int value) async {
    return _methodChannelHelper.invokeBoolMethod('setTimeout', {'value': value});
  }
}
