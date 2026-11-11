import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/di/injection.dart';
import '../../../../core/rfid/rfid_service.dart';
import '../../../../core/session/app_session.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/result.dart';
import '../../domain/entities/customer_record.dart';
import '../../domain/entities/quotation_detail.dart';
import '../../domain/entities/quotation_draft.dart';
import '../../domain/entities/quotation_field.dart';
import '../../domain/quotation_math.dart';
import '../../domain/entities/stock_item.dart';
import '../widgets/quotation_items_popup.dart';
import '../widgets/stock_picker_sheet.dart';
import 'add_customer_page.dart';

class PosQuotationPage extends StatefulWidget {
  const PosQuotationPage({super.key, this.detail, this.orderMode = false});

  final QuotationDetail? detail;

  /// Permission-driven order form. Quotation save and fields stay unchanged.
  final bool orderMode;

  @override
  State<PosQuotationPage> createState() => _PosQuotationPageState();
}

class _PosQuotationPageState extends State<PosQuotationPage> {
  final Map<String, TextEditingController> _fields = {};
  final TextEditingController _lookup = TextEditingController();
  final TextEditingController _customerName = TextEditingController();
  List<QuotationField> _layout = const [];
  CustomerIndex _customers = CustomerIndex(const []);
  CustomerRecord? _customer;
  final List<StockItem> _items = [];
  var _loading = true;
  var _saving = false;
  var _readingTag = false;
  var _seenTags = 0;
  final _rfidTrigger = RfidTrigger();
  final _tray = RfidTrayScan();
  var _summaryPopup = false;
  var _gstOn = true;
  String? _error;
  int _quotationId = 0;
  String _quotationNo = '';
  Map<String, dynamic> _source = const {};

  String get _clientCode => AppSession.clientCode;
  String get _userId => AppSession.userId;
  bool get _editing => _quotationId > 0;

  List<QuotationField> get _gridFields {
    final chosen = <String, QuotationField>{};
    final order = <String>[];
    for (final field in _layout) {
      if (field.isCustomer || field.isItemLookup || field.isAction || field.isChrome) {
        continue;
      }
      final id = field.labelToken.isEmpty ? field.keyToken : field.labelToken;
      if (id.isEmpty) continue;
      final current = chosen[id];
      if (current == null) {
        chosen[id] = field;
        order.add(id);
        continue;
      }
      if (current.showsAsValue && !field.showsAsValue) {
        chosen[id] = field;
      }
    }
    return [for (final id in order) chosen[id]!];
  }

  String get _gstLabel {
    for (final field in _layout) {
      if (!field.isGstLabel) continue;
      final label = field.label.trim();
      if (label.isNotEmpty) return label;
    }
    return 'GST 3%';
  }

  double get _gstRate {
    final match = RegExp(r'(\d+(?:\.\d+)?)').firstMatch(_gstLabel);
    final percent = match == null ? 3.0 : (double.tryParse(match.group(1)!) ?? 3);
    return percent / 100;
  }

  @override
  void initState() {
    super.initState();
    _rfidTrigger.attach(_readTagIntoQuotation);
    if (_clientCode.isNotEmpty) {
      unawaited(Injection.quotations.warmLabeledStock(_clientCode, () {}));
    }
    _load();
  }

