import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import '../../../../core/constants/app_strings.dart';
import '../../../../core/theme/app_colors.dart';
import '../demo/order_demo_session.dart';

enum _OrderPage { list, editor }

class OrdersPage extends StatefulWidget {
  const OrdersPage({super.key});

  @override
  State<OrdersPage> createState() => _OrdersPageState();
}

class _OrdersPageState extends State<OrdersPage> {
  static const _surface = Color(0xFFFAF9F7);
  static const _ink = Color(0xFF20201E);
  static const _headLine = Color(0xFFE8E3D9);
  static const _line = Color(0xFFE3DDD1);
  static const _muted = Color(0xFF6D6B66);
  static const _gold = Color(0xFF85652C);
  static const _tagFill = Color(0xFFEEE9DD);
  static const _tagInk = Color(0xFF837657);
  static const _tagLine = Color(0xFFE3DAC6);
  static const _searchLine = Color(0xFFDAD5CA);
  static const _searchIcon = Color(0xFF8C7B57);
  static const _note = Color(0xFF817866);

  final _session = OrderDemoSession.instance;
  final _orderQuery = TextEditingController();
  final _itemQuery = TextEditingController();
  var _page = _OrderPage.list;
  var _capturing = false;
  Timer? _timer;
  String? _removeId;

  @override
  void initState() {
    super.initState();
    _orderQuery.text = _session.query;
    _orderQuery.addListener(() {
      _session.query = _orderQuery.text;
      if (mounted && _page == _OrderPage.list) setState(() {});
    });
    _itemQuery.addListener(() {
      if (mounted && _page == _OrderPage.editor) setState(() {});
    });
  }

  @override
  void dispose() {
    _stopScan();
    _orderQuery.dispose();
    _itemQuery.dispose();
    super.dispose();
  }

  DemoOrder? get _draft => _session.draft;

