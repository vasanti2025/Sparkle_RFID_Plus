import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:rfid_flutter_android/rfid_flutter_android.dart';

/// Chainway inventory mode for LED tags. The Dart enum only lists EPC modes,
/// but the Android plugin accepts this value.
const int kLedTagInventoryMode = 14;

const int kEpcInventoryMode = 0;

class RfidService {
  RfidService._();

  static final RfidService instance = RfidService._();

  static const MethodChannel _uart = MethodChannel('rfid_flutter_android/uart');

  bool _ready = false;

  bool get isSupported => Platform.isAndroid;

  bool get isReady => _ready;

  RfidWithUart get _reader => RfidWithUart.instance;

  Stream<RfidKeyEvent> get keyDownStream => DeviceManager.instance.keyDownEventStream;

  Future<String?> init() async {
    if (!isSupported) {
      return 'This RFID reader runs on Android handhelds only.';
    }
    if (_ready) return null;

    final result = await _reader.init();
    if (!result.isEffective) {
      return result.error ?? 'RFID init failed';
    }
    _ready = true;
    return null;
  }

  Future<void> stopIfRunning() async {
    if (!isSupported || !_ready) return;
    final running = await _reader.isInventorying();
    if (running.data == true) {
      await _reader.stopInventory();
    }
  }

  /// Reads one nearby tag in EPC mode. Used by quotation scan.
  Future<({String? error, String? epc})> readOneEpc() async {
    final blocked = await _requireReady();
    if (blocked != null) return (error: blocked, epc: null);
    await stopIfRunning();
    final modeError = await setInventoryMode(kEpcInventoryMode);
    if (modeError != null) return (error: modeError, epc: null);
    final result = await singleInventory();
    final epc = result.tag?.epc.trim() ?? '';
    if (epc.isEmpty) {
      return (error: result.error ?? 'No tag found', epc: null);
    }
    return (error: null, epc: epc);
  }

  Future<String?> setInventoryMode(int bank) async {
    final blocked = await _requireReady();
    if (blocked != null) return blocked;
    try {
      final ok = await _uart.invokeMethod<bool>('setInventoryMode', {
        'inventoryBank': bank,
        'offset': 0,
        'length': 0,
      });
      if (ok != true) return 'Could not set inventory mode';
      return null;
    } on PlatformException catch (error) {
      return error.message ?? error.code;
    }
  }

  Future<({String? error, String label})> readInventoryMode() async {
    final blocked = await _requireReady();
    if (blocked != null) return (error: blocked, label: '');
    try {
      final raw = await _uart.invokeMethod<dynamic>('getInventoryMode');
      if (raw is! Map) return (error: 'Could not read inventory mode', label: '');
      final bank = raw['inventoryBank'];
      return (error: null, label: inventoryModeLabel(bank));
    } on PlatformException catch (error) {
      return (error: error.message ?? error.code, label: '');
    }
  }

  Stream<List<RfidTagInfo>> get tagStream => _reader.rfidTagStream;

  Future<String?> startInventory({List<RfidFilter>? filters, bool unique = false}) async {
    final blocked = await _requireReady();
    if (blocked != null) return blocked;
    final result = await _reader.startInventory(
      filters: filters,
      inventoryParam: RfidInventoryParam(unique: unique),
    );
    if (!result.isEffective) return result.error ?? 'Start scan failed';
    return null;
  }

  Future<String?> stopInventory() async {
    final blocked = await _requireReady();
    if (blocked != null) return blocked;
    final result = await _reader.stopInventory();
    if (!result.isEffective) return result.error ?? 'Stop scan failed';
    return null;
  }

  Future<({String? error, RfidTagInfo? tag})> singleInventory({
    List<RfidFilter>? filters,
  }) async {
    final blocked = await _requireReady();
    if (blocked != null) return (error: blocked, tag: null);
    final result = await _reader.singleInventory(filters: filters);
    if (!result.result || result.data == null) {
      return (error: result.error ?? 'No tag found', tag: null);
    }
    return (error: null, tag: result.data);
  }

  Future<({String? error, String? data})> readData({
    required RfidBank bank,
    required int offset,
    required int length,
    required String password,
    RfidFilter? filter,
  }) async {
    final blocked = await _requireReady();
    if (blocked != null) return (error: blocked, data: null);
    final result = await _reader.readData(
      filter: filter,
      bank: bank,
      offset: offset,
      length: length,
      password: password,
    );
    if (!result.result || result.data == null) {
      return (error: result.error ?? 'Read failed', data: null);
    }
    return (error: null, data: result.data);
  }

