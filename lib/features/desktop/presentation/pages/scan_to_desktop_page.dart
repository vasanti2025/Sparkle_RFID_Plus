import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:rfid_flutter_android/rfid_flutter_android.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../core/constants/app_strings.dart';
import '../../../../core/di/injection.dart';
import '../../../../core/locale/feature_strings.dart';
import '../../../../core/error/exceptions.dart';
import '../../../../core/rfid/rfid_service.dart';
import '../../../../core/rfid/scan_sound.dart';
import '../../../../core/session/app_session.dart';
import '../../../../core/theme/app_colors.dart';
import '../../data/desktop_scan_api.dart';
import '../../data/desktop_scan_excel.dart';

String _encodeBody(Map<String, dynamic> body) => jsonEncode(body);

class _Tag {
  _Tag(this.epc, this.rfid);

  final String epc;
  String rfid;
}

/// Scan to Desktop. Scanning follows the previous RFID app.
/// The list only keeps a total, and rows are built as they scroll so a
/// long scan stays usable on a small device.
class ScanToDesktopPage extends StatefulWidget {
  const ScanToDesktopPage({super.key});

  @override
  State<ScanToDesktopPage> createState() => _ScanToDesktopPageState();
}

class _ScanToDesktopPageState extends State<ScanToDesktopPage> {
  static const _line = Color(0xFFE4DFD6);
  static const _canvas = Color(0xFFFCF7F6);
  static const _powerKey = 'desktop_scan_power';
  static const _deviceKey = 'desktop_device_id';

  final DesktopScanApi _api = DesktopScanApi();
  final List<_Tag> _scans = [];
  final Set<String> _seen = {};
  final List<_Tag> _pending = [];
  final Set<WebSocket> _sockets = {};

  StreamSubscription<List<RfidTagInfo>>? _tags;
  RfidTrigger? _trigger;
  HttpServer? _server;
  Timer? _singleTimer;
  Timer? _flushTimer;
  Timer? _liveTimer;
  Timer? _serverRetry;

  var _power = 5;
  var _scanning = false;
  var _single = false;
  var _busy = false;
  var _loading = false;
  var _gotTag = false;
  var _closing = false;
  var _generation = 0;
  var _lastTriggerMs = 0;
  String _deviceId = '';
  String _liveJson = '{}';
  final List<_Tag> _liveQueue = [];

  @override
  void initState() {
    super.initState();
    Injection.settings.addListener(_onLanguage);
    _trigger = RfidTrigger()..attach(_onTrigger);
    _tags = RfidService.instance.tagStream.listen(_onTags);
    unawaited(_open());
  }

