import 'package:flutter/material.dart';

import '../../../../core/di/injection.dart';
import '../../../../core/session/app_session.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/result.dart';
import '../../domain/entities/customer_record.dart';
import '../../domain/entities/quotation_detail.dart';
import '../../domain/entities/quotation_summary.dart';
import '../quotation_output.dart';
import 'pos_quotation_page.dart';
import 'sparkle_quotation_page.dart';

class QuotationListPage extends StatefulWidget {
  const QuotationListPage({super.key});

  @override
  State<QuotationListPage> createState() => _QuotationListPageState();
}

class _QuotationListPageState extends State<QuotationListPage> {
  final TextEditingController _search = TextEditingController();
  List<QuotationSummary> _rows = const [];
  var _waitingForFirst = true;
  String? _error;
  var _opening = false;

  String get _clientCode => AppSession.clientCode;

  @override
  void initState() {
    super.initState();
    final cached = Injection.quotations.quotationsMatching(_clientCode, '');
    if (cached.isNotEmpty) {
      _rows = cached;
      _waitingForFirst = false;
    }
    _load();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _load({bool refresh = false}) {
    if (_clientCode.isEmpty) {
      setState(() {
        _waitingForFirst = false;
        _error = 'Sign in to load quotations.';
      });
      return;
    }
    Injection.quotations
        .warmQuotations(_clientCode, _showRows, refresh: refresh)
        .catchError((_) {
          if (!mounted || _rows.isNotEmpty) return;
          setState(() {
            _waitingForFirst = false;
            _error = 'Quotations could not be loaded.';
          });
        });
  }

  void _showRows() {
    if (!mounted) return;
    setState(() {
      _rows = Injection.quotations.quotationsMatching(_clientCode, _search.text);
      _waitingForFirst = false;
      _error = null;
    });
  }

  Future<void> _openForm({QuotationDetail? detail}) async {
    final page = Injection.settings.enablePos
        ? PosQuotationPage(detail: detail)
        : SparkleQuotationPage(detail: detail);
    final saved = await Navigator.of(context).push<String>(
      MaterialPageRoute<String>(builder: (_) => page),
    );
    if (!mounted || saved == null || saved.isEmpty) return;
    _load(refresh: true);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(saved)));
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
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(failure.message)));
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
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Quotation sent to the POS printer')),
        );
      }
    } catch (error) {
      if (!mounted) return;
      final message = '$error'.replaceFirst('Exception: ', '');
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
    }
  }

  Future<void> _delete(QuotationSummary row) async {
    if (_opening || row.id == 0) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete quotation'),
        content: Text('Delete quotation ${row.number.isEmpty ? row.id : row.number}?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: const Color(0xFFB42318)),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final result = await Injection.quotations.deleteQuotation(
      clientCode: _clientCode,
      id: row.id,
    );
    if (!mounted) return;
    switch (result) {
      case Success():
        _showRows();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Quotation deleted')),
        );
      case Error(:final failure):
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(failure.message)));
    }
  }

  Future<void> _edit(QuotationSummary row) async {
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
        await _openForm(detail: data);
      case Error(:final failure):
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(failure.message)));
    }
  }

  static const _actionSlot = 120.0;

  Widget _line(Widget number, Widget customer, Widget amount, Widget action) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(flex: 2, child: number),
        Expanded(flex: 3, child: customer),
        Expanded(flex: 2, child: amount),
        SizedBox(width: _actionSlot, child: action),
      ],
    );
  }

  Widget _action(IconData icon, Color color, String tip, VoidCallback onTap) {
    return IconButton(
      tooltip: tip,
      onPressed: onTap,
      visualDensity: VisualDensity.compact,
      padding: EdgeInsets.zero,
      style: IconButton.styleFrom(
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        padding: EdgeInsets.zero,
        minimumSize: const Size(32, 32),
        fixedSize: const Size(32, 32),
        maximumSize: const Size(32, 32),
      ),
      icon: Icon(icon, color: color, size: 18),
    );
  }

  Widget _actionRow(QuotationSummary row) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        _action(Icons.edit, Colors.blue, 'Edit', () => _edit(row)),
        _action(Icons.delete, const Color(0xFFB42318), 'Delete', () => _delete(row)),
        _action(Icons.print, const Color(0xFF1B7F3A), 'Print', () => _print(row)),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.homeSurface,
      appBar: AppBar(
        backgroundColor: AppColors.charcoal,
        foregroundColor: Colors.white,
        title: const Text('Quotations'),
        actions: [
          IconButton(
            onPressed: () => _openForm(),
            icon: const Icon(Icons.add),
            tooltip: 'New quotation',
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: TextField(
              controller: _search,
              onChanged: (_) => _showRows(),
              decoration: InputDecoration(
                hintText: 'Search quotation or customer',
                prefixIcon: const Icon(Icons.search),
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),
          Container(
            margin: const EdgeInsets.fromLTRB(8, 0, 8, 0),
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: AppColors.cardBorder)),
            ),
            child: _line(
              const Text('Q. No', style: TextStyle(fontWeight: FontWeight.w700)),
              const Text('Customer', style: TextStyle(fontWeight: FontWeight.w700)),
              const Text('Amount', style: TextStyle(fontWeight: FontWeight.w700)),
              const Center(
                child: Text('Action', style: TextStyle(fontWeight: FontWeight.w700)),
              ),
            ),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(_error!, style: const TextStyle(color: AppColors.goldText)),
            ),
          Expanded(
            child: _waitingForFirst && _rows.isEmpty
                ? const Center(child: CircularProgressIndicator(color: AppColors.goldText))
                : ListView.builder(
                    itemCount: _rows.length,
                    itemBuilder: (context, index) {
                      final row = _rows[index];
                      return Container(
                        margin: const EdgeInsets.symmetric(horizontal: 8),
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        decoration: const BoxDecoration(
                          border: Border(bottom: BorderSide(color: AppColors.fieldBorder)),
                        ),
                        child: _line(
                          Text(
                            row.number.isEmpty ? '${row.id}' : row.number,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          Text(
                            row.customerName.isEmpty ? '—' : row.customerName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          Text(
                            row.amount.isEmpty ? '—' : row.amount,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          _actionRow(row),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
