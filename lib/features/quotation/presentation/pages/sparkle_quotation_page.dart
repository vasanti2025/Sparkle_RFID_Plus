import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/constants/app_strings.dart';
import '../../../../core/locale/oq_text.dart';
import '../../../../core/di/injection.dart';
import '../../../../core/rfid/rfid_service.dart';
import '../../../../core/session/app_session.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/result.dart';
import '../../domain/entities/customer_record.dart';
import '../../domain/entities/quotation_detail.dart';
import '../../domain/entities/quotation_draft.dart';
import '../../domain/entities/quotation_summary.dart';
import '../../domain/entities/stock_item.dart';
import '../quotation_output.dart';
import '../widgets/stock_picker_sheet.dart';
import 'add_customer_page.dart';

enum _QuoteScreen { list, editor }

class SparkleQuotationPage extends StatefulWidget {
  const SparkleQuotationPage({super.key, this.detail});

  final QuotationDetail? detail;

  @override
  State<SparkleQuotationPage> createState() => _SparkleQuotationPageState();
}

class _SparkleQuotationPageState extends State<SparkleQuotationPage> {
  static const _surface = Color(0xFFFAF9F7);
  static const _ink = Color(0xFF20201E);
  static const _headLine = Color(0xFFE8E3D9);
  static const _line = Color(0xFFE3DDD1);
  static const _muted = Color(0xFF6D6B66);
  static const _gold = Color(0xFF85652C);
  static const _searchLine = Color(0xFFDAD5CA);
  static const _searchIcon = Color(0xFF8C7B57);
  static const _note = Color(0xFF817866);

  final TextEditingController _listQuery = TextEditingController();
  final TextEditingController _lookup = TextEditingController();
  final TextEditingController _branch = TextEditingController();
  final TextEditingController _reference = TextEditingController();
  final TextEditingController _notes = TextEditingController();
  CustomerIndex _customers = CustomerIndex(const []);
  CustomerRecord? _customer;
  final List<StockItem> _items = [];
  Timer? _debounce;
  var _searchToken = 0;
  List<StockItem> _suggestions = const [];
  var _loadingCustomers = false;
  var _saving = false;
  var _readingTag = false;
  var _seenTags = 0;
  final _rfidTrigger = RfidTrigger();
  final _tray = RfidTrayScan();
  late DateTime _docDate;
  late DateTime _validUntil;
  int _quotationId = 0;
  String _quotationNo = '';
  Map<String, dynamic> _source = const {};
  var _screen = _QuoteScreen.list;
  var _triggerOn = false;
  var _opening = false;
  var _waitingList = true;
  String? _listError;
  List<QuotationSummary> _quotations = const [];

  String get _clientCode => AppSession.clientCode;

  @override
  void initState() {
    super.initState();
    final today = DateTime.now();
    _docDate = DateTime(today.year, today.month, today.day);
    _validUntil = _docDate.add(const Duration(days: 7));
    final detail = widget.detail;
    if (detail != null) {
      _screen = _QuoteScreen.editor;
      _applyDetail(detail);
      _armTrigger();
    } else {
      _listQuery.addListener(() {
        if (mounted && _screen == _QuoteScreen.list) _showQuotations();
      });
      _loadQuotations();
    }
    _loadCustomers();
    if (_clientCode.isNotEmpty) {
      unawaited(Injection.quotations.warmLabeledStock(_clientCode, () {}));
    }
  }

  @override
  void dispose() {
    if (_triggerOn) _rfidTrigger.detach();
    _tray.cancel();
    _debounce?.cancel();
    _listQuery.dispose();
    _lookup.dispose();
    _branch.dispose();
    _reference.dispose();
    _notes.dispose();
    super.dispose();
  }

  void _applyDetail(QuotationDetail detail) {
    _quotationId = detail.id;
    _quotationNo = detail.number;
    _source = detail.source;
    _customer = detail.customer;
    _items
      ..clear()
      ..addAll(detail.items);
  }

  void _armTrigger() {
    if (_triggerOn) return;
    _triggerOn = true;
    _rfidTrigger.attach(_readTagIntoQuotation);
  }

  void _disarmTrigger() {
    _tray.cancel();
    _readingTag = false;
    if (!_triggerOn) return;
    _triggerOn = false;
    _rfidTrigger.detach();
  }

  void _clearDraft() {
    final today = DateTime.now();
    _quotationId = 0;
    _quotationNo = '';
    _source = const {};
    _customer = null;
    _items.clear();
    _lookup.clear();
    _branch.clear();
    _reference.clear();
    _notes.clear();
    _suggestions = const [];
    _docDate = DateTime(today.year, today.month, today.day);
    _validUntil = _docDate.add(const Duration(days: 7));
  }

