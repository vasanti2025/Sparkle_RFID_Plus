/// ### English
///
/// Flutter plug-in implementation of RFID, Barcode and other functions. The specific interface is as follows: <br/>
///
/// - [RfidWithUart] - Handheld device RFID-related interface.
/// - [RfidWithUra4] - Fixed device RFID-related interface.
/// - [BarcodeDecoder] - Barcode decoding-related interface.
/// - [DeviceManager] - Device information-related interface.
///
///
/// ### 中文
///
/// Flutter 超高频、条码等功能的插件实现，具体接口如下： <br/>
///
/// - [RfidWithUart] - 手持设备 RFID 相关接口
/// - [RfidWithUra4] - 固定式设备 RFID 相关接口
/// - [BarcodeDecoder] - 条码解码相关接口
/// - [DeviceManager] - 设备信息相关接口
///
library;

export 'src/rfid_with_uart.dart';
export 'src/rfid_with_ura4.dart';
export 'src/device_manager.dart';
export 'src/barcode_decoder.dart';
export 'src/rfid_key_event.dart';

export 'package:rfid_flutter_core/rfid_flutter_core.dart';