  void _toast(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  void _stopScan() {
    _timer?.cancel();
    _timer = null;
    _capturing = false;
  }

  void _goList() {
    _stopScan();
    _itemQuery.clear();
    setState(() => _page = _OrderPage.list);
  }

  void _back() {
    if (_page == _OrderPage.editor && (_draft?.dirty ?? false)) {
      _leaveSheet();
      return;
    }
    if (_page == _OrderPage.editor) {
      _session.draft = null;
      _goList();
      return;
    }
    Navigator.of(context).maybePop();
  }

  void _openNew() {
    _stopScan();
    _session.startNew();
    _itemQuery.clear();
    setState(() => _page = _OrderPage.editor);
  }

  void _openEdit(String id) {
    _stopScan();
    _session.startEdit(id);
    _itemQuery.clear();
    setState(() => _page = _OrderPage.editor);
  }

  void _toggleScan() {
    if (_capturing) {
      setState(_stopScan);
      return;
    }
    setState(() => _capturing = true);
    _timer = Timer.periodic(const Duration(milliseconds: 900), (_) {
      if (!mounted) return;
      final next = _session.nextUnread();
      if (next == null) {
        setState(_stopScan);
        _toast(AppStrings.allPiecesRead);
        return;
      }
      setState(() => _session.addItem(next.id));
    });
  }

  Future<void> _downloadCsv() async {
    final rows = <List<String>>[
      [
        AppStrings.orderWord,
        AppStrings.customerLabel,
        AppStrings.orderDate,
        AppStrings.deliveryDate,
        AppStrings.itemCode,
        'Gross g',
        'Net g',
      ],
    ];
    for (final order in _session.visible) {
      for (final item in order.items) {
        rows.add([
          order.id ?? '',
          order.customer,
          order.details.orderDate,
          order.details.deliveryDate,
          item.id,
          item.grossMg == null ? '' : (item.grossMg! / 1000).toStringAsFixed(3),
          item.netMg == null ? '' : (item.netMg! / 1000).toStringAsFixed(3),
        ]);
      }
    }
    final csv = rows.map((row) => row.map(_csv).join(',')).join('\r\n');
    try {
      final directory = await getApplicationDocumentsDirectory();
      final file = File('${directory.path}/SPARKLE_Demo_Orders.csv');
      await file.writeAsString('\uFEFF$csv');
      if (mounted) _toast(AppStrings.demoOrderCsv);
    } catch (_) {
      if (mounted) _toast(AppStrings.cacheError);
    }
  }

  String _csv(String value) {
    final safe = RegExp(r'^[=+\-@]').hasMatch(value) ? "'$value" : value;
    return '"${safe.replaceAll('"', '""')}"';
  }

  @override
  Widget build(BuildContext context) {
    final dirty = _page == _OrderPage.editor && (_draft?.dirty ?? false);
    return PopScope(
      canPop: _page == _OrderPage.list && !dirty,
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
        child: Scaffold(
          backgroundColor: _surface,
          body: SafeArea(
            child: Column(
              children: [
                _header(),
                Expanded(child: _page == _OrderPage.list ? _list() : _editor()),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _header() {
    final editing = _page == _OrderPage.editor;
    final title = editing
        ? (_draft?.id == null ? AppStrings.newOrder : AppStrings.editOrder)
        : AppStrings.orders;
    final subtitle = editing
        ? (_draft?.id ?? AppStrings.customerPath)
        : AppStrings.customerOrders;
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
              tooltip: AppStrings.home,
              icon: const Icon(Icons.arrow_back, size: 21, color: _ink),
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
                  Text(subtitle, style: _text(size: 10, color: const Color(0xFF787166))),
                ],
              ),
            ),
            IconButton(
              tooltip: AppStrings.moreActions,
              onPressed: editing ? _editorMenu : _tools,
              icon: const Icon(Icons.more_horiz, size: 21, color: _ink),
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
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
            children: [
              Row(
                children: [
                  Text(
                    AppStrings.yourCommitments,
                    style: _text(size: 10, weight: FontWeight.w600, color: const Color(0xFF80745B), letterSpacing: 0.5),
                  ),
                  const Spacer(),
                  _tag(AppStrings.demoData),
                ],
              ),
              const SizedBox(height: 12),
              _search(_orderQuery, AppStrings.searchOrders),
              Row(
                children: [
                  TextButton.icon(
                    onPressed: _views,
                    icon: const Icon(Icons.expand_more, size: 16, color: Color(0xFF8B7550)),
                    label: Text(_viewLabel, style: _text(size: 13, weight: FontWeight.w600)),
                    style: TextButton.styleFrom(foregroundColor: _ink),
                  ),
                  const Spacer(),
                  IconButton(
                    tooltip: AppStrings.filterOrders,
                    onPressed: _filters,
                    style: IconButton.styleFrom(
                      backgroundColor: const Color(0xFFF0EADC),
                      foregroundColor: _gold,
                      fixedSize: const Size(44, 44),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    icon: const Icon(Icons.tune, size: 18),
                  ),
                ],
              ),
              if (_session.view == 'sku')
                _empty(AppStrings.skuSummary, AppStrings.skuSummaryBody)
              else if (rows.isEmpty)
                _empty(AppStrings.noOrdersFound, AppStrings.tryAnotherOrder)
              else if (_session.view == 'customer')
                ..._customerCards(rows)
              else ...[
                Text(
                  '${rows.length} ${AppStrings.ordersInDemo}',
                  style: _text(size: 11, color: const Color(0xFF8D7C5A)),
                ),
                const SizedBox(height: 8),
                for (final order in rows) _orderCard(order),
              ],
            ],
          ),
        ),
        _footer(
          label: AppStrings.newOrder,
          icon: Icons.add,
          onPressed: _openNew,
          note: AppStrings.newOrderNote,
        ),
      ],
    );
  }

  String get _viewLabel => switch (_session.view) {
    'customer' => AppStrings.byCustomer,
    'sku' => AppStrings.bySku,
    _ => AppStrings.allOrders,
  };

  List<Widget> _customerCards(List<DemoOrder> rows) {
    final names = rows.map((order) => order.customer).toSet();
    return [
      for (final name in names)
        Builder(
          builder: (context) {
            final group = rows.where((order) => order.customer == name).toList();
            final pieces = group.expand((order) => order.items).toList();
            final totals = OrderDemoSession.totals(pieces);
            return Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppColors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFE2DCCF)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(name, style: _text(size: 14, weight: FontWeight.w600)),
                  const SizedBox(height: 6),
                  Text(
                    '${group.length} orders · ${totals.count} ${totals.count == 1 ? AppStrings.piece : AppStrings.pieces}\nGross ${OrderDemoSession.grams(totals.gross)} g',
                    style: _text(size: 11, color: const Color(0xFF796E59), height: 1.6),
                  ),
                ],
              ),
            );
          },
        ),
    ];
  }

  Widget _orderCard(DemoOrder order) {
    final totals = OrderDemoSession.totals(order.items);
    return Container(
      margin: const EdgeInsets.only(bottom: 11),
      padding: const EdgeInsets.fromLTRB(15, 8, 6, 12),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE2DDD1)),
      ),
      child: Column(
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: InkWell(
                  onTap: () => _openEdit(order.id!),
                  child: Padding(
                    padding: const EdgeInsets.only(top: 8, bottom: 6),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(order.customer, style: _text(size: 15, weight: FontWeight.w600)),
                        const SizedBox(height: 4),
                        Text(
                          '${order.id} · ${OrderDemoSession.formatDate(order.details.orderDate)}\n${order.details.branch}',
                          style: _text(size: 10, color: const Color(0xFF7B7467), height: 1.7),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              IconButton(
                tooltip: AppStrings.orderActions,
                onPressed: () => _actions(order.id!),
                icon: const Icon(Icons.more_horiz, size: 18),
              ),
            ],
          ),
          const Divider(height: 16, color: Color(0xFFEEE9DF)),
          Row(
            children: [
              Expanded(
                child: Text(
                  '${totals.count} ${totals.count == 1 ? AppStrings.piece : AppStrings.pieces} · ${OrderDemoSession.grams(totals.gross)} g',
                  style: _text(size: 11, color: const Color(0xFF685F4E)),
                ),
              ),
              const Icon(Icons.check, size: 14, color: Color(0xFF3B744E)),
              const SizedBox(width: 4),
              Text(AppStrings.savedInDemo, style: _text(size: 11, color: const Color(0xFF685F4E))),
            ],
          ),
        ],
      ),
    );
  }

  Widget _editor() {
    final draft = _draft;
    if (draft == null) return const SizedBox.shrink();
    final totals = OrderDemoSession.totals(draft.items);
    final suggestions = _itemQuery.text.trim().isEmpty
        ? const <OrderPiece>[]
        : _session.catalog.where((piece) {
            final haystack = '${piece.id} ${piece.name} ${piece.rfid}'.toLowerCase();
            return haystack.contains(_itemQuery.text.trim().toLowerCase());
          }).toList();
    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      _capturing
                          ? AppStrings.capturingPieces
                          : draft.dirty
                          ? AppStrings.unsavedChanges
                          : AppStrings.buildTheOrder,
                      style: _text(size: 10, weight: FontWeight.w600, color: const Color(0xFF80745B), letterSpacing: 0.5),
                    ),
                  ),
                  _tag(AppStrings.demoData),
                ],
              ),
              const SizedBox(height: 12),
              Material(
                color: const Color(0xFFF8F2E6),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(13),
                  side: const BorderSide(color: Color(0xFFDFD3B8)),
                ),
                child: InkWell(
                  onTap: _customers,
                  borderRadius: BorderRadius.circular(13),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Row(
                      children: [
                        Container(
                          width: 35,
                          height: 35,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: const Color(0xFFECE0C5),
                            borderRadius: BorderRadius.circular(9),
                          ),
                          child: const Icon(Icons.person_outline, size: 18, color: Color(0xFF8B6A2E)),
                        ),
                        const SizedBox(width: 11),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(AppStrings.customerLabel, style: _text(size: 9, color: const Color(0xFF80704F))),
                              Text(
                                draft.customer.isEmpty ? AppStrings.chooseCustomer : draft.customer,
                                style: _text(size: 14, weight: FontWeight.w600),
                              ),
                            ],
                          ),
                        ),
                        const Icon(Icons.expand_more, color: Color(0xFF8B6A2E)),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              InkWell(
                onTap: _details,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              draft.details.branch.isEmpty ? AppStrings.chooseBranch : draft.details.branch,
                              style: _text(size: 14, weight: FontWeight.w600),
                            ),
                            Text(
                              '${AppStrings.deliveryWord} ${OrderDemoSession.formatDate(draft.details.deliveryDate)}',
                              style: _text(size: 11, color: _muted),
                            ),
                          ],
                        ),
                      ),
                      Text(AppStrings.orderDetails, style: _text(size: 12, color: _gold)),
                      const Icon(Icons.tune, size: 16, color: _gold),
                    ],
                  ),
                ),
              ),
              Row(
                children: [
                  Expanded(child: _search(_itemQuery, AppStrings.rfidOrItem)),
                  const SizedBox(width: 8),
                  Material(
                    color: const Color(0xFFEEE6D5),
                    borderRadius: BorderRadius.circular(11),
                    child: InkWell(
                      onTap: _pick,
                      borderRadius: BorderRadius.circular(11),
                      child: const SizedBox(
                        width: 50,
                        height: 50,
                        child: Icon(Icons.add, color: _gold),
                      ),
                    ),
                  ),
                ],
              ),
              if (suggestions.isNotEmpty) ...[
                const SizedBox(height: 8),
                for (final piece in suggestions) _pickTile(piece),
              ],
              if (_capturing) ...[
                const SizedBox(height: 10),
                Text(AppStrings.readingOrderTags, style: _text(size: 12, weight: FontWeight.w600, color: const Color(0xFF8A682B))),
              ],
              const SizedBox(height: 14),
              Row(
                children: [
                  Text(AppStrings.piecesInOrder, style: _text(size: 12, weight: FontWeight.w700, letterSpacing: 0.4)),
                  const Spacer(),
                  Text(
                    '${totals.count} ${totals.count == 1 ? AppStrings.piece : AppStrings.pieces}',
                    style: _text(size: 12, color: _muted),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              if (draft.items.isEmpty)
                _empty(AppStrings.addTheJewellery, AppStrings.orderScanOrSelect)
              else
                for (final piece in draft.items) _pieceCard(piece),
              TextButton.icon(
                onPressed: _pick,
                icon: const Icon(Icons.add, size: 16),
                label: const Text(AppStrings.addAnotherPiece),
              ),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFFF0EBE0),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFE3D9C4)),
                ),
                child: Column(
                  children: [
                    _totalLine(AppStrings.netWeight, totals.net),
                    _totalLine(AppStrings.fwWeight, totals.fw),
                    _totalLine(AppStrings.orderAmount, null, pending: true),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Text(AppStrings.tapPiece, style: _text(size: 12, color: _muted)),
            ],
          ),
        ),
        Container(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
          decoration: const BoxDecoration(
            color: AppColors.white,
            border: Border(top: BorderSide(color: _line)),
          ),
          child: Column(
            children: [
              Row(
                children: [
                  Text('${totals.count}', style: _text(size: 14, weight: FontWeight.w700)),
                  Text(' ${AppStrings.pieces}', style: _text(size: 13, color: _muted)),
                  const Spacer(),
                  Text(
                    '${AppStrings.grossShort} ${OrderDemoSession.grams(totals.gross)} g',
                    style: _text(size: 13),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  SizedBox(
                    width: 64,
                    height: 52,
                    child: OutlinedButton(
                      onPressed: _toggleScan,
                      style: OutlinedButton.styleFrom(
                        backgroundColor: const Color(0xFFEEE5D1),
                        foregroundColor: _gold,
                        side: const BorderSide(color: Color(0xFFDFCEA9)),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(11)),
                        padding: EdgeInsets.zero,
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(_capturing ? Icons.pause : Icons.document_scanner_outlined, size: 18),
                          Text(
                            _capturing ? AppStrings.pause : AppStrings.scan,
                            style: _text(size: 9, weight: FontWeight.w600, color: _gold),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: draft.items.isEmpty ? null : _review,
                      icon: const Icon(Icons.arrow_forward, size: 18),
                      label: const Text(AppStrings.reviewOrder),
                      style: FilledButton.styleFrom(
                        backgroundColor: _ink,
                        foregroundColor: AppColors.white,
                        disabledBackgroundColor: const Color(0xFFDDD8CC),
                        minimumSize: const Size.fromHeight(52),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(AppStrings.scanningAdds, textAlign: TextAlign.center, style: _text(size: 9, color: _note)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _pieceCard(OrderPiece piece) {
    return Container(
      margin: const EdgeInsets.only(bottom: 9),
      padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _line),
      ),
      child: Row(
        children: [
          Expanded(
            child: InkWell(
              onTap: () => _pieceDetails(piece),
              child: Row(
                children: [
                  _thumb(piece.name),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(piece.name, style: _text(size: 13, weight: FontWeight.w600)),
                        Text(
                          '${piece.id} · ${AppStrings.grossShort} ${OrderDemoSession.grams(piece.grossMg)} g\n${AppStrings.netWeight} ${OrderDemoSession.grams(piece.netMg)}${piece.netMg == null ? '' : ' g'} · F+W ${OrderDemoSession.grams(piece.fwMg)}${piece.fwMg == null ? '' : ' g'}',
                          style: _text(size: 10, color: const Color(0xFF7A705F), height: 1.6),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          IconButton(
            tooltip: AppStrings.removeThisPiece,
            onPressed: () => _confirmRemove(piece.id),
            icon: const Icon(Icons.delete_outline, size: 18, color: Color(0xFFA27361)),
          ),
        ],
      ),
    );
  }

  Widget _pickTile(OrderPiece piece) {
    final added = _draft?.items.any((item) => item.id == piece.id) ?? false;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      enabled: !added,
      leading: _thumb(piece.name),
      title: Text('${piece.id} · ${piece.name}', style: _text(size: 13, weight: FontWeight.w600)),
      subtitle: Text(
        '${AppStrings.grossShort} ${OrderDemoSession.grams(piece.grossMg)} g${added ? ' · ${AppStrings.alreadyAdded}' : ''}',
        style: _text(size: 11, color: _muted),
      ),
      trailing: Icon(added ? Icons.check : Icons.add, color: _gold),
      onTap: () {
        final ok = _session.addItem(piece.id);
        _itemQuery.clear();
        setState(() {});
        _toast(ok ? '${piece.id} added.' : AppStrings.alreadyInOrder);
      },
    );
  }

  void _review() {
    final draft = _draft;
    if (draft == null) return;
    final errors = _session.orderErrors(draft);
    if (errors.isNotEmpty) {
      _toast(errors.join(' '));
      if (draft.customer.trim().isEmpty) _customers();
      return;
    }
    final totals = OrderDemoSession.totals(draft.items);
    var gst = draft.gst;
    _openSheet(AppStrings.reviewOrder, StatefulBuilder(
      builder: (context, setSheet) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _row(AppStrings.customerLabel, draft.customer),
            _row(AppStrings.branch, draft.details.branch),
            _row(AppStrings.deliveryWord, OrderDemoSession.formatDate(draft.details.deliveryDate)),
            _row(AppStrings.pieces, '${totals.count}'),
            _row(
              AppStrings.grossSlashNet,
              '${OrderDemoSession.grams(totals.gross)} / ${OrderDemoSession.grams(totals.net)} g',
            ),
            Container(
              width: double.infinity,
              margin: const EdgeInsets.symmetric(vertical: 8),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFF2EDE2),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                draft.items.map((item) => '${item.id} · ${item.name}').join('\n'),
                style: _text(size: 11, color: const Color(0xFF7B705B), height: 1.7),
              ),
            ),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              value: gst,
              onChanged: (value) => setSheet(() => gst = value ?? false),
              title: Text(AppStrings.gstLabel, style: _text(size: 12)),
              controlAffinity: ListTileControlAffinity.leading,
            ),
            _row(AppStrings.orderAmount, AppStrings.pricingPending),
            const SizedBox(height: 8),
            Text(AppStrings.checkCustomer, style: _text(size: 11, color: const Color(0xFF75603B), height: 1.6)),
            const SizedBox(height: 12),
            _filled(AppStrings.saveDemoOrder, () {
              draft.gst = gst;
              final saved = _session.save();
              if (saved == null) return;
              Navigator.pop(context);
              _goList();
              _savedSheet(saved.id!);
            }),
            const SizedBox(height: 8),
            Text(AppStrings.demoSaveOnly, style: _text(size: 12, color: _note)),
          ],
        );
      },
    ));
  }

  void _savedSheet(String id) {
    _openSheet(AppStrings.orderSavedDemo, Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 52,
          height: 52,
          alignment: Alignment.center,
          decoration: const BoxDecoration(color: Color(0xFFE9F1E7), shape: BoxShape.circle),
          child: const Icon(Icons.check, color: Color(0xFF3B744E)),
        ),
        const SizedBox(height: 12),
        Text('$id ${AppStrings.readyInList}', style: _text(size: 13, height: 1.5)),
        const SizedBox(height: 8),
        Text(AppStrings.noLiveErp, style: _text(size: 12, color: _muted, height: 1.5)),
        const SizedBox(height: 12),
        _filled(AppStrings.backToOrders, () => Navigator.pop(context)),
      ],
    ));
  }

  void _customers() {
    final query = TextEditingController();
    _openSheet(
      AppStrings.chooseCustomer,
      StatefulBuilder(
        builder: (context, setSheet) {
          final names = _session.customers
              .where((name) => name.toLowerCase().contains(query.text.toLowerCase()))
              .toList();
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _search(query, AppStrings.customerName, onChanged: (_) => setSheet(() {})),
              if (names.isEmpty)
                Text(AppStrings.noCustomerMatch, style: _text(size: 13, color: _muted))
              else
                for (final name in names)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.person_outline, color: _gold),
                    title: Text(name, style: _text(size: 14, weight: FontWeight.w600)),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () {
                      final draft = _draft;
                      if (draft != null) {
                        draft.customer = name;
                        draft.dirty = true;
                      }
                      Navigator.pop(context);
                      setState(() {});
                    },
                  ),
              TextButton.icon(
                onPressed: () {
                  Navigator.pop(context);
                  _addCustomer();
                },
                icon: const Icon(Icons.add),
                label: const Text(AppStrings.addCustomer),
              ),
            ],
          );
        },
      ),
    ).whenComplete(query.dispose);
  }

  void _addCustomer() {
    final name = TextEditingController();
    String? error;
    _openSheet(
      AppStrings.addCustomer,
      StatefulBuilder(
        builder: (context, setSheet) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: name,
                decoration: _input(AppStrings.customerName),
              ),
              if (error != null) Text(error!, style: _text(size: 12, color: AppColors.error)),
              const SizedBox(height: 12),
              _filled(AppStrings.useCustomer, () {
                final value = name.text.trim();
                if (value.isEmpty) {
                  setSheet(() => error = AppStrings.enterCustomerName);
                  return;
                }
                if (!_session.customers.contains(value)) _session.customers.add(value);
                final draft = _draft;
                if (draft != null) {
                  draft.customer = value;
                  draft.dirty = true;
                }
                Navigator.pop(context);
                setState(() {});
              }),
              const SizedBox(height: 8),
              Text(AppStrings.addsNameDemo, style: _text(size: 12, color: _note)),
            ],
          );
        },
      ),
    ).whenComplete(name.dispose);
  }

  void _pick() {
    final query = TextEditingController();
    _openSheet(
      AppStrings.addAPiece,
      StatefulBuilder(
        builder: (context, setSheet) {
          final items = _session.catalog.where((piece) {
            final haystack = '${piece.id} ${piece.name} ${piece.rfid}'.toLowerCase();
            return haystack.contains(query.text.trim().toLowerCase());
          });
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _search(query, AppStrings.rfidOrItem, onChanged: (_) => setSheet(() {})),
              if (items.isEmpty)
                Text(AppStrings.noMatchingItem, style: _text(size: 13, color: _muted))
              else
                for (final piece in items) _sheetPick(piece),
            ],
          );
        },
      ),
    ).whenComplete(query.dispose);
  }

  Widget _sheetPick(OrderPiece piece) {
    final added = _draft?.items.any((item) => item.id == piece.id) ?? false;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      enabled: !added,
      title: Text('${piece.id} · ${piece.name}', style: _text(size: 14, weight: FontWeight.w600)),
      subtitle: Text(
        '${AppStrings.grossShort} ${OrderDemoSession.grams(piece.grossMg)} g${added ? ' · ${AppStrings.alreadyAdded}' : ''}',
        style: _text(size: 12, color: _muted),
      ),
      trailing: Icon(added ? Icons.check : Icons.add, color: _gold),
      onTap: added
          ? null
          : () {
              final ok = _session.addItem(piece.id);
              Navigator.pop(context);
              setState(() {});
              _toast(ok ? '${piece.id} added.' : AppStrings.alreadyInOrder);
            },
    );
  }

  void _confirmRemove(String id) {
    _removeId = id;
    _openSheet(AppStrings.removeThisPiece, Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Remove $id from this order? ${AppStrings.stockUnchanged}',
          style: _text(size: 13, color: _muted, height: 1.5),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(child: OutlinedButton(onPressed: () => Navigator.pop(context), child: const Text(AppStrings.keep))),
            const SizedBox(width: 8),
            Expanded(
              child: FilledButton(
                onPressed: () {
                  _session.removeItem(_removeId ?? id);
                  Navigator.pop(context);
                  setState(() {});
                },
                style: FilledButton.styleFrom(backgroundColor: _ink),
                child: const Text(AppStrings.removePiece),
              ),
            ),
          ],
        ),
      ],
    ));
  }

  void _details() {
    final details = _draft?.details;
    if (details == null) return;
    final fields = <String, TextEditingController>{
      'orderDate': TextEditingController(text: details.orderDate),
      'deliveryDate': TextEditingController(text: details.deliveryDate),
      'exhibition': TextEditingController(text: details.exhibition),
      'remark': TextEditingController(text: details.remark),
      'purity': TextEditingController(text: details.purity),
      'size': TextEditingController(text: details.size),
      'length': TextEditingController(text: details.length),
      'colour': TextEditingController(text: details.colour),
      'screw': TextEditingController(text: details.screw),
      'polish': TextEditingController(text: details.polish),
      'fine': TextEditingController(text: details.fine),
      'wastage': TextEditingController(text: details.wastage),
    };
    String? error;
    _openSheet(
      AppStrings.orderDetails,
      StatefulBuilder(
        builder: (context, setSheet) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              InputDecorator(
                decoration: _input(AppStrings.branch),
                child: Text(details.branch, style: _text(size: 14)),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(child: TextField(controller: fields['orderDate'], decoration: _input(AppStrings.orderDate))),
                  const SizedBox(width: 8),
                  Expanded(child: TextField(controller: fields['deliveryDate'], decoration: _input(AppStrings.deliveryDate))),
                ],
              ),
              _group(AppStrings.eventNotes, [
                TextField(controller: fields['exhibition'], decoration: _input(AppStrings.exhibitionField)),
                const SizedBox(height: 8),
                TextField(controller: fields['remark'], decoration: _input(AppStrings.remark)),
              ]),
              _group(AppStrings.jewellerySpecs, [
                TextField(controller: fields['purity'], decoration: _input(AppStrings.purity)),
                const SizedBox(height: 8),
                TextField(controller: fields['size'], decoration: _input(AppStrings.size)),
                const SizedBox(height: 8),
                TextField(controller: fields['length'], decoration: _input(AppStrings.lengthField)),
                const SizedBox(height: 8),
                TextField(controller: fields['colour'], decoration: _input(AppStrings.colourType)),
                const SizedBox(height: 8),
                TextField(controller: fields['screw'], decoration: _input(AppStrings.screwType)),
                const SizedBox(height: 8),
                TextField(controller: fields['polish'], decoration: _input(AppStrings.polishType)),
              ]),
              _group(AppStrings.fineWastage, [
                TextField(controller: fields['fine'], decoration: _input(AppStrings.finePercent), keyboardType: TextInputType.number),
                const SizedBox(height: 8),
                TextField(controller: fields['wastage'], decoration: _input(AppStrings.wastagePercent), keyboardType: TextInputType.number),
              ]),
              if (error != null) Text(error!, style: _text(size: 12, color: AppColors.error)),
              const SizedBox(height: 12),
              _filled(AppStrings.applyDetails, () {
                final next = details.copy()
                  ..orderDate = fields['orderDate']!.text.trim()
                  ..deliveryDate = fields['deliveryDate']!.text.trim()
                  ..exhibition = fields['exhibition']!.text.trim()
                  ..remark = fields['remark']!.text.trim()
                  ..purity = fields['purity']!.text.trim()
                  ..size = fields['size']!.text.trim()
                  ..length = fields['length']!.text.trim()
                  ..colour = fields['colour']!.text.trim()
                  ..screw = fields['screw']!.text.trim()
                  ..polish = fields['polish']!.text.trim()
                  ..fine = fields['fine']!.text.trim()
                  ..wastage = fields['wastage']!.text.trim();
                final errors = _session.detailErrors(next);
                if (errors.isNotEmpty) {
                  setSheet(() => error = errors.join(' '));
                  return;
                }
                _draft?.details = next;
                _draft?.dirty = true;
                Navigator.pop(context);
                setState(() {});
              }),
              const SizedBox(height: 8),
              Text(AppStrings.appliesToOrder, style: _text(size: 12, color: _note)),
            ],
          );
        },
      ),
    ).whenComplete(() {
      for (final controller in fields.values) {
        controller.dispose();
      }
    });
  }

  void _pieceDetails(OrderPiece piece) {
    String textOf(int? milligrams) => milligrams == null ? '' : (milligrams / 1000).toStringAsFixed(3);
    final branch = TextEditingController(text: piece.branch ?? _draft?.details.branch ?? '');
    final weights = {
      'total': TextEditingController(text: textOf(piece.totalMg)),
      'packing': TextEditingController(text: textOf(piece.packingMg)),
      'gross': TextEditingController(text: textOf(piece.grossMg)),
      'net': TextEditingController(text: textOf(piece.netMg)),
      'fw': TextEditingController(text: textOf(piece.fwMg)),
    };
    String? error;
    _openSheet(
      AppStrings.pieceDetails,
      StatefulBuilder(
        builder: (context, setSheet) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _row(AppStrings.product, piece.name),
              _row(AppStrings.itemCode, piece.id),
              TextField(controller: branch, decoration: _input(AppStrings.branch)),
              const SizedBox(height: 8),
              Text(AppStrings.weightsAndPacking, style: _text(size: 13, weight: FontWeight.w600)),
              const SizedBox(height: 8),
              TextField(controller: weights['total'], decoration: _input(AppStrings.totalWeightG), keyboardType: TextInputType.number),
              const SizedBox(height: 8),
              TextField(controller: weights['packing'], decoration: _input(AppStrings.packingWeightG), keyboardType: TextInputType.number),
              const SizedBox(height: 8),
              TextField(controller: weights['gross'], decoration: _input(AppStrings.grossWeightG), keyboardType: TextInputType.number),
              const SizedBox(height: 8),
              TextField(controller: weights['net'], decoration: _input(AppStrings.netWeightG), keyboardType: TextInputType.number),
              const SizedBox(height: 8),
              TextField(controller: weights['fw'], decoration: _input('F+W weight (g)'), keyboardType: TextInputType.number),
              if (error != null) Text(error!, style: _text(size: 12, color: AppColors.error)),
              const SizedBox(height: 12),
              _filled(AppStrings.applyToPiece, () {
                int? read(String key) {
                  final raw = weights[key]!.text.trim();
                  if (raw.isEmpty) return null;
                  final value = num.tryParse(raw);
                  if (value == null || value < 0) return -1;
                  return (value * 1000).round();
                }

                final parsed = {for (final key in weights.keys) key: read(key)};
                if (parsed.values.any((value) => value == -1)) {
                  setSheet(() => error = AppStrings.weightsNonNegative);
                  return;
                }
                piece
                  ..totalMg = parsed['total']
                  ..packingMg = parsed['packing']
                  ..grossMg = parsed['gross']
                  ..netMg = parsed['net']
                  ..fwMg = parsed['fw']
                  ..branch = branch.text.trim();
                _draft?.dirty = true;
                Navigator.pop(context);
                setState(() {});
              }),
              const SizedBox(height: 8),
              Text(AppStrings.missingWeights, style: _text(size: 12, color: _note)),
            ],
          );
        },
      ),
    ).whenComplete(() {
      branch.dispose();
      for (final controller in weights.values) {
        controller.dispose();
      }
    });
  }

  void _views() {
    _openSheet(AppStrings.viewOrders, Column(
      children: [
        _menu(AppStrings.allOrders, () => _setView('orders')),
        _menu(AppStrings.skuSummary, () => _setView('sku')),
        _menu(AppStrings.customerSummary, () => _setView('customer')),
      ],
    ));
  }

  void _setView(String view) {
    _session.view = view;
    Navigator.pop(context);
    setState(() {});
  }

  void _filters() {
    var field = _session.dateField;
    final from = TextEditingController(text: _session.from);
    final to = TextEditingController(text: _session.to);
    String? error;
    _openSheet(
      AppStrings.filterOrders,
      StatefulBuilder(
        builder: (context, setSheet) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              DropdownButtonFormField<String>(
                initialValue: field,
                decoration: _input(AppStrings.dateField),
                items: const [
                  DropdownMenuItem(value: 'orderDate', child: Text(AppStrings.orderDate)),
                  DropdownMenuItem(value: 'deliveryDate', child: Text(AppStrings.deliveryDate)),
                ],
                onChanged: (value) => setSheet(() => field = value ?? field),
              ),
              const SizedBox(height: 8),
              TextField(controller: from, decoration: _input(AppStrings.fromDate)),
              const SizedBox(height: 8),
              TextField(controller: to, decoration: _input(AppStrings.toDate)),
              const SizedBox(height: 8),
              Text(AppStrings.allStatuses, style: _text(size: 14, weight: FontWeight.w600)),
              Text(AppStrings.noStatusValues, style: _text(size: 12, color: _note)),
              if (error != null) Text(error!, style: _text(size: 12, color: AppColors.error)),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () {
                        _session
                          ..dateField = 'orderDate'
                          ..from = ''
                          ..to = '';
                        Navigator.pop(context);
                        setState(() {});
                      },
                      child: const Text(AppStrings.reset),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: FilledButton(
                      onPressed: () {
                        final start = from.text.trim();
                        final end = to.text.trim();
                        if (start.isNotEmpty && end.isNotEmpty && start.compareTo(end) > 0) {
                          setSheet(() => error = AppStrings.endDateAfter);
                          return;
                        }
                        _session
                          ..dateField = field
                          ..from = start
                          ..to = end;
                        Navigator.pop(context);
                        setState(() {});
                      },
                      style: FilledButton.styleFrom(backgroundColor: _ink),
                      child: const Text(AppStrings.applyFilters),
                    ),
                  ),
                ],
              ),
            ],
          );
        },
      ),
    ).whenComplete(() {
      from.dispose();
      to.dispose();
    });
  }

  void _actions(String id) {
    _openSheet(AppStrings.orderActions, Column(
      children: [
        _menu(AppStrings.editOrder, () {
          Navigator.pop(context);
          _openEdit(id);
        }),
        _menu(AppStrings.printPreview, () {
          Navigator.pop(context);
          _print(id);
        }),
        _menu(AppStrings.deleteOrder, () {
          Navigator.pop(context);
          _delete(id);
        }),
      ],
    ));
  }

  void _print(String id) {
    final order = _session.orders.cast<DemoOrder?>().firstWhere(
      (item) => item?.id == id,
      orElse: () => null,
    );
    if (order == null) return;
    _openSheet(AppStrings.orderPrintPreview, Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _row(AppStrings.orderWord, order.id ?? ''),
        _row(AppStrings.customerLabel, order.customer),
        const SizedBox(height: 8),
        Text(
          order.items
              .map((item) => '${item.id} · ${item.name} · ${OrderDemoSession.grams(item.grossMg)} g')
              .join('\n'),
          style: _text(size: 12, height: 1.6),
        ),
        const SizedBox(height: 8),
        Text(AppStrings.previewOnlyPrint, style: _text(size: 12, color: _note, height: 1.5)),
        const SizedBox(height: 12),
        _filled(AppStrings.done, () => Navigator.pop(context)),
      ],
    ));
  }

  void _delete(String id) {
    _openSheet(AppStrings.deleteDemoOrder, Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Remove $id ${AppStrings.removeFromDemoList}',
          style: _text(size: 13, color: _muted, height: 1.5),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(child: OutlinedButton(onPressed: () => Navigator.pop(context), child: const Text(AppStrings.keep))),
            const SizedBox(width: 8),
            Expanded(
              child: FilledButton(
                onPressed: () {
                  _session.orders.removeWhere((order) => order.id == id);
                  Navigator.pop(context);
                  setState(() {});
                },
                style: FilledButton.styleFrom(backgroundColor: _ink),
                child: const Text(AppStrings.deleteDemoOrderAction),
              ),
            ),
          ],
        ),
      ],
    ));
  }

  void _tools() {
    _openSheet(AppStrings.orderTools, Column(
      children: [
        _menu(AppStrings.syncOrders, () {
          Navigator.pop(context);
          _sync();
        }),
        _menu(AppStrings.reportView, () {
          Navigator.pop(context);
          _views();
        }),
        _menu(AppStrings.filterOrders, () {
          Navigator.pop(context);
          _filters();
        }),
        _menu(AppStrings.downloadDemoCsv, () {
          Navigator.pop(context);
          _downloadCsv();
        }),
      ],
    ));
  }

  void _sync() {
    _openSheet(AppStrings.syncOrders, Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Icon(Icons.cloud_upload_outlined, size: 32, color: _gold),
        const SizedBox(height: 8),
        Text(
          '${_session.orders.length} ${AppStrings.sampleOrdersNote}',
          style: _text(size: 13, height: 1.5),
        ),
        const SizedBox(height: 8),
        Text(AppStrings.notConnectedErp, style: _text(size: 12, color: _note, height: 1.5)),
        const SizedBox(height: 12),
        _filled(AppStrings.understood, () => Navigator.pop(context)),
      ],
    ));
  }

  void _editorMenu() {
    _openSheet(AppStrings.orderOptions, Column(
      children: [
        _menu(AppStrings.gscan, () {
          Navigator.pop(context);
          _gscan();
        }),
        _menu(AppStrings.orderDetails, () {
          Navigator.pop(context);
          _details();
        }),
        _menu(AppStrings.clearPieces, () {
          Navigator.pop(context);
          _clearPieces();
        }),
      ],
    ));
  }

  void _gscan() {
    _openSheet(AppStrings.gscan, Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(AppStrings.gscanStays, style: _text(size: 13, height: 1.5)),
        const SizedBox(height: 8),
        Text(AppStrings.gscanNotShown, style: _text(size: 12, color: _note, height: 1.5)),
        const SizedBox(height: 12),
        _filled(AppStrings.backToOrders, () => Navigator.pop(context)),
      ],
    ));
  }

  void _clearPieces() {
    _openSheet(AppStrings.clearThisSelection, Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(AppStrings.clearPiecesBody, style: _text(size: 13, color: _muted, height: 1.5)),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(child: OutlinedButton(onPressed: () => Navigator.pop(context), child: const Text(AppStrings.keep))),
            const SizedBox(width: 8),
            Expanded(
              child: FilledButton(
                onPressed: () {
                  _draft?.items.clear();
                  _draft?.dirty = true;
                  Navigator.pop(context);
                  setState(() {});
                },
                style: FilledButton.styleFrom(backgroundColor: _ink),
                child: const Text(AppStrings.clearPieces),
              ),
            ),
          ],
        ),
      ],
    ));
  }

  void _leaveSheet() {
    _openSheet(AppStrings.leaveOrder, Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(AppStrings.leaveOrderBody, style: _text(size: 13, color: _muted, height: 1.5)),
        const SizedBox(height: 12),
        _filled(AppStrings.keepEditing, () => Navigator.pop(context)),
        TextButton(
          onPressed: () {
            _session.draft = null;
            Navigator.pop(context);
            _goList();
          },
          child: const Text(AppStrings.discardChanges),
        ),
      ],
    ));
  }

  Future<void> _openSheet(String title, Widget body) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: _surface,
      barrierColor: const Color(0x70151410),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(23)),
      ),
      builder: (context) {
        return Padding(
          padding: EdgeInsets.fromLTRB(22, 0, 22, 20 + MediaQuery.viewInsetsOf(context).bottom),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 11),
                Center(
                  child: Container(
                    width: 33,
                    height: 4,
                    decoration: BoxDecoration(
                      color: const Color(0xFFD3CFC6),
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                ),
                Row(
                  children: [
                    Expanded(
                      child: Text(title, style: _text(size: 20, weight: FontWeight.w600, letterSpacing: -0.6)),
                    ),
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close, size: 20),
                    ),
                  ],
                ),
                body,
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _menu(String label, VoidCallback onTap) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(label, style: _text(size: 15, weight: FontWeight.w600)),
      trailing: const Icon(Icons.chevron_right, color: Color(0xFF917C53)),
      onTap: onTap,
    );
  }

  Widget _row(String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Color(0xFFE7DFD0))),
      ),
      child: Row(
        children: [
          Expanded(child: Text(label, style: _text(size: 12, color: const Color(0xFF807254)))),
          Flexible(
            child: Text(value, textAlign: TextAlign.end, style: _text(size: 12, weight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }

  Widget _totalLine(String label, int? milligrams, {bool pending = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Expanded(child: Text(label, style: _text(size: 11))),
          Text(
            pending ? AppStrings.pricingPending : '${OrderDemoSession.grams(milligrams)}${milligrams == null ? '' : ' g'}',
            style: _text(size: 11, weight: FontWeight.w600),
          ),
        ],
      ),
    );
  }

  Widget _group(String title, List<Widget> children) {
    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        tilePadding: EdgeInsets.zero,
        title: Text(title, style: _text(size: 13, weight: FontWeight.w600)),
        children: children,
      ),
    );
  }

  Widget _search(TextEditingController controller, String hint, {ValueChanged<String>? onChanged}) {
    return TextField(
      controller: controller,
      onChanged: onChanged,
      style: _text(size: 12),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: _text(size: 12, color: _searchIcon),
        prefixIcon: const Icon(Icons.search, size: 18, color: _searchIcon),
        filled: true,
        fillColor: AppColors.white,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(vertical: 14),
        border: _border(_searchLine),
        enabledBorder: _border(_searchLine),
        focusedBorder: _border(const Color(0xFF967431)),
      ),
    );
  }

  Widget _filled(String label, VoidCallback onPressed) {
    return FilledButton(
      onPressed: onPressed,
      style: FilledButton.styleFrom(
        backgroundColor: _ink,
        foregroundColor: AppColors.white,
        minimumSize: const Size.fromHeight(52),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      child: Text(label),
    );
  }

  Widget _footer({
    required String label,
    required IconData icon,
    required VoidCallback onPressed,
    required String note,
  }) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
      decoration: const BoxDecoration(
        color: AppColors.white,
        border: Border(top: BorderSide(color: _line)),
      ),
      child: Column(
        children: [
          FilledButton.icon(
            onPressed: onPressed,
            icon: Icon(icon, size: 18),
            label: Text(label),
            style: FilledButton.styleFrom(
              backgroundColor: _ink,
              foregroundColor: AppColors.white,
              minimumSize: const Size.fromHeight(52),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
          const SizedBox(height: 6),
          Text(note, textAlign: TextAlign.center, style: _text(size: 9, color: _note)),
        ],
      ),
    );
  }

  Widget _empty(String title, String body) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 28),
      child: Column(
        children: [
          Text(title, textAlign: TextAlign.center, style: _text(size: 16, weight: FontWeight.w700)),
          const SizedBox(height: 6),
          Text(body, textAlign: TextAlign.center, style: _text(size: 12, color: _muted, height: 1.5)),
        ],
      ),
    );
  }

  Widget _thumb(String name) {
    return Container(
      width: 41,
      height: 46,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: const Color(0xFFF4EFE4),
        borderRadius: BorderRadius.circular(8),
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
      child: Text(label, style: _text(size: 9, color: _tagInk, letterSpacing: 0.4)),
    );
  }
}

InputDecoration _input(String label) {
  return InputDecoration(
    labelText: label,
    filled: true,
    fillColor: AppColors.white,
    border: _border(const Color(0xFFD5CBBC)),
    enabledBorder: _border(const Color(0xFFD5CBBC)),
    focusedBorder: _border(const Color(0xFF967431)),
  );
}

OutlineInputBorder _border(Color color) {
  return OutlineInputBorder(
    borderRadius: const BorderRadius.all(Radius.circular(10)),
    borderSide: BorderSide(color: color),
  );
}

TextStyle _text({
  required double size,
  FontWeight weight = FontWeight.w400,
  Color color = const Color(0xFF20201F),
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