  void _loadQuotations({bool refresh = false}) {
    if (_clientCode.isEmpty) {
      _waitingList = false;
      _listError = tr('Sign in to load quotations.');
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() {});
      });
      return;
    }
    final cached = Injection.quotations.quotationsMatching(_clientCode, _listQuery.text);
    if (cached.isNotEmpty) {
      _quotations = cached;
      _waitingList = false;
      _listError = null;
    }
    Injection.quotations.warmQuotations(_clientCode, _showQuotations, refresh: refresh).catchError((_) {
      if (!mounted || _quotations.isNotEmpty) return;
      setState(() {
        _waitingList = false;
        _listError = tr('Quotations could not be loaded.');
      });
    });
  }

  void _showQuotations() {
    if (!mounted) return;
    setState(() {
      _quotations = Injection.quotations.quotationsMatching(_clientCode, _listQuery.text);
      _waitingList = false;
      _listError = null;
    });
  }

  void _openNew() {
    _disarmTrigger();
    _clearDraft();
    _armTrigger();
    setState(() => _screen = _QuoteScreen.editor);
  }

  Future<void> _openExisting(QuotationSummary row) async {
    if (_opening || row.id == 0) return;
    setState(() => _opening = true);
    final result = await Injection.quotations.loadQuotation(
      clientCode: _clientCode,
      id: row.id,
    );
    if (!mounted) return;
    setState(() => _opening = false);
    switch (result) {
      case Success(:final data):
        final detail = data.customer.name.trim().isNotEmpty
            ? data
            : QuotationDetail(
                id: data.id,
                number: data.number,
                customer: CustomerRecord(
                  id: data.customer.id,
                  name: row.customerName,
                  mobile: data.customer.mobile,
                  email: data.customer.email,
                ),
                items: data.items,
                gstApplied: data.gstApplied,
                source: data.source,
              );
        _disarmTrigger();
        _clearDraft();
        _applyDetail(detail);
        _armTrigger();
        setState(() => _screen = _QuoteScreen.editor);
      case Error(:final failure):
        _toast(failure.message);
    }
  }

  void _goList({bool refresh = true}) {
    _disarmTrigger();
    setState(() => _screen = _QuoteScreen.list);
    _loadQuotations(refresh: refresh);
  }

  void _back() {
    if (_screen == _QuoteScreen.editor && widget.detail == null) {
      _goList();
      return;
    }
    Navigator.of(context).maybePop();
  }

  void _toast(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _loadCustomers() async {
    if (_clientCode.isEmpty) return;
    setState(() => _loadingCustomers = true);
    final result = await Injection.quotations.loadCustomers(_clientCode);
    if (!mounted) return;
    setState(() {
      _loadingCustomers = false;
      if (result case Success(:final data)) _customers = data;
    });
  }

  void _onLookupChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 280), () {
      _lookupSuggestions(value);
    });
  }

  Future<void> _lookupSuggestions(String value) async {
    final query = value.trim();
    if (query.isEmpty || _clientCode.isEmpty) {
      if (mounted) setState(() => _suggestions = const []);
      return;
    }
    final token = ++_searchToken;
    final result = await Injection.quotations.searchStock(
      clientCode: _clientCode,
      query: query,
    );
    if (!mounted || token != _searchToken) return;
    if (result case Success(:final data)) {
      setState(() => _suggestions = data);
    }
  }

  void _addItem(StockItem item) {
    if (_items.any((current) => current.identity == item.identity)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${item.identity} is already on this quotation')),
      );
      return;
    }
    setState(() {
      _items.add(item);
      _suggestions = const [];
      _lookup.clear();
    });
  }

  Future<void> _openPicker() async {
    final item = await showStockPicker(
      context: context,
      clientCode: _clientCode,
      initialQuery: _lookup.text,
    );
    if (item != null) _addItem(item);
  }

  Future<void> _scanLookup() async {
    final query = _lookup.text.trim();
    if (query.isEmpty) {
      await _readTagIntoQuotation();
      return;
    }
    await _findAndAdd(query);
  }

  Future<void> _readTagIntoQuotation() async {
    if (_readingTag || _saving) return;
    final typed = _lookup.text.trim();
    if (!RfidService.instance.isSupported) {
      if (typed.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Enter an RFID or item code, then scan or use +.')),
        );
        return;
      }
      await _findAndAdd(typed);
      return;
    }

    setState(() {
      _readingTag = true;
      _seenTags = 0;
    });
    final read = await _tray.collect(
      onCount: (count) {
        if (mounted) setState(() => _seenTags = count);
      },
    );
    if (!mounted) return;
    if (read.error != null || read.codes.isEmpty) {
      setState(() => _readingTag = false);
      if (typed.isNotEmpty) {
        await _findAndAdd(typed);
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(read.error ?? tr('No tag found'))),
      );
      return;
    }

    final matches = await Injection.quotations.stockForTags(_clientCode, read.codes);
    if (!mounted) return;
    var added = 0;
    setState(() {
      for (final item in matches) {
        if (_items.any((current) => current.identity == item.identity)) continue;
        _items.add(item);
        added++;
      }
      _suggestions = const [];
      _lookup.clear();
      _readingTag = false;
    });
    if (added == 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            matches.isEmpty ? 'Tags scanned but items were not found in stock.' : 'Already on this quotation',
          ),
        ),
      );
    }
  }

  Future<void> _findAndAdd(String query) async {
    final result = await Injection.quotations.searchStock(
      clientCode: _clientCode,
      query: query,
    );
    if (!mounted) return;
    switch (result) {
      case Success(:final data) when data.isNotEmpty:
        _addItem(data.first);
      case Success():
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(tr('No matching item'))),
        );
      case Error(:final failure):
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(failure.message)),
        );
    }
  }

  double get _gross {
    var total = 0.0;
    for (final item in _items) {
      total += double.tryParse(item.gross) ?? 0;
    }
    return total;
  }

  @override
  Widget build(BuildContext context) {
    final editing = _screen == _QuoteScreen.editor;
    final title = editing
        ? (_quotationNo.isEmpty ? tr(AppStrings.newQuotation) : _quotationNo)
        : tr(AppStrings.quotations);
    final subtitle = editing ? tr(AppStrings.customerPath) : tr('All quotations');
    return OrderQuotationScope(
      child: PopScope(
        canPop: !editing || widget.detail != null,
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
                  _header(title, subtitle),
                  Expanded(child: editing ? _editor() : _list()),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _header(String title, String subtitle) {
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
              tooltip: tr(AppStrings.home),
              icon: const Icon(Icons.arrow_back, size: 21, color: _ink),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: _qText(size: 21, weight: FontWeight.w600, letterSpacing: -0.7)),
                  const SizedBox(height: 4),
                  Text(subtitle, style: _qText(size: 10, color: const Color(0xFF787166))),
                ],
              ),
            ),
            const LanguageButton(),
          ],
        ),
      ),
    );
  }

  Widget _list() {
    final rows = _quotations;
    return Column(
      children: [
        Expanded(
          child: CustomScrollView(
            slivers: [
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                sliver: SliverToBoxAdapter(
                  child: Column(
                    children: [
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          tr(AppStrings.quotations).toUpperCase(),
                          style: _qText(size: 10, weight: FontWeight.w600, color: const Color(0xFF80745B), letterSpacing: 0.5),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _listQuery,
                        style: _qText(size: 12),
                        decoration: InputDecoration(
                          hintText: tr('Search quotation or customer'),
                          hintStyle: _qText(size: 12, color: _searchIcon),
                          prefixIcon: const Icon(Icons.search, size: 18, color: _searchIcon),
                          filled: true,
                          fillColor: AppColors.white,
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(vertical: 14),
                          border: _qBorder(_searchLine),
                          enabledBorder: _qBorder(_searchLine),
                          focusedBorder: _qBorder(const Color(0xFF967431)),
                        ),
                      ),
                      const SizedBox(height: 12),
                      if (_listError != null)
                        _empty(tr('Quotations'), _listError!)
                      else if (_waitingList && rows.isEmpty)
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 28),
                          child: Center(child: CircularProgressIndicator(color: _gold)),
                        )
                      else if (rows.isEmpty)
                        _empty(tr('No quotations found'), tr('Search quotation or customer'))
                      else
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: Text(
                              '${rows.length} ${tr(AppStrings.quotations)}',
                              style: _qText(size: 11, color: const Color(0xFF8D7C5A)),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              if (rows.isNotEmpty)
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  sliver: SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (context, index) => _quotationCard(rows[index]),
                      childCount: rows.length,
                    ),
                  ),
                ),
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
              FilledButton.icon(
                onPressed: _opening ? null : _openNew,
                icon: const Icon(Icons.add, size: 18),
                label: Text(tr(AppStrings.newQuotation)),
                style: FilledButton.styleFrom(
                  backgroundColor: _ink,
                  foregroundColor: AppColors.white,
                  minimumSize: const Size.fromHeight(52),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                tr(AppStrings.newOrderNote),
                textAlign: TextAlign.center,
                style: _qText(size: 9, color: _note),
              ),
            ],
          ),
        ),
      ],
    );
  }

  String _listDate(String raw) {
    final text = raw.trim();
    if (text.isEmpty) return '';
    final head = text.length >= 10 ? text.substring(0, 10) : text;
    final parts = head.split('-');
    if (parts.length != 3) return text;
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    final month = int.tryParse(parts[1]) ?? 0;
    final day = int.tryParse(parts[2]) ?? 0;
    if (month < 1 || month > 12 || day < 1) return text;
    return '$day ${months[month - 1]} ${parts[0]}';
  }

  String _weight(String raw) {
    final value = double.tryParse(raw.trim());
    if (value == null) return raw.trim().isEmpty ? '—' : raw.trim();
    return value.toStringAsFixed(3);
  }

  Widget _quotationCard(QuotationSummary row) {
    final number = row.number.isEmpty ? '${row.id}' : row.number;
    final customer = row.customerName.isEmpty ? '—' : row.customerName;
    final when = _listDate(row.date);
    final branch = row.branch.trim().isEmpty ? '—' : row.branch.trim();
    final pieces = row.pieces;
    final gross = _weight(row.gross);
    final net = _weight(row.net);
    final amount = row.amount.trim();
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
                  onTap: () => _openExisting(row),
                  child: Padding(
                    padding: const EdgeInsets.only(top: 8, bottom: 6),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(customer, style: _qText(size: 15, weight: FontWeight.w600)),
                        const SizedBox(height: 4),
                        Text(
                          when.isEmpty ? '$number\n$branch' : '$number · $when\n$branch',
                          style: _qText(size: 10, color: const Color(0xFF7B7467), height: 1.7),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              IconButton(
                tooltip: tr(AppStrings.moreActions),
                onPressed: () => _rowActions(row),
                icon: const Icon(Icons.more_horiz, size: 18),
              ),
            ],
          ),
          const Divider(height: 16, color: Color(0xFFEEE9DF)),
          Row(
            children: [
              Expanded(
                child: Text(
                  '$pieces ${pieces == 1 ? tr(AppStrings.piece) : tr(AppStrings.pieces)}'
                  ' · ${tr(AppStrings.grossShort)} $gross g'
                  '${net == '—' ? '' : ' · ${tr(AppStrings.netWeight)} $net g'}',
                  style: _qText(size: 11, color: const Color(0xFF685F4E)),
                ),
              ),
              if (amount.isNotEmpty)
                Text(amount, style: _qText(size: 11, weight: FontWeight.w600, color: const Color(0xFF685F4E))),
            ],
          ),
        ],
      ),
    );
  }

  void _rowActions(QuotationSummary row) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: _surface,
      builder: (context) {
        return oqDirection(SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                title: Text(tr('Edit'), style: _qText(size: 15, weight: FontWeight.w600)),
                onTap: () {
                  Navigator.pop(context);
                  _openExisting(row);
                },
              ),
              ListTile(
                title: Text(tr('Print'), style: _qText(size: 15, weight: FontWeight.w600)),
                onTap: () {
                  Navigator.pop(context);
                  _print(row);
                },
              ),
              ListTile(
                title: Text(tr('Delete'), style: _qText(size: 15, weight: FontWeight.w600, color: const Color(0xFFB42318))),
                onTap: () {
                  Navigator.pop(context);
                  _delete(row);
                },
              ),
            ],
          ),
        ));
      },
    );
  }

  Future<void> _print(QuotationSummary row) async {
    if (_opening || row.id == 0) return;
    final choice = await askPrintChoice(context);
    if (choice == null || !mounted) return;
    setState(() => _opening = true);
    final result = await Injection.quotations.loadQuotation(
      clientCode: _clientCode,
      id: row.id,
    );
    if (!mounted) return;
    setState(() => _opening = false);
    if (result case Error(:final failure)) {
      _toast(failure.message);
      return;
    }
    final loaded = (result as Success<QuotationDetail>).data;
    final detail = loaded.customer.name.trim().isNotEmpty
        ? loaded
        : QuotationDetail(
            id: loaded.id,
            number: loaded.number,
            customer: CustomerRecord(
              id: loaded.customer.id,
              name: row.customerName,
              mobile: loaded.customer.mobile,
              email: loaded.customer.email,
            ),
            items: loaded.items,
            gstApplied: loaded.gstApplied,
            source: loaded.source,
          );
    final company = await Injection.quotations.companyProfile(_clientCode);
    if (!mounted) return;
    final profile = company is Success<({String name, String address, String gst})>
        ? company.data
        : (name: '', address: '', gst: '');
    final copy = PrintCopy(
      detail: detail,
      companyName: profile.name,
      companyAddress: profile.address,
      gstNumber: profile.gst,
      gstFraction: detail.gstApplied ? 0.03 : 0,
    );
    try {
      if (choice == 'pdf') {
        await printQuotationPdf(copy);
      } else {
        await printQuotationOnPos(copy);
        if (!mounted) return;
        _toast(tr('Quotation sent to the POS printer'));
      }
    } catch (error) {
      if (!mounted) return;
      _toast('$error'.replaceFirst('Exception: ', ''));
    }
  }

  Future<void> _delete(QuotationSummary row) async {
    if (_opening || row.id == 0) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => oqDirection(AlertDialog(
        title: Text(tr('Delete quotation'), style: _qText(size: 18, weight: FontWeight.w700)),
        content: Text(
          '${tr('Delete quotation')} ${row.number.isEmpty ? row.id : row.number}?',
          style: _qText(size: 14),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text(tr('Cancel'))),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: const Color(0xFFB42318)),
            onPressed: () => Navigator.pop(context, true),
            child: Text(tr('Delete')),
          ),
        ],
      )),
    );
    if (confirmed != true || !mounted) return;
    final result = await Injection.quotations.deleteQuotation(
      clientCode: _clientCode,
      id: row.id,
    );
    if (!mounted) return;
    switch (result) {
      case Success():
        _showQuotations();
        _toast(tr('Quotation deleted'));
      case Error(:final failure):
        _toast(failure.message);
    }
  }

  Widget _editor() {
    final count = _items.length;
    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
            children: [
              Text(
                _readingTag
                    ? (_seenTags == 0 ? tr('Scanning') : '${tr('Scan')} $_seenTags')
                    : tr('A price proposal. It does not move stock.'),
                style: _qText(size: 10, weight: FontWeight.w600, color: const Color(0xFF80745B), letterSpacing: 0.5),
              ),
              const SizedBox(height: 12),
              _CustomerChooser(
                customer: _customer,
                loading: _loadingCustomers,
                onTap: _chooseCustomer,
              ),
              const SizedBox(height: 10),
              _DetailsLink(
                branch: _branch.text,
                validUntil: _validUntil,
                onTap: _editDetails,
              ),
              Row(
                children: [
                  Expanded(child: _searchField()),
                  const SizedBox(width: 8),
                  Material(
                    color: const Color(0xFFEEE6D5),
                    borderRadius: BorderRadius.circular(11),
                    child: InkWell(
                      onTap: _openPicker,
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
              if (_suggestions.isNotEmpty) ...[
                const SizedBox(height: 8),
                for (final item in _suggestions) _suggestionTile(item),
              ],
              if (_readingTag) ...[
                const SizedBox(height: 10),
                Text(
                  _seenTags == 0 ? tr('Scanning') : '${tr('Scan')} $_seenTags',
                  style: _qText(size: 12, weight: FontWeight.w600, color: const Color(0xFF8A682B)),
                ),
              ],
              const SizedBox(height: 14),
              Row(
                children: [
                  Text(
                    tr(AppStrings.selectedJewellery).toUpperCase(),
                    style: _qText(size: 12, weight: FontWeight.w700, letterSpacing: 0.4),
                  ),
                  const Spacer(),
                  Text(
                    '$count ${count == 1 ? tr(AppStrings.piece) : tr(AppStrings.pieces)}',
                    style: _qText(size: 12, color: _muted),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              if (_items.isEmpty)
                _empty(tr(AppStrings.noPiecesYet), tr(AppStrings.scanOrSelect))
              else
                for (final item in _items)
                  _pieceCard(item),
              TextButton.icon(
                onPressed: _openPicker,
                icon: const Icon(Icons.add, size: 16),
                label: Text(tr(AppStrings.addAnotherPiece), style: _qText(size: 13, weight: FontWeight.w600)),
              ),
              const _PricePending(),
              const SizedBox(height: 8),
              Text(
                tr('A price proposal. It does not move stock.'),
                style: _qText(size: 12, color: _muted),
              ),
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
                  Text('$count', style: _qText(size: 14, weight: FontWeight.w700)),
                  Text(' ${tr(AppStrings.pieces)}', style: _qText(size: 13, color: _muted)),
                  const Spacer(),
                  Text(
                    '${tr(AppStrings.grossShort)} ${_gross.toStringAsFixed(3)} g',
                    style: _qText(size: 13),
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
                      onPressed: _readingTag ? null : _readTagIntoQuotation,
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
                          Icon(_readingTag ? Icons.pause : Icons.document_scanner_outlined, size: 18),
                          Text(
                            _readingTag ? tr('Scanning') : tr(AppStrings.scan),
                            style: _qText(size: 9, weight: FontWeight.w600, color: _gold),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: count == 0 ? null : _review,
                      icon: const Icon(Icons.arrow_forward, size: 18),
                      label: Text(tr(AppStrings.reviewQuotation)),
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
              Text(
                tr('Draft only. No stock or order is changed.'),
                textAlign: TextAlign.center,
                style: _qText(size: 9, color: _note),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _searchField() {
    return TextField(
      controller: _lookup,
      onChanged: _onLookupChanged,
      onSubmitted: (_) => _scanLookup(),
      style: _qText(size: 12),
      decoration: InputDecoration(
        hintText: tr(AppStrings.rfidOrItem),
        hintStyle: _qText(size: 12, color: _searchIcon),
        prefixIcon: const Icon(Icons.search, size: 18, color: _searchIcon),
        filled: true,
        fillColor: AppColors.white,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(vertical: 14),
        border: _qBorder(_searchLine),
        enabledBorder: _qBorder(_searchLine),
        focusedBorder: _qBorder(const Color(0xFF967431)),
      ),
    );
  }

  Widget _suggestionTile(StockItem item) {
    final added = _items.any((current) => current.identity == item.identity);
    final name = item.name.isEmpty ? item.itemCode : item.name;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      enabled: !added,
      leading: _thumb(name),
      title: Text('${item.itemCode} · $name', style: _qText(size: 13, weight: FontWeight.w600)),
      subtitle: Text(
        '${tr(AppStrings.grossShort)} ${item.gross.isEmpty ? '—' : item.gross} g',
        style: _qText(size: 11, color: _muted),
      ),
      trailing: Icon(added ? Icons.check : Icons.add, color: _gold),
      onTap: added ? null : () => _addItem(item),
    );
  }

  Widget _pieceCard(StockItem item) {
    final name = item.name.isEmpty ? item.itemCode : item.name;
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
          _thumb(name),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name, style: _qText(size: 13, weight: FontWeight.w600)),
                Text(
                  '${item.itemCode} · ${tr(AppStrings.grossShort)} ${item.gross.isEmpty ? '—' : item.gross} g\n'
                  '${tr(AppStrings.netWeight)} ${item.net.isEmpty ? '—' : item.net}${item.net.isEmpty ? '' : ' g'} · RFID ${item.rfid.isEmpty ? '—' : item.rfid}',
                  style: _qText(size: 10, color: const Color(0xFF7A705F), height: 1.6),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: tr(AppStrings.removeThisPiece),
            onPressed: () => setState(() => _items.remove(item)),
            icon: const Icon(Icons.delete_outline, size: 18, color: Color(0xFFA27361)),
          ),
        ],
      ),
    );
  }

  Widget _empty(String title, String body) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 28),
      child: Column(
        children: [
          Text(title, textAlign: TextAlign.center, style: _qText(size: 16, weight: FontWeight.w700)),
          const SizedBox(height: 6),
          Text(body, textAlign: TextAlign.center, style: _qText(size: 12, color: _muted, height: 1.5)),
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
        style: _qText(size: 16, weight: FontWeight.w700, color: _gold),
      ),
    );
  }

  Future<void> _chooseCustomer() async {
    final selected = await showModalBottomSheet<CustomerRecord>(
      context: context,
      isScrollControlled: true,
      builder: (context) => oqDirection(_CustomerSheet(
        index: _customers,
        clientCode: _clientCode,
        onCreated: (record) {
          setState(() => _customers = _customers.add(record));
        },
      )),
    );
    if (selected != null) setState(() => _customer = selected);
  }

  Future<void> _editDetails() async {
    final branch = TextEditingController(text: _branch.text);
    final reference = TextEditingController(text: _reference.text);
    final notes = TextEditingController(text: _notes.text);
    var docDate = _docDate;
    var validUntil = _validUntil;
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setSheet) {
            return oqDirection(Padding(
              padding: EdgeInsets.fromLTRB(20, 16, 20, 16 + MediaQuery.viewInsetsOf(context).bottom),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(tr('Document details'), style: _qText(size: 18, weight: FontWeight.w700)),
                  const SizedBox(height: 12),
                  TextField(controller: branch, style: _qText(size: 14), decoration: _qInput(tr('Branch'))),
                  TextField(
                    readOnly: true,
                    style: _qText(size: 14),
                    decoration: _qInput(tr('Document date'), hint: _formatDate(docDate)),
                    onTap: () async {
                      final picked = await showDatePicker(
                        context: context,
                        firstDate: DateTime(2020),
                        lastDate: DateTime(2100),
                        initialDate: docDate,
                      );
                      if (picked != null) setSheet(() => docDate = picked);
                    },
                  ),
                  TextField(
                    readOnly: true,
                    style: _qText(size: 14),
                    decoration: _qInput(tr('Valid until'), hint: _formatDate(validUntil)),
                    onTap: () async {
                      final picked = await showDatePicker(
                        context: context,
                        firstDate: DateTime(2020),
                        lastDate: DateTime(2100),
                        initialDate: validUntil,
                      );
                      if (picked != null) setSheet(() => validUntil = picked);
                    },
                  ),
                  TextField(controller: reference, style: _qText(size: 14), decoration: _qInput(tr('Reference'))),
                  TextField(controller: notes, style: _qText(size: 14), decoration: _qInput(tr('Notes'))),
                  const SizedBox(height: 12),
                  FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF20201E),
                      foregroundColor: AppColors.white,
                      minimumSize: const Size.fromHeight(52),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    onPressed: () {
                      if (validUntil.isBefore(docDate)) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text(tr('Valid-until date cannot be before the document date.'))),
                        );
                        return;
                      }
                      Navigator.pop(context, true);
                    },
                    child: Text(tr('Apply details')),
                  ),
                ],
              ),
            ));
          },
        );
      },
    );
    if (saved == true && mounted) {
      setState(() {
        _branch.text = branch.text.trim();
        _reference.text = reference.text.trim();
        _notes.text = notes.text.trim();
        _docDate = docDate;
        _validUntil = validUntil;
      });
    }
    branch.dispose();
    reference.dispose();
    notes.dispose();
  }

  void _review() {
    if (_customer == null || _items.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(tr('Choose a customer and add at least one piece.'))),
      );
      return;
    }
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) {
        return oqDirection(Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(tr('Review quotation'), style: _qText(size: 18, weight: FontWeight.w700)),
              const SizedBox(height: 12),
              _reviewLine(tr('Customer'), _customer!.name),
              _reviewLine(tr('Branch'), _branch.text.isEmpty ? tr('Not set') : _branch.text),
              _reviewLine(tr('Valid until'), _formatDate(_validUntil)),
              _reviewLine(tr('Pieces / gross'), '${_items.length} / ${_gross.toStringAsFixed(3)} g'),
              const SizedBox(height: 8),
              const _PricePending(),
              const SizedBox(height: 8),
              Text(
                tr('A price proposal. It does not move stock.'),
                style: _qText(size: 12, color: const Color(0xFF6D6B66)),
              ),
              const SizedBox(height: 12),
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF20201E),
                  foregroundColor: AppColors.white,
                  minimumSize: const Size.fromHeight(52),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                onPressed: _saving ? null : _saveQuotation,
                child: Text(_quotationId > 0 ? tr('Update') : tr('Save')),
              ),
              const SizedBox(height: 8),
              Text(
                tr('Draft only. No stock or order is changed.'),
                textAlign: TextAlign.center,
                style: _qText(size: 12, color: const Color(0xFF6D6B66)),
              ),
            ],
          ),
        ));
      },
    );
  }

  Future<void> _saveQuotation() async {
    final customer = _customer;
    if (customer == null || _items.isEmpty || _saving) return;
    final editing = _quotationId > 0;
    setState(() => _saving = true);
    final result = await Injection.quotations.saveQuotation(
      clientCode: _clientCode,
      customer: customer,
      items: List<StockItem>.from(_items),
      gstApplied: false,
      gstRate: 0,
      id: _quotationId,
      number: _quotationNo,
      source: _source,
    );
    if (!mounted) return;
    setState(() => _saving = false);
    switch (result) {
      case Success(:final data):
        Injection.quotations.rememberQuotationCustomer(
          number: data,
          customerName: customer.name,
        );
        Injection.quotations.saveDraft(
          QuotationDraft(
            customerName: customer.name,
            items: List<StockItem>.from(_items),
            posMode: false,
            createdAt: DateTime.now(),
          ),
        );
        if (!mounted) return;
        final message = editing
            ? 'Quotation updated successfully'
            : (data.isEmpty ? 'Quotation saved' : 'Quotation $data saved');
        Navigator.pop(context);
        if (widget.detail != null) {
          Navigator.pop(context, message);
          return;
        }
        _clearDraft();
        _goList();
        _toast(message);
      case Error(:final failure):
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(failure.message)));
    }
  }
}