  void _onLanguage() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    Injection.settings.removeListener(_onLanguage);
    _closing = true;
    _singleTimer?.cancel();
    _flushTimer?.cancel();
    _liveTimer?.cancel();
    _serverRetry?.cancel();
    _tags?.cancel();
    _trigger?.detach();
    unawaited(_stopRadio());
    unawaited(_stopServer());
    super.dispose();
  }

  Future<void> _open() async {
    final prefs = await SharedPreferences.getInstance();
    _power = (prefs.getInt(_powerKey) ?? 5).clamp(1, 30);
    var stored = prefs.getString(_deviceKey) ?? '';
    if (stored.isEmpty) {
      final random = Random.secure();
      stored = List<int>.generate(16, (_) => random.nextInt(256))
          .map((value) => value.toRadixString(16).padLeft(2, '0'))
          .join();
      await prefs.setString(_deviceKey, stored);
    }
    _deviceId = _shortId(stored);
    if (mounted) setState(() {});
    await _startServer();
    final code = AppSession.clientCode;
    if (code.isEmpty || _deviceId.isEmpty) return;
    unawaited(_api.registerDevice(clientCode: code, deviceId: _deviceId).catchError((_) {}));
    unawaited(Injection.quotations.warmLabeledStock(code, _fillMissingRfid));
  }

  String _shortId(String serial) {
    if (serial.length < 2) return 'A$serial';
    return 'A${serial.substring(serial.length - 2)}';
  }

  String _tagKey(String raw) {
    return raw.trim().toUpperCase().replaceAll(RegExp(r'[^0-9A-Z]'), '');
  }

  bool _rememberTag(String epc, String tid) {
    final keys = <String>{
      if (epc.isNotEmpty) epc,
      if (tid.isNotEmpty) tid,
    };
    if (keys.isEmpty || keys.any(_seen.contains)) {
      _seen.addAll(keys);
      return false;
    }
    _seen.addAll(keys);
    return true;
  }

  void _onTags(List<RfidTagInfo> tags) {
    if (!_scanning) return;
    if (_single && _gotTag) return;
    final fresh = <_Tag>[];
    for (final tag in tags) {
      final epc = _tagKey(tag.epc);
      final tid = _tagKey(tag.tid);
      final shown = epc.isNotEmpty ? epc : tid;
      if (shown.isEmpty || !_rememberTag(epc, tid)) continue;
      fresh.add(_Tag(shown, _rfidFor(shown, tid)));
      if (_single) {
        _gotTag = true;
        break;
      }
    }
    if (fresh.isEmpty) {
      if (_single) unawaited(_stopRadio());
      return;
    }
    _pending.addAll(fresh);
    _flushTimer ??= Timer(const Duration(milliseconds: 120), _flush);
    if (_single) unawaited(_stopRadio());
  }

  String _rfidFor(String epc, String tid) {
    if (epc.startsWith('E') || tid.isNotEmpty) {
      final code = AppSession.clientCode;
      final item = Injection.quotations.stockForTag(code, tid.isEmpty ? epc : tid) ??
          Injection.quotations.stockForTag(code, epc);
      final rfid = item?.rfid.trim() ?? '';
      if (rfid.isNotEmpty) return rfid;
      final extra = item?.extras['rfidcode']?.trim() ?? '';
      if (extra.isNotEmpty) return extra;
    }
    if (!epc.startsWith('E')) return _hexToAscii(epc);
    return '';
  }

  String _hexToAscii(String hex) {
    final clean = hex.replaceAll(' ', '');
    if (clean.length.isOdd) return '';
    final buffer = StringBuffer();
    try {
      for (var index = 0; index < clean.length; index += 2) {
        buffer.writeCharCode(int.parse(clean.substring(index, index + 2), radix: 16));
      }
    } catch (_) {
      return '';
    }
    return buffer.toString().replaceAll('\u0000', '').trim();
  }

  void _flush() {
    _flushTimer = null;
    if (!mounted || _pending.isEmpty) return;
    final added = List<_Tag>.from(_pending);
    _pending.clear();
    setState(() => _scans.addAll(added));
    _queueLive(added);
  }

  void _fillMissingRfid() {
    if (!mounted) return;
    var changed = false;
    for (final tag in _scans) {
      if (tag.rfid.trim().isNotEmpty) continue;
      final next = _rfidFor(tag.epc, '');
      if (next.isEmpty) continue;
      tag.rfid = next;
      changed = true;
    }
    if (changed) {
      setState(() {});
      _queueLive(_scans.where((tag) => tag.rfid.isNotEmpty).toList());
    }
  }

  Future<void> _onTrigger() async {
    if (!mounted || _busy) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    if (now - _lastTriggerMs < 300) return;
    _lastTriggerMs = now;
    if (_scanning) {
      await _stopRadio();
    } else {
      await _start(single: false);
    }
  }

  Future<void> _start({required bool single}) async {
    if (_busy) return;
    if (_scanning && _single == single) {
      await _stopRadio();
      return;
    }
    if (_scanning) await _stopRadio();
    _busy = true;
    final generation = ++_generation;
    _singleTimer?.cancel();
    setState(() {
      _scanning = true;
      _single = single;
      _gotTag = false;
    });
    final blocked = await RfidService.instance.init();
    if (!mounted || generation != _generation) {
      _busy = false;
      return;
    }
    if (blocked != null) {
      setState(() {
        _scanning = false;
        _single = false;
      });
      _busy = false;
      _toast(blocked);
      return;
    }
    await RfidService.instance.stopIfRunning();
    await RfidService.instance.setInventoryMode(kEpcInventoryMode);
    await RfidService.instance.setPower(_power);
    final error = await RfidService.instance.startInventory(unique: true);
    if (!mounted || generation != _generation) {
      _busy = false;
      if (error == null) await RfidService.instance.stopIfRunning();
      return;
    }
    if (error != null) {
      setState(() {
        _scanning = false;
        _single = false;
      });
      _busy = false;
      _toast(error);
      return;
    }
    unawaited(ScanSound.startInventory());
    if (single) {
      _singleTimer = Timer(const Duration(seconds: 2), () {
        if (_single && _scanning) unawaited(_stopRadio());
      });
    }
    _busy = false;
    if (mounted) setState(() {});
  }

  Future<void> _stopRadio() async {
    _generation++;
    _singleTimer?.cancel();
    _flush();
    final wasScanning = _scanning;
    if (mounted) {
      setState(() {
        _scanning = false;
        _single = false;
      });
    }
    if (wasScanning || RfidService.instance.isReady) {
      await RfidService.instance.stopIfRunning();
      await ScanSound.stopAll();
    }
    _flush();
  }

  Future<void> _setPower(int value) async {
    setState(() => _power = value);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_powerKey, value);
    if (RfidService.instance.isReady) {
      await RfidService.instance.setPower(value);
    }
  }

  Future<void> _save() async {
    if (_loading) return;
    final code = AppSession.clientCode;
    if (code.isEmpty || _deviceId.isEmpty) {
      _toast(tx('deviceMissing', AppStrings.deviceMissing));
      return;
    }
    if (Injection.settings.localWifiMode) {
      await _saveLocal(code);
      return;
    }
    final now = _stamp(DateTime.now());
    final rows = <Map<String, dynamic>>[];
    for (final tag in _scans) {
      final rfid = tag.rfid.trim();
      if (tag.epc.isEmpty || rfid.isEmpty) continue;
      rows.add({
        'Id': 0,
        'CreatedOn': now,
        'LastUpdated': now,
        'StatusType': true,
        'ClientCode': code,
        'DeviceId': _deviceId,
        'TIDValue': tag.epc,
        'RFIDCode': rfid,
      });
    }
    if (rows.isEmpty) {
      _toast(tx('needRfid', AppStrings.needRfid));
      return;
    }
    setState(() => _loading = true);
    try {
      await _api.save(rows);
      if (!mounted) return;
      setState(() {
        _scans.clear();
        _seen.clear();
        _pending.clear();
      });
      _toast(tx('itemsSaved', AppStrings.itemsSaved));
    } on ServerException {
      _toast(tx('saveFailed', AppStrings.saveFailed));
    } catch (_) {
      _toast(tx('saveFailed', AppStrings.saveFailed));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _saveLocal(String code) async {
    final items = _payload(_scans);
    if (items.isEmpty) {
      _toast(tx('needRfid', AppStrings.needRfid));
      return;
    }
    if (_server == null) await _startServer();
    await _publishFull(code);
    final ip = await _wifiAddress();
    if (!mounted) return;
    if (ip == null) {
      _toast(tx('noWifiAddress', AppStrings.noWifiAddress));
      return;
    }
    _toast('${tx('localDesktopReady', AppStrings.localDesktopReady)} http://$ip:8080/rfid-data');
  }

  Future<void> _clear() async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(tx('clear', AppStrings.clear)),
        content: Text(tx('clearDesktopConfirm', AppStrings.clearDesktopConfirm)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text(tx('cancel', AppStrings.cancel))),
          TextButton(onPressed: () => Navigator.pop(context, true), child: Text(tx('clear', AppStrings.clear))),
        ],
      ),
    );
    if (yes != true || !mounted) return;
    final code = AppSession.clientCode;
    if (code.isEmpty || _deviceId.isEmpty) {
      _toast(tx('deviceMissing', AppStrings.deviceMissing));
      return;
    }
    setState(() => _loading = true);
    try {
      final deleted = await _api.clear(clientCode: code, deviceId: _deviceId);
      if (!mounted) return;
      if (deleted < 0) {
        _toast(tx('clearFailed', AppStrings.clearFailed));
        return;
      }
      setState(() {
        _scans.clear();
        _seen.clear();
        _pending.clear();
      });
      _queueLive(const []);
      _toast(deleted == 0 ? 'Cleared' : '$deleted records cleared');
    } catch (_) {
      _toast(tx('clearFailed', AppStrings.clearFailed));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _reset() async {
    if (_busy) return;
    await _stopRadio();
    _pending.clear();
    setState(() {
      _scans.clear();
      _seen.clear();
    });
    _queueLive(const []);
    _toast(tx('scanReset', AppStrings.scanReset));
  }

  Future<void> _exportSheet() async {
    if (_scans.isEmpty) {
      _toast(tx('newScansAppear', AppStrings.newScansAppear));
      return;
    }
    final choice = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: _ScanToDesktopPageState._canvas,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.mail_outline, color: AppColors.charcoal),
              title: Text(tx('mailExport', AppStrings.mailExport)),
              onTap: () => Navigator.pop(context, 'mail'),
            ),
            ListTile(
              leading: const Icon(Icons.download_outlined, color: AppColors.charcoal),
              title: Text(tx('downloadExcel', AppStrings.downloadExcel)),
              onTap: () => Navigator.pop(context, 'download'),
            ),
          ],
        ),
      ),
    );
    if (choice == null || !mounted) return;
    setState(() => _loading = true);
    try {
      final file = await _writeExcel();
      if (!mounted || file == null) return;
      if (choice == 'mail') {
        await Share.shareXFiles(
          [XFile(file.path, mimeType: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet')],
          subject: tx('scanToDesktopTitle', AppStrings.scanToDesktopTitle),
        );
      } else {
        _toast('${tx('excelSaved', AppStrings.excelSaved)}: ${file.path}');
      }
    } catch (_) {
      _toast(tx('excelFailed', AppStrings.excelFailed));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<File?> _writeExcel() async {
    final rows = <List<String>>[
      const ['Sr', 'RFID', 'EPC'],
      for (var index = 0; index < _scans.length; index++)
        ['${index + 1}', _scans[index].rfid, _scans[index].epc],
    ];
    final bytes = await compute(buildDesktopWorkbook, rows);
    if (bytes.isEmpty) return null;
    final directory = await getDownloadsDirectory() ?? await getApplicationDocumentsDirectory();
    final file = File('${directory.path}${Platform.pathSeparator}scan-to-desktop.xlsx');
    await file.writeAsBytes(bytes, flush: true);
    return file;
  }

  Future<void> _assign(int index) async {
    final tag = _scans[index];
    final controller = TextEditingController(text: tag.rfid);
    await _stopRadio();
    if (!mounted) return;
    final next = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(tag.epc, maxLines: 2),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(labelText: 'RFID'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: Text(tx('cancel', AppStrings.cancel))),
          TextButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: Text(tx('save', AppStrings.save)),
          ),
        ],
      ),
    );
    controller.dispose();
    if (next == null || !mounted) return;
    setState(() => tag.rfid = next);
    _queueLive([tag]);
  }

  List<Map<String, String>> _payload(List<_Tag> tags) {
    final items = <Map<String, String>>[];
    for (final tag in tags) {
      final rfid = tag.rfid.trim();
      if (tag.epc.isEmpty || rfid.isEmpty) continue;
      items.add({'EPC': tag.epc, 'RFIDCode': rfid});
    }
    return items;
  }

  void _queueLive(List<_Tag> tags) {
    if (!Injection.settings.localWifiMode) return;
    _liveQueue.addAll(tags);
    _liveTimer ??= Timer(const Duration(milliseconds: 500), () {
      _liveTimer = null;
      final batch = List<_Tag>.from(_liveQueue);
      _liveQueue.clear();
      final items = _payload(batch);
      if (items.isNotEmpty) {
        _broadcast(
          jsonEncode({
            'type': 'tags',
            'ClientCode': AppSession.clientCode,
            'DeviceId': _deviceId,
            'Items': items,
          }),
        );
      }
      unawaited(_publishFull(AppSession.clientCode));
    });
  }

  Future<void> _publishFull(String code) async {
    final items = _payload(_scans);
    final body = <String, dynamic>{
      'ClientCode': code,
      'DeviceId': _deviceId,
      'Items': items,
    };
    final text = await compute(_encodeBody, body);
    if (!mounted) return;
    _liveJson = text;
    _broadcast(jsonEncode({'type': 'sync', ...body}));
  }

  Future<void> _startServer() async {
    if (_closing || _server != null) return;
    try {
      final server = await HttpServer.bind(InternetAddress.anyIPv4, 8080, shared: true);
      _server = server;
      server.listen(_onRequest, onError: (_) {}, onDone: () {
        _server = null;
        if (!_closing) {
          _serverRetry?.cancel();
          _serverRetry = Timer(const Duration(seconds: 2), () {
            unawaited(_startServer());
          });
        }
      });
    } catch (_) {
      _server = null;
    }
  }

  Future<void> _onRequest(HttpRequest request) async {
    try {
      if (WebSocketTransformer.isUpgradeRequest(request)) {
        final path = request.uri.path;
        if (path != '/rfid-ws' && path != '/rfid-data') {
          request.response.statusCode = HttpStatus.notFound;
          await request.response.close();
          return;
        }
        final socket = await WebSocketTransformer.upgrade(request);
        _sockets.add(socket);
        if (Injection.settings.localWifiMode) {
          socket.add(
            jsonEncode({
              'type': 'sync',
              'ClientCode': AppSession.clientCode,
              'DeviceId': _deviceId,
              'Items': _payload(_scans),
            }),
          );
        }
        socket.done.whenComplete(() => _sockets.remove(socket));
        return;
      }
      if (request.uri.path == '/rfid-data') {
        request.response
          ..headers.contentType = ContentType.json
          ..headers.add('Access-Control-Allow-Origin', '*')
          ..write(_liveJson);
      } else {
        request.response
          ..statusCode = HttpStatus.ok
          ..headers.contentType = ContentType.html
          ..write('<html><body><h2>RFID Local Server Running</h2><p>/rfid-data</p></body></html>');
      }
      await request.response.close();
    } catch (_) {}
  }

  void _broadcast(String message) {
    final stale = <WebSocket>[];
    for (final socket in _sockets) {
      try {
        socket.add(message);
      } catch (_) {
        stale.add(socket);
      }
    }
    _sockets.removeAll(stale);
  }

  Future<void> _stopServer() async {
    _serverRetry?.cancel();
    for (final socket in _sockets.toList()) {
      try {
        await socket.close();
      } catch (_) {}
    }
    _sockets.clear();
    await _server?.close(force: true);
    _server = null;
  }

  Future<String?> _wifiAddress() async {
    try {
      final interfaces = await NetworkInterface.list();
      for (final interface in interfaces) {
        final name = interface.name.toLowerCase();
        if (!name.contains('wlan') && !name.contains('ap') && !name.contains('wifi')) continue;
        for (final address in interface.addresses) {
          if (address.type == InternetAddressType.IPv4 && !address.isLoopback) {
            return address.address;
          }
        }
      }
      for (final interface in interfaces) {
        for (final address in interface.addresses) {
          if (address.type == InternetAddressType.IPv4 && !address.isLoopback) {
            return address.address;
          }
        }
      }
    } catch (_) {}
    return null;
  }

  String _stamp(DateTime time) {
    String two(int value) => value.toString().padLeft(2, '0');
    return '${time.year}-${two(time.month)}-${two(time.day)}T${two(time.hour)}:${two(time.minute)}:${two(time.second)}';
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: featureDirection,
      child: Scaffold(
      backgroundColor: _canvas,
      body: SafeArea(
        child: Stack(
          children: [
            Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(4, 4, 12, 0),
                  child: Row(
                    children: [
                      IconButton(
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(Icons.arrow_back, color: AppColors.charcoal),
                      ),
                      const Expanded(
                        child: Text(
                          'SPARKLE RFID',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: AppColors.charcoal,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 1.4,
                            fontSize: 13,
                          ),
                        ),
                      ),
                      _powerButton(),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        tx('scanToDesktopTitle', AppStrings.scanToDesktopTitle),
                        style: TextStyle(color: AppColors.charcoal, fontSize: 22, fontWeight: FontWeight.w700, height: 1.1),
                      ),
                      const SizedBox(height: 2),
                      Text(tx('scanTagsReview', AppStrings.scanTagsReview), style: TextStyle(color: AppColors.muted, fontSize: 13)),
                      const SizedBox(height: 10),
                      _totalCard(),
                      const SizedBox(height: 10),
                      const Divider(height: 1, thickness: 1, color: _ScanToDesktopPageState._line),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              tx('scannedItems', AppStrings.scannedItems),
                              style: TextStyle(color: AppColors.charcoal, fontSize: 16, fontWeight: FontWeight.w700),
                            ),
                          ),
                          OutlinedButton.icon(
                            onPressed: _exportSheet,
                            icon: const Icon(Icons.upload_outlined, size: 16),
                            label: Text(tx('exportData', AppStrings.exportData)),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: AppColors.charcoal,
                              side: const BorderSide(color: AppColors.fieldBorder),
                              visualDensity: VisualDensity.compact,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                Expanded(child: _list()),
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    tx('newScansAppear', AppStrings.newScansAppear),
                    style: TextStyle(color: Color(0xFFB7B2A8), fontSize: 13),
                  ),
                ),
                const Divider(height: 1, thickness: 1, color: _ScanToDesktopPageState._line),
                Padding(
                  padding: const EdgeInsets.fromLTRB(4, 2, 4, 2),
                  child: Row(
                    children: [
                      _action(Icons.download_outlined, tx('save', AppStrings.save), _save),
                      const _ActionLine(),
                      _action(Icons.sensors, _scanning && !_single ? 'Stop' : tx('gscan', AppStrings.gscan), () {
                        unawaited(_start(single: false));
                      }),
                      const _ActionLine(),
                      _action(Icons.delete_outline, tx('clear', AppStrings.clear), _clear),
                      const _ActionLine(),
                      _action(Icons.restart_alt, tx('reset', AppStrings.reset), () => unawaited(_reset())),
                    ],
                  ),
                ),
              ],
            ),
            if (_loading)
              const Positioned(
                left: 0,
                right: 0,
                top: 0,
                child: LinearProgressIndicator(
                  minHeight: 2,
                  color: AppColors.goldText,
                  backgroundColor: Colors.transparent,
                ),
              ),
          ],
        ),
      ),
      ),
    );
  }

  Widget _powerButton() {
    return PopupMenuButton<int>(
      initialValue: _power,
      color: _canvas,
      surfaceTintColor: Colors.transparent,
      onSelected: (value) => unawaited(_setPower(value)),
      itemBuilder: (context) => [
        for (var value = 1; value <= 30; value++) PopupMenuItem(value: value, child: Text('$value')),
      ],
      child: Container(
        width: 36,
        height: 36,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: AppColors.charcoal,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text('$_power', style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.white)),
      ),
    );
  }

  Widget _totalCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.charcoal,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Material(
            color: const Color(0xFF3A3937),
            borderRadius: BorderRadius.circular(10),
            child: InkWell(
              onTap: () => unawaited(_start(single: true)),
              borderRadius: BorderRadius.circular(10),
              child: SizedBox(
                width: 36,
                height: 36,
                child: Icon(
                  _scanning && _single ? Icons.stop : Icons.qr_code_scanner,
                  color: AppColors.white,
                  size: 18,
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Container(width: 1, height: 28, color: Color(0x33FFFFFF)),
          const SizedBox(width: 12),
          Expanded(
            child: Text(tx('totalItems', AppStrings.totalItems), style: TextStyle(color: AppColors.white, fontSize: 14)),
          ),
          Text(
            '${_scans.length}',
            style: const TextStyle(color: AppColors.white, fontSize: 26, fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }

  Widget _list() {
    if (_scans.isEmpty) return const SizedBox.expand();
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
      itemCount: _scans.length,
      addAutomaticKeepAlives: false,
      separatorBuilder: (context, index) => const Divider(height: 1, thickness: 1, color: _ScanToDesktopPageState._line),
      itemBuilder: (context, index) {
        final tag = _scans[index];
        final rfid = tag.rfid.trim().isEmpty ? '—' : tag.rfid.trim();
        return InkWell(
          onTap: () => unawaited(_assign(index)),
          child: SizedBox(
            height: 46,
            child: Row(
              children: [
                SizedBox(
                  width: 24,
                  child: Text('${index + 1}', style: const TextStyle(color: Color(0xFFB7B2A8), fontSize: 12)),
                ),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'RFID  $rfid',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: AppColors.charcoal, fontWeight: FontWeight.w700, fontSize: 13, height: 1.1),
                      ),
                      Text(
                        'EPC  ${tag.epc}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: AppColors.muted, fontSize: 11, height: 1.1),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _action(IconData icon, String label, VoidCallback onTap) {
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: AppColors.charcoal, size: 22),
              const SizedBox(height: 4),
              Text(label, style: const TextStyle(color: AppColors.charcoal, fontSize: 12)),
            ],
          ),
        ),
      ),
    );
  }
}

class _ActionLine extends StatelessWidget {
  const _ActionLine();

  @override
  Widget build(BuildContext context) {
    return const SizedBox(
      height: 28,
      child: VerticalDivider(width: 1, thickness: 1, color: _ScanToDesktopPageState._line),
    );
  }
}
