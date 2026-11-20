import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:rfid_flutter_android/rfid_flutter_android.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../core/constants/app_strings.dart';
import '../../../../core/di/injection.dart';
import '../../../../core/locale/feature_strings.dart';
import '../../../../core/rfid/rfid_service.dart';
import '../../../../core/session/app_session.dart';
import '../../../inventory/data/inventory_stock.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../desktop/presentation/pages/scan_to_desktop_page.dart';
import '../../data/datasources/product_local_data_source.dart';
import '../../data/product_csv.dart';
import '../../data/single_product_save.dart';
import '../../domain/entities/stored_record.dart';
import '../import_excel_flow.dart';

import '../demo/product_demo_session.dart';

enum _ProductPage { list, single, bulk, sync }

class ProductsPage extends StatefulWidget {
  const ProductsPage({super.key});

  @override
  State<ProductsPage> createState() => _ProductsPageState();
}

class _ProductsPageState extends State<ProductsPage> {
  static const _surface = Color(0xFFFAF9F7);
  static const _line = Color(0xFFE3DDD1);
  static const _ink = Color(0xFF20201E);
  static const _headLine = Color(0xFFE8E3D9);
  static const _subtitle = Color(0xFF787166);
  static const _demoInk = Color(0xFF83765D);
  static const _tagInk = Color(0xFF837657);
  static const _tagFill = Color(0xFFEEE9DD);
  static const _tagLine = Color(0xFFE3DAC6);
  static const _searchLine = Color(0xFFDAD5CA);
  static const _searchIcon = Color(0xFF8C7B57);
  static const _searchFocus = Color(0xFF967431);
  static const _actionLine = Color(0xFFDDD3C0);
  static const _actionInk = Color(0xFF80612B);
  static const _chipFill = Color(0xFFF3EEE4);
  static const _chipLine = Color(0xFFDFD4BF);
  static const _chipInk = Color(0xFF7B6E55);
  static const _chipOn = Color(0xFFE9DABC);
  static const _chipOnInk = Color(0xFF715120);
  static const _chipOnLine = Color(0xFFB89C60);
  static const _gold = Color(0xFF866526);
  static const _chevron = Color(0xFF917C53);
  static const _status = Color(0xFF82745A);
  static const _classFill = Color(0xFFF5EEDF);
  static const _classLine = Color(0xFFDFCFAC);
  static const _panelLine = Color(0xFFE0D8C9);
  static const _note = Color(0xFF817866);
  static const _alertFill = Color(0xFFFBE9E9);
  static const _alertLine = Color(0xFFDFB8A7);
  static const _alertInk = Color(0xFF964A32);
  static const _track = Color(0xFFE9E3D7);
  static const _progress = Color(0xFF927030);
  static const _captureFill = Color(0xFFEEE5D1);
  static const _captureLine = Color(0xFFDFCEA9);
  static const _captureInk = Color(0xFF85652C);
  static const _detailFill = Color(0xFFF4EFE4);

  final _session = ProductDemoSession.instance;
  final _query = TextEditingController();
  final _storedScroll = ScrollController();
  final _stored = <CataloguePiece>[];
  var _sheetCatalogue = false;
  var _catalogueSource = '';
  var _storedTotal = 0;
  var _storedLoading = false;
  var _storedTicket = 0;
  Timer? _searchTimer;
  final _fields = <String, TextEditingController>{};
  final _rows = <_RowEditors>[];
  var _page = _ProductPage.list;
  var _capturing = false;
  var _exporting = false;
  var _suspend = false;
  var _readingTag = false;
  var _saving = false;
  var _sharedOpen = false;
  var _copyItem = false;
  var _copyRfid = false;
  var _radioOn = false;
  var _barcodeOn = false;
  var _power = 5;
  int? _scanRow;
  int? _scanCreatedRow;
  int? _selectedRow;
  int? _rfidFocus;
  StreamSubscription<RfidBarcodeInfo>? _barcodeSub;
  var _readTicket = 0;
  String _imagePath = '';
  String? _error;
  Timer? _timer;
  StreamSubscription<List<RfidTagInfo>>? _readSub;

  static const _singleKeys = [
    'id',
    'rfid',
    'epc',
    'gross',
    'net',
    'stone',
    'diamond',
    'vendor',
    'sku',
    'makingGram',
    'makingPercent',
    'fixedMaking',
    'fixedWastage',
    'stoneAmount',
    'diamondAmount',
  ];

  @override
  void initState() {
    super.initState();
    _query.text = _session.query;
    _storedScroll.addListener(_onStoredScroll);
    _query.addListener(() {
      if (_suspend || !mounted) return;
      _session.query = _query.text;
      _searchTimer?.cancel();
      if (_sheetCatalogue) {
        _searchTimer = Timer(const Duration(milliseconds: 300), () {
          unawaited(_reloadStored());
        });
        return;
      }
      if (_page == _ProductPage.list) setState(() {});
    });
    unawaited(_reloadStored());
    unawaited(_loadBulkPower());
    Injection.settings.addListener(_onLanguage);
    for (final key in _singleKeys) {
      final controller = TextEditingController();
      controller.addListener(() {
        if (_suspend) return;
        _writeSingle(key, controller.text.trim());
        _session.dirty = true;
      });
      _fields[key] = controller;
    }
  }

