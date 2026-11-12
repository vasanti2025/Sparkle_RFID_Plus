import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:rfid_flutter_android/rfid_flutter_android.dart';

import '../../../../core/constants/app_strings.dart';
import '../../../../core/rfid/rfid_service.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../data/inventory_stock.dart';
import '../../domain/inventory_catalog.dart';

enum _InvPage { scopes, setup, list, search, locate, details, save, saved }

class InventoryPage extends StatefulWidget {
  const InventoryPage({super.key});

  @override
  State<InventoryPage> createState() => _InventoryPageState();
}

class _InventoryPageState extends State<InventoryPage> {
  static const _surface = Color(0xFFFAF9F7);
  static const _line = Color(0xFFE4D7C4);
  static const _countFill = Color(0xFF262622);
  static const _track = Color(0xFFDCC180);

  _InvPage _page = _InvPage.scopes;
  String _mode = 'Display';
  String _scope = 'All labelled stock';
  var _loadingStock = true;
  var _uiQueued = false;
  StreamSubscription<List<RfidTagInfo>>? _tags;
  final Set<String> _categories = {};
  final Set<String> _products = {};
  final Set<String> _designs = {};
  final Set<String> _reads = {};
  final List<InventoryPiece> _unlabelled = [];
  String _status = 'ready';
  String _listTab = 'unmatched';
  String _query = '';
  String _searchQuery = '';
  int _limit = 20;
  bool _saved = false;
  String _note = '';
  bool _acknowledged = false;
  String? _ackError;
  String? _detailId;
  String? _searchId;
  _InvPage _detailBack = _InvPage.list;
  _InvPage _locateBack = _InvPage.list;
  int _signal = 0;
  bool _searching = false;
  bool _multiSearching = false;
  final Map<String, int> _signals = {};
  Timer? _timer;
  final _noteController = TextEditingController();
  final _listQuery = TextEditingController();
  final _findQuery = TextEditingController();

  List<String> get _categoryOptions =>
      InventoryStock.instance.ready ? InventoryStock.instance.categories : InventoryCatalog.categories;

  List<String> get _productOptions =>
      InventoryStock.instance.ready ? InventoryStock.instance.products : InventoryCatalog.products;

  List<String> get _designOptions =>
      InventoryStock.instance.ready ? InventoryStock.instance.designs : InventoryCatalog.designs;

  @override
  void initState() {
    super.initState();
    unawaited(_loadStock());
  }

  @override
  void dispose() {
    _timer?.cancel();
    _tags?.cancel();
    unawaited(RfidService.instance.stopIfRunning());
    _noteController.dispose();
    _listQuery.dispose();
    _findQuery.dispose();
    super.dispose();
  }

  List<InventoryPiece> get _expected => InventoryStock.instance.ready
      ? InventoryStock.instance.select(
          mode: _mode,
          scope: _scope,
          categoriesSelected: _categories,
          productsSelected: _products,
          designsSelected: _designs,
        )
      : InventoryCatalog.selected(
          categoriesSelected: _categories,
          productsSelected: _products,
          designsSelected: _designs,
        );

  List<InventoryPiece> get _matched =>
      _expected.where((item) => _reads.contains(item.id)).toList();

  List<InventoryPiece> get _unmatched =>
      _expected.where((item) => !_reads.contains(item.id)).toList();

  int get _gross => _expected.fold(0, (sum, item) => sum + item.milligrams);

  int get _matchedGross =>
      _matched.fold(0, (sum, item) => sum + item.milligrams);

  String get _modeTitle => _mode == 'Exhibition'
      ? AppStrings.exhibition
      : 'Scan ${_mode.toLowerCase()}';

  void _pauseScan() {
    _timer?.cancel();
    _timer = null;
    if (_status == 'scanning' || _status == 'arming') {
      _status = 'paused';
      unawaited(RfidService.instance.stopInventory());
    }
    _searching = false;
    _multiSearching = false;
  }

  Future<void> _loadStock() async {
    await InventoryStock.instance.load();
    if (!mounted) return;
    setState(() {
      _loadingStock = false;
      _categories
        ..clear()
        ..addAll(_categoryOptions);
      _products
        ..clear()
        ..addAll(_productOptions);
      _designs
        ..clear()
        ..addAll(_designOptions);
    });
  }

  void _open(_InvPage page) {
    _pauseScan();
    setState(() => _page = page);
  }

  Future<void> _chooseMode(String mode) async {
    if (_loadingStock) {
      _toast(AppStrings.pleaseWaitItemsLoading);
      return;
    }
    if (!InventoryStock.instance.ready || InventoryStock.instance.pieces.isEmpty) {
      _toast(AppStrings.syncProductsFirst);
      return;
    }
    final places = InventoryStock.instance.places(mode);
    if (mode != 'Display' && places.isEmpty) {
      _toast(AppStrings.noScopeValues);
      return;
    }
    setState(() {
      _mode = mode;
      _scope = mode == 'Display' ? 'All labelled stock' : places.first;
      _page = _InvPage.setup;
      _saved = false;
      _categories
        ..clear()
        ..addAll(_categoryOptions);
      _products
        ..clear()
        ..addAll(_productOptions);
      _designs
        ..clear()
        ..addAll(_designOptions);
    });
  }

  Future<void> _ensureReader() async {
    _tags ??= RfidService.instance.tagStream.listen(_onTags);
  }

  void _queueUi() {
    if (_uiQueued) return;
    _uiQueued = true;
    Future<void>.delayed(const Duration(milliseconds: 80), () {
      _uiQueued = false;
      if (mounted) setState(() {});
    });
  }

