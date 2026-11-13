import 'package:flutter/material.dart';

import '../../../../core/di/injection.dart';
import '../../../../core/locale/oq_text.dart';
import '../../../../core/session/app_session.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/result.dart';
import '../../../quotation/domain/entities/customer_record.dart';
import '../../../quotation/domain/entities/quotation_detail.dart';
import '../../../quotation/presentation/pages/pos_quotation_page.dart';
import '../../../quotation/presentation/quotation_output.dart';
import '../../domain/entities/order_record.dart';

class OrderListPage extends StatefulWidget {
  const OrderListPage({super.key});

  @override
  State<OrderListPage> createState() => _OrderListPageState();
}

class _OrderListPageState extends State<OrderListPage> {
  final TextEditingController _search = TextEditingController();
  List<OrderRecord> _rows = const [];
  var _waitingForFirst = true;
  String? _error;

  String get _clientCode => AppSession.clientCode;

  @override
  void initState() {
    super.initState();
    final cached = Injection.orders.ordersMatching(_clientCode, '');
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
        _error = tr('Sign in to load orders.');
      });
      return;
    }
    Injection.orders.warmOrders(_clientCode, _showRows, refresh: refresh).catchError((_) {
      if (!mounted || _rows.isNotEmpty) return;
      setState(() {
        _waitingForFirst = false;
        _error = tr('Orders could not be loaded.');
      });
    });
  }

  void _showRows() {
    if (!mounted) return;
    setState(() {
      _rows = Injection.orders.ordersMatching(_clientCode, _search.text);
      _waitingForFirst = false;
      _error = null;
    });
  }

  Future<void> _openForm({QuotationDetail? detail}) async {
    final saved = await Navigator.of(context).push<String>(
      MaterialPageRoute<String>(
        builder: (_) => PosQuotationPage(detail: detail, orderMode: true),
      ),
    );
    if (!mounted || saved == null || saved.isEmpty) return;
    _load(refresh: true);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(saved)));
  }

  Future<void> _print(OrderRecord row) async {
    if (row.id == 0) return;
    final choice = await askPrintChoice(context, title: tr('Print order'));
    if (choice == null || !mounted) return;
    final loaded = Injection.orders.detailFor(row.id);
    if (loaded == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(tr('Order could not be opened'))),
      );
      return;
    }
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
      documentName: tr('Order'),
    );
    try {
      if (choice == 'pdf') {
        await printQuotationPdf(copy);
      } else {
        await printQuotationOnPos(copy);
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(tr('Order sent to the POS printer'))),
        );
      }
    } catch (error) {
      if (!mounted) return;
      final message = '$error'.replaceFirst('Exception: ', '');
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
    }
  }

  Future<void> _delete(OrderRecord row) async {
    if (row.id == 0) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => oqDirection(AlertDialog(
        title: Text(tr('Delete order')),
        content: Text('${tr('Delete order')} ${row.number.isEmpty ? row.id : row.number}?'),
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
    final result = await Injection.orders.deleteOrder(clientCode: _clientCode, id: row.id);
    if (!mounted) return;
    switch (result) {
      case Success():
        _showRows();
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr('Order deleted'))));
      case Error(:final failure):
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(failure.message)));
    }
  }

  Future<void> _edit(OrderRecord row) async {
    if (row.id == 0) return;
    final detail = Injection.orders.detailFor(row.id);
    if (detail == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(tr('Order could not be opened'))),
      );
      return;
    }
    await _openForm(detail: detail);
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

  Widget _actionRow(OrderRecord row) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        _action(Icons.edit, Colors.blue, tr('Edit'), () => _edit(row)),
        _action(Icons.delete, const Color(0xFFB42318), tr('Delete'), () => _delete(row)),
        _action(Icons.print, const Color(0xFF1B7F3A), tr('Print'), () => _print(row)),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return OrderQuotationScope(
      child: Scaffold(
      backgroundColor: AppColors.homeSurface,
      appBar: AppBar(
        backgroundColor: AppColors.charcoal,
        foregroundColor: Colors.white,
        title: Text(tr('Orders')),
        actions: [
          const LanguageButton(light: true),
          IconButton(
            onPressed: () => _openForm(),
            icon: const Icon(Icons.add),
            tooltip: tr('New order'),
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
                hintText: tr('Search order or customer'),
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
              Text(tr('Order No'), style: const TextStyle(fontWeight: FontWeight.w700)),
              Text(tr('Customer'), style: const TextStyle(fontWeight: FontWeight.w700)),
              Text(tr('Amount'), style: const TextStyle(fontWeight: FontWeight.w700)),
              Center(child: Text(tr('Action'), style: const TextStyle(fontWeight: FontWeight.w700))),
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
    ),
    );
  }
}