  void _onLanguage() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    Injection.settings.removeListener(_onLanguage);
    _readTicket++;
    final reading = _readSub;
    if (reading != null) unawaited(reading.cancel());
    if (_readingTag || _radioOn) unawaited(RfidService.instance.stopInventory());
    unawaited(_stopBarcode());
    _suspend = true;
    _timer?.cancel();
    _searchTimer?.cancel();
    _storedScroll.dispose();
    if (_session.syncPhase == 'running') _session.syncPhase = 'paused';
    _query.dispose();
    for (final controller in _fields.values) {
      controller.dispose();
    }
    for (final row in _rows) {
      row.dispose();
    }
    super.dispose();
  }

  ProductDraft get _draft => _session.draft ??= ProductDraft();

  void _toast(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  void _stopCapture() {
    _timer?.cancel();
    _timer = null;
    _capturing = false;
    _scanRow = null;
    final reading = _readSub;
    _readSub = null;
    if (reading != null) unawaited(reading.cancel());
    if (_radioOn) {
      _radioOn = false;
      unawaited(RfidService.instance.stopInventory());
    }
  }

  void _pauseSync() {
    _timer?.cancel();
    _timer = null;
    if (_session.syncPhase == 'running') _session.syncPhase = 'paused';
  }

  void _fillSingle() {
    final draft = _draft;
    _suspend = true;
    _fields['id']!.text = draft.id;
    _fields['rfid']!.text = draft.rfid;
    _fields['epc']!.text = draft.epc;
    _fields['gross']!.text = draft.gross;
    _fields['net']!.text = draft.net;
    _fields['stone']!.text = draft.stone;
    _fields['diamond']!.text = draft.diamond;
    _fields['vendor']!.text = draft.vendor;
    _fields['sku']!.text = draft.sku;
    _fields['makingGram']!.text = draft.makingGram;
    _fields['makingPercent']!.text = draft.makingPercent;
    _fields['fixedMaking']!.text = draft.fixedMaking;
    _fields['fixedWastage']!.text = draft.fixedWastage;
    _fields['stoneAmount']!.text = draft.stoneAmount;
    _fields['diamondAmount']!.text = draft.diamondAmount;
    _imagePath = draft.imagePath;
    _suspend = false;
  }

  void _writeSingle(String key, String value) {
    final draft = _draft;
    switch (key) {
      case 'id':
        draft.id = value;
      case 'rfid':
        draft.rfid = value;
      case 'epc':
        draft.epc = value;
      case 'gross':
        draft.gross = value;
      case 'net':
        draft.net = value;
      case 'stone':
        draft.stone = value;
      case 'diamond':
        draft.diamond = value;
      case 'vendor':
        draft.vendor = value;
      case 'sku':
        draft.sku = value;
      case 'makingGram':
        draft.makingGram = value;
      case 'makingPercent':
        draft.makingPercent = value;
      case 'fixedMaking':
        draft.fixedMaking = value;
      case 'fixedWastage':
        draft.fixedWastage = value;
      case 'stoneAmount':
        draft.stoneAmount = value;
      case 'diamondAmount':
        draft.diamondAmount = value;
      default:
        break;
    }
  }

  void _reloadRows() {
    for (final row in _rows) {
      row.dispose();
    }
    _rows
      ..clear()
      ..addAll(_session.bulkRows.map((piece) => _RowEditors(piece, _session, onEdit: () {
        if (_rows.isNotEmpty && identical(piece, _rows.first.piece)) _copyFromFirst();
      })));
  }

  void _goList() {
    _stopCapture();
    unawaited(_stopBarcode());
    setState(() {
      _page = _ProductPage.list;
      _error = null;
    });
  }

  void _back() {
    if (_page == _ProductPage.sync) {
      _pauseSync();
      _goList();
      return;
    }
    if (_page == _ProductPage.single || _page == _ProductPage.bulk) {
      _stopCapture();
      if (_session.dirty) {
        _keepOrDiscard();
        return;
      }
      _goList();
      return;
    }
    Navigator.of(context).maybePop();
  }

  void _startSingle() {
    _session.mode = 'single';
    _session.draft = ProductDraft();
    _session.dirty = false;
    _fillSingle();
    _session.dirty = false;
    setState(() {
      _page = _ProductPage.single;
      _error = null;
    });
  }

  void _startBulk() {
    _session.mode = 'bulk';
    _session.bulkCategory = '';
    _session.bulkName = '';
    _session.bulkDesign = '';
    _session.bulkRows.clear();
    _session.dirty = false;
    _reloadRows();
    setState(() {
      _page = _ProductPage.bulk;
      _error = null;
    });
  }

  void _resumeDraft() {
    if (_session.mode == 'bulk') {
      _reloadRows();
      setState(() {
        _page = _ProductPage.bulk;
        _error = null;
      });
      return;
    }
    _session.draft ??= ProductDraft();
    _fillSingle();
    setState(() {
      _page = _ProductPage.single;
      _error = null;
    });
  }

  void _discard() {
    _stopCapture();
    _suspend = true;
    for (final controller in _fields.values) {
      controller.clear();
    }
    _suspend = false;
    _imagePath = '';
    _session.discardDraft();
    _reloadRows();
    _goList();
  }

  Future<void> _readTag() async {
    if (_readingTag) return;
    final ticket = ++_readTicket;
    setState(() => _readingTag = true);
    final service = RfidService.instance;
    final blocked = await service.init();
    if (!mounted || ticket != _readTicket) return;
    if (blocked != null) {
      setState(() => _readingTag = false);
      _toast(blocked);
      return;
    }
    await service.stopIfRunning();
    await service.setInventoryMode(1);
    final found = Completer<RfidTagInfo?>();
    await _readSub?.cancel();
    _readSub = service.tagStream.listen((tags) {
      if (found.isCompleted || ticket != _readTicket) return;
      for (final tag in tags) {
        final epc = tag.epc.trim();
        final tid = tag.tid.trim();
        final usable = epc.isNotEmpty && !epc.toUpperCase().startsWith('0000');
        if (!usable && tid.isEmpty) continue;
        if (!found.isCompleted) found.complete(tag);
        return;
      }
    });
    final error = await service.startInventory(unique: true);
    if (!mounted || ticket != _readTicket) return;
    if (error != null) {
      await _finishRead(ticket);
      if (mounted) _toast(error);
      return;
    }
    _radioOn = true;
    final tag = await found.future.timeout(const Duration(seconds: 6), onTimeout: () => null);
    await _finishRead(ticket);
    if (!mounted || ticket != _readTicket) return;
    if (tag == null) {
      _toast(AppStrings.noTagFound);
      return;
    }
    final epc = tag.epc.trim();
    final tid = tag.tid.trim();
    final usable = epc.isNotEmpty && !epc.toUpperCase().startsWith('0000');
    final code = (usable ? epc : tid).toUpperCase();
    _suspend = true;
    _fields['rfid']!.text = code;
    if (RegExp(r'^[A-F0-9]+$').hasMatch(code)) _fields['epc']!.text = code;
    _suspend = false;
    _draft.rfid = code;
    if (RegExp(r'^[A-F0-9]+$').hasMatch(code)) _draft.epc = code;
    _session.dirty = true;
    setState(() {});
    _toast(AppStrings.demoIdentityRead);
  }

  Future<void> _finishRead(int ticket) async {
    await _readSub?.cancel();
    _readSub = null;
    final radio = _radioOn;
    _radioOn = false;
    _scanRow = null;
    _scanCreatedRow = null;
    if (radio) await RfidService.instance.stopInventory();
    if (mounted && ticket == _readTicket) setState(() => _readingTag = false);
  }

  Future<void> _toggleCapture() async {
    if (_capturing) {
      setState(_stopCapture);
      return;
    }
    _scanRow = null;
    final started = await _armReader(multi: true);
    if (!started || !mounted) return;
    setState(() => _capturing = true);
  }

  Future<void> _startSingleScan() async {
    if (_scanRow != null && _radioOn && !_capturing) {
      setState(_stopCapture);
      return;
    }
    if (_capturing) setState(_stopCapture);
    final selected = _selectedRow;
    if (selected == null || selected >= _rows.length) {
      setState(() {
        _addPiece(BulkPiece());
        if (_copyItem) _copyFromFirst();
        _scanCreatedRow = _rows.length - 1;
      });
      await _scanOneRow(_rows.length - 1);
      return;
    }
    _scanCreatedRow = null;
    await _scanOneRow(selected);
  }

  void _addManualRow() {
    setState(() {
      _addPiece(BulkPiece());
      if (_copyItem) _copyFromFirst();
      _selectedRow = _rows.length - 1;
    });
  }

  void _removeSelectedRow() {
    if (_rows.isEmpty) return;
    final index = _selectedRow != null && _selectedRow! < _rows.length ? _selectedRow! : _rows.length - 1;
    final row = _rows[index];
    row.dispose();
    setState(() {
      _rows.removeAt(index);
      _session.bulkRows.removeAt(index);
      _session.dirty = true;
      _selectedRow = _rows.isEmpty ? null : index.clamp(0, _rows.length - 1);
      if (_rfidFocus != null && (_rfidFocus! >= _rows.length)) _rfidFocus = _selectedRow;
    });
  }

  Future<void> _armBarcode(int index) async {
    _rfidFocus = index;
    if (_radioOn || _capturing) return;
    try {
      final decoder = BarcodeDecoder.instance;
      final ready = await decoder.init();
      if (!ready.isEffective || !mounted) return;
      _barcodeSub ??= decoder.barcodeStream.listen(_onBarcode);
      if (_barcodeOn) return;
      final started = await decoder.startScan();
      _barcodeOn = started.isEffective;
    } catch (_) {}
  }

  void _onBarcode(RfidBarcodeInfo info) {
    final index = _rfidFocus;
    if (!mounted || index == null || index >= _rows.length) return;
    final code = info.barcode.trim().toUpperCase();
    if (code.isEmpty) return;
    final row = _rows[index];
    if (row.rfid.text != code) row.rfid.text = code;
    if (_copyRfid && index == 0) _copyFromFirst();
    setState(() => _selectedRow = index);
    unawaited(_stopBarcode());
  }

  Future<void> _stopBarcode() async {
    _barcodeOn = false;
    final reading = _barcodeSub;
    _barcodeSub = null;
    if (reading != null) await reading.cancel();
    try {
      await BarcodeDecoder.instance.stopScan();
    } catch (_) {}
  }

  Future<void> _scanOneRow(int index) async {
    if (_capturing) setState(_stopCapture);
    _scanRow = index;
    final started = await _armReader(multi: false);
    if (!mounted) return;
    if (!started) _scanRow = null;
    setState(() {});
  }

  Future<bool> _armReader({required bool multi}) async {
    final ticket = ++_readTicket;
    final service = RfidService.instance;
    final blocked = await service.init();
    if (!mounted || ticket != _readTicket) return false;
    if (blocked != null) {
      _toast(blocked);
      return false;
    }
    await _stopBarcode();
    await service.stopIfRunning();
    await service.setPower(_power);
    await service.setInventoryMode(1);
    final reading = _readSub;
    _readSub = null;
    if (reading != null) await reading.cancel();
    _readSub = service.tagStream.listen((tags) {
      if (ticket != _readTicket || !mounted) return;
      var changed = false;
      for (final tag in tags) {
        final epc = tag.epc.trim();
        final tid = tag.tid.trim();
        final usable = epc.isNotEmpty && !epc.toUpperCase().startsWith('0000');
        final code = (usable ? epc : tid).trim().toUpperCase();
        if (code.isEmpty) continue;
        final storedEpc = usable ? epc.toUpperCase() : code;
        final storedTid = tid.trim().toUpperCase();
        if (!multi) {
          final index = _scanRow;
          if (index == null || index >= _rows.length) continue;
          if (_epcTaken(storedEpc, except: index)) {
            _dropEmptyScanRow();
            unawaited(_finishRead(ticket));
            changed = true;
            break;
          }
          _rememberTag(index, storedEpc, storedTid);
          _scanCreatedRow = null;
          if (_copyItem) _copyFromFirst();
          unawaited(_finishRead(ticket));
          changed = true;
          break;
        }
        if (_epcTaken(storedEpc)) continue;
        if (_addPiece(BulkPiece(epc: storedEpc, tid: storedTid))) {
          if (_copyItem) _copyFromFirst();
          changed = true;
        }
      }
      if (changed) setState(() {});
    });
    final error = await service.startInventory(unique: true);
    if (!mounted || ticket != _readTicket) return false;
    if (error != null) {
      await _finishRead(ticket);
      if (mounted) _toast(error);
      return false;
    }
    _radioOn = true;
    if (!multi) {
      _timer?.cancel();
      _timer = Timer(const Duration(seconds: 6), () {
        if (ticket == _readTicket) unawaited(_finishRead(ticket));
      });
    }
    return true;
  }

  static const _powerKey = 'bulk_scan_power';

  Future<void> _loadBulkPower() async {
    final prefs = await SharedPreferences.getInstance();
    final value = prefs.getInt(_powerKey) ?? 5;
    if (!mounted) return;
    setState(() => _power = value < 1 ? 1 : (value > 30 ? 30 : value));
  }

  Future<void> _setBulkPower(int value) async {
    final power = value < 1 ? 1 : (value > 30 ? 30 : value);
    setState(() => _power = power);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_powerKey, power);
    final error = await RfidService.instance.setPower(power);
    if (!mounted || error == null) return;
    _toast(error);
  }

  Widget _powerButton() {
    return PopupMenuButton<int>(
      tooltip: 'Power',
      initialValue: _power,
      padding: EdgeInsets.zero,
      offset: const Offset(0, 40),
      constraints: const BoxConstraints(minWidth: 72, maxHeight: 280),
      onSelected: (value) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) unawaited(_setBulkPower(value));
        });
      },
      itemBuilder: (context) => [
        for (var value = 1; value <= 30; value++)
          PopupMenuItem<int>(
            value: value,
            height: 40,
            child: Text('$value', style: _text(size: 14, weight: value == _power ? FontWeight.w700 : FontWeight.w500)),
          ),
      ],
      child: Container(
        width: 36,
        height: 36,
        alignment: Alignment.center,
        decoration: BoxDecoration(color: _ink, borderRadius: BorderRadius.circular(8)),
        child: Text('$_power', style: _text(size: 14, weight: FontWeight.w700, color: AppColors.white)),
      ),
    );
  }

  void _copyFromFirst() {
    if (_rows.isEmpty) return;
    final first = _rows.first;
    if (_copyItem) {
      final value = first.id.text;
      for (var i = 1; i < _rows.length; i++) {
        if (_rows[i].id.text != value) _rows[i].id.text = value;
      }
    }
    if (_copyRfid) {
      final value = first.rfid.text;
      for (var i = 1; i < _rows.length; i++) {
        if (_rows[i].rfid.text != value) _rows[i].rfid.text = value;
      }
    }
  }

  bool _epcTaken(String epc, {int except = -1}) {
    final key = epc.trim().toUpperCase();
    if (key.isEmpty) return false;
    for (var i = 0; i < _rows.length; i++) {
      if (i == except) continue;
      if (_rows[i].piece.epc.trim().toUpperCase() == key) return true;
    }
    for (var i = 0; i < _session.bulkRows.length; i++) {
      if (i == except) continue;
      if (_session.bulkRows[i].epc.trim().toUpperCase() == key) return true;
    }
    return false;
  }

  void _dropEmptyScanRow() {
    final index = _scanCreatedRow;
    _scanCreatedRow = null;
    if (index == null || index < 0 || index >= _rows.length || index >= _session.bulkRows.length) return;
    final editor = _rows[index];
    if (editor.piece.epc.trim().isNotEmpty) return;
    if (editor.id.text.trim().isNotEmpty || editor.rfid.text.trim().isNotEmpty) return;
    editor.dispose();
    _rows.removeAt(index);
    _session.bulkRows.removeAt(index);
    if (_selectedRow != null && (_selectedRow! >= _rows.length || _selectedRow == index)) {
      _selectedRow = _rows.isEmpty ? null : _rows.length - 1;
    }
  }

  void _rememberTag(int index, String epc, String tid) {
    if (index < 0 || index >= _rows.length) return;
    final piece = _rows[index].piece;
    piece.epc = epc;
    if (tid.isNotEmpty) piece.tid = tid;
    if (index < _session.bulkRows.length) {
      final stored = _session.bulkRows[index];
      stored.epc = epc;
      if (tid.isNotEmpty) stored.tid = tid;
    }
  }

  void _commitBulkRows() {
    final count = _rows.length < _session.bulkRows.length ? _rows.length : _session.bulkRows.length;
    for (var i = 0; i < count; i++) {
      final editor = _rows[i];
      final piece = _session.bulkRows[i];
      piece.id = editor.id.text.trim();
      piece.rfid = editor.rfid.text.trim();
      final scanned = editor.piece.epc.trim();
      if (scanned.isNotEmpty) piece.epc = scanned;
      final tid = editor.piece.tid.trim();
      if (tid.isNotEmpty) piece.tid = tid;
      if (!identical(editor.piece, piece)) {
        editor.piece.epc = piece.epc;
        editor.piece.tid = piece.tid;
      }
    }
  }

  bool _addPiece(BulkPiece piece) {
    if (_epcTaken(piece.epc)) return false;
    _session.bulkRows.add(piece);
    _rows.add(_RowEditors(piece, _session, onEdit: () {
      if (_rows.isNotEmpty && identical(piece, _rows.first.piece)) _copyFromFirst();
    }));
    _session.dirty = true;
    return true;
  }

  void _reviewSingle() {
    final errors = _session.validateSingle(_draft);
    if (errors.isNotEmpty) {
      setState(() => _error = errors.join('\n'));
      return;
    }
    setState(() => _error = null);
    _reviewSheet(bulk: false);
  }

  void _reviewBulk() {
    _commitBulkRows();
    final errors = _session.validateBulk();
    if (errors.isNotEmpty) {
      setState(() => _error = errors.join('\n'));
      return;
    }
    setState(() => _error = null);
    _reviewSheet(bulk: true);
  }

  Future<void> _saveSingle() async {
    if (_saving) return;
    final errors = _session.validateSingle(_draft);
    if (errors.isNotEmpty) {
      setState(() => _error = errors.join('\n'));
      return;
    }
    if (AppSession.clientCode.trim().isEmpty) {
      setState(() => _error = AppStrings.signInToSaveProduct);
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    final result = await saveSingleProduct(draft: _draft, imagePath: _imagePath);
    if (!mounted) return;
    if (result.error != null) {
      setState(() {
        _saving = false;
        _error = result.error;
      });
      _toast(result.error!);
      return;
    }
    if (result.imageUrl.isNotEmpty) _draft.imagePath = result.imageUrl;
    final record = _session.saveSingle();
    _saving = false;
    _imagePath = '';
    if (record == null) {
      setState(() {});
      _toast(result.imageSaved ? AppStrings.productAndPhotoSaved : AppStrings.productSavedLive);
      return;
    }
    _suspend = true;
    for (final controller in _fields.values) {
      controller.clear();
    }
    _suspend = false;
    _goList();
    _toast(result.imageSaved ? AppStrings.productAndPhotoSaved : AppStrings.productSavedLive);
  }

  Future<void> _pickProductPhoto(ImageSource source) async {
    try {
      final photo = await ImagePicker().pickImage(source: source, imageQuality: 100);
      if (photo == null || !mounted) return;
      setState(() {
        _imagePath = photo.path;
        _draft.imagePath = photo.path;
        _session.dirty = true;
      });
    } catch (_) {
      if (mounted) _toast(AppStrings.couldNotSavePhoto);
    }
  }

  void _photoSource() {
    _sheet(AppStrings.productPhoto, [
      ListTile(
        leading: const Icon(Icons.photo_camera_outlined, color: _ink),
        title: const Text(AppStrings.camera),
        onTap: () {
          Navigator.pop(context);
          unawaited(_pickProductPhoto(ImageSource.camera));
        },
      ),
      ListTile(
        leading: const Icon(Icons.photo_library_outlined, color: _ink),
        title: const Text(AppStrings.gallery),
        onTap: () {
          Navigator.pop(context);
          unawaited(_pickProductPhoto(ImageSource.gallery));
        },
      ),
    ]);
  }

  void _zoomPhoto(String path) {
    if (path.trim().isEmpty) return;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => Scaffold(
          backgroundColor: Colors.black,
          appBar: AppBar(
            backgroundColor: Colors.black,
            foregroundColor: Colors.white,
            title: const Text(AppStrings.productPhoto),
          ),
          body: InteractiveViewer(
            minScale: 1,
            maxScale: 6,
            child: Center(child: _photoImage(path, BoxFit.contain)),
          ),
        ),
      ),
    );
  }

  Widget _photoImage(String path, BoxFit fit) {
    if (path.startsWith('http')) {
      return Image.network(path, fit: fit);
    }
    return Image.file(File(path), fit: fit);
  }

  Widget _productPhoto() {
    final path = _imagePath.trim();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(AppStrings.productPhoto, style: _text(size: 13, weight: FontWeight.w700)),
        const SizedBox(height: 8),
        if (path.isEmpty)
          OutlinedButton.icon(
            onPressed: _photoSource,
            icon: const Icon(Icons.add_a_photo_outlined, size: 18),
            label: const Text(AppStrings.productPhoto),
          )
        else
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              GestureDetector(
                onTap: () => _zoomPhoto(path),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: SizedBox(
                    height: 220,
                    width: double.infinity,
                    child: InteractiveViewer(
                      minScale: 1,
                      maxScale: 4,
                      child: _photoImage(path, BoxFit.cover),
                    ),
                  ),
                ),
              ),
              Row(
                children: [
                  TextButton.icon(
                    onPressed: _photoSource,
                    icon: const Icon(Icons.add_a_photo_outlined, size: 18),
                    label: const Text(AppStrings.productPhoto),
                  ),
                  TextButton(
                    onPressed: () => setState(() {
                      _imagePath = '';
                      _draft.imagePath = '';
                    }),
                    child: const Text(AppStrings.clear),
                  ),
                ],
              ),
            ],
          ),
      ],
    );
  }

  Future<void> _saveBulk() async {
    if (_saving) return;
    _commitBulkRows();
    final errors = _session.validateBulk();
    if (errors.isNotEmpty) {
      setState(() => _error = errors.join('\n'));
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    final items = <Map<String, dynamic>>[];
    for (var i = 0; i < _session.bulkRows.length; i++) {
      final row = _session.bulkRows[i];
      final live = i < _rows.length ? _rows[i].piece : row;
      final epc = live.epc.trim().isNotEmpty ? live.epc.trim() : row.epc.trim();
      final tid = live.tid.trim().isNotEmpty
          ? live.tid.trim()
          : (row.tid.trim().isNotEmpty ? row.tid.trim() : epc);
      row.epc = epc;
      row.tid = tid;
      items.add({
        'ItemCode': row.id.trim(),
        'RFIDCode': row.rfid.trim(),
        'EPC': epc,
        'Epc': epc,
        'epc': epc,
        'TIDNumber': tid,
        'TidNumber': tid,
        'TidValue': tid,
        'CategoryName': _session.bulkCategory.trim(),
        'ProductName': _session.bulkName.trim(),
        'DesignName': _session.bulkDesign.trim(),
      });
    }
    try {
      await Injection.productRepository.saveBulkProducts(items);
      await InventoryStock.instance.load();
    } catch (_) {
      if (!mounted) return;
      setState(() => _saving = false);
      _toast(AppStrings.couldNotSaveProduct);
      return;
    }
    if (!mounted) return;
    _stopCapture();
    _session.bulkRows.clear();
    _reloadRows();
    _session.dirty = false;
    _saving = false;
    _goList();
    unawaited(_reloadStored());
    _toast(AppStrings.productSavedLive);
  }

  Future<void> _exportProducts(String mode) async {
    if (_exporting) return;
    _exporting = true;
    final progress = ValueNotifier<int>(0);
    if (!mounted) return;
    unawaited(
      showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (context) => PopScope(
          canPop: false,
          child: AlertDialog(
            content: ValueListenableBuilder<int>(
              valueListenable: progress,
              builder: (context, written, _) => Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const CircularProgressIndicator(color: _ink),
                  const SizedBox(height: 16),
                  Text(
                    written == 0 ? AppStrings.exportingProducts : '${AppStrings.exportingProducts} $written',
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    var closed = false;
    void closeDialog() {
      if (closed || !mounted) return;
      closed = true;
      Navigator.of(context, rootNavigator: true).pop();
    }

    try {
      await Future<void>.delayed(Duration.zero);
      final directory = mode == 'device'
          ? (await getDownloadsDirectory() ?? await getApplicationDocumentsDirectory())
          : await getTemporaryDirectory();
      final path = '${directory.path}${Platform.pathSeparator}all_items.csv';
      final stored = Injection.ready ? await Injection.productRepository.storedCount() : 0;
      final count = stored > 0
          ? await Injection.productRepository.exportStoredCsv(path, onProgress: (written) => progress.value = written)
          : await _writeSessionCsv(path, progress);
      closeDialog();
      if (!mounted) return;
      if (count == 0) {
        final file = File(path);
        if (await file.exists()) await file.delete();
        if (mounted) _toast(AppStrings.noProductsToExport);
        return;
      }
      if (mode == 'mail') {
        await Share.shareXFiles(
          [XFile(path, mimeType: 'text/csv', name: 'all_items.csv')],
          subject: AppStrings.exportProducts,
        );
      } else if (mounted) {
        _toast('${AppStrings.productCsvSaved}: $path');
      }
    } catch (_) {
      closeDialog();
      if (mounted) _toast(AppStrings.productExportFailed);
    } finally {
      _exporting = false;
      Future<void>.delayed(const Duration(milliseconds: 300), progress.dispose);
    }
  }

  Future<int> _writeSessionCsv(String path, ValueNotifier<int> progress) async {
    final file = File(path);
    final sink = file.openWrite();
    var written = 0;
    try {
      sink.write('\uFEFF${productCsvHeader.join(',')}\r\n');
      for (final item in _session.items) {
        sink
          ..write(
            productCsvLine([
              item.category,
              item.name,
              item.design,
              item.id,
              item.rfid,
              item.grossMg == null ? '' : (item.grossMg! / 1000).toString(),
              '',
              '',
              item.netMg == null ? '' : (item.netMg! / 1000).toString(),
              item.purity,
              '',
              '',
              '',
              '',
              '',
              '',
              item.sku,
              item.epc,
              item.vendor,
              '',
              '',
              '',
              '',
            ]),
          )
          ..write('\r\n');
        written++;
        if (written % 500 == 0) {
          progress.value = written;
          await Future<void>.delayed(Duration.zero);
        }
      }
      await sink.flush();
    } catch (_) {
      await sink.close();
      if (await file.exists()) await file.delete();
      rethrow;
    }
    await sink.close();
    progress.value = written;
    return written;
  }

  void _runSync(String id, {bool resume = false}) {
    _stopCapture();
    if (resume) {
      _session.syncPhase = 'running';
    } else if (!_session.startSync(id)) {
      return;
    }
    setState(() => _page = _ProductPage.sync);
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(milliseconds: 650), (_) {
      if (!mounted) return;
      setState(_session.tickSync);
      if (_session.syncPhase == 'complete') {
        _timer?.cancel();
        _timer = null;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: _page == _ProductPage.list,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _back();
      },
      child: AnnotatedRegion<SystemUiOverlayStyle>(
        value: const SystemUiOverlayStyle(
          statusBarColor: Color(0x00000000),
          statusBarIconBrightness: Brightness.dark,
          statusBarBrightness: Brightness.light,
          systemNavigationBarColor: _surface,
          systemNavigationBarIconBrightness: Brightness.dark,
        ),
        child: Theme(
          data: Theme.of(context).copyWith(
            textButtonTheme: TextButtonThemeData(
              style: TextButton.styleFrom(foregroundColor: _gold),
            ),
            iconButtonTheme: IconButtonThemeData(
              style: IconButton.styleFrom(foregroundColor: _ink),
            ),
          ),
          child: Scaffold(
          backgroundColor: _surface,
          body: SafeArea(
            child: Column(
              children: [
                _header(),
                Expanded(
                  child: switch (_page) {
                    _ProductPage.list => _list(),
                    _ProductPage.single => _single(),
                    _ProductPage.bulk => _bulk(),
                    _ProductPage.sync => _sync(),
                  },
                ),
              ],
            ),
          ),
        ),
        ),
      ),
    );
  }

  Widget _header() {
    final (title, subtitle) = switch (_page) {
      _ProductPage.list => (AppStrings.products, AppStrings.yourJewelleryCatalogue),
      _ProductPage.single => (AppStrings.addProductTitle, AppStrings.addProductSubtitle),
      _ProductPage.bulk => (AppStrings.addInBulk, AppStrings.bulkSubtitle),
      _ProductPage.sync => (AppStrings.dataSync, AppStrings.dataSyncSubtitle),
    };
    return DecoratedBox(
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: _headLine)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(4, 6, 4, 6),
        child: Row(
          children: [
            IconButton(
              onPressed: _back,
              icon: const Icon(Icons.arrow_back, size: 21),
              color: _ink,
              tooltip: AppStrings.home,
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: _text(size: 21, weight: FontWeight.w600, letterSpacing: -0.7),
                  ),
                  const SizedBox(height: 4),
                  Text(subtitle, style: _text(size: 10, color: _subtitle)),
                ],
              ),
            ),
            if (_page == _ProductPage.bulk) ...[
              _powerButton(),
              const SizedBox(width: 4),
            ],
            IconButton(
              tooltip: AppStrings.moreActions,
              onPressed: _page == _ProductPage.single || _page == _ProductPage.bulk
                  ? _formMenu
                  : _dataTools,
              icon: const Icon(Icons.more_horiz, size: 21),
              color: _ink,
            ),
          ],
        ),
      ),
    );
  }

  void _onStoredScroll() {
    if (!_sheetCatalogue || !_storedScroll.hasClients) return;
    final position = _storedScroll.position;
    if (position.pixels < position.maxScrollExtent - 480) return;
    unawaited(_loadMoreStored());
  }

  Future<void> _reloadStored() async {
    if (!Injection.ready) return;
    final ticket = ++_storedTicket;
    final prefs = await SharedPreferences.getInstance();
    final source = prefs.getString(productCatalogueSourceKey) ?? '';
    final local = source == productCatalogueSheet || source == productCatalogueBulk || source == productCatalogueServer;
    if (!local) {
      if (!mounted || ticket != _storedTicket) return;
      setState(() {
        _sheetCatalogue = false;
        _catalogueSource = '';
        _storedTotal = 0;
        _stored.clear();
      });
      return;
    }
    final query = _query.text.trim();
    final total = await Injection.productRepository.storedCount();
    final page = await Injection.productRepository.searchStored(query: query, limit: 40);
    if (!mounted || ticket != _storedTicket) return;
    setState(() {
      _sheetCatalogue = true;
      _catalogueSource = source;
      _storedTotal = total;
      _stored
        ..clear()
        ..addAll(page.map((record) => _pieceFromStored(record, source)));
    });
  }

  Future<void> _loadMoreStored() async {
    if (!_sheetCatalogue || _storedLoading || !Injection.ready) return;
    final query = _query.text.trim();
    if (query.isEmpty && _stored.length >= _storedTotal) return;
    final ticket = _storedTicket;
    _storedLoading = true;
    final page = await Injection.productRepository.searchStored(
      query: query,
      limit: 40,
      offset: _stored.length,
    );
    _storedLoading = false;
    if (!mounted || ticket != _storedTicket || page.isEmpty) return;
    final source = _stored.isEmpty ? 'sheet' : _stored.first.origin;
    setState(() => _stored.addAll(page.map((record) => _pieceFromStored(record, source))));
  }

  CataloguePiece _pieceFromStored(StoredRecord record, String origin) {
    String? text(List<String> keys) {
      for (final key in keys) {
        final value = record.payload[key]?.toString().trim();
        if (value != null && value.isNotEmpty && value.toLowerCase() != 'null') return value;
      }
      return null;
    }

    int? milligrams(String? raw) {
      if (raw == null) return null;
      final value = double.tryParse(raw.replaceAll(',', ''));
      if (value == null) return null;
      return (value * 1000).round();
    }

    return CataloguePiece(
      id: text(const ['ItemCode', 'itemCode']) ?? record.itemCode ?? '',
      name: text(const ['ProductName', 'productName', 'ItemName']) ?? record.name ?? '',
      epc: text(const ['EPC', 'Epc', 'epc']) ?? '',
      rfid: text(const ['RFIDCode', 'RfidCode', 'RFID']) ?? '',
      category: text(const ['CategoryName']) ?? '',
      design: text(const ['DesignName']) ?? '',
      purity: text(const ['PurityName']) ?? '',
      vendor: text(const ['VendorName']) ?? '',
      sku: text(const ['SKU', 'Sku']) ?? '',
      grossMg: milligrams(text(const ['GrossWeight'])),
      netMg: milligrams(text(const ['NetWeight'])),
      origin: origin,
    );
  }

  Widget _list() {
    if (_sheetCatalogue) return _sheetList();
    final rows = _session.visible;
    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
            children: [
              Row(
                children: [
                  Text(
                    AppStrings.findAddSync,
                    style: _text(size: 10, weight: FontWeight.w600, color: _demoInk),
                  ),
                  const Spacer(),
                  _tag(AppStrings.demoData),
                ],
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _query,
                style: _text(size: 12),
                cursorColor: _searchFocus,
                decoration: InputDecoration(
                  hintText: AppStrings.searchProducts,
                  hintStyle: _text(size: 12, color: _searchIcon),
                  prefixIcon: const Icon(Icons.search, size: 18, color: _searchIcon),
                  filled: true,
                  fillColor: AppColors.white,
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(vertical: 14),
                  border: _searchBorder(_searchLine),
                  enabledBorder: _searchBorder(_searchLine),
                  focusedBorder: _searchBorder(_searchFocus),
                ),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  _toolButton(
                    icon: Icons.sync,
                    label: AppStrings.syncData,
                    onPressed: () => setState(() => _page = _ProductPage.sync),
                  ),
                  const SizedBox(width: 8),
                  _toolButton(
                    icon: Icons.swap_vert,
                    label: tx('dataTools', AppStrings.dataTools),
                    onPressed: _dataTools,
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  _filterChip(AppStrings.allProducts, 'all'),
                  const SizedBox(width: 7),
                  _filterChip(AppStrings.addedHere, 'local'),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Text(
                    AppStrings.productsLabel,
                    style: _text(size: 12, weight: FontWeight.w700, letterSpacing: 0.6),
                  ),
                  const Spacer(),
                  Text(
                    '${rows.length} ${rows.length == 1 ? AppStrings.piece : AppStrings.pieces}',
                    style: _text(size: 12, color: AppColors.muted),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              if (rows.isEmpty)
                _empty(AppStrings.noMatchingProducts, AppStrings.tryProductSearch)
              else
                for (final item in rows) _productCard(item),
            ],
          ),
        ),
        _footer(
          label: AppStrings.addProducts,
          icon: Icons.add,
          onPressed: _addSheet,
          note: AppStrings.addProductsNote,
        ),
      ],
    );
  }

  Widget _sheetList() {
    final rows = _stored;
    final count = _query.text.trim().isEmpty ? _storedTotal : rows.length;
    return Column(
      children: [
        Expanded(
          child: CustomScrollView(
            controller: _storedScroll,
            slivers: [
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
                sliver: SliverList(
                  delegate: SliverChildListDelegate([
                    Row(
                      children: [
                        Text(
                          AppStrings.findAddSync,
                          style: _text(size: 10, weight: FontWeight.w600, color: _demoInk),
                        ),
                        const Spacer(),
                        if (_catalogueSource == productCatalogueSheet)
                          _tag(tx('sheetData', 'Sheet data'))
                        else if (_catalogueSource == productCatalogueBulk)
                          _tag('Bulk'),
                      ],
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _query,
                      style: _text(size: 12),
                      cursorColor: _searchFocus,
                      decoration: InputDecoration(
                        hintText: AppStrings.searchProducts,
                        hintStyle: _text(size: 12, color: _searchIcon),
                        prefixIcon: const Icon(Icons.search, size: 18, color: _searchIcon),
                        filled: true,
                        fillColor: AppColors.white,
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(vertical: 14),
                        border: _searchBorder(_searchLine),
                        enabledBorder: _searchBorder(_searchLine),
                        focusedBorder: _searchBorder(_searchFocus),
                      ),
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        _toolButton(
                          icon: Icons.sync,
                          label: AppStrings.syncData,
                          onPressed: () => setState(() => _page = _ProductPage.sync),
                        ),
                        const SizedBox(width: 8),
                        _toolButton(
                          icon: Icons.swap_vert,
                          label: tx('dataTools', AppStrings.dataTools),
                          onPressed: _dataTools,
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Text(
                          AppStrings.productsLabel,
                          style: _text(size: 12, weight: FontWeight.w700, letterSpacing: 0.6),
                        ),
                        const Spacer(),
                        Text(
                          '$count ${count == 1 ? AppStrings.piece : AppStrings.pieces}',
                          style: _text(size: 12, color: AppColors.muted),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    if (rows.isEmpty) _empty(AppStrings.noMatchingProducts, AppStrings.tryProductSearch),
                  ]),
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
                sliver: SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (context, index) => _productCard(rows[index]),
                    childCount: rows.length,
                  ),
                ),
              ),
            ],
          ),
        ),
        _footer(
          label: AppStrings.addProducts,
          icon: Icons.add,
          onPressed: _addSheet,
          note: AppStrings.addProductsNote,
        ),
      ],
    );
  }

  Widget _productCard(CataloguePiece item) {
    final gross = item.grossMg == null
        ? '—'
        : '${ProductDemoSession.grams(item.grossMg)} g';
    final saved = item.origin == 'manual';
    final sheet = item.origin == 'sheet';
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: _card(
        onTap: () => _detail(item),
        child: Row(
          children: [
            _thumb(item.name),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(item.name, style: _text(size: 16, weight: FontWeight.w700)),
                  Text(
                    '${item.id} · ${AppStrings.grossShort} $gross',
                    style: _text(size: 12, color: AppColors.muted),
                  ),
                  if (item.epc.isNotEmpty)
                    Text(
                      item.epc,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: _text(size: 11, color: AppColors.muted),
                    ),
                  const SizedBox(height: 2),
                  Text(
                    sheet
                        ? tx('sheetData', 'Sheet data')
                        : item.origin == productCatalogueBulk
                            ? 'Bulk'
                            : saved
                                ? AppStrings.savedOnDeviceDemo
                                : item.origin == productCatalogueServer
                                    ? item.category
                                    : AppStrings.referenceItemDemo,
                    style: _text(size: 10, color: _status),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, size: 17, color: _chevron),
          ],
        ),
      ),
    );
  }

  Widget _single() {
    final draft = _draft;
    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
            children: [
              Row(
                children: [
                  Text(
                    AppStrings.newProduct,
                    style: _text(size: 10, weight: FontWeight.w600, color: _demoInk),
                  ),
                  const Spacer(),
                  _tag(AppStrings.demoTag),
                ],
              ),
              const SizedBox(height: 12),
              _field(AppStrings.itemCodeRequired, _fields['id']!, hint: AppStrings.itemCodeExample),
              const SizedBox(height: 8),
              _classDropdowns(
                category: draft.category,
                name: draft.name,
                design: draft.design,
                purity: draft.purity,
                showPurity: true,
                onChanged: (key, value) => setState(() {
                  _session.dirty = true;
                  switch (key) {
                    case 'category':
                      draft.category = value;
                    case 'name':
                      draft.name = value;
                    case 'design':
                      draft.design = value;
                    case 'purity':
                      draft.purity = value;
                  }
                }),
              ),
              _productPhoto(),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: _masterSheet,
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text(AppStrings.addClassification),
                ),
              ),
              _section(
                AppStrings.tagIdentity,
                open: true,
                children: [
                  _field(AppStrings.rfidCode, _fields['rfid']!),
                  const SizedBox(height: 8),
                  _field(AppStrings.epc, _fields['epc']!),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: _readingTag ? null : () => unawaited(_readTag()),
                      icon: const Icon(Icons.document_scanner_outlined, size: 18),
                      label: const Text(AppStrings.readDemoTag),
                    ),
                  ),
                ],
              ),
              _section(
                AppStrings.weights,
                open: true,
                children: [
                  _pair(
                    _field(AppStrings.grossWeightG, _fields['gross']!, number: true),
                    _field(AppStrings.netWeightG, _fields['net']!, number: true),
                  ),
                  const SizedBox(height: 8),
                  _pair(
                    _field(AppStrings.stoneWeight, _fields['stone']!, number: true),
                    _field(AppStrings.diamondWeight, _fields['diamond']!, number: true),
                  ),
                  const SizedBox(height: 8),
                  Text(AppStrings.weightUnitsNote, style: _text(size: 12, color: AppColors.muted)),
                ],
              ),
              _section(
                AppStrings.vendorAndSku,
                children: [
                  _field(AppStrings.vendor, _fields['vendor']!, hint: AppStrings.masterDataHint),
                  const SizedBox(height: 8),
                  _field(AppStrings.sku, _fields['sku']!, hint: AppStrings.masterDataHint),
                ],
              ),
              _section(
                AppStrings.makingSection,
                children: [
                  _pair(
                    _field(AppStrings.makingPerGram, _fields['makingGram']!, number: true),
                    _field(AppStrings.makingPercentLabel, _fields['makingPercent']!, number: true),
                  ),
                  const SizedBox(height: 8),
                  _pair(
                    _field(AppStrings.fixedMaking, _fields['fixedMaking']!, number: true),
                    _field(AppStrings.fixedWastage, _fields['fixedWastage']!, number: true),
                  ),
                  const SizedBox(height: 8),
                  _pair(
                    _field(AppStrings.stoneAmount, _fields['stoneAmount']!, number: true),
                    _field(AppStrings.diamondAmount, _fields['diamondAmount']!, number: true),
                  ),
                  const SizedBox(height: 8),
                  Text(AppStrings.calculationNote, style: _text(size: 12, color: AppColors.muted)),
                ],
              ),
              if (_saving) const LinearProgressIndicator(color: _ink, minHeight: 2),
              if (_error != null) _errorText(_error!),
            ],
          ),
        ),
        _footer(
          label: AppStrings.reviewProduct,
          icon: Icons.arrow_forward,
          onPressed: _reviewSingle,
          note: AppStrings.tagFillsIdentity,
        ),
      ],
    );
  }

  Widget _bulk() {
    final shared = [
      _session.bulkName,
      _session.bulkDesign,
    ].where((value) => value.isNotEmpty).join(' · ');
    final singleBusy = _scanRow != null && _radioOn;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: _card(
            onTap: () => setState(() => _sharedOpen = !_sharedOpen),
            fill: _classFill,
            border: _classLine,
            radius: 12,
            child: Row(
              children: [
                const Icon(Icons.layers_outlined, color: _captureInk),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _session.bulkCategory.isEmpty
                            ? AppStrings.setSharedDetails
                            : _session.bulkCategory,
                        style: _text(size: 15, weight: FontWeight.w700),
                      ),
                      Text(
                        shared.isEmpty ? AppStrings.classificationHint : shared,
                        style: _text(size: 12, color: AppColors.muted),
                      ),
                    ],
                  ),
                ),
                Icon(_sharedOpen ? Icons.expand_less : Icons.expand_more, color: _chevron),
              ],
            ),
          ),
        ),
        _bulkHeader(),
        Expanded(child: _bulkBody()),
        if (_error != null)
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 96),
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: _errorText(_error!),
            ),
          ),
        if (_saving) const LinearProgressIndicator(color: _ink, minHeight: 2),
        Container(
          decoration: const BoxDecoration(
            color: AppColors.white,
            border: Border(top: BorderSide(color: _line)),
          ),
          padding: const EdgeInsets.fromLTRB(4, 6, 4, 8),
          child: Row(
            children: [
              _barAction(Icons.add, 'Add', _addManualRow),
              _barAction(Icons.remove, 'Remove', _rows.isEmpty ? null : _removeSelectedRow),
              _barAction(
                singleBusy ? Icons.close : Icons.qr_code_scanner,
                singleBusy ? AppStrings.pause : AppStrings.scan,
                () => unawaited(_startSingleScan()),
              ),
              _barAction(
                _capturing ? Icons.close : Icons.radio_button_checked,
                _capturing ? AppStrings.pause : AppStrings.gscan,
                () => unawaited(_toggleCapture()),
              ),
              _barAction(Icons.fact_check_outlined, AppStrings.reviewBatch, _rows.isEmpty ? null : _reviewBulk),
            ],
          ),
        ),
      ],
    );
  }

  Widget _bulkBody() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final share = constraints.maxHeight * 0.5;
        final panelMax = !_sharedOpen ? 0.0 : (share > 248 ? 248.0 : share);
        return Column(
          children: [
            Expanded(
              child: _rows.isEmpty
                  ? _empty(AppStrings.readyForBatch, AppStrings.scanOrAddRows)
                  : ListView.builder(
                      itemCount: _rows.length,
                      itemBuilder: (context, index) => _bulkRow(index),
                    ),
            ),
            if (_sharedOpen && panelMax > 0)
              ConstrainedBox(
                constraints: BoxConstraints(maxHeight: panelMax),
                child: DecoratedBox(
                  decoration: const BoxDecoration(
                    color: Color(0xFFF8F2E6),
                    border: Border(top: BorderSide(color: _classLine)),
                  ),
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          children: [
                            Text(AppStrings.sharedDetails, style: _text(size: 13, weight: FontWeight.w700)),
                            const Spacer(),
                            InkWell(
                              onTap: () => setState(() => _sharedOpen = false),
                              child: Text(AppStrings.done, style: _text(size: 12, weight: FontWeight.w700, color: _gold)),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        _classDropdowns(
                          category: _session.bulkCategory,
                          name: _session.bulkName,
                          design: _session.bulkDesign,
                          onChanged: (key, value) => setState(() {
                            _session.dirty = true;
                            if (key == 'category') _session.bulkCategory = value;
                            if (key == 'name') _session.bulkName = value;
                            if (key == 'design') _session.bulkDesign = value;
                          }),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _barAction(IconData icon, String label, VoidCallback? onPressed) {
    final enabled = onPressed != null;
    return Expanded(
      child: InkWell(
        onTap: onPressed,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 20, color: enabled ? _ink : const Color(0xFFC8C2B6)),
              const SizedBox(height: 2),
              Text(
                label,
                maxLines: 2,
                textAlign: TextAlign.center,
                overflow: TextOverflow.ellipsis,
                style: _text(size: 9, weight: FontWeight.w600, color: enabled ? _ink : const Color(0xFFC8C2B6)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _bulkHeader() {
    return Container(
      color: _ink,
      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
      child: Row(
        children: [
          SizedBox(
            width: 36,
            child: Text('Sr', textAlign: TextAlign.center, style: _text(size: 12, weight: FontWeight.w700, color: AppColors.white)),
          ),
          _headerCheck(AppStrings.itemCode, _copyItem, (value) {
            setState(() => _copyItem = value);
            if (value) _copyFromFirst();
          }),
          _headerCheck(AppStrings.rfidCode, _copyRfid, (value) {
            setState(() => _copyRfid = value);
            if (value) _copyFromFirst();
          }),
        ],
      ),
    );
  }

  Widget _headerCheck(String label, bool checked, ValueChanged<bool> onChanged) {
    return Expanded(
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          SizedBox(
            width: 22,
            height: 22,
            child: Checkbox(
              value: checked,
              activeColor: AppColors.white,
              checkColor: const Color(0xFF424242),
              side: BorderSide(color: AppColors.white.withValues(alpha: checked ? 1 : 0.7), width: 1.5),
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              visualDensity: VisualDensity.compact,
              onChanged: (value) => onChanged(value ?? false),
            ),
          ),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              label,
              overflow: TextOverflow.ellipsis,
              style: _text(size: 12, weight: FontWeight.w700, color: AppColors.white),
            ),
          ),
        ],
      ),
    );
  }

  Widget _bulkRow(int index) {
    final row = _rows[index];
    final selected = _selectedRow == index;
    return Column(
      children: [
        Material(
          color: selected ? const Color(0xFFF8F2E6) : AppColors.white,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            child: Row(
              children: [
                SizedBox(
                  width: 36,
                  height: 36,
                  child: Center(child: Text('${index + 1}', style: _text(size: 11, color: const Color(0xFF424242)))),
                ),
                Expanded(child: _inlineField(row.id, onTap: () => setState(() => _selectedRow = index))),
                Expanded(
                  child: _inlineField(
                    row.rfid,
                    onTap: () {
                      setState(() => _selectedRow = index);
                      unawaited(_armBarcode(index));
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
        const Divider(height: 1, thickness: 0.6, color: Color(0xFFE3DDD1)),
      ],
    );
  }

  Widget _inlineField(TextEditingController controller, {VoidCallback? onTap}) {
    return SizedBox(
      height: 36,
      child: TextField(
        controller: controller,
        onTap: onTap,
        textAlign: TextAlign.center,
        textCapitalization: TextCapitalization.characters,
        style: _text(size: 12, color: const Color(0xFF424242)),
        decoration: const InputDecoration(
          isDense: true,
          contentPadding: EdgeInsets.symmetric(horizontal: 6, vertical: 8),
          border: InputBorder.none,
          enabledBorder: InputBorder.none,
          focusedBorder: InputBorder.none,
          filled: false,
        ),
      ),
    );
  }

  Widget _sync() {
    final method = _session.methodById(_session.syncMethod);
    final phase = _session.syncPhase;
    final active = phase == 'running' || phase == 'paused' || phase == 'complete';
    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      AppStrings.threeDataActions,
                      style: _text(size: 10, weight: FontWeight.w600, color: _demoInk),
                    ),
                  ),
                  _tag(AppStrings.demoTag),
                ],
              ),
              if (active && method != null) ...[
                const SizedBox(height: 12),
                _card(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(method.name, style: _text(size: 16, weight: FontWeight.w700)),
                      Text(
                        '${_session.syncDone} / ${_session.syncTotal}',
                        style: _text(size: 28, weight: FontWeight.w700),
                      ),
                      Text(_syncCaption(phase), style: _text(size: 13, color: AppColors.muted)),
                      const SizedBox(height: 8),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(99),
                        child: LinearProgressIndicator(
                          value: _session.syncTotal == 0
                              ? 0
                              : _session.syncDone / _session.syncTotal,
                          minHeight: 6,
                          color: _progress,
                          backgroundColor: _track,
                        ),
                      ),
                      if (phase == 'complete') ...[
                        const SizedBox(height: 8),
                        Text(AppStrings.noLiveDataChanged, style: _text(size: 12, color: AppColors.muted)),
                      ],
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 12),
              for (final option in ProductDemoSession.methods)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: _card(
                    onTap: () => option.id == 'sheet' ? _openExcelImport() : _syncMethodSheet(option),
                    child: Row(
                      children: [
                        const Icon(Icons.sync, color: _gold),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(option.name, style: _text(size: 15, weight: FontWeight.w700)),
                              Text(option.copy, style: _text(size: 12, color: AppColors.muted)),
                            ],
                          ),
                        ),
                        const Icon(Icons.chevron_right, color: _chevron),
                      ],
                    ),
                  ),
                ),
              Text(AppStrings.excelAlsoInTools, style: _text(size: 12, color: AppColors.muted)),
              const SizedBox(height: 14),
              Text(
                AppStrings.recentActivity,
                style: _text(size: 12, weight: FontWeight.w700, letterSpacing: 0.4),
              ),
              const SizedBox(height: 8),
              if (_session.history.isEmpty)
                Text(AppStrings.noSyncYet, style: _text(size: 13, color: AppColors.muted))
              else
                for (final activity in _session.history.take(3))
                  _summaryLine(
                    _session.methodById(activity.methodId)?.name ?? activity.methodId,
                    '${activity.count} · ${AppStrings.demoTag}',
                  ),
            ],
          ),
        ),
        _footer(
          label: phase == 'running'
              ? AppStrings.pauseSync
              : phase == 'paused'
              ? AppStrings.resumeDemoSync
              : AppStrings.backToProducts,
          icon: phase == 'running'
              ? Icons.pause
              : phase == 'paused'
              ? Icons.play_arrow
              : Icons.arrow_back,
          onPressed: () {
            if (phase == 'running') {
              setState(_pauseSync);
            } else if (phase == 'paused') {
              _runSync(_session.syncMethod ?? 'data', resume: true);
            } else {
              _goList();
            }
          },
          note: AppStrings.syncSimulated,
        ),
      ],
    );
  }

  String _syncCaption(String phase) {
    return switch (phase) {
      'complete' => AppStrings.demoCompleted,
      'paused' => AppStrings.pausedProgressKept,
      _ => AppStrings.processingDemoRecords,
    };
  }

  Future<void> _sheet(String title, List<Widget> children) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: _surface,
      builder: (context) {
        return Directionality(
          textDirection: featureDirection,
          child: Padding(
          padding: EdgeInsets.fromLTRB(
            20,
            16,
            20,
            20 + MediaQuery.viewInsetsOf(context).bottom,
          ),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(title, style: _text(size: 18, weight: FontWeight.w700)),
                const SizedBox(height: 8),
                ...children,
              ],
            ),
          ),
        ),
        );
      },
    );
  }

  void _addSheet() {
    _sheet(AppStrings.addProducts, [
      if (_session.dirty)
        _choice(
          icon: Icons.edit_outlined,
          title: AppStrings.resumeYourDraft,
          subtitle: _session.mode == 'bulk'
              ? '${_session.bulkRows.length} ${AppStrings.piecesInProgress}'
              : AppStrings.singleProductEntry,
          onTap: () {
            Navigator.pop(context);
            _resumeDraft();
          },
        ),
      _choice(
        icon: Icons.add_circle_outline,
        title: AppStrings.oneProduct,
        subtitle: AppStrings.oneProductHint,
        onTap: () {
          if (_session.dirty) {
            _toast(AppStrings.resumeOrDiscard);
            return;
          }
          Navigator.pop(context);
          _startSingle();
        },
      ),
      _choice(
        icon: Icons.layers_outlined,
        title: AppStrings.multipleProducts,
        subtitle: AppStrings.multipleProductsHint,
        onTap: () {
          if (_session.dirty) {
            _toast(AppStrings.resumeOrDiscard);
            return;
          }
          Navigator.pop(context);
          _startBulk();
        },
      ),
      _choice(
        icon: Icons.table_chart_outlined,
        title: AppStrings.importExcel,
        subtitle: AppStrings.importExcelHint,
        onTap: () {
          Navigator.pop(context);
          _openExcelImport();
        },
      ),
    ]);
  }

  void _dataTools() {
    _sheet(tx('productDataTools', AppStrings.productDataTools), [
      _choice(
        icon: Icons.sync,
        title: tx('syncCentre', AppStrings.syncCentre),
        subtitle: tx('dataSyncSubtitle', AppStrings.dataSyncSubtitle),
        onTap: () {
          Navigator.pop(context);
          _pauseSync();
          setState(() => _page = _ProductPage.sync);
        },
      ),
      _choice(
        icon: Icons.table_chart_outlined,
        title: tx('importExcel', AppStrings.importExcel),
        subtitle: tx('importExcelHint', AppStrings.importExcelHint),
        onTap: () {
          Navigator.pop(context);
          _openExcelImport();
        },
      ),
      _choice(
        icon: Icons.grid_on_outlined,
        title: tx('syncSheetData', 'Sync Sheet data'),
        subtitle: tx('syncSheetHint', 'Use the same column mapping from a Google Sheet.'),
        onTap: () {
          Navigator.pop(context);
          unawaited(ImportExcelFlow.startSheet(context).whenComplete(() {
            if (mounted) unawaited(_reloadStored());
          }));
        },
      ),
      _choice(
        icon: Icons.download_outlined,
        title: tx('exportExcel', AppStrings.exportExcel),
        subtitle: tx('csvHint', AppStrings.csvHint),
        onTap: () {
          Navigator.pop(context);
          _exportSheet();
        },
      ),
      _choice(
        icon: Icons.desktop_windows_outlined,
        title: tx('scanToDesktop', AppStrings.scanToDesktop),
        subtitle: tx('desktopNote', AppStrings.desktopNote),
        onTap: () {
          Navigator.pop(context);
          Navigator.of(context).push(
            MaterialPageRoute<void>(builder: (_) => const ScanToDesktopPage()),
          );
        },
      ),
    ]);
  }

  void _formMenu() {
    _sheet(AppStrings.productEntryOptions, [
      _choice(
        icon: Icons.save_outlined,
        title: AppStrings.keepDraftReturn,
        subtitle: AppStrings.keepDraftBody,
        onTap: () {
          Navigator.pop(context);
          _stopCapture();
          _goList();
        },
      ),
      if (_page == _ProductPage.bulk)
        _choice(
          icon: Icons.fact_check_outlined,
          title: AppStrings.reviewBatch,
          subtitle: AppStrings.duplicatesBlocked,
          onTap: () {
            Navigator.pop(context);
            _reviewBulk();
          },
        ),
      _choice(
        icon: Icons.document_scanner_outlined,
        title: AppStrings.gscan,
        subtitle: AppStrings.gscanNote,
        onTap: () {
          Navigator.pop(context);
          if (_page == _ProductPage.bulk) {
            unawaited(_toggleCapture());
          } else {
            _previewSheet(AppStrings.gscan, AppStrings.gscanNote, Icons.document_scanner_outlined);
          }
        },
      ),
      _choice(
        icon: Icons.replay,
        title: AppStrings.resetThisDraft,
        subtitle: AppStrings.resetDraftBody,
        onTap: () {
          Navigator.pop(context);
          _confirmReset();
        },
      ),
    ]);
  }

  void _keepOrDiscard() {
    _sheet(AppStrings.keepDraftQuestion, [
      Text(AppStrings.keepDraftBody, style: _text(size: 14, color: AppColors.muted)),
      const SizedBox(height: 12),
      FilledButton(
        onPressed: () {
          Navigator.pop(context);
          _goList();
        },
        style: FilledButton.styleFrom(
          backgroundColor: _ink,
          minimumSize: const Size.fromHeight(48),
        ),
        child: const Text(AppStrings.keepDraftReturn),
      ),
      TextButton(
        onPressed: () {
          Navigator.pop(context);
          _discard();
        },
        child: const Text(AppStrings.discardDraft),
      ),
    ]);
  }

  void _confirmReset() {
    _sheet(AppStrings.resetDraftQuestion, [
      Text(AppStrings.resetDraftBody, style: _text(size: 14, color: AppColors.muted)),
      const SizedBox(height: 12),
      FilledButton.icon(
        onPressed: () {
          Navigator.pop(context);
          _discard();
        },
        style: FilledButton.styleFrom(backgroundColor: _ink),
        icon: const Icon(Icons.replay),
        label: const Text(AppStrings.resetDraft),
      ),
    ]);
  }

  void _detail(CataloguePiece item) {
    final saved = item.origin == 'manual';
    final sheet = item.origin == 'sheet';
    _sheet(item.name, [
      _summaryLine(AppStrings.itemCode, item.id),
      const SizedBox(height: 8),
      Row(
        children: [
          Expanded(child: _weightBox(AppStrings.grossWeight, item.grossMg, suffix: item.grossMg != null)),
          const SizedBox(width: 8),
          Expanded(child: _weightBox(AppStrings.netWeight, item.netMg, suffix: item.netMg != null)),
        ],
      ),
      _summaryLine(AppStrings.rfidCode, item.rfid.isEmpty ? AppStrings.notProvided : item.rfid),
      _summaryLine(AppStrings.epc, item.epc.isEmpty ? AppStrings.notProvided : item.epc),
      _summaryLine(AppStrings.category, item.category.isEmpty ? AppStrings.notProvided : item.category),
      _summaryLine(AppStrings.design, item.design.isEmpty ? AppStrings.notProvided : item.design),
      _summaryLine(AppStrings.purity, item.purity.isEmpty ? AppStrings.notProvided : item.purity),
      _summaryLine(AppStrings.vendor, item.vendor.isEmpty ? AppStrings.notProvided : item.vendor),
      _summaryLine(AppStrings.sku, item.sku.isEmpty ? AppStrings.notProvided : item.sku),
      if (item.imagePath.trim().isNotEmpty) ...[
        const SizedBox(height: 8),
        GestureDetector(
          onTap: () => _zoomPhoto(item.imagePath),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: SizedBox(
              height: 180,
              width: double.infinity,
              child: InteractiveViewer(
                minScale: 1,
                maxScale: 4,
                child: _photoImage(item.imagePath, BoxFit.cover),
              ),
            ),
          ),
        ),
      ],
      const SizedBox(height: 8),
      Text(
        sheet
            ? tx('sheetData', 'Sheet data')
            : item.origin == productCatalogueBulk
                ? 'Bulk'
                : saved
                    ? AppStrings.savedThisSession
                    : AppStrings.referenceUnspecified,
        style: _text(size: 13, color: AppColors.muted, height: 1.35),
      ),
    ]);
  }

  void _reviewSheet({required bool bulk}) {
    final rows = bulk
        ? _session.bulkRows.map((row) {
            final rfid = row.rfid.isEmpty ? AppStrings.noRfidCode : row.rfid;
            final epc = row.epc.trim();
            return epc.isEmpty ? '${row.id} · $rfid' : '${row.id} · $rfid · $epc';
          }).toList()
        : [
            '${_draft.id} · ${_draft.rfid.isEmpty ? AppStrings.noRfidCode : _draft.rfid}',
          ];
    final missingTag = bulk
        ? _session.bulkRows.any((row) => row.rfid.isEmpty && row.epc.isEmpty)
        : _draft.rfid.isEmpty && _draft.epc.isEmpty;
    final category = bulk ? _session.bulkCategory : _draft.category;
    final name = bulk ? _session.bulkName : _draft.name;
    _sheet(bulk ? AppStrings.reviewProductBatch : AppStrings.reviewProduct, [
      _summaryLine(AppStrings.productsToAdd, '${rows.length}'),
      _summaryLine(AppStrings.categorySlashProduct, '$category / $name'),
      const SizedBox(height: 8),
      Text(rows.join('\n'), style: _text(size: 14, height: 1.4)),
      if (missingTag) ...[
        const SizedBox(height: 8),
        Text(AppStrings.noTagYet, style: _text(size: 13, color: _gold, height: 1.35)),
      ],
      const SizedBox(height: 8),
      Text(AppStrings.checkEachCode, style: _text(size: 13, color: AppColors.muted)),
      const SizedBox(height: 12),
      FilledButton.icon(
        onPressed: _saving
            ? null
            : () {
                Navigator.pop(context);
                if (bulk) {
                  unawaited(_saveBulk());
                } else {
                  unawaited(_saveSingle());
                }
              },
        style: FilledButton.styleFrom(
          backgroundColor: _ink,
          minimumSize: const Size.fromHeight(48),
        ),
        icon: const Icon(Icons.save_outlined),
        label: Text(bulk ? AppStrings.saveDemoBatch : AppStrings.saveProduct),
      ),
      if (bulk) ...[
        const SizedBox(height: 8),
        Text(AppStrings.savedSessionOnly, style: _text(size: 12, color: AppColors.muted)),
      ],
    ]);
  }

  void _openExcelImport() {
    unawaited(ImportExcelFlow.start(context).whenComplete(() {
      if (mounted) unawaited(_reloadStored());
    }));
  }

  void _syncMethodSheet(SyncMethod method) {
    _pauseSync();
    setState(() {});
    _sheet(method.name, [
      Text(method.copy, style: _text(size: 14, color: AppColors.muted, height: 1.35)),
      _summaryLine(
        AppStrings.demoScope,
        '${_session.items.length} ${AppStrings.productRecords}',
      ),
      const SizedBox(height: 8),
      Text(AppStrings.checkConnection, style: _text(size: 13, height: 1.35)),
      const SizedBox(height: 12),
      FilledButton.icon(
        onPressed: () {
          Navigator.pop(context);
          _runSync(method.id);
        },
        style: FilledButton.styleFrom(
          backgroundColor: _ink,
          minimumSize: const Size.fromHeight(48),
        ),
        icon: const Icon(Icons.sync),
        label: const Text(AppStrings.runDemoSync),
      ),
      const SizedBox(height: 8),
      Text(AppStrings.liveSyncRules, style: _text(size: 12, color: AppColors.muted)),
    ]);
  }

  void _masterSheet() {
    unawaited(() async {
      final entered = await showDialog<({String kind, String name})>(
        context: context,
        useRootNavigator: true,
        builder: (context) => const _ClassDialog(kinds: ['Category', 'Product', 'Design']),
      );
      if (!mounted || entered == null || entered.name.trim().isEmpty) return;
      final name = entered.name.trim();
      final key = switch (entered.kind) {
        'Product' => 'name',
        'Design' => 'design',
        _ => 'category',
      };
      final options = _session.masters[key];
      if (options == null) return;
      if (!options.contains(name)) options.add(name);
      _session.dirty = true;
      setState(() {
        if (key == 'category') _session.bulkCategory = name;
        if (key == 'name') _session.bulkName = name;
        if (key == 'design') _session.bulkDesign = name;
      });
      _toast(AppStrings.optionAdded);
    }());
  }

  Future<void> _exportSheet() async {
    final stored = Injection.ready ? await Injection.productRepository.storedCount() : 0;
    if (!mounted) return;
    final total = stored > 0 ? stored : _session.items.length;
    _sheet(tx('exportProducts', AppStrings.exportProducts), [
      Text(
        '$total ${tx('productRecords', AppStrings.productRecords)}',
        style: _text(size: 14, color: AppColors.muted),
      ),
      const SizedBox(height: 8),
      Text(tx('csvHint', AppStrings.csvHint), style: _text(size: 12, color: AppColors.muted, height: 1.35)),
      const SizedBox(height: 12),
      FilledButton.icon(
        onPressed: _exporting
            ? null
            : () {
                Navigator.pop(context);
                unawaited(_exportProducts('mail'));
              },
        style: FilledButton.styleFrom(
          backgroundColor: _ink,
          minimumSize: const Size.fromHeight(48),
        ),
        icon: const Icon(Icons.mail_outline),
        label: Text(tx('mailExport', AppStrings.mailExport)),
      ),
      const SizedBox(height: 8),
      OutlinedButton.icon(
        onPressed: _exporting
            ? null
            : () {
                Navigator.pop(context);
                unawaited(_exportProducts('device'));
              },
        style: OutlinedButton.styleFrom(
          foregroundColor: _ink,
          minimumSize: const Size.fromHeight(48),
          side: const BorderSide(color: _ink),
        ),
        icon: const Icon(Icons.download_outlined),
        label: Text(tx('saveOnDevice', AppStrings.saveOnDevice)),
      ),
    ]);
  }

  void _previewSheet(String title, String note, IconData icon) {
    _sheet(title, [
      Icon(icon, size: 36, color: _gold),
      const SizedBox(height: 8),
      Text(note, style: _text(size: 14, color: AppColors.muted, height: 1.35)),
      const SizedBox(height: 8),
      Text(AppStrings.entryPreview, style: _text(size: 12, color: AppColors.muted, height: 1.35)),
      const SizedBox(height: 12),
      FilledButton(
        onPressed: () => Navigator.pop(context),
        style: FilledButton.styleFrom(backgroundColor: _ink),
        child: const Text(AppStrings.done),
      ),
    ]);
  }

  Widget _classDropdowns({
    required String category,
    required String name,
    required String design,
    String purity = '',
    bool showPurity = false,
    required void Function(String key, String value) onChanged,
  }) {
    return Column(
      children: [
        _drop(
          AppStrings.category,
          category,
          _session.masters['category']!,
          true,
          (value) => onChanged('category', value),
          addLabel: AppStrings.addNewCategory,
          onAdd: () => _addMasterValue(
            'category',
            (value) => onChanged('category', value),
            title: AppStrings.addNewCategory,
            field: AppStrings.category,
          ),
        ),
        const SizedBox(height: 8),
        _drop(
          AppStrings.product,
          name,
          _session.masters['name']!,
          category.isNotEmpty,
          (value) => onChanged('name', value),
          addLabel: AppStrings.addNewProduct,
          onAdd: category.isEmpty
              ? null
              : () => _addMasterValue(
                    'name',
                    (value) => onChanged('name', value),
                    title: AppStrings.addNewProduct,
                    field: AppStrings.product,
                  ),
        ),
        const SizedBox(height: 8),
        _drop(
          AppStrings.design,
          design,
          _session.masters['design']!,
          name.isNotEmpty,
          (value) => onChanged('design', value),
          addLabel: AppStrings.addNewDesign,
          onAdd: name.isEmpty
              ? null
              : () => _addMasterValue(
                    'design',
                    (value) => onChanged('design', value),
                    title: AppStrings.addNewDesign,
                    field: AppStrings.design,
                  ),
        ),
        if (showPurity) ...[
          const SizedBox(height: 8),
          _drop(
            AppStrings.purity,
            purity,
            _session.masters['purity']!,
            design.isNotEmpty,
            (value) => onChanged('purity', value),
            addLabel: AppStrings.addNewPurity,
            onAdd: design.isEmpty
                ? null
                : () => _addMasterValue(
                      'purity',
                      (value) => onChanged('purity', value),
                      title: AppStrings.addNewPurity,
                      field: AppStrings.purity,
                    ),
          ),
        ],
      ],
    );
  }

  Future<void> _addMasterValue(
    String key,
    ValueChanged<String> onSelected, {
    required String title,
    required String field,
  }) async {
    final entered = await showDialog<({String kind, String name})>(
      context: context,
      useRootNavigator: true,
      builder: (context) => _ClassDialog(title: title, fieldLabel: field),
    );
    if (!mounted || entered == null || entered.name.trim().isEmpty) return;
    final name = entered.name.trim();
    final options = _session.masters[key];
    if (options == null) return;
    if (!options.contains(name)) options.add(name);
    _session.dirty = true;
    onSelected(name);
    _toast(AppStrings.optionAdded);
  }

  Widget _drop(
    String label,
    String current,
    List<String> options,
    bool enabled,
    ValueChanged<String> onChanged, {
    VoidCallback? onAdd,
    String? addLabel,
  }) {
    final unique = <String>[];
    for (final option in options) {
      if (option.trim().isNotEmpty && !unique.contains(option)) unique.add(option);
    }
    final selected = unique.contains(current) ? current : null;
    final field = InputDecorator(
      decoration: _input.copyWith(
        labelText: label,
        fillColor: enabled ? AppColors.white : const Color(0xFFEEEAE2),
        enabled: enabled,
        suffixIcon: Icon(Icons.expand_more, color: enabled ? _ink : AppColors.muted),
      ),
      child: Text(
        selected ?? '${AppStrings.chooseOption} ${label.toLowerCase()}',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: _text(size: 14, color: selected == null ? AppColors.muted : const Color(0xFF20201F)),
      ),
    );
    if (!enabled) return field;
    return PopupMenuButton<String>(
      tooltip: label,
      padding: EdgeInsets.zero,
      offset: const Offset(0, 4),
      position: PopupMenuPosition.under,
      constraints: const BoxConstraints(minWidth: 220, maxHeight: 280),
      onSelected: (value) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          if (value == '__ADD_NEW__') {
            onAdd?.call();
            return;
          }
          if (value != current) onChanged(value);
        });
      },
      itemBuilder: (context) => [
        if (onAdd != null)
          PopupMenuItem<String>(
            value: '__ADD_NEW__',
            height: 44,
            child: Text(addLabel ?? AppStrings.addClassification, style: _text(size: 13, weight: FontWeight.w700, color: _gold)),
          ),
        for (final option in unique)
          PopupMenuItem<String>(
            value: option,
            height: 44,
            child: Text(
              option,
              style: _text(size: 14, weight: option == selected ? FontWeight.w700 : FontWeight.w500),
            ),
          ),
      ],
      child: field,
    );
  }

  Widget _field(
    String label,
    TextEditingController controller, {
    String? hint,
    bool number = false,
  }) {
    return TextField(
      controller: controller,
      keyboardType: number
          ? const TextInputType.numberWithOptions(decimal: true)
          : TextInputType.text,
      decoration: _input.copyWith(labelText: label, hintText: hint),
    );
  }

  Widget _pair(Widget left, Widget right) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: left),
        const SizedBox(width: 8),
        Expanded(child: right),
      ],
    );
  }

  Widget _section(String title, {bool open = false, required List<Widget> children}) {
    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        initiallyExpanded: open,
        tilePadding: EdgeInsets.zero,
        title: Text(title, style: _text(size: 13, weight: FontWeight.w600, color: const Color(0xFF746345))),
        children: children,
      ),
    );
  }

  Widget _toolButton({
    required IconData icon,
    required String label,
    required VoidCallback onPressed,
  }) {
    return Expanded(
      child: Material(
        color: AppColors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(11),
          side: const BorderSide(color: _actionLine),
        ),
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(11),
          child: SizedBox(
            height: 48,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 17, color: _actionInk),
                const SizedBox(width: 8),
                Text(
                  label,
                  style: _text(size: 12, weight: FontWeight.w600, color: _actionInk),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _filterChip(String label, String value) {
    final active = _session.filter == value;
    return Material(
      color: active ? _chipOn : _chipFill,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(100),
        side: BorderSide(color: active ? _chipOnLine : _chipLine),
      ),
      child: InkWell(
        onTap: () => setState(() => _session.filter = value),
        customBorder: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(100),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Text(
            label,
            style: _text(
              size: 11,
              weight: FontWeight.w600,
              color: active ? _chipOnInk : _chipInk,
            ),
          ),
        ),
      ),
    );
  }

  Widget _choice({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: AppColors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(13),
          side: const BorderSide(color: _panelLine),
        ),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(13),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
            child: Row(
              children: [
                Icon(icon, color: _gold, size: 23),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: _text(size: 14, weight: FontWeight.w600)),
                      const SizedBox(height: 4),
                      Text(subtitle, style: _text(size: 11, color: const Color(0xFF797265), height: 1.4)),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right, size: 17, color: _chevron),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _summaryLine(String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: _line)),
      ),
      child: Row(
        children: [
          Expanded(child: Text(label, style: _text(size: 14, color: AppColors.muted))),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: _text(size: 14, weight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }

  Widget _weightBox(String label, int? milligrams, {required bool suffix}) {
    final shown = ProductDemoSession.grams(milligrams);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _detailFill,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: _text(size: 12, color: AppColors.muted)),
          Text(
            suffix ? '$shown g' : shown,
            style: _text(size: 16, weight: FontWeight.w700),
          ),
        ],
      ),
    );
  }

  Widget _errorText(String message) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _alertFill,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _alertLine),
      ),
      child: Text(message, style: _text(size: 11, color: _alertInk, height: 1.5)),
    );
  }

  Widget _empty(String title, String body) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Column(
        children: [
          Text(title, style: _text(size: 16, weight: FontWeight.w700)),
          const SizedBox(height: 4),
          Text(body, textAlign: TextAlign.center, style: _text(size: 13, color: AppColors.muted)),
        ],
      ),
    );
  }

  Widget _footer({
    required String label,
    required IconData icon,
    required VoidCallback onPressed,
    String? secondary,
    VoidCallback? onSecondary,
    String? note,
  }) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
      decoration: const BoxDecoration(
        color: AppColors.white,
        border: Border(top: BorderSide(color: _line)),
      ),
      child: Column(
        children: [
          if (secondary == null)
            FilledButton.icon(
              onPressed: onPressed,
              icon: Icon(icon, size: 18),
              label: Text(label),
              style: FilledButton.styleFrom(
                backgroundColor: _ink,
                foregroundColor: AppColors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                minimumSize: const Size.fromHeight(52),
                textStyle: _text(size: 14, weight: FontWeight.w600, color: AppColors.white),
              ),
            )
          else
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: onPressed,
                    icon: Icon(icon, size: 18, color: _captureInk),
                    label: Text(label, style: _text(size: 12, weight: FontWeight.w600, color: _captureInk)),
                    style: OutlinedButton.styleFrom(
                      backgroundColor: _captureFill,
                      foregroundColor: _captureInk,
                      side: const BorderSide(color: _captureLine),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(11)),
                      minimumSize: const Size.fromHeight(52),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: FilledButton(
                    onPressed: onSecondary,
                    style: FilledButton.styleFrom(
                      backgroundColor: _ink,
                      foregroundColor: AppColors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      minimumSize: const Size.fromHeight(52),
                    ),
                    child: Text(secondary),
                  ),
                ),
              ],
            ),
          if (note != null) ...[
            const SizedBox(height: 6),
            Text(
              note,
              textAlign: TextAlign.center,
              style: _text(size: 9, color: _note, height: 1.5),
            ),
          ],
        ],
      ),
    );
  }

  Widget _card({
    required Widget child,
    VoidCallback? onTap,
    Color fill = AppColors.white,
    Color border = _line,
    double radius = 13,
  }) {
    return Material(
      color: fill,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(radius),
        side: BorderSide(color: border),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(radius),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 13),
          child: child,
        ),
      ),
    );
  }

  Widget _thumb(String name) {
    return Container(
      width: 44,
      height: 44,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: AppColors.chipSurface,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        name.isEmpty ? '?' : name.characters.first,
        style: _text(size: 16, weight: FontWeight.w700, color: _gold),
      ),
    );
  }

  Widget _tag(String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      decoration: BoxDecoration(
        color: _tagFill,
        borderRadius: BorderRadius.circular(5),
        border: Border.all(color: _tagLine),
      ),
      child: Text(
        label,
        style: _text(
          size: 9,
          weight: FontWeight.w500,
          color: _tagInk,
          letterSpacing: 0.4,
        ),
      ),
    );
  }
}