Widget _reviewLine(String label, String value) {
  return Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: Row(
      children: [
        Expanded(child: Text(label, style: _qText(size: 13, color: const Color(0xFF6D6B66)))),
        Text(value, style: _qText(size: 13, weight: FontWeight.w700)),
      ],
    ),
  );
}

String _formatDate(DateTime date) {
  return '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';
}

class _CustomerChooser extends StatelessWidget {
  const _CustomerChooser({
    required this.customer,
    required this.loading,
    required this.onTap,
  });

  final CustomerRecord? customer;
  final bool loading;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final name = customer != null && customer!.name.isNotEmpty ? customer!.name : tr(AppStrings.chooseCustomer);
    return Material(
      color: const Color(0xFFF8F2E6),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(13),
        side: const BorderSide(color: Color(0xFFDFD3B8)),
      ),
      child: InkWell(
        onTap: onTap,
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
                    Text(tr(AppStrings.customerLabel), style: _qText(size: 9, color: const Color(0xFF80704F))),
                    Text(
                      loading ? tr(AppStrings.chooseCustomer) : name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: _qText(size: 14, weight: FontWeight.w600),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.expand_more, color: Color(0xFF8B6A2E)),
            ],
          ),
        ),
      ),
    );
  }
}

class _DetailsLink extends StatelessWidget {
  const _DetailsLink({
    required this.branch,
    required this.validUntil,
    required this.onTap,
  });

