import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/locale/oq_text.dart';
import '../../../../core/di/injection.dart';
import '../../../../core/rfid/rfid_service.dart';
import '../../../../core/session/app_session.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/result.dart';
import '../../domain/entities/customer_record.dart';
import '../../domain/entities/quotation_detail.dart';
import '../../domain/entities/quotation_draft.dart';
import '../../domain/entities/quotation_field.dart';
import '../../../orders/domain/order_math.dart';
import '../../domain/quotation_math.dart';
import '../../domain/entities/stock_item.dart';
import '../widgets/quotation_items_popup.dart';
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
  Timer? _tagSuggestTimer;
  var _tagSuggestToken = 0;
  List<StockItem> _suggestions = const [];
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
  var _orderRefreshQueued = false;
  QuotationField? _orderEditedField;
  Map<String, double> _purityRates = const {};
  List<({int id, String name})> _branches = const [];
  int _quotationBranchId = 0;
  String? _error;
  int _quotationId = 0;
  String _quotationNo = '';
  Map<String, dynamic> _source = const {};

  String get _clientCode => AppSession.clientCode;
  String get _userId => AppSession.userId;
  bool get _editing => _quotationId > 0;

  List<QuotationField> get _gridFields {
    if (widget.orderMode) {
      return _fieldsIn('middle').where((field) => !field.isCustomer).toList();
    }
    return _quotationGrid(_dedupedQuotationFields());
  }

  List<QuotationField> _dedupedQuotationFields() {
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

  bool _isQuotationKind(QuotationField field, String kind) {
    final token = '${field.keyToken} ${field.labelToken}';
    return switch (kind) {
      'category' => token.contains('category'),
      'product' => token.contains('product') && !token.contains('code'),
      'branch' => token.contains('branch'),
      'design' => token.contains('design'),
      _ => false,
    };
  }

  List<QuotationField> _quotationGrid(List<QuotationField> fields) {
    const added = <QuotationField>[
      QuotationField(
        key: 'branchname',
        label: 'Branch',
        placeholder: '',
        place: 'middle',
        priority: 0,
        type: 'dropdown',
      ),
      QuotationField(
        key: 'categoryname',
        label: 'Category',
        placeholder: '',
        place: 'middle',
        priority: 0,
        type: 'dropdown',
      ),
      QuotationField(
        key: 'productname',
        label: 'Product',
        placeholder: '',
        place: 'middle',
        priority: 0,
        type: 'dropdown',
      ),
    ];
    final rest = <QuotationField>[];
    final leaders = <QuotationField>[];
    for (final field in fields) {
      if (_isQuotationKind(field, 'category') ||
          _isQuotationKind(field, 'product') ||
          _isQuotationKind(field, 'branch')) {
        leaders.add(field);
      } else {
        rest.add(field);
      }
    }
    for (final field in added) {
      final kind = _isQuotationKind(field, 'category')
          ? 'category'
          : _isQuotationKind(field, 'product')
          ? 'product'
          : 'branch';
      if (leaders.any((current) => _isQuotationKind(current, kind))) continue;
      leaders.add(field);
    }
    int rank(QuotationField field) {
      if (_isQuotationKind(field, 'branch')) return 0;
      if (_isQuotationKind(field, 'category')) return 1;
      return 2;
    }

    leaders.sort((a, b) => rank(a).compareTo(rank(b)));
    return [...leaders, ...rest];
  }

  void _ensureGridControllers() {
    for (final field in _gridFields) {
      _fields.putIfAbsent(field.key, TextEditingController.new);
    }
  }

  List<QuotationField> _fieldsIn(String place) {
    final fields = [for (final field in _layout) if (field.place == place) field];
    fields.sort((a, b) => a.priority.compareTo(b.priority));
    return fields;
  }

  String get _gstLabel {
    for (final field in _layout) {
      if (!field.isGstLabel) continue;
      final label = field.label.trim();
      if (label.isNotEmpty) return label;
    }
    return tr('GST 3%');
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
      if (!widget.orderMode) unawaited(_loadQuotationBranches());
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
    _tagSuggestTimer?.cancel();
    _lookup.dispose();
    _customerName.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    if (_clientCode.isEmpty || _userId.isEmpty) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = widget.orderMode ? tr('Sign in to load orders.') : tr('Sign in to load quotations.');
      });
      return;
    }
    final fields = await Injection.quotations.loadPosFields(
      clientCode: _clientCode,
      userId: _userId,
      pageName: widget.orderMode ? AppConstants.orderPageName : AppConstants.quotationPageName,
    );
    final customers = await Injection.quotations.loadCustomers(_clientCode);
    if (_clientCode.isNotEmpty) {
      _purityRates = await Injection.orders.dailyRates(_clientCode);
    }
    if (!mounted) return;
    setState(() {
      _loading = false;
      switch (fields) {
        case Success(:final data):
          _layout = data;
          for (final field in data) {
            _fields.putIfAbsent(field.key, TextEditingController.new);
          }
          _ensureGridControllers();
          if (widget.orderMode) {
            final today = _today();
            for (final field in data) {
              if (!field.type.toLowerCase().contains('date')) continue;
              final controller = _fields[field.key];
              if (controller == null || controller.text.isNotEmpty) continue;
              final initial = _isDeliveryDate(field) ? today.add(const Duration(days: 7)) : today;
              controller.text = _day(initial);
            }
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
          final savedBranch = int.tryParse(item.extras['branchid'] ?? '') ?? 0;
          if (savedBranch > 0) _quotationBranchId = savedBranch;
        }
      }
      if (!widget.orderMode) _applyDefaultBranch();
    });
  }

  Future<void> _loadQuotationBranches() async {
    final result = await Injection.quotations.loadBranches(_clientCode);
    if (!mounted || result is! Success<List<({int id, String name})>>) return;
    setState(() {
      _branches = result.data;
      _applyDefaultBranch();
    });
  }

  void _applyDefaultBranch() {
    if (widget.orderMode || _branches.isEmpty) return;
    var shown = '';
    TextEditingController? empty;
    for (final field in _gridFields) {
      if (!_isQuotationKind(field, 'branch')) continue;
      final controller = _fields[field.key];
      final text = controller?.text.trim() ?? '';
      if (text.isNotEmpty) {
        shown = text;
        break;
      }
      empty ??= controller;
    }
    if (shown.isNotEmpty) {
      final named = _branches.where((branch) => branch.name == shown);
      if (named.isNotEmpty) _quotationBranchId = named.first.id;
      return;
    }
    final preferred = _quotationBranchId > 0 ? _quotationBranchId : AppSession.branchId;
    final match = _branches.where((branch) => branch.id == preferred);
    final branch = match.isEmpty ? _branches.first : match.first;
    _quotationBranchId = branch.id;
    if (empty != null && empty.text.trim().isEmpty) empty.text = branch.name;
  }

  Future<void> _pickItem() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFFFAF9F7),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (context) => oqDirection(
        _AddPieceSheet(
          clientCode: _clientCode,
          initialQuery: _lookup.text,
          alreadyAdded: _alreadyAdded,
          onAdd: (item) {
            if (!mounted) return;
            _useItem(item);
          },
        ),
      ),
    );
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
      fast: widget.orderMode,
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
      _toast(read.error ?? tr('No tag found'));
      return;
    }

    final matches = await Injection.quotations.stockForTags(
      _clientCode,
      read.codes,
      tags: widget.orderMode ? read.tags : const [],
    );
    if (!mounted) return;
    final added = <StockItem>[];
    for (final item in matches) {
      if (_items.any((current) => current.identity == item.identity)) continue;
      _useItem(item);
      added.add(item);
    }
    setState(() => _readingTag = false);
    if (added.isEmpty) {
      _toast(
        matches.isEmpty
            ? tr('Tags scanned but items were not found in stock.')
            : tr(widget.orderMode ? 'Already on this order' : 'Already on this quotation'),
      );
      return;
    }
    await showQuotationItemsPopup(
      context,
      items: added,
      gstApplied: _gstOn,
      gstFraction: _gstRate,
    );
  }

  void _onTagChanged(String value) {
    _tagSuggestTimer?.cancel();
    final query = value.trim();
    if (query.length < 2 || _clientCode.isEmpty) {
      if (_suggestions.isEmpty) return;
      setState(() => _suggestions = const []);
      return;
    }
    final local = Injection.quotations.labeledStockMatching(_clientCode, query);
    if (local.isNotEmpty) {
      setState(() => _suggestions = local.length > 40 ? local.sublist(0, 40) : local);
      return;
    }
    final token = ++_tagSuggestToken;
    _tagSuggestTimer = Timer(const Duration(milliseconds: 280), () {
      _searchTagSuggestions(query, token);
    });
  }

  Future<void> _searchTagSuggestions(String query, int token) async {
    final result = await Injection.quotations.searchStock(
      clientCode: _clientCode,
      query: query,
    );
    if (!mounted || token != _tagSuggestToken) return;
    if (_lookup.text.trim() != query) return;
    if (result case Success(:final data)) {
      setState(() => _suggestions = data.length > 40 ? data.sublist(0, 40) : data);
    }
  }

  void _chooseSuggestion(StockItem item) {
    if (_alreadyAdded(item)) return;
    _suggestions = const [];
    _useItem(item);
  }

  bool _alreadyAdded(StockItem item) {
    return _items.any((current) => current.identity == item.identity);
  }

  Widget _suggestionList() {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxHeight: 320),
      child: ListView.builder(
        shrinkWrap: true,
        itemCount: _suggestions.length,
        itemBuilder: (context, index) {
          final item = _suggestions[index];
          final added = _alreadyAdded(item);
          return _PieceSuggestTile(
            item: item,
            added: added,
            onAdd: added ? null : () => _chooseSuggestion(item),
          );
        },
      ),
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
        _toast(tr('No matching item'));
      case Error(:final failure):
        _toast(failure.message);
    }
  }

  void _useItem(StockItem raw) {
    final item = widget.orderMode
        ? priceOrderSelection(raw, purityRate: _purityRate(raw))
        : withLinePrice(raw, priceLine(raw, applyGst: false, gstFraction: 0));
    _lookup.text = item.itemCode.isEmpty ? item.rfid : item.itemCode;
    for (final field in _gridFields) {
      final value = _valueFor(field, item);
      if (value == null) continue;
      _fields[field.key]?.text = value;
    }
    final existing = _items.indexWhere((current) => current.identity == item.identity);
    if (existing >= 0) {
      setState(() {
        if (widget.orderMode) _items[existing] = item;
      });
      return;
    }
    setState(() => _items.add(item));
  }

  double _purityRate(StockItem item) {
    final purity = (item.extras['purity'] ?? item.extras['purityname'] ?? '').trim().toLowerCase();
    if (purity.isEmpty) return 0;
    return _purityRates[purity] ?? 0;
  }

  String? _valueFor(QuotationField field, StockItem item) {
    final aliases = <String, List<String>>{
      'designname': ['designname', 'design'],
      'categoryname': ['categoryname', 'category'],
      'category': ['category', 'categoryname'],
      'productname': ['productname', 'name'],
      'product': ['productname', 'name'],
      'branchname': ['branchname', 'branch'],
      'branch': ['branch', 'branchname'],
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
    if (widget.orderMode) {
      aliases['purity'] = ['purity', 'purityname'];
      aliases['stonewt'] = ['stonewt', 'stoneweight', 'totalstoneweight', 'stone'];
      aliases['diamondwt'] = ['diamondwt', 'diamondweight', 'totaldiamondweight', 'diamond'];
      aliases['rate'] = ['rate', 'ratepergram', 'todaysrate', 'metalrate', 'goldrate'];
      aliases['stoneamt'] = ['stoneamt', 'stoneamount', 'totalstoneamount'];
      aliases['diamondamt'] = ['diamondamt', 'diamondamount', 'totaldiamondamount'];
      aliases.addAll(const {
        'category': ['category', 'categoryname'],
        'product': ['productname', 'name'],
        'fixedmaking': ['makingfixedamt', 'fixmaking', 'makingfixed'],
        'totalmakingamount': ['makingamt', 'makingamount'],
        'totalitemamount': ['itemamt', 'itemamount', 'amount'],
        'diamondpieces': ['diamondpcs', 'diamondpieces'],
        'diamondrate': ['diamondrate'],
        'quantity': ['quantity', 'pieces', 'pcs'],
        'fixedwt': ['fixedwt', 'finewastagewt'],
        'samplewt': ['samplewt'],
        'ratepergram': ['rate', 'ratepergram', 'todaysrate'],
        'todaysrate': ['rate', 'todaysrate', 'ratepergram'],
        'hallmark': ['hallmarkamt', 'hallmarkamount'],
        'hallmarkamt': ['hallmarkamt', 'hallmarkamount'],
        'totalwt': ['totalwt', 'totalweight'],
        'packingwt': ['packingwt', 'packingweight'],
        'fineper': ['fineper', 'finepercentage'],
        'wastage': ['wastage', 'makingpercent', 'makingpercentage'],
        'finepluswt': ['finepluswt'],
        'makingpergram': ['makingpergram'],
        'makingpercent': ['makingpercent', 'makingpercentage'],
        'makingfixed': ['makingfixedamt', 'fixmaking', 'makingfixed'],
        'fixmaking': ['makingfixedamt', 'fixmaking'],
        'sku': ['sku'],
        'purityname': ['purity', 'purityname'],
        'color': ['color', 'colour', 'typesofcolor', 'typesodcolors', 'typeofcolor'],
        'colour': ['colour', 'color', 'typesofcolor', 'typesodcolors'],
        'typesofcolor': ['typesofcolor', 'color', 'typesodcolors', 'typeofcolor'],
        'screw': ['screw', 'screwtype'],
        'screwtype': ['screwtype', 'screw'],
        'polish': ['polish', 'polishtype'],
        'polishtype': ['polishtype', 'polish'],
      });
    }
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
    if (widget.orderMode) {
      var total = 0.0;
      for (final item in _formItems) {
        total += orderAmount(item);
      }
      return total;
    }
    var total = 0.0;
    for (final item in _formItems) {
      final line = priceLine(item, applyGst: _gstOn, gstFraction: _gstRate);
      total += line.mrp ? line.total : line.item;
    }
    return total;
  }

  double get _gst {
    if (widget.orderMode) {
      if (!_gstOn) return 0;
      var total = 0.0;
      for (final item in _formItems) {
        if (_readOrder(item, 'mrp') > 0) continue;
        total += orderAmount(item);
      }
      return total * _gstRate;
    }
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
      if (widget.orderMode) {
        final mapped = _orderInputKey(field.keyToken) ?? _orderInputKey(field.labelToken);
        if (mapped != null) tokens.add(mapped);
      } else if (_quotationBranchId > 0 && _isQuotationKind(field, 'branch')) {
        extras['branchid'] = '$_quotationBranchId';
      }
      for (final token in tokens) {
        if (token.isEmpty) continue;
        extras[token] = text;
      }
      final key = widget.orderMode
          ? (_orderInputKey(field.labelToken) ??
              _orderInputKey(field.keyToken) ??
              _inputKey(field.labelToken) ??
              _inputKey(field.keyToken))
          : (_inputKey(field.labelToken) ?? _inputKey(field.keyToken));
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
      'category': 'categoryname',
      'categoryname': 'categoryname',
      'product': 'productname',
      'productname': 'productname',
      'branch': 'branchname',
      'branchname': 'branchname',
      'hsn': 'hsncode',
      'hsncode': 'hsncode',
      'diamondpcs': 'diamondpcs',
      'mrp': 'mrp',
    };
    return keys[token];
  }

  String? _orderInputKey(String token) {
    const keys = {
      'hallmark': 'hallmarkamt',
      'hallmarkamt': 'hallmarkamt',
      'hallmarkamount': 'hallmarkamt',
      'totalwt': 'totalwt',
      'totalweight': 'totalwt',
      'packingwt': 'packingweight',
      'packingweight': 'packingwt',
      'fineper': 'fineper',
      'finepercentage': 'fineper',
      'wastage': 'wastage',
      'finepluswt': 'finepluswt',
      'itemamt': 'itemamt',
      'itemamount': 'itemamt',
      'amount': 'itemamt',
      'metalamt': 'metalamt',
      'metalamount': 'metalamt',
      'makingamt': 'makingamt',
      'makingamount': 'makingamt',
      'ratepergram': 'rate',
      'todaysrate': 'rate',
      'makingpergram': 'makingpergram',
      'makingpercentage': 'makingpercent',
      'fixmaking': 'makingfixedamt',
      'fixedmaking': 'makingfixedamt',
      'makingfixed': 'makingfixedamt',
      'totalmakingamount': 'makingamt',
      'totalitemamount': 'itemamt',
      'category': 'categoryname',
      'product': 'productname',
      'diamondpieces': 'diamondpcs',
      'remarks': 'description',
      'screw': 'screwtype',
      'screwtype': 'screwtype',
      'color': 'typesodcolors',
      'colour': 'typesodcolors',
      'typesofcolor': 'typesodcolors',
      'typeofcolor': 'typesodcolors',
      'polish': 'polish',
      'polishtype': 'polish',
      'fixwastage': 'makingfixedwastage',
      'sku': 'sku',
      'purityname': 'purity',
      'totalstoneweight': 'stonewt',
      'totaldiamondweight': 'diamondwt',
      'totalstoneamount': 'stoneamt',
      'totaldiamondamount': 'diamondamt',
    };
    return keys[token] ?? _inputKey(token);
  }

  double _readOrder(StockItem item, String key) {
    return double.tryParse((item.extras[key] ?? '').replaceAll(',', '').trim()) ?? 0;
  }

  void _queueOrderRefresh(QuotationField field) {
    _orderEditedField = field;
    if (_orderRefreshQueued) return;
    _orderRefreshQueued = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _orderRefreshQueued = false;
      if (!mounted) return;
      final edited = _orderEditedField;
      _orderEditedField = null;
      _refreshOrderFields(edited);
      setState(() {});
    });
  }

  void _refreshCalculatedFields({QuotationField? edited}) {
    if (widget.orderMode) {
      _refreshOrderFields(edited);
      return;
    }
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

  void _refreshOrderFields(QuotationField? edited) {
    final index = _items.indexWhere(_isFormItem);
    if (index < 0) return;
    final editedToken = edited == null
        ? ''
        : (_orderInputKey(edited.labelToken) ?? _orderInputKey(edited.keyToken) ?? '');
    final priced = priceOrderEdit(_withGrid(_items[index]), lockGross: editedToken == 'grosswt');
    _items[index] = priced;
    const derived = {'netwt', 'itemamt', 'metalamt', 'finepluswt', 'grosswt'};
    for (final field in _gridFields) {
      if (edited != null && field.key == edited.key) continue;
      final token = _orderInputKey(field.labelToken) ?? _orderInputKey(field.keyToken) ?? field.keyToken;
      if (!derived.contains(token)) continue;
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
      _toast(tr('Select a customer'));
      return;
    }
    if (_items.isEmpty) {
      _toast(tr('Add at least one item'));
      return;
    }
    if (widget.orderMode && !_datesAreValid()) return;
    setState(() => _saving = true);
    final editing = _editing;
    if (widget.orderMode) {
      final result = await Injection.orders.saveOrder(
        clientCode: _clientCode,
        customer: customer,
        items: List<StockItem>.from(_formItems),
        gstApplied: _gstOn,
        gstRate: _gstRate,
        discount: _discount,
        orderDate: _dateFromField('orderDate'),
        deliveryDate: _dateFromField('deliveryDate'),
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
              ? tr('Order updated successfully')
              : (data.isEmpty ? tr('Order saved') : '${tr('Order')} $data ${tr('saved')}');
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
      branchId: _quotationBranchId,
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
            ? tr('Quotation updated successfully')
            : (data.isEmpty ? tr('Quotation saved') : '${tr('Quotation')} $data ${tr('saved')}');
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
        builder: (context) => oqDirection(AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Text(tr('Items')),
          content: Text(tr('No items available yet. Add an item to view the summary.')),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: Text(tr('OK'))),
          ],
        )),
      );
    } else {
      await showQuotationItemsPopup(
        context,
        items: items,
        gstApplied: _gstOn,
        gstFraction: _gstRate,
        orderLines: widget.orderMode
            ? [for (final item in items) _orderPopupLines(item)]
            : null,
      );
    }
    if (mounted) setState(() => _summaryPopup = false);
  }

  void _toast(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return OrderQuotationScope(
      child: Scaffold(
      backgroundColor: AppColors.homeSurface,
      appBar: AppBar(
        elevation: 0,
        backgroundColor: AppColors.charcoal,
        foregroundColor: AppColors.white,
        title: Text(
          widget.orderMode
              ? (widget.detail == null ? tr('Order') : tr('Edit order'))
              : (widget.detail == null ? tr('Quotation') : tr('Edit quotation')),
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        actions: [
          const LanguageButton(light: true),
          IconButton(
            onPressed: _openSummaryPopup,
            icon: const Icon(Icons.view_list_outlined),
            tooltip: tr('Summary'),
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
                      if (_suggestions.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        _suggestionList(),
                      ],
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
        : tr('Select tag number');
    return _labeledRow(
      label: lookup?.label.isNotEmpty == true ? tr(lookup!.label) : tr('Tag Number'),
      child: _borderedRow(
        controller: _lookup,
        hint: hint,
        onChanged: _onTagChanged,
        onSubmitted: (_) => _scanLookup(),
        actions: [
          IconButton(
            onPressed: _readTagIntoQuotation,
            icon: const Icon(Icons.qr_code_scanner, color: AppColors.goldText),
            tooltip: tr('Scan RFID tag'),
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
    if (widget.orderMode && field.type.toLowerCase().contains('date')) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _header(field.label),
          const SizedBox(height: 6),
          TextField(
            controller: controller,
            readOnly: true,
            onTap: () => _pickDate(field, controller),
            decoration: _fieldDecoration(suffixIcon: const Icon(Icons.calendar_today_outlined, size: 18)),
          ),
        ],
      );
    }
    if (widget.orderMode && field.readOnly) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _header(field.label),
          const SizedBox(height: 6),
          TextField(
            controller: controller,
            readOnly: true,
            showCursor: false,
            enableInteractiveSelection: false,
            decoration: _fieldDecoration(),
          ),
        ],
      );
    }
    if (!widget.orderMode && _isQuotationKind(field, 'branch')) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _header(field.label),
          const SizedBox(height: 6),
          TextField(
            controller: controller,
            readOnly: true,
            showCursor: false,
            onTap: () => _pickBranch(field),
            decoration: _fieldDecoration(suffixIcon: const Icon(Icons.arrow_drop_down)),
          ),
        ],
      );
    }
    final fixed = _fixedChoices(field);
    if (fixed != null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _header(field.label),
          const SizedBox(height: 6),
          TextField(
            controller: controller,
            readOnly: true,
            showCursor: false,
            onTap: () => _pickFixed(field, fixed),
            decoration: _fieldDecoration(suffixIcon: const Icon(Icons.arrow_drop_down)),
          ),
        ],
      );
    }
    final catalog = _catalogKind(field);
    if (catalog != null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _header(field.label),
          const SizedBox(height: 6),
          TextField(
            controller: controller,
            readOnly: true,
            showCursor: false,
            onTap: () => _pickCatalog(field, catalog),
            decoration: _fieldDecoration(suffixIcon: const Icon(Icons.arrow_drop_down)),
          ),
        ],
      );
    }
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
            if (widget.orderMode) {
              _queueOrderRefresh(field);
              return;
            }
            _refreshCalculatedFields(edited: field);
            setState(() {});
          },
          keyboardType: _numeric(field)
              ? const TextInputType.numberWithOptions(decimal: true)
              : TextInputType.text,
          inputFormatters: _numeric(field)
              ? [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))]
              : null,
          decoration: _fieldDecoration(
            hint: field.placeholder,
            suffix: field.suffix,
            suffixIcon: widget.orderMode && field.type.toLowerCase().contains('drop')
                ? const Icon(Icons.arrow_drop_down)
                : null,
          ),
        ),
      ],
    );
  }

  List<String>? _fixedChoices(QuotationField field) {
    if (!widget.orderMode) return null;
    final token = '${field.keyToken} ${field.labelToken}';
    if (token.contains('screw')) {
      return const ['Type 1', 'Type 2', 'Type 3'];
    }
    if (token.contains('polish')) {
      return const ['High Polish', 'Matte Finish', 'Satin Finish', 'Hammered'];
    }
    if (!token.contains('diamond') && (token.contains('color') || token.contains('colour'))) {
      return const [
        'Yellow Gold',
        'White Gold',
        'Rose Gold',
        'Green Gold',
        'Black Gold',
        'Blue Gold',
        'Purple Gold',
      ];
    }
    return null;
  }

  Future<void> _pickFixed(QuotationField field, List<String> choices) async {
    final controller = _fields[field.key];
    if (controller == null) return;
    final current = controller.text.trim();
    final options = <String>[
      if (current.isNotEmpty && !choices.contains(current)) current,
      ...choices,
    ];
    final selected = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (context) => oqDirection(_CatalogPicker(title: field.label, choices: options)),
    );
    if (selected == null || !mounted) return;
    controller.text = selected;
    _queueOrderRefresh(field);
    setState(() {});
  }

  Future<void> _pickBranch(QuotationField field) async {
    final controller = _fields[field.key];
    if (controller == null) return;
    final names = [for (final branch in _branches) branch.name];
    final current = controller.text.trim();
    final options = <String>[
      if (current.isNotEmpty && !names.contains(current)) current,
      ...names,
    ];
    final selected = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (context) => oqDirection(_CatalogPicker(title: field.label, choices: options)),
    );
    if (selected == null || !mounted) return;
    final match = _branches.where((branch) => branch.name == selected);
    setState(() {
      controller.text = selected;
      if (match.isNotEmpty) _quotationBranchId = match.first.id;
    });
  }

  String _quotationChoice(String kind) {
    for (final field in _gridFields) {
      if (!_isQuotationKind(field, kind)) continue;
      final text = _fields[field.key]?.text.trim().toLowerCase() ?? '';
      if (text.isNotEmpty) return text;
    }
    return '';
  }

  String? _catalogKind(QuotationField field) {
    final token = '${field.keyToken} ${field.labelToken}';
    final drop = field.type.toLowerCase().contains('drop');
    if (widget.orderMode) {
      if (!drop) return null;
      if (token.contains('category')) return 'category';
      if (token.contains('product')) return 'product';
      if (token.contains('design')) return 'design';
      return null;
    }
    final kind = field.type.toLowerCase();
    if (kind.contains('number') || kind.contains('date')) return null;
    if (token.contains('category')) return 'category';
    if (token.contains('product') && !token.contains('code')) return 'product';
    if (token.contains('design')) return 'design';
    if (token.contains('purity')) return 'purity';
    return null;
  }

  String _catalogValue(String kind, StockItem item) {
    return switch (kind) {
      'category' => item.extras['categoryname'] ?? item.extras['category'] ?? '',
      'product' => item.extras['productname'] ?? item.name,
      'purity' => item.extras['purityname'] ?? item.extras['purity'] ?? '',
      _ => item.design.isNotEmpty ? item.design : (item.extras['designname'] ?? ''),
    }.trim();
  }

  List<String> _catalogChoices(String kind, String current) {
    final values = <String>{};
    if (current.isNotEmpty) values.add(current);
    final selectedCategory = widget.orderMode ? '' : _quotationChoice('category');
    final selectedProduct = widget.orderMode ? '' : _quotationChoice('product');
    if (!widget.orderMode && kind == 'purity') {
      for (final name in _purityRates.keys) {
        final trimmed = name.trim();
        if (trimmed.isNotEmpty) values.add(trimmed);
      }
    }
    for (final item in Injection.quotations.labeledStockMatching(_clientCode, '')) {
      if (!widget.orderMode && kind == 'product' && selectedCategory.isNotEmpty) {
        final itemCategory = _catalogValue('category', item).toLowerCase();
        if (itemCategory.isNotEmpty && itemCategory != selectedCategory) continue;
      }
      if (!widget.orderMode && kind == 'design' && selectedProduct.isNotEmpty) {
        final itemProduct = _catalogValue('product', item).toLowerCase();
        if (itemProduct.isNotEmpty && itemProduct != selectedProduct) continue;
      } else if (!widget.orderMode && kind == 'design' && selectedCategory.isNotEmpty) {
        final itemCategory = _catalogValue('category', item).toLowerCase();
        if (itemCategory.isNotEmpty && itemCategory != selectedCategory) continue;
      }
      final value = _catalogValue(kind, item);
      if (value.isNotEmpty && value.toLowerCase() != 'null') values.add(value);
    }
    final choices = values.toList()..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return choices;
  }

  Future<void> _pickCatalog(QuotationField field, String kind) async {
    final controller = _fields[field.key];
    if (controller == null) return;
    final choices = _catalogChoices(kind, controller.text.trim());
    final selected = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (context) => oqDirection(_CatalogPicker(title: field.label, choices: choices)),
    );
    if (selected == null || !mounted) return;
    controller.text = selected;
    _queueOrderRefresh(field);
    setState(() {});
  }

  Widget _header(String label) {
    final shown = AppLanguage.instance.code == 'en' ? _shortHeader(label) : tr(label);
    return Text(
      shown,
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

  InputDecoration _fieldDecoration({String? hint, String suffix = '', Widget? suffixIcon}) {
    return InputDecoration(
      filled: true,
      fillColor: Colors.white,
      isDense: true,
      hintText: hint == null || hint.isEmpty ? null : hint,
      suffixText: suffix.isEmpty ? null : suffix,
      suffixIcon: suffixIcon,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppColors.fieldBorder),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppColors.fieldBorder),
      ),
    );
  }

  String _day(DateTime date) {
    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');
    return '${date.year}-$month-$day';
  }

  DateTime _today() {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day);
  }

  bool _isDeliveryDate(QuotationField field) {
    return '${field.keyToken} ${field.labelToken}'.contains('deliver');
  }

  bool _isOrderDate(QuotationField field) {
    final token = '${field.keyToken} ${field.labelToken}';
    return token.contains('order') && token.contains('date');
  }

  DateTime? _calendarDay(String text) {
    final raw = text.trim();
    if (raw.isEmpty) return null;
    final written = RegExp(r'^(\d{4})-(\d{2})-(\d{2})').firstMatch(raw);
    if (written != null && !raw.contains('T')) {
      return DateTime(
        int.parse(written.group(1)!),
        int.parse(written.group(2)!),
        int.parse(written.group(3)!),
      );
    }
    final parsed = DateTime.tryParse(raw);
    if (parsed == null) return null;
    final local = parsed.toLocal();
    return DateTime(local.year, local.month, local.day);
  }

  String _dateText(bool delivery) {
    for (final field in _layout) {
      if (!field.type.toLowerCase().contains('date')) continue;
      final match = delivery ? _isDeliveryDate(field) : _isOrderDate(field);
      if (!match) continue;
      final text = _fields[field.key]?.text.trim() ?? '';
      if (text.isNotEmpty) return text;
    }
    return _fields[delivery ? 'deliveryDate' : 'orderDate']?.text.trim() ?? '';
  }

  bool _datesAreValid() {
    final today = _today();
    final orderDay = _calendarDay(_dateText(false));
    final deliverDay = _calendarDay(_dateText(true));
    if (!_editing) {
      if ((orderDay != null && orderDay.isBefore(today)) ||
          (deliverDay != null && deliverDay.isBefore(today))) {
        _toast(tr('Select today or a later date'));
        return false;
      }
    }
    if (orderDay != null && deliverDay != null && deliverDay.isBefore(orderDay)) {
      _toast(tr('Delivery cannot be before the order date.'));
      return false;
    }
    return true;
  }

  Future<void> _pickDate(QuotationField field, TextEditingController controller) async {
    final today = _today();
    var first = today;
    if (_isDeliveryDate(field)) {
      final orderDay = _calendarDay(_dateText(false));
      if (orderDay != null && orderDay.isAfter(first)) first = orderDay;
    }
    final current = _calendarDay(controller.text);
    var initial = current == null || current.isBefore(first) ? first : current;
    final last = DateTime(2035);
    if (initial.isAfter(last)) initial = last;
    final picked = await showDatePicker(
      context: context,
      firstDate: first,
      lastDate: last,
      initialDate: initial,
    );
    if (picked == null || !mounted) return;
    final day = DateTime(picked.year, picked.month, picked.day);
    setState(() {
      controller.text = _day(day);
      if (!_isOrderDate(field)) return;
      for (final other in _layout) {
        if (!_isDeliveryDate(other)) continue;
        final delivery = _fields[other.key];
        if (delivery == null) continue;
        final deliverDay = _calendarDay(delivery.text);
        if (deliverDay != null && deliverDay.isBefore(day)) delivery.text = _day(day);
      }
    });
  }

  DateTime? _dateFromField(String key) {
    final text = _dateText(key.toLowerCase().contains('deliver'));
    final day = _calendarDay(text);
    if (day == null) return null;
    final now = DateTime.now();
    return DateTime(day.year, day.month, day.day, now.hour, now.minute, now.second);
  }

  double get _discount => double.tryParse((_fields['discount']?.text ?? '').replaceAll(',', '').trim()) ?? 0;

  List<(String, String)> _orderPopupLines(StockItem item) {
    return [
      for (final field in _fieldsIn('summarytable'))
        (field.label, _summaryCell(field, item)),
    ];
  }

  String _summaryCell(QuotationField field, StockItem item) {
    if (field.keyToken == 'itemdetails') {
      if (item.itemCode.isNotEmpty) return item.itemCode;
      if (item.design.isNotEmpty) return item.design;
      if (item.name.isNotEmpty) return item.name;
    }
    final value = _valueFor(field, item);
    if (value != null && value.isNotEmpty) return value;
    if (field.keyToken == 'quantity') return '1';
    return '—';
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
                Expanded(
                  child: Text(tr('Summary'), style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
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
                _metric(tr('Gross Wt'), '${_gross.toStringAsFixed(3)} g'),
                _metric(tr('Amount'), '₹ ${_itemAmount.toStringAsFixed(2)}', alignEnd: true),
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
        Expanded(child: _amountBox(tr('GST Amt'), _gst)),
        const SizedBox(width: 8),
        Expanded(child: _amountBox(tr('Total (with GST)'), _itemAmount + _gst)),
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
              Expanded(child: _action(tr('Cancel'), Icons.close, AppColors.charcoal, () => Navigator.pop(context))),
              const SizedBox(width: 8),
              Expanded(
                child: _action(
                  _readingTag ? (_seenTags == 0 ? tr('Scanning') : '${tr('Scan')} $_seenTags') : tr('Scan'),
                  Icons.qr_code_scanner,
                  AppColors.charcoal,
                  _readingTag ? null : _readTagIntoQuotation,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _action(
                  _saving ? (_editing ? tr('Updating') : tr('Saving')) : (_editing ? tr('Update') : tr('Save')),
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
          ? tr(customerField!.label)
          : tr(widget.orderMode ? 'Select customer' : 'Customer Name'),
      child: _borderedRow(
        controller: _customerName,
        hint: customerField?.placeholder.isNotEmpty == true
            ? tr(customerField!.placeholder)
            : tr('Select customer'),
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
    ValueChanged<String>? onChanged,
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
              onChanged: onChanged,
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
      builder: (context) => oqDirection(_PosCustomerSheet(index: _customers)),
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

class _CatalogPicker extends StatefulWidget {
  const _CatalogPicker({required this.title, required this.choices});

  final String title;
  final List<String> choices;

  @override
  State<_CatalogPicker> createState() => _CatalogPickerState();
}

class _CatalogPickerState extends State<_CatalogPicker> {
  final TextEditingController _query = TextEditingController();
  late List<String> _matches = widget.choices;

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
              decoration: InputDecoration(
                hintText: tr(widget.title),
                prefixIcon: const Icon(Icons.search),
              ),
              onChanged: (value) {
                final needle = value.trim().toLowerCase();
                setState(() {
                  _matches = needle.isEmpty
                      ? widget.choices
                      : widget.choices.where((choice) => choice.toLowerCase().contains(needle)).toList();
                });
              },
            ),
          ),
          Expanded(
            child: _matches.isEmpty
                ? Center(child: Text(tr('No matching item')))
                : ListView.builder(
                    itemCount: _matches.length,
                    itemBuilder: (context, index) {
                      final choice = _matches[index];
                      return ListTile(
                        title: Text(choice),
                        onTap: () => Navigator.pop(context, choice),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _PieceSuggestTile extends StatelessWidget {
  const _PieceSuggestTile({
    required this.item,
    required this.added,
    required this.onAdd,
  });

  final StockItem item;
  final bool added;
  final VoidCallback? onAdd;

  @override
  Widget build(BuildContext context) {
    final name = item.name.trim().isEmpty ? tr('Piece') : item.name.trim();
    final code = item.itemCode.trim().isEmpty ? item.rfid : item.itemCode;
    final gross = item.gross.trim();
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: const Color(0xFFF4EFE4),
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          onTap: onAdd,
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: [
                Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    color: const Color(0xFFFAF6EE),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.diamond_outlined, color: AppColors.goldText),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '$code · $name',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: AppColors.charcoal, fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        added ? tr('Already added') : (gross.isEmpty ? '—' : '${tr('Gross')} $gross g'),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: added ? const Color(0xFF8A7A58) : AppColors.muted,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(added ? Icons.check : Icons.add, color: AppColors.charcoal),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _AddPieceSheet extends StatefulWidget {
  const _AddPieceSheet({
    required this.clientCode,
    required this.initialQuery,
    required this.alreadyAdded,
    required this.onAdd,
  });

  final String clientCode;
  final String initialQuery;
  final bool Function(StockItem item) alreadyAdded;
  final ValueChanged<StockItem> onAdd;

  @override
  State<_AddPieceSheet> createState() => _AddPieceSheetState();
}

class _AddPieceSheetState extends State<_AddPieceSheet> {
  late final TextEditingController _query = TextEditingController(text: widget.initialQuery);
  List<StockItem> _items = const [];
  var _waiting = false;

  @override
  void initState() {
    super.initState();
    _refresh();
    if (widget.clientCode.isNotEmpty) {
      Injection.quotations.warmLabeledStock(widget.clientCode, () {
        if (mounted) _refresh();
      });
    }
  }

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  void _refresh() {
    final query = _query.text.trim();
    final local = Injection.quotations.labeledStockMatching(widget.clientCode, query);
    setState(() {
      _items = local.length > 40 ? local.sublist(0, 40) : local;
      _waiting = local.isEmpty && query.length >= 2;
    });
    if (query.length < 2 || local.isNotEmpty || widget.clientCode.isEmpty) return;
    _search(query);
  }

  Future<void> _search(String query) async {
    final result = await Injection.quotations.searchStock(
      clientCode: widget.clientCode,
      query: query,
    );
    if (!mounted || _query.text.trim() != query) return;
    if (result case Success(:final data)) {
      setState(() {
        _items = data.length > 40 ? data.sublist(0, 40) : data;
        _waiting = false;
      });
      return;
    }
    if (mounted) setState(() => _waiting = false);
  }

  @override
  Widget build(BuildContext context) {
    final height = MediaQuery.sizeOf(context).height * 0.86;
    return SizedBox(
      height: height,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    tr('Add a piece'),
                    style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: AppColors.charcoal),
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close, color: AppColors.charcoal),
                ),
              ],
            ),
            TextField(
              controller: _query,
              decoration: InputDecoration(
                hintText: tr('RFID or item code'),
                prefixIcon: const Icon(Icons.search),
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
              ),
              onChanged: (_) => _refresh(),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: _waiting
                  ? const Center(child: CircularProgressIndicator(color: AppColors.goldText))
                  : ListView.builder(
                      itemCount: _items.length,
                      itemBuilder: (context, index) {
                        final item = _items[index];
                        final added = widget.alreadyAdded(item);
                        return _PieceSuggestTile(
                          item: item,
                          added: added,
                          onAdd: added
                              ? null
                              : () {
                                  widget.onAdd(item);
                                  setState(() {});
                                },
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