  void _onTags(List<RfidTagInfo> batch) {
    if (_status != 'scanning' && !_searching && !_multiSearching) return;
    final expectedIds = _expected.map((item) => item.id).toSet();
    var stillOpen = expectedIds.difference(_reads).length;
    var changed = false;
    for (final tag in batch) {
      final id = InventoryStock.instance.match(tag.epc.isNotEmpty ? tag.epc : tag.tid);
      final bars = signalBars(tag.rssi);
      if (id != null && expectedIds.contains(id)) {
        if (_status == 'scanning' && !_searching && _reads.add(id)) {
          changed = true;
          stillOpen -= 1;
          if (stillOpen <= 0) {
            _status = 'paused';
            unawaited(RfidService.instance.stopInventory());
            _toast(AppStrings.allItemsMatchedScanStopped);
          }
        }
        if ((_signals[id] ?? 0) != bars) {
          _signals[id] = bars;
          changed = true;
        }
        if (_searchId == id && _signal != bars) {
          _signal = bars;
          changed = true;
        }
        continue;
      }
      if (id != null) continue;
      final epc = tag.epc.trim();
      if (epc.isEmpty || _unlabelled.any((item) => item.epc == epc)) continue;
      _unlabelled.add(
        InventoryPiece(
          id: epc,
          category: null,
          product: 'Unlabelled tag',
          design: null,
          milligrams: 0,
          epc: epc,
          rfid: epc,
          weightKnown: false,
        ),
      );
      changed = true;
    }
    if (changed) {
      _saved = false;
      _queueUi();
    }
  }

  Future<void> _startScan() async {
    if (_status == 'arming') return;
    if (_loadingStock) {
      _toast(AppStrings.pleaseWaitItemsLoading);
      return;
    }
    if (_expected.isEmpty) {
      _toast(AppStrings.noItemsInCurrentScope);
      return;
    }
    if (!_searching && _unmatched.isEmpty) {
      _toast(AppStrings.allItemsMatchedScanStopped);
      return;
    }
    setState(() => _status = 'arming');
    await _ensureReader();
    final blocked = await RfidService.instance.init();
    if (!mounted) return;
    if (blocked != null) {
      setState(() {
        _status = 'paused';
        _searching = false;
        _multiSearching = false;
      });
      _toast(blocked);
      return;
    }
    await RfidService.instance.stopIfRunning();
    await RfidService.instance.setInventoryMode(kEpcInventoryMode);
    final error = await RfidService.instance.startInventory();
    if (!mounted) return;
    if (error != null) {
      setState(() {
        _status = 'paused';
        _searching = false;
        _multiSearching = false;
      });
      _toast(error);
      return;
    }
    setState(() => _status = 'scanning');
  }

  void _reset() {
    _timer?.cancel();
    setState(() {
      _reads.clear();
      _unlabelled.clear();
      _status = 'ready';
      _saved = false;
      _note = '';
      _noteController.clear();
      _acknowledged = false;
      _ackError = null;
      _signal = 0;
      _signals.clear();
      _searchId = null;
      _detailId = null;
      _page = _InvPage.setup;
    });
  }

  void _confirmSave() {
    if (!_acknowledged) {
      setState(() => _ackError = AppStrings.ackRequired);
      return;
    }
    setState(() {
      _note = _noteController.text.trim();
      _saved = true;
      _status = 'paused';
      _page = _InvPage.saved;
      _ackError = null;
    });
  }