  final String branch;
  final DateTime validUntil;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    branch.isEmpty ? tr(AppStrings.chooseBranch) : branch,
                    style: _qText(size: 14, weight: FontWeight.w600),
                  ),
                  Text(
                    '${tr('Valid until')} ${_formatDate(validUntil)}',
                    style: _qText(size: 11, color: const Color(0xFF6D6B66)),
                  ),
                ],
              ),
            ),
            Text(tr('Details'), style: _qText(size: 12, color: const Color(0xFF85652C))),
            const Icon(Icons.tune, size: 16, color: Color(0xFF85652C)),
          ],
        ),
      ),
    );
  }
}

class _PricePending extends StatelessWidget {
  const _PricePending();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF0EBE0),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE3D9C4)),
      ),
      child: Row(
        children: [
          Expanded(child: Text(tr('Document amount'), style: _qText(size: 13))),
          Text(tr('Pricing pending'), style: _qText(size: 13, weight: FontWeight.w700)),
        ],
      ),
    );
  }
}

class _CustomerSheet extends StatefulWidget {
  const _CustomerSheet({
    required this.index,
    required this.clientCode,
    required this.onCreated,
  });

  final CustomerIndex index;
  final String clientCode;
  final ValueChanged<CustomerRecord> onCreated;

  @override
  State<_CustomerSheet> createState() => _CustomerSheetState();
}

