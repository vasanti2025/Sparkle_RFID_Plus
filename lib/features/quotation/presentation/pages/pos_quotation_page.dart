import 'package:flutter/material.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/constants/app_strings.dart';
import '../../../../core/di/injection.dart';
import '../../../../core/utils/result.dart';
import '../../domain/entities/customer_record.dart';
import '../../domain/entities/quotation_draft.dart';
import '../../domain/entities/quotation_field.dart';
import '../../domain/entities/stock_item.dart';
import '../widgets/stock_picker_sheet.dart';

const _burgundy = Color(0xFF9B3B5C);
const _page = Color(0xFFF5F5F5);

class PosQuotationPage extends StatefulWidget {
  const PosQuotationPage({super.key});

  @override
  State<PosQuotationPage> createState() => _PosQuotationPageState();
}

class _PosQuotationPageState extends State<PosQuotationPage> {
  final Map<String, TextEditingController> _fields = {};
  List<QuotationField> _layout = const [];
  CustomerIndex _customers = CustomerIndex(const []);
  CustomerRecord? _customer;
  final List<StockItem> _items = [];
  var _loading = true;
  String? _error;

  String get _clientCode => AppConstants.qaClientCode;
  String get _userId => AppConstants.qaUserId;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final controller in _fields.values) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    final fields = await Injection.quotations.loadPosFields(
      clientCode: _clientCode,
      userId: _userId,
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
    });
  }

  Future<void> _pickItem(QuotationField field) async {
    final item = await showStockPicker(
      context: context,
      clientCode: _clientCode,
      initialQuery: _fields[field.key]?.text ?? '',
    );
    if (item == null || !mounted) return;
    _fields[field.key]?.text = item.itemCode.isEmpty ? item.rfid : item.itemCode;
    if (_items.any((current) => current.identity == item.identity)) return;
    setState(() => _items.add(item));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _page,
      appBar: AppBar(
        backgroundColor: _burgundy,
        foregroundColor: Colors.white,
        title: const Text(AppStrings.newQuotation),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: _burgundy))
          : _error != null
          ? _ErrorState(message: _error!, onRetry: () {
              setState(() {
                _loading = true;
                _error = null;
              });
              _load();
            })
          : Column(
              children: [
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      _customerTile(),
                      const SizedBox(height: 12),
                      ..._layout.map(_fieldTile),
                      const SizedBox(height: 8),
                      Text(
                        'Selected items (${_items.length})',
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 8),
                      if (_items.isEmpty)
                        const Text('Use + on an RFID or item code field to add pieces.')
                      else
                        for (final item in _items)
                          Card(
                            child: ListTile(
                              title: Text(item.name.isEmpty ? item.itemCode : item.name),
                              subtitle: Text(
                                '${item.itemCode} · RFID ${item.rfid.isEmpty ? 'not linked' : item.rfid}',
                              ),
                              trailing: IconButton(
                                onPressed: () => setState(() => _items.remove(item)),
                                icon: const Icon(Icons.close),
                              ),
                            ),
                          ),
                    ],
                  ),
                ),
                SafeArea(
                  top: false,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: _burgundy,
                        minimumSize: const Size.fromHeight(48),
                      ),
                      onPressed: _review,
                      child: const Text(AppStrings.reviewQuotation),
                    ),
                  ),
                ),
              ],
            ),
    );
  }

  Widget _customerTile() {
    return Material(
      color: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ListTile(
        title: const Text(AppStrings.customer),
        subtitle: Text(_customer?.name ?? AppStrings.chooseCustomer),
        trailing: const Icon(Icons.arrow_drop_down),
        onTap: _chooseCustomer,
      ),
    );
  }

  Future<void> _chooseCustomer() async {
    final selected = await showModalBottomSheet<CustomerRecord>(
      context: context,
      isScrollControlled: true,
      builder: (context) => _PosCustomerSheet(index: _customers),
    );
    if (selected != null) setState(() => _customer = selected);
  }

  Widget _fieldTile(QuotationField field) {
    final controller = _fields[field.key]!;
    if (field.isCustomer) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        controller: controller,
        keyboardType: field.type.toLowerCase().contains('number')
            ? const TextInputType.numberWithOptions(decimal: true)
            : TextInputType.text,
        decoration: InputDecoration(
          filled: true,
          fillColor: Colors.white,
          labelText: field.label,
          hintText: field.placeholder,
          suffixIcon: field.isItemLookup
              ? IconButton(
                  tooltip: 'Add ${field.label}',
                  onPressed: () => _pickItem(field),
                  icon: const Icon(Icons.add),
                )
              : null,
        ),
      ),
    );
  }

  void _review() {
    if (_customer == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Select a customer.')),
      );
      return;
    }
    Injection.quotations.saveDraft(
      QuotationDraft(
        customerName: _customer!.name,
        items: List<StockItem>.from(_items),
        posMode: true,
        createdAt: DateTime.now(),
      ),
    );
    Navigator.pop(context, true);
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
