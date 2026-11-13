import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/constants/app_strings.dart';
import '../../../../core/locale/oq_text.dart';
import '../../../../core/di/injection.dart';
import '../../../../core/rfid/rfid_service.dart';
import '../../../../core/session/app_session.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/utils/result.dart';
import '../../domain/entities/customer_record.dart';
import '../../domain/entities/quotation_detail.dart';
import '../../domain/entities/quotation_draft.dart';
import '../../domain/entities/stock_item.dart';
import '../widgets/stock_picker_sheet.dart';
import 'add_customer_page.dart';

class SparkleQuotationPage extends StatefulWidget {
  const SparkleQuotationPage({super.key, this.detail});

  final QuotationDetail? detail;

  @override
  State<SparkleQuotationPage> createState() => _SparkleQuotationPageState();
}

class _SparkleQuotationPageState extends State<SparkleQuotationPage> {
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

  String get _clientCode => AppSession.clientCode;

  @override
  void initState() {
    super.initState();
    final today = DateTime.now();
    _docDate = DateTime(today.year, today.month, today.day);
    _validUntil = _docDate.add(const Duration(days: 7));
    final detail = widget.detail;
    if (detail != null) {
      _quotationId = detail.id;
      _quotationNo = detail.number;
      _source = detail.source;
      _customer = detail.customer;
      _items.addAll(detail.items);
    }
    _loadCustomers();
    if (_clientCode.isNotEmpty) {
      unawaited(Injection.quotations.warmLabeledStock(_clientCode, () {}));
    }
    _rfidTrigger.attach(_readTagIntoQuotation);
  }

  @override
  void dispose() {
    _rfidTrigger.detach();
    _tray.cancel();
    _debounce?.cancel();
    _lookup.dispose();
    _branch.dispose();
    _reference.dispose();
    _notes.dispose();
    super.dispose();
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
    return OrderQuotationScope(
      child: Scaffold(
      backgroundColor: AppColors.homeSurface,
      appBar: AppBar(
        backgroundColor: AppColors.homeSurface,
        foregroundColor: AppColors.charcoal,
        elevation: 0,
        actions: const [LanguageButton()],
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(tr(AppStrings.newQuotation)),
            Text(
              tr('Customer → pieces → review'),
              style: TextStyle(fontSize: 12, color: AppColors.muted, fontWeight: FontWeight.w500),
            ),
          ],
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
              children: [
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
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _lookup,
                        decoration: InputDecoration(
                          hintText: tr(AppStrings.rfidOrItemCode),
                          prefixIcon: const Icon(Icons.search),
                        ),
                        onChanged: _onLookupChanged,
                        onSubmitted: (_) => _scanLookup(),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton.filled(
                      style: IconButton.styleFrom(
                        backgroundColor: AppColors.charcoal,
                        foregroundColor: AppColors.champagne,
                        minimumSize: const Size(AppTypography.minTouch, AppTypography.minTouch),
                      ),
                      onPressed: _openPicker,
                      icon: const Icon(Icons.add),
                      tooltip: 'Browse pieces',
                    ),
                  ],
                ),
                if (_suggestions.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  _SuggestionList(items: _suggestions, onAdd: _addItem),
                ],
                const SizedBox(height: 18),
                Row(
                  children: [
                    Text(
                      tr(AppStrings.selectedJewellery).toUpperCase(),
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.4,
                      ),
                    ),
                    const Spacer(),
                    Text('${_items.length} pieces', style: const TextStyle(color: AppColors.muted)),
                  ],
                ),
                const SizedBox(height: 8),
                if (_items.isEmpty)
                  const _EmptyPieces()
                else
                  for (final item in _items)
                    _PieceCard(
                      item: item,
                      onRemove: () => setState(() => _items.remove(item)),
                    ),
                const SizedBox(height: 12),
                const _PricePending(),
                const SizedBox(height: 8),
                Text(
                  tr('A price proposal. It does not move stock.'),
                  style: const TextStyle(color: AppColors.muted, fontSize: 12),
                ),
              ],
            ),
          ),
          _Footer(
            count: _items.length,
            gross: _gross,
            onScan: _readTagIntoQuotation,
            scanning: _readingTag,
            scanLabel: _readingTag ? (_seenTags == 0 ? tr('Scanning') : '${tr('Scan')} $_seenTags') : tr('Scan'),
            onReview: _review,
          ),
        ],
      ),
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
                  Text(tr('Document details'), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 12),
                  TextField(controller: branch, decoration: InputDecoration(labelText: tr('Branch'))),
                  TextField(
                    readOnly: true,
                    decoration: InputDecoration(labelText: tr('Document date'), hintText: _formatDate(docDate)),
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
                    decoration: InputDecoration(labelText: tr('Valid until'), hintText: _formatDate(validUntil)),
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
                  TextField(controller: reference, decoration: InputDecoration(labelText: tr('Reference'))),
                  TextField(controller: notes, decoration: InputDecoration(labelText: tr('Notes'))),
                  const SizedBox(height: 12),
                  FilledButton(
                    style: FilledButton.styleFrom(backgroundColor: AppColors.charcoal),
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
              Text(tr('Review quotation'), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
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
                style: const TextStyle(color: AppColors.muted, fontSize: 12),
              ),
              const SizedBox(height: 12),
              FilledButton(
                style: FilledButton.styleFrom(backgroundColor: AppColors.charcoal),
                onPressed: _saving ? null : _saveQuotation,
                child: Text(_quotationId > 0 ? tr('Update') : tr('Save')),
              ),
              const SizedBox(height: 8),
              Text(
                tr('Draft only. No stock or order is changed.'),
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppColors.muted, fontSize: 12),
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
        Navigator.pop(context);
        Navigator.pop(
          context,
          editing
              ? 'Quotation updated successfully'
              : (data.isEmpty ? 'Quotation saved' : 'Quotation $data saved'),
        );
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
        Expanded(child: Text(label, style: const TextStyle(color: AppColors.muted))),
        Text(value, style: const TextStyle(fontWeight: FontWeight.w700)),
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
    return Material(
      color: AppColors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: AppColors.cardBorder),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              const Icon(Icons.person_outline, color: AppColors.goldText),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  loading
                      ? 'Select customer'
                      : (customer != null && customer!.name.isNotEmpty
                            ? customer!.name
                            : 'Select customer'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                ),
              ),
              const Icon(Icons.expand_more, color: AppColors.muted),
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
                    branch.isEmpty ? 'Branch' : branch,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  Text(
                    'Valid until · ${_formatDate(validUntil)}',
                    style: const TextStyle(color: AppColors.muted, fontSize: 12),
                  ),
                ],
              ),
            ),
            Text(tr('Details'), style: const TextStyle(color: AppColors.goldText, fontWeight: FontWeight.w700)),
            const Icon(Icons.tune, color: AppColors.goldText, size: 18),
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
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.cardBorder),
      ),
      child: Row(
        children: [
          Expanded(child: Text(tr('Document amount'))),
          Text(tr('Pricing pending'), style: const TextStyle(fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}

class _SuggestionList extends StatelessWidget {
  const _SuggestionList({required this.items, required this.onAdd});

  final List<StockItem> items;
  final ValueChanged<StockItem> onAdd;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: const BorderSide(color: AppColors.cardBorder),
      ),
      child: ListView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: items.length,
        itemBuilder: (context, index) {
          final item = items[index];
          return ListTile(
            title: Text('${item.itemCode} · ${item.name.isEmpty ? 'Piece' : item.name}'),
            subtitle: Text('RFID ${item.rfid.isEmpty ? 'not linked' : item.rfid}'),
            trailing: const Icon(Icons.add, color: AppColors.goldText),
            onTap: () => onAdd(item),
          );
        },
      ),
    );
  }
}