class _CustomerSheetState extends State<_CustomerSheet> {
  final TextEditingController _query = TextEditingController();
  late List<CustomerRecord> _matches;

  @override
  void initState() {
    super.initState();
    _matches = widget.index.search('');
  }

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final height = MediaQuery.sizeOf(context).height * 0.7;
    return SizedBox(
      height: height,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: TextField(
              controller: _query,
              style: _qText(size: 12),
              decoration: InputDecoration(
                hintText: tr('Customer name'),
                hintStyle: _qText(size: 12, color: const Color(0xFF8C7B57)),
                prefixIcon: const Icon(Icons.search, size: 18, color: Color(0xFF8C7B57)),
                filled: true,
                fillColor: AppColors.white,
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(vertical: 14),
                border: _qBorder(const Color(0xFFDAD5CA)),
                enabledBorder: _qBorder(const Color(0xFFDAD5CA)),
                focusedBorder: _qBorder(const Color(0xFF967431)),
              ),
              onChanged: (value) {
                setState(() {
                  _matches = widget.index.search(
                    value,
                    limit: AppConstants.customerResultLimit,
                  );
                });
              },
            ),
          ),
          Expanded(
            child: ListView.builder(
              itemCount: _matches.length,
              itemBuilder: (context, index) {
                final customer = _matches[index];
                return ListTile(
                  leading: const Icon(Icons.person_outline),
                  title: Text(customer.name, style: _qText(size: 14, weight: FontWeight.w600)),
                  subtitle: Text(
                    customer.mobile.isEmpty ? tr('No mobile') : customer.mobile,
                    style: _qText(size: 11, color: const Color(0xFF6D6B66)),
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.pop(context, customer),
                );
              },
            ),
          ),
          SafeArea(
            top: false,
            child: TextButton.icon(
              onPressed: () => _addCustomer(context),
              icon: const Icon(Icons.add),
              label: Text(tr(AppStrings.addCustomer), style: _qText(size: 13, weight: FontWeight.w600)),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _addCustomer(BuildContext context) async {
    final created = await Navigator.push<CustomerRecord>(
      context,
      MaterialPageRoute(builder: (_) => const AddCustomerPage()),
    );
    if (created == null || !context.mounted) return;
    widget.onCreated(created);
    Navigator.pop(context, created);
  }
}

TextStyle _qText({
  required double size,
  FontWeight weight = FontWeight.w400,
  Color color = const Color(0xFF20201F),
  double? height,
  double? letterSpacing,
}) {
  return TextStyle(
    fontFamily: 'Inter',
    fontFamilyFallback: const ['Noto Sans Devanagari', 'Noto Sans Arabic', 'Noto Naskh Arabic', 'Roboto'],
    fontSize: size,
    fontWeight: weight,
    color: color,
    height: height,
    letterSpacing: letterSpacing,
    decoration: TextDecoration.none,
  );
}

InputDecoration _qInput(String label, {String? hint}) {
  return InputDecoration(
    labelText: label,
    hintText: hint,
    labelStyle: _qText(size: 12, color: const Color(0xFF6D6B66)),
    hintStyle: _qText(size: 14),
    filled: true,
    fillColor: AppColors.white,
    border: _qBorder(const Color(0xFFD5CBBC)),
    enabledBorder: _qBorder(const Color(0xFFD5CBBC)),
    focusedBorder: _qBorder(const Color(0xFF967431)),
  );
}

OutlineInputBorder _qBorder(Color color) {
  return OutlineInputBorder(
    borderRadius: const BorderRadius.all(Radius.circular(10)),
    borderSide: BorderSide(color: color),
  );
}