class _RowEditors {
  _RowEditors(this.piece, this.session, {this.onEdit}) {
    id.text = piece.id;
    rfid.text = piece.rfid;
    id.addListener(_sync);
    rfid.addListener(_sync);
  }

  final BulkPiece piece;
  final ProductDemoSession session;
  final VoidCallback? onEdit;
  final id = TextEditingController();
  final rfid = TextEditingController();

  var _closed = false;

  void _sync() {
    if (_closed) return;
    piece.id = id.text.trim();
    piece.rfid = rfid.text.trim();
    session.dirty = true;
    onEdit?.call();
  }

  void dispose() {
    _closed = true;
    id.dispose();
    rfid.dispose();
  }
}

const _input = InputDecoration(
  filled: true,
  fillColor: AppColors.white,
  contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 14),
  border: OutlineInputBorder(
    borderRadius: BorderRadius.all(Radius.circular(10)),
    borderSide: BorderSide(color: Color(0xFFD5CBBC)),
  ),
  enabledBorder: OutlineInputBorder(
    borderRadius: BorderRadius.all(Radius.circular(10)),
    borderSide: BorderSide(color: Color(0xFFD5CBBC)),
  ),
  focusedBorder: OutlineInputBorder(
    borderRadius: BorderRadius.all(Radius.circular(10)),
    borderSide: BorderSide(color: Color(0xFF967431)),
  ),
  labelStyle: TextStyle(
    fontFamily: 'Inter',
    fontFamilyFallback: <String>[],
    fontSize: 12,
    fontWeight: FontWeight.w600,
    color: Color(0xFF645B4D),
  ),
);