class _EmptyPieces extends StatelessWidget {
  const _EmptyPieces();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 28),
      child: Column(
        children: [
          const Icon(Icons.diamond_outlined, color: AppColors.goldText, size: 36),
          const SizedBox(height: 8),
          Text(tr(AppStrings.noPiecesYet), style: const TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          Text(tr(AppStrings.scanOrSelect), style: const TextStyle(color: AppColors.muted)),
        ],
      ),
    );
  }
}

class _PieceCard extends StatelessWidget {
  const _PieceCard({required this.item, required this.onRemove});

  final StockItem item;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      color: AppColors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: AppColors.cardBorder),
      ),
      child: ListTile(
        title: Text(item.name.isEmpty ? item.itemCode : item.name),
        subtitle: Text(
          '${item.itemCode} · Gross ${item.gross.isEmpty ? '—' : item.gross} g\n'
          'Net ${item.net.isEmpty ? '—' : item.net} · RFID ${item.rfid.isEmpty ? 'not linked' : item.rfid}',
        ),
        isThreeLine: true,
        trailing: IconButton(
          onPressed: onRemove,
          icon: const Icon(Icons.delete_outline),
          tooltip: 'Remove ${item.itemCode}',
        ),
      ),
    );
  }
}

class _Footer extends StatelessWidget {
  const _Footer({
    required this.count,
    required this.gross,
    required this.onScan,
    required this.onReview,
    this.scanning = false,
    this.scanLabel = 'Scan',
  });

  final int count;
  final double gross;
  final VoidCallback onScan;
  final VoidCallback onReview;
  final bool scanning;
  final String scanLabel;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.white,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
          child: Column(
            children: [
              Row(
                children: [
                  Text('$count pieces', style: const TextStyle(fontWeight: FontWeight.w700)),
                  const Spacer(),
                  Text('Gross ${gross.toStringAsFixed(3)} g'),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  OutlinedButton.icon(
                    onPressed: scanning ? null : onScan,
                    icon: const Icon(Icons.wifi_tethering),
                    label: Text(scanLabel),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.charcoal,
                        foregroundColor: AppColors.white,
                        minimumSize: const Size.fromHeight(AppTypography.minTouch),
                      ),
                      onPressed: count == 0 ? null : onReview,
                      child: Text(tr(AppStrings.reviewQuotation)),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              const Text(
                'Draft only. No stock or order is changed.',
                style: TextStyle(color: AppColors.muted, fontSize: 12),
              ),
            ],
          ),
        ),
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
              decoration: InputDecoration(
                hintText: tr('Customer name'),
                prefixIcon: const Icon(Icons.search),
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
                  title: Text(customer.name),
                  subtitle: Text(customer.mobile.isEmpty ? tr('No mobile') : customer.mobile),
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
              label: Text(tr(AppStrings.addCustomer)),
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
