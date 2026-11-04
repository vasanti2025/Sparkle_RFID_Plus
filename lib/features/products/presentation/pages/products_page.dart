import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import '../../../../core/constants/app_strings.dart';
import '../../../../core/theme/app_colors.dart';
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
  final _fields = <String, TextEditingController>{};
  final _rows = <_RowEditors>[];
  var _page = _ProductPage.list;
  var _capturing = false;
  var _suspend = false;
  String? _error;
  Timer? _timer;

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
    _query.addListener(() {
      if (_suspend || !mounted) return;
      _session.query = _query.text;
      if (_page == _ProductPage.list) setState(() {});
    });
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

  @override
  void dispose() {
    _suspend = true;
    _timer?.cancel();
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
      ..addAll(_session.bulkRows.map((piece) => _RowEditors(piece, _session)));
  }

  void _goList() {
    _stopCapture();
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
    _session.discardDraft();
    _reloadRows();
    _goList();
  }

  void _readDemoTag() {
    final now = DateTime.now().millisecondsSinceEpoch;
    final epc = 'E280${now.toRadixString(16).toUpperCase()}';
    final stamp = now.toString();
    final rfid = 'DEMO-${stamp.substring(stamp.length - 6)}';
    _draft.epc = epc;
    _draft.rfid = rfid;
    _suspend = true;
    _fields['epc']!.text = epc;
    _fields['rfid']!.text = rfid;
    _suspend = false;
    _session.dirty = true;
    setState(() {});
    _toast(AppStrings.demoIdentityRead);
  }

  void _toggleCapture() {
    if (_capturing) {
      setState(_stopCapture);
      return;
    }
    if (_session.bulkCategory.isEmpty ||
        _session.bulkName.isEmpty ||
        _session.bulkDesign.isEmpty) {
      _classifySheet();
      return;
    }
    _stopCapture();
    setState(() => _capturing = true);
    _timer = Timer.periodic(const Duration(milliseconds: 1300), (_) {
      if (!mounted) return;
      if (_session.bulkRows.length >= 5) {
        setState(_stopCapture);
        return;
      }
      final stamp = DateTime.now().millisecondsSinceEpoch.toRadixString(16).toUpperCase();
      final piece = BulkPiece(
        epc: 'E280$stamp',
        rfid: 'DEMO-${stamp.substring(stamp.length - 5)}',
      );
      setState(() => _addPiece(piece));
    });
  }

  bool _addPiece(BulkPiece piece) {
    if (piece.epc.isNotEmpty &&
        _session.bulkRows.any((row) => row.epc == piece.epc)) {
      return false;
    }
    _session.bulkRows.add(piece);
    _rows.add(_RowEditors(piece, _session));
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
    final errors = _session.validateBulk();
    if (errors.isNotEmpty) {
      setState(() => _error = errors.join('\n'));
      return;
    }
    setState(() => _error = null);
    _reviewSheet(bulk: true);
  }

  void _saveSingle() {
    final record = _session.saveSingle();
    if (record == null) return;
    _suspend = true;
    for (final controller in _fields.values) {
      controller.clear();
    }
    _suspend = false;
    _goList();
    _toast(AppStrings.productSaved);
  }

  void _saveBulk() {
    final records = _session.saveBulk();
    if (records == null) return;
    _reloadRows();
    _goList();
    _toast('${records.length} ${AppStrings.productsSaved}');
  }

  void _loadSample() {
    _session.mode = 'bulk';
    _session.bulkCategory = 'GOLD';
    _session.bulkName = 'Necklace';
    _session.bulkDesign = 'Abstract';
    _session.bulkRows
      ..clear()
      ..add(BulkPiece(id: 'DEMO-IMPORT-01', rfid: 'DEMO-I001'))
      ..add(BulkPiece(id: 'DEMO-IMPORT-02', rfid: 'DEMO-I002'))
      ..add(BulkPiece(id: 'GNK53'));
    _session.dirty = true;
    _reloadRows();
    setState(() {
      _page = _ProductPage.bulk;
      _error = AppStrings.sampleImportError;
    });
  }

  Future<void> _downloadCsv() async {
    final rows = <List<String>>[
      [
        AppStrings.itemCode,
        AppStrings.product,
        AppStrings.rfidCode,
        AppStrings.epc,
        'Gross g',
        'Net g',
      ],
      for (final item in _session.visible)
        [
          item.id,
          item.name,
          item.rfid,
          item.epc,
          item.grossMg == null ? '' : (item.grossMg! / 1000).toString(),
          item.netMg == null ? '' : (item.netMg! / 1000).toString(),
        ],
    ];
    final csv = rows.map((row) => row.map(_csv).join(',')).join('\r\n');
    try {
      final directory = await getApplicationDocumentsDirectory();
      final file = File('${directory.path}/SPARKLE_Demo_Products.csv');
      await file.writeAsString('\uFEFF$csv');
      if (mounted) _toast(AppStrings.demoCsvSaved);
    } catch (_) {
      if (mounted) _toast(AppStrings.cacheError);
    }
  }

  String _csv(String value) {
    var safe = value;
    if (RegExp(r'^[\s]*[=+\-@]').hasMatch(safe)) safe = "'$safe";
    return '"${safe.replaceAll('"', '""')}"';
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

  Widget _list() {
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
                    label: AppStrings.dataTools,
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

  Widget _productCard(CataloguePiece item) {
    final gross = item.grossMg == null
        ? '—'
        : '${ProductDemoSession.grams(item.grossMg)} g';
    final saved = item.origin == 'manual';
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
                  const SizedBox(height: 2),
                  Text(
                    saved ? AppStrings.savedOnDeviceDemo : AppStrings.referenceItemDemo,
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
                      onPressed: _readDemoTag,
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
                      _capturing ? AppStrings.readingDemoTags : AppStrings.bulkProductEntry,
                      style: _text(size: 10, weight: FontWeight.w600, color: _demoInk),
                    ),
                  ),
                  _tag(AppStrings.demoTag),
                ],
              ),
              const SizedBox(height: 12),
              _card(
                onTap: _classifySheet,
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
                    const Icon(Icons.chevron_right, color: _chevron),
                  ],
                ),
              ),
              if (_capturing) ...[
                const SizedBox(height: 10),
                Text(AppStrings.readingOnce, style: _text(size: 13, weight: FontWeight.w600)),
              ],
              const SizedBox(height: 14),
              Row(
                children: [
                  Text(
                    AppStrings.piecesToAdd,
                    style: _text(size: 12, weight: FontWeight.w700, letterSpacing: 0.6),
                  ),
                  const Spacer(),
                  Text(
                    '${_rows.length} ${AppStrings.rowsWord}',
                    style: _text(size: 12, color: AppColors.muted),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              if (_rows.isEmpty)
                _empty(AppStrings.readyForBatch, AppStrings.scanOrAddRows)
              else
                for (var i = 0; i < _rows.length; i++) _bulkCard(i),
              OutlinedButton.icon(
                onPressed: () => setState(() => _addPiece(BulkPiece())),
                icon: const Icon(Icons.add),
                label: const Text(AppStrings.addRowManually),
              ),
              if (_error != null) ...[
                const SizedBox(height: 8),
                _errorText(_error!),
              ],
            ],
          ),
        ),
        _footer(
          label: _capturing ? AppStrings.pause : AppStrings.scan,
          icon: _capturing ? Icons.pause : Icons.document_scanner_outlined,
          onPressed: _toggleCapture,
          secondary: AppStrings.reviewBatch,
          onSecondary: _rows.isEmpty ? null : _reviewBulk,
          note: AppStrings.duplicatesBlocked,
        ),
      ],
    );
  }

  Widget _bulkCard(int index) {
    final row = _rows[index];
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: _card(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Text(
                  '${AppStrings.piece} ${index + 1}',
                  style: _text(size: 14, weight: FontWeight.w700),
                ),
                const Spacer(),
                IconButton(
                  tooltip: AppStrings.removePiece,
                  onPressed: () {
                    row.dispose();
                    setState(() {
                      _rows.removeAt(index);
                      _session.bulkRows.removeAt(index);
                      _session.dirty = true;
                    });
                  },
                  icon: const Icon(Icons.close, size: 18),
                ),
              ],
            ),
            _field(AppStrings.itemCodeRequired, row.id),
            const SizedBox(height: 8),
            _field(AppStrings.rfidCode, row.rfid),
            if (row.piece.epc.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                '${AppStrings.epc} ${row.piece.epc}',
                style: _text(size: 12, color: AppColors.muted),
              ),
            ],
          ],
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
                    onTap: () => _syncMethodSheet(option),
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
        return Padding(
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
          _importSheet();
        },
      ),
    ]);
  }

  void _dataTools() {
    _sheet(AppStrings.productDataTools, [
      _choice(
        icon: Icons.sync,
        title: AppStrings.syncCentre,
        subtitle: AppStrings.dataSyncSubtitle,
        onTap: () {
          Navigator.pop(context);
          _pauseSync();
          setState(() => _page = _ProductPage.sync);
        },
      ),
      _choice(
        icon: Icons.table_chart_outlined,
        title: AppStrings.importExcel,
        subtitle: AppStrings.importExcelHint,
        onTap: () {
          Navigator.pop(context);
          _importSheet();
        },
      ),
      _choice(
        icon: Icons.download_outlined,
        title: AppStrings.exportExcel,
        subtitle: AppStrings.csvHint,
        onTap: () {
          Navigator.pop(context);
          _exportSheet();
        },
      ),
      _choice(
        icon: Icons.desktop_windows_outlined,
        title: AppStrings.scanToDesktop,
        subtitle: AppStrings.desktopNote,
        onTap: () {
          Navigator.pop(context);
          _previewSheet(
            AppStrings.scanToDesktop,
            AppStrings.desktopNote,
            Icons.desktop_windows_outlined,
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
      _choice(
        icon: Icons.document_scanner_outlined,
        title: AppStrings.gscan,
        subtitle: AppStrings.gscanNote,
        onTap: () {
          Navigator.pop(context);
          _previewSheet(AppStrings.gscan, AppStrings.gscanNote, Icons.document_scanner_outlined);
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
      const SizedBox(height: 8),
      Text(
        saved ? AppStrings.savedThisSession : AppStrings.referenceUnspecified,
        style: _text(size: 13, color: AppColors.muted, height: 1.35),
      ),
    ]);
  }

  void _reviewSheet({required bool bulk}) {
    final rows = bulk
        ? _session.bulkRows
            .map((row) => '${row.id} · ${row.rfid.isEmpty ? AppStrings.noRfidCode : row.rfid}')
            .toList()
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
        onPressed: () {
          Navigator.pop(context);
          if (bulk) {
            _saveBulk();
          } else {
            _saveSingle();
          }
        },
        style: FilledButton.styleFrom(
          backgroundColor: _ink,
          minimumSize: const Size.fromHeight(48),
        ),
        icon: const Icon(Icons.save_outlined),
        label: Text(bulk ? AppStrings.saveDemoBatch : AppStrings.saveDemoProduct),
      ),
      const SizedBox(height: 8),
      Text(AppStrings.savedSessionOnly, style: _text(size: 12, color: AppColors.muted)),
    ]);
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

  void _classifySheet() {
    var category = _session.bulkCategory;
    var name = _session.bulkName;
    var design = _session.bulkDesign;
    String? error;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: _surface,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setSheet) {
            return Padding(
              padding: EdgeInsets.fromLTRB(20, 16, 20, 20 + MediaQuery.viewInsetsOf(context).bottom),
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(AppStrings.sharedDetails, style: _text(size: 18, weight: FontWeight.w700)),
                    const SizedBox(height: 8),
                    _classDropdowns(
                      category: category,
                      name: name,
                      design: design,
                      onChanged: (key, value) => setSheet(() {
                        if (key == 'category') category = value;
                        if (key == 'name') name = value;
                        if (key == 'design') design = value;
                      }),
                    ),
                    TextButton.icon(
                      onPressed: () {
                        Navigator.pop(context);
                        _masterSheet();
                      },
                      icon: const Icon(Icons.add, size: 18),
                      label: const Text(AppStrings.addClassification),
                    ),
                    if (error != null) _errorText(error!),
                    FilledButton(
                      onPressed: () {
                        if (category.isEmpty || name.isEmpty || design.isEmpty) {
                          setSheet(() => error = AppStrings.chooseShared);
                          return;
                        }
                        _session.bulkCategory = category;
                        _session.bulkName = name;
                        _session.bulkDesign = design;
                        _session.dirty = true;
                        Navigator.pop(context);
                        setState(() {});
                      },
                      style: FilledButton.styleFrom(
                        backgroundColor: _ink,
                        minimumSize: const Size.fromHeight(48),
                      ),
                      child: const Text(AppStrings.applyToBatch),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  void _masterSheet() {
    var kind = 'Category';
    final value = TextEditingController();
    String? error;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: _surface,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setSheet) {
            return Padding(
              padding: EdgeInsets.fromLTRB(20, 16, 20, 20 + MediaQuery.viewInsetsOf(context).bottom),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(AppStrings.addClassification, style: _text(size: 18, weight: FontWeight.w700)),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String>(
                    initialValue: kind,
                    decoration: _input.copyWith(labelText: AppStrings.fieldLabel),
                    items: [
                      for (final option in ['Category', 'Product', 'Design', 'Purity'])
                        DropdownMenuItem(value: option, child: Text(option)),
                    ],
                    onChanged: (next) => setSheet(() => kind = next ?? kind),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: value,
                    decoration: _input.copyWith(labelText: AppStrings.newValue),
                  ),
                  if (error != null) _errorText(error!),
                  const SizedBox(height: 8),
                  FilledButton.icon(
                    onPressed: () {
                      final entered = value.text.trim();
                      if (entered.isEmpty) {
                        setSheet(() => error = AppStrings.chooseClass);
                        return;
                      }
                      final key = switch (kind) {
                        'Product' => 'name',
                        'Design' => 'design',
                        'Purity' => 'purity',
                        _ => 'category',
                      };
                      final options = _session.masters[key]!;
                      if (!options.contains(entered)) options.add(entered);
                      _session.dirty = true;
                      Navigator.pop(context);
                      setState(() {});
                      _toast(AppStrings.optionAdded);
                    },
                    style: FilledButton.styleFrom(backgroundColor: _ink),
                    icon: const Icon(Icons.add),
                    label: const Text(AppStrings.addOption),
                  ),
                  const SizedBox(height: 8),
                  Text(AppStrings.masterDemoHint, style: _text(size: 12, color: AppColors.muted)),
                ],
              ),
            );
          },
        );
      },
    ).whenComplete(value.dispose);
  }

  void _importSheet() {
    if (_session.dirty) {
      _toast(AppStrings.saveOrDiscardImport);
      return;
    }
    _sheet(AppStrings.importExcel, [
      Text(AppStrings.importExcelBody, style: _text(size: 14, color: AppColors.muted)),
      const SizedBox(height: 8),
      Text(AppStrings.noFileSelected, style: _text(size: 13)),
      const SizedBox(height: 8),
      FilledButton(
        onPressed: () {
          Navigator.pop(context);
          _loadSample();
        },
        style: FilledButton.styleFrom(
          backgroundColor: _ink,
          minimumSize: const Size.fromHeight(48),
        ),
        child: const Text(AppStrings.exploreSampleImport),
      ),
      const SizedBox(height: 8),
      Text(AppStrings.importNotConnected, style: _text(size: 12, color: AppColors.muted, height: 1.35)),
    ]);
  }

  void _exportSheet() {
    _sheet(AppStrings.exportProducts, [
      Text(
        '${AppStrings.exportProducts} (${_session.visible.length}).',
        style: _text(size: 14, color: AppColors.muted),
      ),
      _summaryLine(AppStrings.productionFormat, AppStrings.excel),
      const SizedBox(height: 12),
      FilledButton.icon(
        onPressed: () {
          Navigator.pop(context);
          _downloadCsv();
        },
        style: FilledButton.styleFrom(
          backgroundColor: _ink,
          minimumSize: const Size.fromHeight(48),
        ),
        icon: const Icon(Icons.download_outlined),
        label: const Text(AppStrings.downloadDemoCsv),
      ),
      const SizedBox(height: 8),
      Text(AppStrings.csvHint, style: _text(size: 12, color: AppColors.muted, height: 1.35)),
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
        _drop(AppStrings.category, category, _session.masters['category']!, true, (value) {
          onChanged('category', value);
        }),
        const SizedBox(height: 8),
        _drop(AppStrings.product, name, _session.masters['name']!, category.isNotEmpty, (value) {
          onChanged('name', value);
        }),
        const SizedBox(height: 8),
        _drop(AppStrings.design, design, _session.masters['design']!, name.isNotEmpty, (value) {
          onChanged('design', value);
        }),
        if (showPurity) ...[
          const SizedBox(height: 8),
          _drop(AppStrings.purity, purity, _session.masters['purity']!, design.isNotEmpty, (value) {
            onChanged('purity', value);
          }),
        ],
      ],
    );
  }

  Widget _drop(
    String label,
    String current,
    List<String> options,
    bool enabled,
    ValueChanged<String> onChanged,
  ) {
    final selected = options.contains(current) ? current : null;
    return DropdownButtonFormField<String>(
      key: ValueKey('$label-$selected-$enabled-${options.length}'),
      initialValue: selected,
      decoration: _input.copyWith(
        labelText: label,
        fillColor: enabled ? AppColors.white : const Color(0xFFEEEAE2),
      ),
      hint: Text('${AppStrings.chooseOption} ${label.toLowerCase()}'),
      items: [
        for (final option in options)
          DropdownMenuItem(value: option, child: Text(option)),
      ],
      onChanged: enabled ? (value) => onChanged(value ?? '') : null,
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
  _RowEditors(this.piece, this.session) {
    id.text = piece.id;
    rfid.text = piece.rfid;
    id.addListener(_sync);
    rfid.addListener(_sync);
  }

  final BulkPiece piece;
  final ProductDemoSession session;
  final id = TextEditingController();
  final rfid = TextEditingController();

  var _closed = false;

  void _sync() {
    if (_closed) return;
    piece.id = id.text.trim();
    piece.rfid = rfid.text.trim();
    session.dirty = true;
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