  void _toast(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _askReset() async {
    final clear = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text(AppStrings.resetCheckTitle),
        content: const Text(AppStrings.resetCheckBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text(AppStrings.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text(AppStrings.reset),
          ),
        ],
      ),
    );
    if (clear ?? false) _reset();
  }

  void _copyEpc(String value) {
    Clipboard.setData(ClipboardData(text: value));
    _toast(AppStrings.copied);
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Color(0x00000000),
        statusBarIconBrightness: Brightness.dark,
        statusBarBrightness: Brightness.light,
        systemNavigationBarColor: _surface,
        systemNavigationBarIconBrightness: Brightness.dark,
      ),
      child: Scaffold(
        backgroundColor: _surface,
        body: SafeArea(
          child: Column(
            children: [
              _header(),
              Expanded(
                child: switch (_page) {
                  _InvPage.scopes => _scopes(),
                  _InvPage.setup => _setup(),
                  _InvPage.list => _list(),
                  _InvPage.search => _searchMany(),
                  _InvPage.locate => _locate(),
                  _InvPage.details => _details(),
                  _InvPage.save => _save(),
                  _InvPage.saved => _savedView(),
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _header() {
    final (title, subtitle, back) = switch (_page) {
      _InvPage.scopes => (
        AppStrings.inventory,
        AppStrings.inventoryScope,
        null as VoidCallback?,
      ),
      _InvPage.setup => (_modeTitle, '${AppStrings.inventorySlash} / $_mode', () => _open(_InvPage.scopes)),
      _InvPage.list => (AppStrings.results, _scope, () => _open(_InvPage.setup)),
      _InvPage.search => (
        AppStrings.findUnmatched,
        _scope,
        () => _open(_InvPage.list),
      ),
      _InvPage.locate => (
        AppStrings.findJewelleryTitle,
        AppStrings.focusSelected,
        () => _open(_locateBack),
      ),
      _InvPage.details => (
        AppStrings.itemDetails,
        _scope,
        () => _open(_detailBack),
      ),
      _InvPage.save => (
        AppStrings.saveScanReport,
        _modeTitle,
        () => _open(_InvPage.setup),
      ),
      _InvPage.saved => (
        AppStrings.reportSaved,
        AppStrings.demonstrationResult,
        () => _open(_InvPage.setup),
      ),
    };
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 4, 4, 0),
      child: Row(
        children: [
          IconButton(
            onPressed: () {
              if (back == null) {
                Navigator.of(context).maybePop();
              } else {
                back();
              }
            },
            icon: const Icon(Icons.arrow_back, size: 22),
            color: AppColors.charcoal,
            tooltip: AppStrings.home,
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: _text(size: 20, weight: FontWeight.w700)),
                Text(
                  subtitle,
                  style: _text(size: 12, color: AppColors.muted),
                ),
              ],
            ),
          ),
          if (_page != _InvPage.scopes)
            IconButton(
              onPressed: _matched.isEmpty ? null : _askReset,
              icon: const Icon(Icons.more_horiz, size: 22),
              color: AppColors.charcoal,
            ),
        ],
      ),
    );
  }

  Widget _scopes() {
    const modes = [
      ('Display', Icons.grid_view_rounded, AppStrings.scanDisplay, AppStrings.scanDisplayHint),
      ('Counter', Icons.point_of_sale_outlined, AppStrings.scanCounter, AppStrings.scanCounterHint),
      ('Box', Icons.inventory_2_outlined, AppStrings.scanBox, AppStrings.scanBoxHint),
      ('Branch', Icons.storefront_outlined, AppStrings.scanBranch, AppStrings.scanBranchHint),
      ('Exhibition', Icons.diamond_outlined, AppStrings.exhibition, AppStrings.exhibitionHint),
    ];
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 24),
      children: [
        Text(
          AppStrings.clearerStockCheck,
          style: _text(
            size: 12,
            weight: FontWeight.w700,
            color: AppColors.goldText,
            letterSpacing: 0.8,
          ),
        ),
        const SizedBox(height: 10),
        Text(
          AppStrings.whereAreYouCounting,
          style: _text(size: 34, weight: FontWeight.w700, height: 1.05),
        ),
        const SizedBox(height: 12),
        Text(
          AppStrings.chooseAScope,
          style: _text(size: 16, color: AppColors.muted, height: 1.35),
        ),
        if (_loadingStock) ...[
          const SizedBox(height: 16),
          const LinearProgressIndicator(color: AppColors.goldText, backgroundColor: Color(0xFFE8E0D2)),
          const SizedBox(height: 8),
          Text(AppStrings.startingReader, style: _text(size: 13, color: AppColors.muted)),
        ],
        if (_reads.isNotEmpty) ...[
          const SizedBox(height: 16),
          _card(
            onTap: () => _open(_InvPage.setup),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${AppStrings.continueCheck} · ${_mode.toLowerCase()}',
                        style: _text(size: 15, weight: FontWeight.w700),
                      ),
                      Text(
                        '${_matched.length} ${AppStrings.matchedOf} · ${_unmatched.length} ${AppStrings.notYetRead}',
                        style: _text(size: 13, color: AppColors.muted),
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right, color: Color(0xFFC4B08A)),
              ],
            ),
          ),
        ],
        const SizedBox(height: 18),
        for (final mode in modes) ...[
          _card(
            onTap: () => _chooseMode(mode.$1),
            child: Row(
              children: [
                _symbol(mode.$2),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        mode.$3,
                        style: _text(size: 16, weight: FontWeight.w700),
                      ),
                      Text(
                        mode.$4,
                        style: _text(size: 14, color: AppColors.muted),
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right, color: Color(0xFFC4B08A)),
              ],
            ),
          ),
          const SizedBox(height: 12),
        ],
        const SizedBox(height: 4),
        Row(
          children: [
            const Icon(Icons.check_circle_outline, size: 16, color: AppColors.muted),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                AppStrings.oneWorkflow,
                style: _text(size: 14, color: AppColors.muted),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _setup() {
    final expected = _expected;
    final scanning = _status == 'scanning' || _status == 'arming';
    final hasReads = _matched.isNotEmpty;
    final label = scanning
        ? AppStrings.pauseScan
        : hasReads
        ? AppStrings.resumeScan
        : AppStrings.startScan;
    final stateText = _status == 'arming'
        ? AppStrings.startingReader
        : scanning
        ? AppStrings.scanningNow
        : _saved
        ? AppStrings.reportSaved
        : hasReads
        ? AppStrings.scanPausedReview
        : AppStrings.readyToScan;
    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
            children: [
              Row(
                children: [
                  _statusPill(stateText, live: scanning, review: hasReads),
                  const Spacer(),
                  if (_status == 'arming')
                    const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.goldText),
                    )
                  else
                    _tag(InventoryStock.instance.ready ? AppStrings.localStock : AppStrings.demoData),
                ],
              ),
              const SizedBox(height: 14),
              _card(
                onTap: _pickScope,
                child: Row(
                  children: [
                    _symbol(_modeIcon),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${AppStrings.selectedScope} ${_mode.toLowerCase()}',
                            style: _text(size: 12, color: AppColors.muted),
                          ),
                          Text(
                            _scope,
                            style: _text(size: 16, weight: FontWeight.w700),
                          ),
                        ],
                      ),
                    ),
                    const Icon(Icons.expand_more, color: AppColors.muted),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  _filterChip(AppStrings.category, _filterLabel(_categories, _categoryOptions), () => _openFilters('category')),
                  const SizedBox(width: 8),
                  _filterChip(AppStrings.product, _filterLabel(_products, _productOptions), () => _openFilters('product')),
                  const SizedBox(width: 8),
                  _filterChip(AppStrings.design, _filterLabel(_designs, _designOptions), () => _openFilters('design')),
                ],
              ),
              const SizedBox(height: 16),
              if (expected.isEmpty)
                _empty(
                  Icons.tune,
                  AppStrings.noStockInSelection,
                  AppStrings.changeFilters,
                  action: AppStrings.clearFilters,
                  onAction: _clearFilters,
                )
              else ...[
                _countCard(),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: _miniCount(
                        _unmatched.length,
                        AppStrings.unmatchedNotYetRead,
                        amber: true,
                        onTap: () => _openList('unmatched'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _miniCount(
                        _unlabelled.length,
                        AppStrings.unlabelledItems,
                        onTap: () => _openList('unlabelled'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.help_outline, size: 16, color: AppColors.muted),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        AppStrings.notYetReadCaution,
                        style: _text(size: 13, color: AppColors.muted, height: 1.35),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
        _footer(
          primary: label,
          icon: scanning
              ? Icons.pause
              : hasReads
              ? Icons.play_arrow
              : Icons.document_scanner_outlined,
          enabled: expected.isNotEmpty,
          onPrimary: scanning ? () => setState(_pauseScan) : _startScan,
          tools: [
            _tool(Icons.filter_list, AppStrings.results, () => _openList('matched')),
            _tool(Icons.save_outlined, AppStrings.save, () => _open(_InvPage.save), enabled: hasReads),
            _tool(Icons.mail_outline, AppStrings.email, _emailPreview, enabled: hasReads),
            _tool(Icons.replay, AppStrings.reset, _askReset, enabled: hasReads, danger: true),
          ],
        ),
      ],
    );
  }

  Widget _countCard() {
    final expected = _expected.length;
    final matched = _matched.length;
    final fraction = expected == 0 ? 0.0 : matched / expected;
    final caption = _status == 'scanning'
        ? AppStrings.readingTagged
        : matched > 0
        ? AppStrings.scanPausedHint
        : AppStrings.readyWhenYouAre;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _countFill,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                AppStrings.matchedItems,
                style: _text(size: 13, color: const Color(0xFFD9D3C7)),
              ),
              const Spacer(),
              const Icon(Icons.document_scanner_outlined, color: Color(0xFFE6C477), size: 18),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '$matched',
                style: _text(size: 40, weight: FontWeight.w700, color: AppColors.white, height: 1),
              ),
              const SizedBox(width: 8),
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text(
                  '/ $expected ${AppStrings.expected}',
                  style: _text(size: 14, color: const Color(0xFFC8C2B6)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(caption, style: _text(size: 13, color: const Color(0xFFC8C2B6))),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(99),
            child: LinearProgressIndicator(
              value: fraction,
              minHeight: 6,
              backgroundColor: const Color(0xFF3A3936),
              color: _track,
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Text(
                '${_unmatched.length} ${AppStrings.notYetRead}',
                style: _text(size: 12, color: const Color(0xFFC8C2B6)),
              ),
              const Spacer(),
              Text(
                _saved ? AppStrings.reportSaved : AppStrings.notSaved,
                style: _text(size: 12, color: const Color(0xFFC8C2B6)),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(child: _weightStat(AppStrings.systemGrossWeight, _gross)),
              const SizedBox(width: 10),
              Expanded(child: _weightStat(AppStrings.matchedGrossWeight, _matchedGross)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _weightStat(String label, int milligrams) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: _text(size: 11, color: const Color(0xFFB7B1A6))),
        const SizedBox(height: 2),
        Text(
          '${InventoryCatalog.grams(milligrams)} g',
          style: _text(size: 14, weight: FontWeight.w700, color: AppColors.white),
        ),
      ],
    );
  }

  Widget _list() {
    final source = switch (_listTab) {
      'matched' => _matched,
      'unlabelled' => _unlabelled,
      _ => _unmatched,
    };
    final items = _filterQuery(source, _query);
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
          child: Column(
            children: [
              _searchBox(
                _listQuery,
                AppStrings.searchItems,
                (value) => setState(() {
                  _query = value;
                  _limit = 20;
                }),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  _tab(AppStrings.matched, 'matched'),
                  _tab(AppStrings.unmatched, 'unmatched'),
                  _tab(AppStrings.unlabelled, 'unlabelled'),
                ],
              ),
            ],
          ),
        ),
        Expanded(
          child: items.isEmpty
              ? _empty(Icons.search, _emptyTitle(), _emptyBody())
              : ListView(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
                  children: [
                    for (final item in items.take(_limit)) _resultRow(item),
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Text(
                        '${math.min(_limit, items.length)} of ${items.length} items',
                        textAlign: TextAlign.center,
                        style: _text(size: 12, color: AppColors.muted),
                      ),
                    ),
                    if (items.length > _limit)
                      OutlinedButton(
                        onPressed: () => setState(() => _limit += 20),
                        child: const Text(AppStrings.showMoreItems),
                      ),
                    if (_listTab == 'unmatched' && _unmatched.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: OutlinedButton.icon(
                          onPressed: () => _open(_InvPage.search),
                          icon: const Icon(Icons.search),
                          label: const Text(AppStrings.findUnmatched),
                        ),
                      ),
                  ],
                ),
        ),
      ],
    );
  }

  Widget _resultRow(InventoryPiece item) {
    final matched = _listTab == 'matched';
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: _card(
        padding: const EdgeInsets.fromLTRB(8, 8, 4, 8),
        child: Row(
          children: [
            Expanded(
              child: InkWell(
                onTap: () => _openDetails(item, _InvPage.list),
                child: Row(
                  children: [
                    _thumb(item),
                    const SizedBox(width: 10),
                    Expanded(child: _itemInfo(item)),
                  ],
                ),
              ),
            ),
            if (matched)
              const Icon(Icons.check_circle, color: AppColors.statusReady, size: 22)
            else
              IconButton(
                tooltip: item.rfid == null ? AppStrings.rfidNotLinked : AppStrings.findThisItem,
                onPressed: () {
                  if (item.rfid == null) {
                    _toast(AppStrings.rfidNotLinked);
                    return;
                  }
                  _openLocate(item, _InvPage.list);
                },
                icon: Icon(
                  item.rfid == null ? Icons.help_outline : Icons.search,
                  color: AppColors.goldText,
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _searchMany() {
    final items = _filterQuery(_unmatched, _searchQuery);
    final responding = _unmatched.where((item) => (_signals[item.id] ?? 0) > 0).length;
    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
            children: [
              Row(
                children: [
                  _statusPill(
                    _status == 'arming'
                        ? AppStrings.startingReader
                        : _multiSearching
                        ? AppStrings.listeningForTag
                        : AppStrings.searchPaused,
                    live: _multiSearching || _status == 'arming',
                    review: !_multiSearching,
                  ),
                  const Spacer(),
                  if (_status == 'arming')
                    const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.goldText),
                    )
                  else
                    _tag(AppStrings.localStock),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(child: _summaryStat(AppStrings.notYetReadInventory, '${_unmatched.length}')),
                  const SizedBox(width: 10),
                  Expanded(child: _summaryStat(AppStrings.searchResponses, '$responding')),
                ],
              ),
              const SizedBox(height: 12),
              _searchBox(
                _findQuery,
                AppStrings.rfidOrItem,
                (value) => setState(() => _searchQuery = value),
              ),
              const SizedBox(height: 10),
              Text(
                AppStrings.signalGuides,
                style: _text(size: 14, weight: FontWeight.w700),
              ),
              Text(
                AppStrings.openATarget,
                style: _text(size: 13, color: AppColors.muted),
              ),
              const SizedBox(height: 12),
              for (final item in items.take(30))
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: _card(
                    onTap: () => _openLocate(item, _InvPage.search),
                    child: Row(
                      children: [
                        _thumb(item),
                        const SizedBox(width: 10),
                        Expanded(child: _itemInfo(item)),
                        _miniSignal(_signals[item.id] ?? 0),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
        _footer(
          primary: _multiSearching ? AppStrings.pauseSearch : AppStrings.startSearch,
          icon: _multiSearching ? Icons.pause : Icons.document_scanner_outlined,
          onPrimary: _toggleMultiSearch,
          note: AppStrings.signalGuideBody,
        ),
      ],
    );
  }

  void _toggleMultiSearch() {
    if (_multiSearching) {
      setState(_pauseScan);
      return;
    }
    setState(() => _multiSearching = true);
    unawaited(_startScan());
  }

  Widget _locate() {
    final item = _piece(_searchId);
    if (item == null) return _list();
    final label = _signal >= 8
        ? AppStrings.strongerSignal
        : _signal > 0
        ? AppStrings.signalDetected
        : AppStrings.noTargetResponse;
    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
            children: [
              Row(
                children: [
                  _statusPill(
                    _status == 'arming'
                        ? AppStrings.startingReader
                        : _searching
                        ? AppStrings.listeningForTag
                        : AppStrings.searchPaused,
                    live: _searching || _status == 'arming',
                    review: !_searching,
                  ),
                  const Spacer(),
                  if (_status == 'arming')
                    const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.goldText),
                    )
                  else
                    _tag(AppStrings.localStock),
                ],
              ),
              const SizedBox(height: 12),
              _card(
                onTap: () => _openDetails(item, _InvPage.locate),
                child: Row(
                  children: [
                    _thumb(item),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(item.name, style: _text(size: 16, weight: FontWeight.w700)),
                          Text(
                            '${item.id} · ${item.rfid ?? AppStrings.notLinked}',
                            style: _text(size: 13, color: AppColors.muted),
                          ),
                        ],
                      ),
                    ),
                    const Icon(Icons.chevron_right, color: Color(0xFFC4B08A)),
                  ],
                ),
              ),
              const SizedBox(height: 22),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  for (var i = 0; i < 10; i++)
                    Container(
                      width: 10,
                      height: 21 + i * 5,
                      margin: const EdgeInsets.symmetric(horizontal: 3),
                      decoration: BoxDecoration(
                        color: i < _signal
                            ? (_signal >= 8 ? AppColors.statusReady : AppColors.goldText)
                            : const Color(0xFFE7E1D6),
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 14),
              Text(label, textAlign: TextAlign.center, style: _text(size: 18, weight: FontWeight.w700)),
              Text(
                _signal > 0 ? AppStrings.moveSlowly : AppStrings.startSearchToLook,
                textAlign: TextAlign.center,
                style: _text(size: 13, color: AppColors.muted),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => setState(() => _signal = math.max(0, _signal - 2)),
                      child: const Text(AppStrings.demoWeaker),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => setState(() => _signal = math.min(10, _signal + 2)),
                      child: const Text(AppStrings.demoStronger),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Text(AppStrings.signalIsGuide, style: _text(size: 14, weight: FontWeight.w700)),
              Text(AppStrings.signalGuideBody, style: _text(size: 13, color: AppColors.muted, height: 1.35)),
              const SizedBox(height: 8),
              Text(AppStrings.checkIdentityBeforeMatch, style: _text(size: 13, color: AppColors.muted)),
            ],
          ),
        ),
        _footer(
          primary: _searching ? AppStrings.pauseSearch : AppStrings.startSearch,
          icon: _searching ? Icons.pause : Icons.search,
          onPrimary: () {
            if (_searching) {
              setState(_pauseScan);
              return;
            }
            setState(() => _searching = true);
            unawaited(_startScan());
          },
          secondary: AppStrings.locatedItem,
          onSecondary: _signal >= 8
              ? () {
                  setState(() {
                    _reads.add(item.id);
                    _saved = false;
                    _searching = false;
                    _page = _InvPage.list;
                    _listTab = 'matched';
                  });
                }
              : null,
          note: AppStrings.searchDoesNotComplete,
        ),
      ],
    );
  }

  Widget _details() {
    final item = _piece(_detailId);
    if (item == null) return _list();
    final matched = _reads.contains(item.id);
    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
            children: [
              Container(
                height: 160,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: AppColors.chipSurface,
                  borderRadius: BorderRadius.circular(18),
                ),
                child: const Icon(Icons.diamond_outlined, size: 48, color: AppColors.goldText),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(item.name, style: _text(size: 22, weight: FontWeight.w700)),
                        Text(
                          '${AppStrings.itemDetails} ${item.id}',
                          style: _text(size: 13, color: AppColors.muted),
                        ),
                      ],
                    ),
                  ),
                  _tag(matched ? AppStrings.matched : AppStrings.notYetRead),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: _plainWeight(
                      AppStrings.grossWeight,
                      item.weightKnown ? item.milligrams : null,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _plainWeight(AppStrings.netWeight, item.netMilligrams),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              _field(AppStrings.category, item.category),
              _field(AppStrings.purity, item.purity),
              _field(AppStrings.design, item.design),
              _field(AppStrings.rfidCode, item.rfid ?? AppStrings.notLinked),
              const SizedBox(height: 12),
              Row(
                children: [
                  Text(
                    AppStrings.electronicProductCode,
                    style: _text(size: 11, weight: FontWeight.w700, letterSpacing: 0.6),
                  ),
                  const Spacer(),
                  if (item.epc != null)
                    IconButton(
                      tooltip: AppStrings.copied,
                      onPressed: () => _copyEpc(item.epc!),
                      icon: const Icon(Icons.copy, size: 18),
                    ),
                ],
              ),
              Text(
                item.epc ?? AppStrings.notProvided,
                style: _text(size: 13, weight: FontWeight.w600),
              ),
              const SizedBox(height: 12),
              Text(
                item.id == 'SM007'
                    ? AppStrings.suppliedItemNote
                    : AppStrings.demoItemNote,
                style: _text(size: 13, color: AppColors.muted, height: 1.35),
              ),
            ],
          ),
        ),
        _footer(
          primary: matched
              ? AppStrings.backToResults
              : item.rfid == null
              ? AppStrings.rfidNotLinked
              : AppStrings.findThisItem,
          icon: matched
              ? Icons.arrow_back
              : item.rfid == null
              ? Icons.sell_outlined
              : Icons.search,
          onPrimary: () {
            if (matched || item.rfid == null) {
              if (item.rfid == null && !matched) _toast(AppStrings.rfidNotLinked);
              _open(_detailBack);
              return;
            }
            _openLocate(item, _InvPage.details);
          },
          note: AppStrings.verifyPhysical,
        ),
      ],
    );
  }

  Widget _save() {
    final outstanding = _unmatched.isNotEmpty;
    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
            children: [
              Text(
                AppStrings.pauseReviewSave,
                style: _text(
                  size: 12,
                  weight: FontWeight.w700,
                  color: AppColors.goldText,
                  letterSpacing: 0.8,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                AppStrings.keepAClearRecord,
                style: _text(size: 30, weight: FontWeight.w700, height: 1.1),
              ),
              const SizedBox(height: 8),
              Text(
                AppStrings.saveCheckLead,
                style: _text(size: 15, color: AppColors.muted, height: 1.35),
              ),
              const SizedBox(height: 16),
              _summaryLine(AppStrings.scopeLabel, _scope),
              _summaryLine(AppStrings.expectedItems, '${_expected.length}'),
              _summaryLine(AppStrings.matched, '${_matched.length}'),
              _summaryLine(AppStrings.notYetRead, '${_unmatched.length}'),
              _summaryLine(AppStrings.unlabelled, '${_unlabelled.length}'),
              if (outstanding) ...[
                const SizedBox(height: 12),
                Text(
                  '${_unmatched.length} ${AppStrings.unmatchedRemain}',
                  style: _text(size: 13, height: 1.35),
                ),
              ],
              const SizedBox(height: 16),
              Text(
                '${AppStrings.reviewNote} ${AppStrings.optional}',
                style: _text(size: 12, weight: FontWeight.w600),
              ),
              const SizedBox(height: 6),
              TextField(
                controller: _noteController,
                minLines: 3,
                maxLines: 5,
                decoration: const InputDecoration(
                  hintText: AppStrings.addContext,
                  filled: true,
                  fillColor: AppColors.white,
                ),
              ),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: _acknowledged,
                onChanged: (value) => setState(() {
                  _acknowledged = value ?? false;
                  _ackError = null;
                }),
                title: Text(
                  AppStrings.reviewAck,
                  style: _text(size: 14),
                ),
                controlAffinity: ListTileControlAffinity.leading,
              ),
              if (_ackError != null)
                Text(_ackError!, style: _text(size: 13, color: AppColors.error)),
            ],
          ),
        ),
        _footer(
          primary: outstanding ? AppStrings.saveWithExceptions : AppStrings.saveReport,
          icon: Icons.save_outlined,
          onPrimary: _confirmSave,
          note: AppStrings.demoSaveNote,
        ),
      ],
    );
  }

  Widget _savedView() {
    final outstanding = _unmatched.length + _unlabelled.length;
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 28, 20, 24),
      children: [
        const Icon(Icons.check_circle, size: 56, color: AppColors.statusReady),
        const SizedBox(height: 16),
        Text(
          AppStrings.nextStepClear,
          style: _text(
            size: 12,
            weight: FontWeight.w700,
            color: AppColors.goldText,
            letterSpacing: 0.8,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          AppStrings.checkReadyForReview,
          style: _text(size: 30, weight: FontWeight.w700, height: 1.1),
        ),
        const SizedBox(height: 8),
        Text(
          AppStrings.reportSavedLead,
          style: _text(size: 15, color: AppColors.muted, height: 1.35),
        ),
        const SizedBox(height: 16),
        _summaryLine(AppStrings.matched, '${_matched.length}'),
        _summaryLine(AppStrings.stillToReview, '$outstanding'),
        _summaryLine(
          AppStrings.reportStatus,
          outstanding == 0 ? AppStrings.allExpectedRead : AppStrings.exceptionsRecorded,
        ),
        if (_note.isNotEmpty) ...[
          const SizedBox(height: 12),
          Text(_note, style: _text(size: 14, height: 1.35)),
        ],
        const SizedBox(height: 20),
        FilledButton(
          onPressed: () => _open(_InvPage.setup),
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.charcoal,
            minimumSize: const Size.fromHeight(52),
          ),
          child: const Text(AppStrings.backToScan),
        ),
      ],
    );
  }

  void _openList(String tab) {
    _pauseScan();
    setState(() {
      _listTab = tab;
      _limit = 20;
      _page = _InvPage.list;
    });
  }

  void _openDetails(InventoryPiece item, _InvPage from) {
    _pauseScan();
    setState(() {
      _detailId = item.id;
      _detailBack = from;
      _page = _InvPage.details;
    });
  }

  void _openLocate(InventoryPiece item, _InvPage from) {
    if (item.rfid == null) {
      _toast(AppStrings.rfidNotLinked);
      return;
    }
    _pauseScan();
    setState(() {
      _searchId = item.id;
      _locateBack = from;
      _signal = _signals[item.id] ?? 0;
      _page = _InvPage.locate;
    });
  }

  InventoryPiece? _piece(String? id) {
    if (id == null) return null;
    final stored = InventoryStock.instance.byId(id);
    if (stored != null) return stored;
    for (final item in [..._expected, ..._unlabelled, ...InventoryCatalog.items]) {
      if (item.id == id) return item;
    }
    return null;
  }

  List<InventoryPiece> _filterQuery(List<InventoryPiece> items, String query) {
    final needle = query.trim().toLowerCase();
    if (needle.isEmpty) return items;
    return items.where((item) {
      final haystack = [
        item.id,
        item.rfid,
        item.epc,
        item.product,
        item.design,
      ].whereType<String>().join(' ').toLowerCase();
      return haystack.contains(needle);
    }).toList();
  }

  String _emptyTitle() {
    if (_query.isNotEmpty) return AppStrings.noMatchingItems;
    return switch (_listTab) {
      'unmatched' => AppStrings.allExpectedItemsRead,
      'unlabelled' => AppStrings.noUnlabelled,
      _ => AppStrings.noMatchedYet,
    };
  }

  String _emptyBody() {
    if (_query.isNotEmpty) return AppStrings.tryItemCode;
    if (_listTab == 'unmatched') return AppStrings.reviewBeforeFinish;
    return AppStrings.continueScan;
  }

  String _filterLabel(Set<String> selected, List<String> all) {
    if (selected.length == all.length) return AppStrings.all;
    if (selected.length == 1) return selected.first;
    return '${selected.length} ${AppStrings.selectedScope.toLowerCase()}';
  }

  IconData get _modeIcon => switch (_mode) {
    'Counter' => Icons.point_of_sale_outlined,
    'Box' => Icons.inventory_2_outlined,
    'Branch' => Icons.storefront_outlined,
    'Exhibition' => Icons.diamond_outlined,
    _ => Icons.grid_view_rounded,
  };

  void _clearFilters() {
    setState(() {
      _categories
        ..clear()
        ..addAll(_categoryOptions);
      _products
        ..clear()
        ..addAll(_productOptions);
      _designs
        ..clear()
        ..addAll(_designOptions);
    });
  }

  Future<void> _pickScope() async {
    _pauseScan();
    setState(() {});
    final choices = InventoryStock.instance.places(_mode);
    if (choices.isEmpty) {
      _toast(AppStrings.noScopeValues);
      return;
    }
    var draft = _scope;
    if (!mounted) return;
    final picked = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: _surface,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setSheet) {
            return Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    '${AppStrings.chooseScopeTitle} ${_mode.toLowerCase()}',
                    style: _text(size: 18, weight: FontWeight.w700),
                  ),
                  const SizedBox(height: 6),
                  Text(AppStrings.chooseLocation, style: _text(size: 13, color: AppColors.muted)),
                  const SizedBox(height: 8),
                  RadioGroup<String>(
                    groupValue: draft,
                    onChanged: (value) => setSheet(() => draft = value ?? draft),
                    child: Column(
                      children: [
                        for (final choice in choices)
                          RadioListTile<String>(
                            value: choice,
                            title: Text(choice),
                          ),
                      ],
                    ),
                  ),
                  FilledButton(
                    onPressed: () => Navigator.pop(context, draft),
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.charcoal,
                      minimumSize: const Size.fromHeight(48),
                    ),
                    child: const Text(AppStrings.useThisScope),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    AppStrings.exampleLocations,
                    style: _text(size: 12, color: AppColors.muted),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
    if (picked != null) {
      setState(() {
        _scope = picked;
        _saved = false;
      });
    }
  }

  Future<void> _openFilters(String tab) async {
    _pauseScan();
    setState(() {});
    final draftCategories = {..._categories};
    final draftProducts = {..._products};
    final draftDesigns = {..._designs};
    var current = tab;
    if (!mounted) return;
    final queryController = TextEditingController();
    final applied = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: _surface,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setSheet) {
            final (label, options, selected) = switch (current) {
              'product' => (AppStrings.product, _productOptions, draftProducts),
              'design' => (AppStrings.design, _designOptions, draftDesigns),
              _ => (AppStrings.category, _categoryOptions, draftCategories),
            };
            final visible = options
                .where(
                  (option) => option.toLowerCase().contains(
                    queryController.text.toLowerCase(),
                  ),
                )
                .toList();
            return Padding(
              padding: EdgeInsets.fromLTRB(20, 16, 20, 16 + MediaQuery.viewInsetsOf(context).bottom),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(AppStrings.filterStock, style: _text(size: 18, weight: FontWeight.w700)),
                  const SizedBox(height: 4),
                  Text(AppStrings.chooseStockIncluded, style: _text(size: 13, color: AppColors.muted)),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      _sheetTab(AppStrings.category, current == 'category', () => setSheet(() {
                        current = 'category';
                        queryController.clear();
                      })),
                      _sheetTab(AppStrings.product, current == 'product', () => setSheet(() {
                        current = 'product';
                        queryController.clear();
                      })),
                      _sheetTab(AppStrings.design, current == 'design', () => setSheet(() {
                        current = 'design';
                        queryController.clear();
                      })),
                    ],
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: queryController,
                    decoration: InputDecoration(
                      hintText: label,
                      prefixIcon: const Icon(Icons.search),
                      filled: true,
                      fillColor: AppColors.white,
                    ),
                    onChanged: (_) => setSheet(() {}),
                  ),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: () => setSheet(() {
                        if (selected.length == options.length) {
                          selected.clear();
                        } else {
                          selected
                            ..clear()
                            ..addAll(options);
                        }
                      }),
                      child: const Text(AppStrings.selectAll),
                    ),
                  ),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 240),
                    child: ListView(
                      shrinkWrap: true,
                      children: [
                        for (final option in visible)
                          CheckboxListTile(
                            value: selected.contains(option),
                            title: Text(option),
                            controlAffinity: ListTileControlAffinity.leading,
                            onChanged: (value) => setSheet(() {
                              if (value ?? false) {
                                selected.add(option);
                              } else {
                                selected.remove(option);
                              }
                            }),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => Navigator.pop(context, false),
                          child: const Text(AppStrings.cancel),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: FilledButton(
                          onPressed: () => Navigator.pop(context, true),
                          style: FilledButton.styleFrom(backgroundColor: AppColors.charcoal),
                          child: const Text(AppStrings.applyFilters),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
        );
      },
    );
    queryController.dispose();
    if ((applied ?? false) && mounted) {
      setState(() {
        _categories
          ..clear()
          ..addAll(draftCategories);
        _products
          ..clear()
          ..addAll(draftProducts);
        _designs
          ..clear()
          ..addAll(draftDesigns);
        _saved = false;
      });
    }
  }

  void _emailPreview() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: _surface,
      builder: (context) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(AppStrings.emailPreview, style: _text(size: 18, weight: FontWeight.w700)),
            const SizedBox(height: 8),
            Text(AppStrings.emailPreviewBody, style: _text(size: 14, color: AppColors.muted)),
            const SizedBox(height: 12),
            _summaryLine(AppStrings.scopeLabel, _scope),
            _summaryLine(AppStrings.matched, '${_matched.length}'),
            _summaryLine(AppStrings.notYetRead, '${_unmatched.length}'),
          ],
        ),
      ),
    );
  }

  Widget _summaryStat(String label, String value) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: _text(size: 12, color: AppColors.muted)),
          Text(value, style: _text(size: 22, weight: FontWeight.w700)),
        ],
      ),
    );
  }

  Widget _summaryLine(String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: _line)),
      ),
      child: Row(
        children: [
          Expanded(child: Text(label, style: _text(size: 14, color: AppColors.muted))),
          Text(value, style: _text(size: 14, weight: FontWeight.w700)),
        ],
      ),
    );
  }

  Widget _plainWeight(String label, int? milligrams) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: _text(size: 12, color: AppColors.muted)),
          Text(
            milligrams == null ? '—' : '${InventoryCatalog.grams(milligrams)} g',
            style: _text(size: 16, weight: FontWeight.w700),
          ),
        ],
      ),
    );
  }

  Widget _field(String label, String? value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Expanded(child: Text(label, style: _text(size: 14, color: AppColors.muted))),
          Text(value ?? AppStrings.notProvided, style: _text(size: 14, weight: FontWeight.w600)),
        ],
      ),
    );
  }

  Widget _itemInfo(InventoryPiece item) {
    final weight = item.weightKnown
        ? '${InventoryCatalog.grams(item.milligrams)} g'
        : AppStrings.weightNotProvided;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(item.name, style: _text(size: 15, weight: FontWeight.w700)),
        Text(
          '${item.id} · $weight',
          style: _text(size: 12, color: AppColors.muted),
        ),
        Text(
          'RFID ${item.rfid ?? AppStrings.notLinked}',
          style: _text(size: 12, color: AppColors.muted),
        ),
        Text(item.design ?? AppStrings.notProvided, style: _text(size: 12, color: AppColors.goldText)),
      ],
    );
  }

  Widget _miniSignal(int level) {
    return Row(
      children: [
        for (var i = 0; i < 6; i++)
          Container(
            width: 3,
            height: 6 + i * 2,
            margin: const EdgeInsets.only(left: 2),
            color: i < (level / 2).ceil() ? AppColors.goldText : const Color(0xFFE7E1D6),
          ),
      ],
    );
  }

  Widget _searchBox(
    TextEditingController controller,
    String hint,
    ValueChanged<String> onChanged,
  ) {
    return TextField(
      controller: controller,
      onChanged: onChanged,
      decoration: InputDecoration(
        hintText: hint,
        prefixIcon: const Icon(Icons.search),
        filled: true,
        fillColor: AppColors.white,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: _line),
        ),
      ),
    );
  }

  Widget _tab(String label, String value) {
    final active = _listTab == value;
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 3),
        child: TextButton(
          onPressed: () => setState(() {
            _listTab = value;
            _limit = 20;
          }),
          style: TextButton.styleFrom(
            backgroundColor: active ? AppColors.charcoal : AppColors.white,
            foregroundColor: active ? AppColors.white : AppColors.charcoal,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: const BorderSide(color: _line),
            ),
          ),
          child: Text(label, style: _text(size: 12, weight: FontWeight.w600, color: active ? AppColors.white : AppColors.charcoal)),
        ),
      ),
    );
  }

  Widget _sheetTab(String label, bool active, VoidCallback onTap) {
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 3),
        child: TextButton(
          onPressed: onTap,
          style: TextButton.styleFrom(
            backgroundColor: active ? AppColors.charcoal : AppColors.white,
            foregroundColor: active ? AppColors.white : AppColors.charcoal,
          ),
          child: Text(label, style: _text(size: 12, color: active ? AppColors.white : AppColors.charcoal)),
        ),
      ),
    );
  }

  Widget _statusPill(String label, {required bool live, required bool review}) {
    final color = live
        ? AppColors.statusReady
        : review
        ? AppColors.goldText
        : AppColors.muted;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: _line),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Text(label, style: _text(size: 12, weight: FontWeight.w600, color: color)),
        ],
      ),
    );
  }

  Widget _tag(String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFFF1EBDF),
        borderRadius: BorderRadius.circular(99),
      ),
      child: Text(
        label,
        style: _text(size: 10, weight: FontWeight.w700, color: AppColors.goldText, letterSpacing: 0.4),
      ),
    );
  }

  Widget _filterChip(String label, String value, VoidCallback onTap) {
    return Expanded(
      child: Material(
        color: AppColors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: _line),
        ),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: _text(size: 11, color: AppColors.muted)),
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: _text(size: 13, weight: FontWeight.w700),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _miniCount(int count, String label, {bool amber = false, required VoidCallback onTap}) {
    return Material(
      color: amber ? const Color(0xFFF8F1E3) : AppColors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: const BorderSide(color: _line),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('$count', style: _text(size: 22, weight: FontWeight.w700)),
              Text(label, style: _text(size: 12, color: AppColors.muted)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _empty(
    IconData icon,
    String title,
    String body, {
    String? action,
    VoidCallback? onAction,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 28),
      child: Column(
        children: [
          Icon(icon, color: AppColors.goldText, size: 28),
          const SizedBox(height: 8),
          Text(title, style: _text(size: 16, weight: FontWeight.w700)),
          const SizedBox(height: 4),
          Text(body, textAlign: TextAlign.center, style: _text(size: 13, color: AppColors.muted)),
          if (action != null)
            TextButton(onPressed: onAction, child: Text(action)),
        ],
      ),
    );
  }

  Widget _footer({
    required String primary,
    required IconData icon,
    required VoidCallback onPrimary,
    bool enabled = true,
    String? secondary,
    VoidCallback? onSecondary,
    String? note,
    List<Widget>? tools,
  }) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
      decoration: const BoxDecoration(
        color: AppColors.white,
        border: Border(top: BorderSide(color: _line)),
      ),
      child: Column(
        children: [
          FilledButton.icon(
            onPressed: enabled ? onPrimary : null,
            icon: Icon(icon, size: 18),
            label: Text(primary),
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.charcoal,
              minimumSize: const Size.fromHeight(AppTypography.mainActionHeight),
            ),
          ),
          if (secondary != null) ...[
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: onSecondary,
              icon: const Icon(Icons.check_circle_outline, size: 18),
              label: Text(secondary),
              style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
            ),
          ],
          if (tools != null) ...[
            const SizedBox(height: 8),
            Row(children: tools),
          ],
          if (note != null) ...[
            const SizedBox(height: 6),
            Text(note, textAlign: TextAlign.center, style: _text(size: 11, color: AppColors.muted)),
          ],
        ],
      ),
    );
  }

  Widget _tool(
    IconData icon,
    String label,
    VoidCallback onTap, {
    bool enabled = true,
    bool danger = false,
  }) {
    final color = danger ? AppColors.error : AppColors.charcoal;
    return Expanded(
      child: TextButton(
        onPressed: enabled ? onTap : null,
        child: Column(
          children: [
            Icon(icon, size: 18, color: enabled ? color : AppColors.muted),
            Text(label, style: _text(size: 11, color: enabled ? color : AppColors.muted)),
          ],
        ),
      ),
    );
  }

  Widget _card({
    required Widget child,
    VoidCallback? onTap,
    EdgeInsetsGeometry padding = const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
  }) {
    return Material(
      color: AppColors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: _line),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(padding: padding, child: child),
      ),
    );
  }

  Widget _symbol(IconData icon) {
    return Container(
      width: 44,
      height: 44,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: AppColors.chipSurface,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Icon(icon, size: 22, color: AppColors.goldText),
    );
  }

  Widget _thumb(InventoryPiece item) {
    return Container(
      width: 44,
      height: 44,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: AppColors.chipSurface,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        item.name.characters.first,
        style: _text(size: 16, weight: FontWeight.w700, color: AppColors.goldText),
      ),
    );
  }
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