  Future<String?> writeData({
    required RfidBank bank,
    required int offset,
    required int length,
    required String password,
    required String data,
    RfidFilter? filter,
  }) async {
    final blocked = await _requireReady();
    if (blocked != null) return blocked;
    final result = await _reader.writeData(
      filter: filter,
      bank: bank,
      offset: offset,
      length: length,
      password: password,
      data: data,
    );
    if (!result.isEffective) return result.error ?? 'Write failed';
    return null;
  }

  Future<String?> lockTag({
    required String password,
    required List<RfidLockBank> banks,
    required RfidLockMode mode,
    RfidFilter? filter,
  }) async {
    final blocked = await _requireReady();
    if (blocked != null) return blocked;
    final result = await _reader.lockTag(
      filter: filter,
      password: password,
      lockBanks: banks,
      lockMode: mode,
    );
    if (!result.isEffective) return result.error ?? 'Lock failed';
    return null;
  }

  Future<String?> killTag({
    required String password,
    RfidFilter? filter,
  }) async {
    final blocked = await _requireReady();
    if (blocked != null) return blocked;
    final result = await _reader.killTag(filter: filter, password: password);
    if (!result.isEffective) return result.error ?? 'Kill failed';
    return null;
  }

  Future<String?> setPower(int power) async {
    final blocked = await _requireReady();
    if (blocked != null) return blocked;
    final result = await _reader.setPower(power);
    if (!result.isEffective) return result.error ?? 'Set power failed';
    return null;
  }

  Future<({String? error, int? power})> getPower() async {
    final blocked = await _requireReady();
    if (blocked != null) return (error: blocked, power: null);
    final result = await _reader.getPower();
    if (!result.result || result.data == null) {
      return (error: result.error ?? 'Get power failed', power: null);
    }
    return (error: null, power: result.data);
  }

  Future<String?> setFrequency(RfidFrequency frequency) async {
    final blocked = await _requireReady();
    if (blocked != null) return blocked;
    final result = await _reader.setFrequency(frequency);
    if (!result.isEffective) return result.error ?? 'Set frequency failed';
    return null;
  }

  Future<({String? error, RfidFrequency? frequency})> getFrequency() async {
    final blocked = await _requireReady();
    if (blocked != null) return (error: blocked, frequency: null);
    final result = await _reader.getFrequency();
    if (!result.result || result.data == null) {
      return (error: result.error ?? 'Get frequency failed', frequency: null);
    }
    return (error: null, frequency: result.data);
  }

  Future<({String? error, String? version})> firmwareVersion() async {
    final blocked = await _requireReady();
    if (blocked != null) return (error: blocked, version: null);
    final result = await _reader.getUhfFirmwareVersion();
    if (!result.result) {
      return (error: result.error ?? 'Firmware read failed', version: null);
    }
    return (error: null, version: result.data);
  }

  Future<({String? error, int? temperature})> temperature() async {
    final blocked = await _requireReady();
    if (blocked != null) return (error: blocked, temperature: null);
    final result = await _reader.getUhfTemperature();
    if (!result.result || result.data == null) {
      return (error: result.error ?? 'Temperature read failed', temperature: null);
    }
    return (error: null, temperature: result.data);
  }

  Future<String?> _requireReady() async {
    final error = await init();
    if (error != null) return error;
    return null;
  }
}

/// Listens for the handheld scan trigger while a screen is open.
class RfidTrigger {
  StreamSubscription<RfidKeyEvent>? _keys;

  void attach(Future<void> Function() onScan) {
    if (!RfidService.instance.isSupported) return;
    unawaited(RfidService.instance.init());
    _keys = RfidService.instance.keyDownStream.listen((event) {
      if (isScanKey(event)) unawaited(onScan());
    });
  }

  void detach() {
    _keys?.cancel();
    _keys = null;
  }
}

String inventoryModeLabel(Object? bank) {
  return switch (bank) {
    kEpcInventoryMode => 'EPC',
    1 => 'EPC + TID',
    2 => 'EPC + TID + USER',
    kLedTagInventoryMode => 'LED tag',
    15 => 'Temperature tag',
    _ => 'Mode $bank',
  };
}

List<RfidFilter>? epcFilter(String raw) {
  final data = raw.trim();
  if (data.isEmpty) return null;
  return [
    RfidFilter(
      enabled: true,
      bank: RfidBank.epc,
      offset: 32,
      length: data.length * 4,
      data: data,
    ),
  ];
}