OutlineInputBorder _searchBorder(Color color) {
  return OutlineInputBorder(
    borderRadius: const BorderRadius.all(Radius.circular(12)),
    borderSide: BorderSide(color: color),
  );
}

TextStyle _text({
  required double size,
  FontWeight weight = FontWeight.w400,
  Color color = AppColors.charcoal,
  double? height,
  double? letterSpacing,
}) {
  return TextStyle(
    fontFamily: 'Inter',
    fontFamilyFallback: const <String>[],
    fontSize: size,
    fontWeight: weight,
    color: color,
    height: height,
    letterSpacing: letterSpacing,
    decoration: TextDecoration.none,
  );
}

class _ClassDialog extends StatefulWidget {
  const _ClassDialog({
    this.kinds = const [],
    this.title = AppStrings.addNewCategory,
    this.fieldLabel = AppStrings.category,
  });

  final List<String> kinds;
  final String title;
  final String fieldLabel;

  @override
  State<_ClassDialog> createState() => _ClassDialogState();
}

class _ClassDialogState extends State<_ClassDialog> {
  final _name = TextEditingController();
  late String _kind = widget.kinds.isEmpty ? '' : widget.kinds.first;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  String _titleFor(String kind) {
    return switch (kind) {
      'Product' => AppStrings.addNewProduct,
      'Design' => AppStrings.addNewDesign,
      'Purity' => AppStrings.addNewPurity,
      _ => AppStrings.addNewCategory,
    };
  }