  @override
  void dispose() {
    _rfidTrigger.detach();
    _tray.cancel();
    for (final controller in _fields.values) {
      controller.dispose();
    }
    _lookup.dispose();
    _customerName.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    if (_clientCode.isEmpty || _userId.isEmpty) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = widget.orderMode ? 'Sign in to load orders.' : 'Sign in to load quotations.';
      });
      return;
    }
    final fields = await Injection.quotations.loadPosFields(
      clientCode: _clientCode,
      userId: _userId,
      pageName: widget.orderMode ? AppConstants.orderPageName : AppConstants.quotationPageName,
    );
    final customers = await Injection.quotations.loadCustomers(_clientCode);
    if (!mounted) return;
    setState(() {
      _loading = false;
      switch (fields) {
        case Success(:final data):
          _layout = data;
          for (final field in data) {
            _fields.putIfAbsent(field.key, TextEditingController.new);
          }
        case Error(:final failure):
          _error = failure.message;
      }
      if (customers case Success(:final data)) _customers = data;
      final detail = widget.detail;
      if (detail != null) {
        _quotationId = detail.id;
        _quotationNo = detail.number;
        _source = detail.source;
        _gstOn = detail.gstApplied;
        _customer = detail.customer;
        _customerName.text = detail.customer.name;
        _items
          ..clear()
          ..addAll(detail.items);
        if (detail.items.isNotEmpty) {
          final item = detail.items.first;
          _lookup.text = item.itemCode.isEmpty ? item.rfid : item.itemCode;
          for (final field in _gridFields) {
            final value = _valueFor(field, item);
            if (value == null) continue;
            _fields[field.key]?.text = value;
          }
        }
      }
    });
  }

  Future<void> _pickItem() async {
    final item = await showStockPicker(
      context: context,
      clientCode: _clientCode,
      initialQuery: _lookup.text,
    );
    if (item == null || !mounted) return;
    _useItem(item);
  }

  Future<void> _readTagIntoQuotation() async {
    if (_readingTag || _saving) return;
    final typed = _lookup.text.trim();
    if (!RfidService.instance.isSupported) {
      if (typed.isEmpty) {
        await _pickItem();
        return;
      }
      await _scanLookup();
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
        await _scanLookup();
        return;
      }
      _toast(read.error ?? 'No tag found');
      return;
    }

    final matches = await Injection.quotations.stockForTags(_clientCode, read.codes);
    if (!mounted) return;
    final added = <StockItem>[];
    for (final item in matches) {
      if (_items.any((current) => current.identity == item.identity)) continue;
      _useItem(item);
      added.add(item);
    }
    setState(() => _readingTag = false);
    if (added.isEmpty) {
      _toast(matches.isEmpty ? 'Tags scanned but items were not found in stock.' : 'Already on this quotation');
      return;
    }
    await showQuotationItemsPopup(
      context,
      items: added,
      gstApplied: _gstOn,
      gstFraction: _gstRate,
    );
  }

  Future<void> _scanLookup() async {
    final query = _lookup.text.trim();
    if (query.isEmpty || _clientCode.isEmpty) {
      await _pickItem();
      return;
    }
    final result = await Injection.quotations.searchStock(
      clientCode: _clientCode,
      query: query,
    );
    if (!mounted) return;
    switch (result) {
      case Success(:final data) when data.isNotEmpty:
        _useItem(data.first);
      case Success():
        _toast('No matching item');
      case Error(:final failure):
        _toast(failure.message);
    }
  }

  void _useItem(StockItem raw) {
    final item = withLinePrice(raw, priceLine(raw, applyGst: false, gstFraction: 0));
    _lookup.text = item.itemCode.isEmpty ? item.rfid : item.itemCode;
    for (final field in _gridFields) {
      final value = _valueFor(field, item);
      if (value == null) continue;
      _fields[field.key]?.text = value;
    }
    if (_items.any((current) => current.identity == item.identity)) {
      setState(() {});
      return;
    }
    setState(() => _items.add(item));
  }

  String? _valueFor(QuotationField field, StockItem item) {
    const aliases = <String, List<String>>{
      'designname': ['designname', 'design'],
      'purity': ['purity'],
      'pieces': ['pieces', 'pcs', 'piece'],
      'grosswt': ['grosswt', 'grossweight', 'gross'],
      'stonewt': ['stonewt', 'stoneweight', 'stone'],
      'diamondwt': ['diamondwt', 'diamondweight', 'diamond'],
      'netwt': ['netwt', 'netweight', 'netwtgm', 'net'],
      'making': ['making', 'makingpercent', 'makingplus'],
      'diamondpcs': ['diamondpcs', 'diamondpieces'],
      'rate': ['rate'],
      'stoneamt': ['stoneamt', 'stoneamount'],
      'diamondamt': ['diamondamt', 'diamondamount'],
      'metalamt': ['metalamt', 'metalamount'],
      'makingamt': ['makingamt', 'makingamount'],
      'itemamt': ['itemamt', 'itemamount', 'amount'],
    };
    final names = <String>{
      field.keyToken,
      field.labelToken,
      ...aliases[field.keyToken] ?? const <String>[],
      ...aliases[field.labelToken] ?? const <String>[],
    };
    for (final name in names) {
      final value = item.extras[name];
      if (value != null && value.isNotEmpty) return value;
    }
    if (field.keyToken == 'pieces' || field.labelToken == 'pieces') return '1';
    return null;
  }

  List<StockItem> get _formItems => [for (final item in _items) _withGrid(item)];

  double get _itemAmount {
    var total = 0.0;
    for (final item in _formItems) {
      final line = priceLine(item, applyGst: _gstOn, gstFraction: _gstRate);
      total += line.mrp ? line.total : line.item;
    }
    return total;
  }

  double get _gst {
    var total = 0.0;
    for (final item in _formItems) {
      final line = priceLine(item, applyGst: _gstOn, gstFraction: _gstRate);
      if (!line.mrp) total += line.gst;
    }
    return total;
  }

  double get _gross {
    var total = 0.0;
    for (final item in _formItems) {
      total += double.tryParse(item.gross) ?? 0;
    }
    return total;
  }

  bool _isFormItem(StockItem item) {
    final shown = _lookup.text.trim();
    if (shown.isEmpty) return false;
    return shown == item.itemCode || shown == item.rfid || shown == item.identity;
  }

  StockItem _withGrid(StockItem item) {
    if (!_isFormItem(item)) return item;
    final extras = Map<String, String>.from(item.extras);
    var gross = item.gross;
    var net = item.net;
    var design = item.design;
    for (final field in _gridFields) {
      if (field.showsAsValue || field.readOnly) continue;
      final text = _fields[field.key]?.text.trim() ?? '';
      if (text.isEmpty) continue;
      final tokens = <String>{
        field.keyToken,
        field.labelToken,
        ?_inputKey(field.keyToken),
        ?_inputKey(field.labelToken),
      };
      for (final token in tokens) {
        if (token.isEmpty) continue;
        extras[token] = text;
      }
      final key = _inputKey(field.labelToken) ?? _inputKey(field.keyToken);
      if (key == 'grosswt') gross = text;
      if (key == 'netwt') net = text;
      if (key == 'designname') design = text;
    }
    return StockItem(
      itemCode: item.itemCode,
      name: item.name,
      rfid: item.rfid,
      gross: gross,
      net: net,
      design: design,
      extras: extras,
    );
  }

  String? _inputKey(String token) {
    const keys = {
      'gross': 'grosswt',
      'grosswt': 'grosswt',
      'grossweight': 'grosswt',
      'stonewt': 'stonewt',
      'stoneweight': 'stonewt',
      'diamondwt': 'diamondwt',
      'diamondweight': 'diamondwt',
      'net': 'netwt',
      'netwt': 'netwt',
      'netweight': 'netwt',
      'rate': 'rate',
      'metalrate': 'rate',
      'goldrate': 'rate',
      'making': 'making',
      'makingcharge': 'making',
      'makingpergram': 'makingpergram',
      'makingpercent': 'makingpercent',
      'makingpercentage': 'makingpercent',
      'makingfixedamt': 'makingfixedamt',
      'fixmaking': 'makingfixedamt',
      'makingfixedwastage': 'makingfixedwastage',
      'fixwastage': 'makingfixedwastage',
      'stoneamt': 'stoneamt',
      'stoneamount': 'stoneamt',
      'diamondamt': 'diamondamt',
      'diamondamount': 'diamondamt',
      'pieces': 'pieces',
      'pcs': 'pieces',
      'purity': 'purity',
      'design': 'designname',
      'designname': 'designname',
      'hsn': 'hsncode',
      'hsncode': 'hsncode',
      'diamondpcs': 'diamondpcs',
      'mrp': 'mrp',
    };
    return keys[token];
  }

  void _refreshCalculatedFields() {
    final index = _items.indexWhere(_isFormItem);
    if (index < 0) return;
    final current = _withGrid(_items[index]);
    final priced = withLinePrice(
      current,
      priceLine(current, applyGst: false, gstFraction: 0),
    );
    for (final field in _gridFields) {
      if (!field.showsAsValue && !field.readOnly) continue;
      final value = _valueFor(field, priced);
      if (value == null) continue;
      final controller = _fields[field.key];
      if (controller != null && controller.text != value) controller.text = value;
    }
  }

  Future<void> _save() async {
    if (_saving) return;
    final customer = _customer;
    if (customer == null) {
      _toast('Select a customer');
      return;
    }
    if (_items.isEmpty) {
      _toast('Add at least one item');
      return;
    }
    setState(() => _saving = true);
    final editing = _editing;
    if (widget.orderMode) {
      final result = await Injection.orders.saveOrder(
        clientCode: _clientCode,
        customer: customer,
        items: List<StockItem>.from(_formItems),
        gstApplied: _gstOn,
        gstRate: _gstRate,
        id: _quotationId,
        number: _quotationNo,
        source: _source,
      );
      if (!mounted) return;
      setState(() => _saving = false);
      switch (result) {
        case Success(:final data):
          Injection.orders.rememberCustomer(number: data, customerName: customer.name);
          final message = editing
              ? 'Order updated successfully'
              : (data.isEmpty ? 'Order saved' : 'Order $data saved');
          Navigator.pop(context, message);
        case Error(:final failure):
          _toast(failure.message);
      }
      return;
    }
    final result = await Injection.quotations.saveQuotation(
      clientCode: _clientCode,
      customer: customer,
      items: List<StockItem>.from(_formItems),
      gstApplied: _gstOn,
      gstRate: _gstRate,
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
            items: List<StockItem>.from(_formItems),
            posMode: true,
            createdAt: DateTime.now(),
          ),
        );
        final message = editing
            ? 'Quotation updated successfully'
            : (data.isEmpty ? 'Quotation saved' : 'Quotation $data saved');
        Navigator.pop(context, message);
      case Error(:final failure):
        _toast(failure.message);
    }
  }

  Future<void> _openSummaryPopup() async {
    if (_summaryPopup) return;
    setState(() => _summaryPopup = true);
    final items = List<StockItem>.from(_formItems);
    if (!mounted) return;
    if (items.isEmpty) {
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text('Items'),
          content: const Text('No items available yet. Add an item to view the summary.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('OK')),
          ],
        ),
      );
    } else {
      await showQuotationItemsPopup(
        context,
        items: items,
        gstApplied: _gstOn,
        gstFraction: _gstRate,
      );
    }
    if (mounted) setState(() => _summaryPopup = false);
  }

  void _toast(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.homeSurface,
      appBar: AppBar(
        elevation: 0,
        backgroundColor: AppColors.charcoal,
        foregroundColor: AppColors.white,
        title: Text(
          widget.orderMode
              ? (widget.detail == null ? 'Order' : 'Edit order')
              : (widget.detail == null ? 'Quotation' : 'Edit quotation'),
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        actions: [
          IconButton(
            onPressed: _openSummaryPopup,
            icon: const Icon(Icons.view_list_outlined),
            tooltip: 'Summary',
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppColors.goldText))
          : _error != null
          ? _ErrorState(
              message: _error!,
              onRetry: () {
                setState(() {
                  _loading = true;
                  _error = null;
                });
                _load();
              },
            )
          : Column(
              children: [
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(14, 14, 14, 18),
                    children: [
                      if (widget.orderMode || _layout.any((field) => field.isCustomer)) ...[
                        _customerTile(),
                        const SizedBox(height: 12),
                      ],
                      _lookupBar(),
                      const SizedBox(height: 16),
                      ..._rows(_gridFields),
                      const SizedBox(height: 8),
                      _summaryCard(),
                      const SizedBox(height: 14),
                      _gstRow(),
                    ],
                  ),
                ),
                _actions(),
              ],
            ),
    );
  }

  Widget _lookupBar() {
    final lookup = _layout.cast<QuotationField?>().firstWhere(
      (field) => field!.isItemLookup,
      orElse: () => null,
    );
    final hint = lookup?.placeholder.isNotEmpty == true
        ? lookup!.placeholder
        : 'Select tag number';
    return _labeledRow(
      label: lookup?.label.isNotEmpty == true ? lookup!.label : 'Tag Number',
      child: _borderedRow(
        controller: _lookup,
        hint: hint,
        onSubmitted: (_) => _scanLookup(),
        actions: [
          IconButton(
            onPressed: _readTagIntoQuotation,
            icon: const Icon(Icons.qr_code_scanner, color: AppColors.goldText),
            tooltip: 'Scan RFID tag',
          ),
          _roundAdd(_pickItem),
        ],
      ),
    );
  }

  List<Widget> _rows(List<QuotationField> fields) {
    final rows = <Widget>[];
    for (var index = 0; index < fields.length; index += 3) {
      final slice = fields.skip(index).take(3).toList();
      rows.add(
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (var slot = 0; slot < 3; slot++) ...[
                if (slot > 0) const SizedBox(width: 10),
                Expanded(
                  child: slot < slice.length
                      ? _control(slice[slot])
                      : const SizedBox.shrink(),
                ),
              ],
            ],
          ),
        ),
      );
    }
    return rows;
  }

  Widget _control(QuotationField field) {
    final controller = _fields[field.key]!;
    if (field.showsAsValue) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _header(field.label),
          const SizedBox(height: 4),
          Text(
            controller.text.isEmpty ? '—' : controller.text,
            maxLines: 1,
            softWrap: false,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: AppColors.charcoal, fontSize: 15, fontWeight: FontWeight.w600),
          ),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
        children: [
        _header(field.label),
        const SizedBox(height: 6),
        TextField(
          controller: controller,
          onChanged: (_) {
            _refreshCalculatedFields();
            setState(() {});
          },
          keyboardType: _numeric(field)
              ? const TextInputType.numberWithOptions(decimal: true)
              : TextInputType.text,
          inputFormatters: _numeric(field)
              ? [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))]
              : null,
          decoration: InputDecoration(
            filled: true,
            fillColor: Colors.white,
            isDense: true,
            hintText: field.placeholder,
            suffixText: field.suffix.isEmpty ? null : field.suffix,
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: AppColors.fieldBorder),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: AppColors.fieldBorder),
            ),
          ),
        ),
      ],
    );
  }

  Widget _header(String label) {
    return Text(
      _shortHeader(label),
      maxLines: 1,
      softWrap: false,
      overflow: TextOverflow.ellipsis,
      style: const TextStyle(color: AppColors.muted, fontSize: 12, height: 1.1),
    );
  }

  String _shortHeader(String label) {
    var text = label.replaceAll(RegExp(r'\s*\([^)]*\)'), '').replaceAll('+', '').trim();
    const words = <String, String>{
      'Design Name': 'Design',
      'Diamond': 'Dia',
      'Making': 'Mak',
      'Weight': 'Wt',
      'Amount': 'Amt',
      'Pieces': 'Pcs',
      'Percentage': '%',
      'Percent': '%',
    };
    for (final entry in words.entries) {
      text = text.replaceAll(entry.key, entry.value);
    }
    return text.replaceAll(RegExp(r'\s{2,}'), ' ').trim();
  }

  bool _numeric(QuotationField field) {
    final kind = '${field.type} ${field.keyToken} ${field.labelToken}'.toLowerCase();
    return kind.contains('number') ||
        kind.contains('decimal') ||
        kind.contains('amount') ||
        kind.contains('wt') ||
        kind.contains('rate') ||
        kind.contains('amt');
  }

  Widget _summaryCard() {
    return Material(
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: const BorderSide(color: AppColors.fieldBorder),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
        child: Column(
          children: [
            Row(
              children: [
                const Icon(Icons.receipt_long_outlined, color: AppColors.muted),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text('Summary', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                ),
                Switch(
                  value: _summaryPopup,
                  activeThumbColor: Colors.white,
                  activeTrackColor: AppColors.goldText,
                  onChanged: (value) {
                    if (value) {
                      _openSummaryPopup();
                    } else {
                      setState(() => _summaryPopup = false);
                    }
                  },
                ),
                IconButton(
                  tooltip: 'Summary',
                  onPressed: _openSummaryPopup,
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                  icon: const Icon(Icons.chevron_right, color: AppColors.muted),
                ),
              ],
            ),
            const Divider(height: 8),
            Row(
              children: [
                _metric('Qty', '${_items.length}'),
                _metric('Gross Wt', '${_gross.toStringAsFixed(3)} g'),
                _metric('Amount', '₹ ${_itemAmount.toStringAsFixed(2)}', alignEnd: true),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _metric(String label, String value, {bool alignEnd = false}) {
    return Expanded(
      child: Column(
        crossAxisAlignment: alignEnd ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(color: AppColors.muted, fontSize: 12)),
          const SizedBox(height: 4),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }

  Widget _gstRow() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Row(
            children: [
              Checkbox(
                value: _gstOn,
                activeColor: AppColors.goldText,
                onChanged: (value) => setState(() => _gstOn = value ?? false),
              ),
              Text(_gstLabel, style: const TextStyle(fontWeight: FontWeight.w700)),
            ],
          ),
        ),
        Expanded(child: _amountBox('GST Amt', _gst)),
        const SizedBox(width: 8),
        Expanded(child: _amountBox('Total (with GST)', _itemAmount + _gst)),
      ],
    );
  }

  Widget _amountBox(String label, double value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(color: AppColors.muted, fontSize: 12)),
        const SizedBox(height: 6),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.fieldBorder),
          ),
          child: Text(
            value.toStringAsFixed(2),
            textAlign: TextAlign.right,
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
        ),
      ],
    );
  }

  Widget _actions() {
    return Material(
      color: AppColors.homeSurface,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
          child: Row(
            children: [
              Expanded(child: _action('Cancel', Icons.close, AppColors.charcoal, () => Navigator.pop(context))),
              const SizedBox(width: 8),
              Expanded(
                child: _action(
                  _readingTag ? (_seenTags == 0 ? 'Scanning' : 'Scan $_seenTags') : 'Scan',
                  Icons.qr_code_scanner,
                  AppColors.charcoal,
                  _readingTag ? null : _readTagIntoQuotation,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _action(
                  _saving ? (_editing ? 'Updating' : 'Saving') : (_editing ? 'Update' : 'Save'),
                  Icons.save_outlined,
                  AppColors.charcoal,
                  _saving ? null : _save,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _action(String label, IconData icon, Color color, VoidCallback? onTap) {
    return FilledButton.icon(
      style: FilledButton.styleFrom(
        backgroundColor: color,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      onPressed: onTap,
      icon: Icon(icon, size: 18),
      label: Text(label),
    );
  }

  Widget _customerTile() {
    final customerField = _layout.cast<QuotationField?>().firstWhere(
      (field) => field!.isCustomer,
      orElse: () => null,
    );
    return _labeledRow(
      label: customerField?.label.isNotEmpty == true
          ? customerField!.label
          : (widget.orderMode ? 'Select customer' : 'Customer Name'),
      child: _borderedRow(
        controller: _customerName,
        hint: customerField?.placeholder.isNotEmpty == true
            ? customerField!.placeholder
            : 'Select customer',
        readOnly: true,
        onTap: _chooseCustomer,
        actions: [_roundAdd(_openAddCustomer)],
      ),
    );
  }

  Widget _labeledRow({required String label, required Widget child}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(color: AppColors.charcoal, fontSize: 14, fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        child,
      ],
    );
  }

  Widget _borderedRow({
    required TextEditingController controller,
    required String hint,
    required List<Widget> actions,
    bool readOnly = false,
    VoidCallback? onTap,
    ValueChanged<String>? onSubmitted,
  }) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.fieldBorder),
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: controller,
              readOnly: readOnly,
              onTap: onTap,
              textInputAction: TextInputAction.search,
              onSubmitted: onSubmitted,
              decoration: InputDecoration(
                hintText: hint,
                hintStyle: const TextStyle(color: AppColors.muted),
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              ),
            ),
          ),
          ...actions,
          const SizedBox(width: 6),
        ],
      ),
    );
  }

  Widget _roundAdd(VoidCallback onTap) {
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: Material(
        color: Colors.white,
        shape: const CircleBorder(side: BorderSide(color: AppColors.goldText, width: 1.4)),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: const SizedBox(
            width: 34,
            height: 34,
            child: Icon(Icons.add, size: 20, color: AppColors.goldText),
          ),
        ),
      ),
    );
  }

  Future<void> _openAddCustomer() async {
    final created = await Navigator.push<CustomerRecord>(
      context,
      MaterialPageRoute(builder: (_) => const AddCustomerPage()),
    );
    if (created == null || !mounted) return;
    setState(() {
      _customers = _customers.add(created);
      _customer = created;
      _customerName.text = created.name;
    });
  }

  Future<void> _chooseCustomer() async {
    final selected = await showModalBottomSheet<CustomerRecord>(
      context: context,
      isScrollControlled: true,
      builder: (context) => _PosCustomerSheet(index: _customers),
    );
    if (selected != null) {
      setState(() {
        _customer = selected;
        _customerName.text = selected.name;
      });
    }
  }
}

class _PosCustomerSheet extends StatefulWidget {
  const _PosCustomerSheet({required this.index});

  final CustomerIndex index;

  @override
  State<_PosCustomerSheet> createState() => _PosCustomerSheetState();
}

class _PosCustomerSheetState extends State<_PosCustomerSheet> {
  final TextEditingController _query = TextEditingController();
  late List<CustomerRecord> _matches = widget.index.search('');

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: MediaQuery.sizeOf(context).height * 0.7,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              controller: _query,
              decoration: const InputDecoration(
                hintText: 'Customer name',
                prefixIcon: Icon(Icons.search),
              ),
              onChanged: (value) {
                setState(() => _matches = widget.index.search(value));
              },
            ),
          ),
          Expanded(
            child: ListView.builder(
              itemCount: _matches.length,
              itemBuilder: (context, index) {
                final customer = _matches[index];
                return ListTile(
                  title: Text(customer.name),
                  subtitle: Text(customer.mobile),
                  onTap: () => Navigator.pop(context, customer),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            FilledButton(onPressed: onRetry, child: const Text('Retry')),
          ],
        ),
      ),
    );
  }
}