bool isHex(String value) {
  return RegExp(r'^[0-9A-Fa-f]*$').hasMatch(value);
}

const scanKeyCodes = <int>{
  139,
  280,
  291,
  293,
  294,
  311,
  312,
  313,
  315,
  591,
  593,
  594,
};

bool isScanKey(RfidKeyEvent event) => scanKeyCodes.contains(event.keyCode);

/// Reads every tag in range, then stops when the tray goes quiet.
///
/// EPC + TID inventory reports tags one after another. The radio stays on
/// long enough for the rest of the tags to arrive, instead of stopping
/// after the first one.
class RfidTrayScan {
  StreamSubscription<List<RfidTagInfo>>? _tags;
  Timer? _idle;
  Timer? _max;
  var _session = 0;
  var _fast = false;

  /// [fast] is the order scan: stop shortly after the last new tag instead of
  /// holding the radio for several seconds. Quotation keeps the longer read.
  Future<({String? error, List<String> codes, List<List<String>> tags})> collect({
    void Function(int count)? onCount,
    bool fast = false,
  }) async {
    final session = ++_session;
    _fast = fast;
    final service = RfidService.instance;
    final blocked = await service.init();
    if (blocked != null) {
      return (error: blocked, codes: const <String>[], tags: const <List<String>>[]);
    }
    await service.stopIfRunning();
    await service.setInventoryMode(1);

    final codes = <String>{};
    final reads = <List<String>>[];
    final done = Completer<void>();
    final started = DateTime.now();
    _tags = service.tagStream.listen((tags) {
      if (session != _session) return;
      var added = false;
      for (final tag in tags) {
        final epc = tag.epc.trim();
        final tid = tag.tid.trim();
        final known = (epc.isNotEmpty && codes.contains(epc)) || (tid.isNotEmpty && codes.contains(tid));
        final values = <String>[];
        for (final value in [epc, tid]) {
          if (value.isEmpty) continue;
          values.add(value);
          if (codes.add(value)) added = true;
        }
        if (values.isEmpty) continue;
        reads.add(values);
        if (!known) _beep();
      }
      if (!added) return;
      onCount?.call(codes.length);
      _armUntilQuiet(session, done, started, codes.isNotEmpty);
    });

    final startError = await service.startInventory(unique: true);
    if (session != _session) {
      return (error: null, codes: codes.toList(), tags: reads);
    }
    if (startError != null) {
      await _finish(session);
      return (error: startError, codes: const <String>[], tags: const <List<String>>[]);
    }
    _armUntilQuiet(session, done, started, codes.isNotEmpty);
    _max?.cancel();
    _max = Timer(_fast ? const Duration(seconds: 4) : const Duration(seconds: 8), () {
      if (session == _session && !done.isCompleted) done.complete();
    });
    await done.future;
    await _finish(session);
    return (error: null, codes: codes.toList(), tags: reads);
  }

  void _beep() {
    unawaited(() async {
      try {
        await DeviceManager.instance.playSound(1);
      } catch (_) {}
    }());
  }

  void cancel() {
    final session = ++_session;
    _idle?.cancel();
    _max?.cancel();
    unawaited(_finish(session));
  }

  /// Order scans stop 650ms after the last new tag. Other scans keep the
  /// radio on for at least 3s so a slower tray still collects every tag.
  void _armUntilQuiet(int session, Completer<void> done, DateTime started, bool hasTags) {
    final elapsed = DateTime.now().difference(started);
    final hold = _fast ? Duration.zero : const Duration(milliseconds: 3000);
    final empty = _fast ? const Duration(milliseconds: 700) : const Duration(milliseconds: 2000);
    final quiet = _fast ? const Duration(milliseconds: 650) : const Duration(milliseconds: 1200);
    final remain = (hasTags ? hold : empty) - elapsed;
    final wait = !hasTags
        ? (remain.isNegative ? Duration.zero : remain)
        : (remain > quiet ? remain : quiet);
    _idle?.cancel();
    _idle = Timer(wait, () {
      if (session == _session && !done.isCompleted) done.complete();
    });
  }

  Future<void> _finish(int session) async {
    _idle?.cancel();
    _max?.cancel();
    await _tags?.cancel();
    _tags = null;
    if (session != _session) return;
    await RfidService.instance.stopIfRunning();
  }
}