  String _fieldFor(String kind) {
    return switch (kind) {
      'Product' => AppStrings.product,
      'Design' => AppStrings.design,
      'Purity' => AppStrings.purity,
      _ => AppStrings.category,
    };
  }

  void _submit() {
    final name = _name.text.trim();
    if (name.isEmpty) {
      setState(() => _error = widget.kinds.isEmpty ? 'Enter a name.' : AppStrings.chooseClass);
      return;
    }
    Navigator.of(context).pop((kind: _kind, name: name));
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.kinds.isEmpty ? widget.title : _titleFor(_kind);
    final field = widget.kinds.isEmpty ? widget.fieldLabel : _fieldFor(_kind);
    return AlertDialog(
      backgroundColor: _ProductsPageState._surface,
      title: Text(title, style: _text(size: 18, weight: FontWeight.w700)),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (widget.kinds.isNotEmpty)
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final option in widget.kinds)
                    ChoiceChip(
                      label: Text(option, style: _text(size: 12, weight: FontWeight.w600)),
                      selected: _kind == option,
                      selectedColor: const Color(0xFFF8F2E6),
                      onSelected: (_) => setState(() => _kind = option),
                    ),
                ],
              ),
            if (widget.kinds.isNotEmpty) const SizedBox(height: 12),
            TextField(
              controller: _name,
              autofocus: true,
              textCapitalization: TextCapitalization.words,
              decoration: _input.copyWith(labelText: field),
              onSubmitted: (_) => _submit(),
            ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(_error!, style: _text(size: 12, color: const Color(0xFF964A32))),
            ],
            const SizedBox(height: 8),
            Text(AppStrings.masterDemoHint, style: _text(size: 12, color: AppColors.muted)),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(AppStrings.cancel, style: _text(size: 14, weight: FontWeight.w600)),
        ),
        FilledButton(
          onPressed: _submit,
          style: FilledButton.styleFrom(backgroundColor: _ProductsPageState._ink),
          child: Text(title),
        ),
      ],
    );
  }
}
