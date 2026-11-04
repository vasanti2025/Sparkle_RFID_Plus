import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/constants/app_strings.dart';
import '../../../../core/di/injection.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/utils/result.dart';
import '../../domain/entities/customer_record.dart';
import '../../domain/entities/quotation_draft.dart';
import '../../domain/entities/stock_item.dart';
import '../widgets/stock_picker_sheet.dart';

class SparkleQuotationPage extends StatefulWidget {
  const SparkleQuotationPage({super.key});

  @override
  State<SparkleQuotationPage> createState() => _SparkleQuotationPageState();
}

class _SparkleQuotationPageState extends State<SparkleQuotationPage> {
  final TextEditingController _lookup = TextEditingController();
  CustomerIndex _customers = CustomerIndex(const []);
  CustomerRecord? _customer;
  final List<StockItem> _items = [];
  Timer? _debounce;
  var _searchToken = 0;
  List<StockItem> _suggestions = const [];
  var _loadingCustomers = false;

  String get _clientCode => AppConstants.qaClientCode;

  @override
  void initState() {
    super.initState();
    _loadCustomers();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _lookup.dispose();
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
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter an RFID or item code, then scan or use +.')),
      );
      return;
    }
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
          const SnackBar(content: Text('No matching item')),
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
    return Scaffold(
      backgroundColor: AppColors.homeSurface,
      appBar: AppBar(
        backgroundColor: AppColors.homeSurface,
        foregroundColor: AppColors.charcoal,
        elevation: 0,
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(AppStrings.newQuotation),
            Text(
              'Customer → pieces → review',
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
                const _DetailsRow(),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _lookup,
                        decoration: const InputDecoration(
                          hintText: AppStrings.rfidOrItemCode,
                          prefixIcon: Icon(Icons.search),
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
                      AppStrings.selectedJewellery.toUpperCase(),
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
              ],
            ),
          ),
          _Footer(
            count: _items.length,
            gross: _gross,
            onScan: _scanLookup,
            onReview: _review,
          ),
        ],
      ),
    );
  }

  Future<void> _chooseCustomer() async {
    final selected = await showModalBottomSheet<CustomerRecord>(
      context: context,
      isScrollControlled: true,
      builder: (context) => _CustomerSheet(
        index: _customers,
        clientCode: _clientCode,
        onCreated: (record) {
          setState(() => _customers = _customers.add(record));
        },
      ),
    );
    if (selected != null) setState(() => _customer = selected);
  }

  void _review() {
    if (_customer == null || _items.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Choose a customer and add at least one piece.')),
      );
      return;
    }
    Injection.quotations.saveDraft(
      QuotationDraft(
        customerName: _customer!.name,
        items: List<StockItem>.from(_items),
        posMode: false,
        createdAt: DateTime.now(),
      ),
    );
    Navigator.pop(context, true);
  }
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
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('CUSTOMER', style: TextStyle(fontSize: 11, color: AppColors.muted)),
                    Text(
                      loading
                          ? 'Loading customers'
                          : customer?.name ?? AppStrings.chooseCustomer,
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                    ),
                  ],
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

class _DetailsRow extends StatelessWidget {
  const _DetailsRow();

  @override
  Widget build(BuildContext context) {
    final today = DateTime.now();
    final date = '${today.day.toString().padLeft(2, '0')}/${today.month.toString().padLeft(2, '0')}/${today.year}';
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: const Text('Branch', style: TextStyle(fontWeight: FontWeight.w700)),
      subtitle: Text('Date · $date'),
      trailing: const Icon(Icons.tune, color: AppColors.goldText),
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
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 28),
      child: Column(
        children: [
          Icon(Icons.diamond_outlined, color: AppColors.goldText, size: 36),
          SizedBox(height: 8),
          Text(AppStrings.noPiecesYet, style: TextStyle(fontWeight: FontWeight.w700)),
          SizedBox(height: 4),
          Text(AppStrings.scanOrSelect, style: TextStyle(color: AppColors.muted)),
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
  });

  final int count;
  final double gross;
  final VoidCallback onScan;
  final VoidCallback onReview;

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
                    onPressed: onScan,
                    icon: const Icon(Icons.wifi_tethering),
                    label: const Text('Scan'),
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
                      child: const Text(AppStrings.reviewQuotation),
                    ),
                  ),
                ],
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
              decoration: const InputDecoration(
                hintText: 'Customer name',
                prefixIcon: Icon(Icons.search),
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
                  subtitle: Text(customer.mobile.isEmpty ? 'No mobile' : customer.mobile),
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
              label: const Text(AppStrings.addCustomer),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _addCustomer(BuildContext context) async {
    final created = await showDialog<CustomerRecord>(
      context: context,
      builder: (context) => _AddCustomerDialog(clientCode: widget.clientCode),
    );
    if (created == null || !context.mounted) return;
    widget.onCreated(created);
    Navigator.pop(context, created);
  }
}

class _AddCustomerDialog extends StatefulWidget {
  const _AddCustomerDialog({required this.clientCode});

  final String clientCode;

  @override
  State<_AddCustomerDialog> createState() => _AddCustomerDialogState();
}

class _AddCustomerDialogState extends State<_AddCustomerDialog> {
  final _name = TextEditingController();
  final _mobile = TextEditingController();
  final _email = TextEditingController();
  var _saving = false;

  @override
  void dispose() {
    _name.dispose();
    _mobile.dispose();
    _email.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text(AppStrings.addCustomer),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(controller: _name, decoration: const InputDecoration(labelText: 'Name')),
          TextField(controller: _mobile, decoration: const InputDecoration(labelText: 'Mobile')),
          TextField(controller: _email, decoration: const InputDecoration(labelText: 'Email')),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: Text(_saving ? 'Saving' : 'Save'),
        ),
      ],
    );
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    if (name.isEmpty) return;
    setState(() => _saving = true);
    if (widget.clientCode.isNotEmpty) {
      await Injection.quotations.addCustomer(
        clientCode: widget.clientCode,
        name: name,
        mobile: _mobile.text.trim(),
        email: _email.text.trim(),
      );
    }
    if (!mounted) return;
    Navigator.pop(
      context,
      CustomerRecord(
        id: 0,
        name: name,
        mobile: _mobile.text.trim(),
        email: _email.text.trim(),
      ),
    );
  }
}
