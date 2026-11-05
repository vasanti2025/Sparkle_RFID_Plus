import 'package:flutter/material.dart';

import '../../../../core/di/injection.dart';
import '../../../../core/session/app_session.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/result.dart';
import '../../domain/entities/quotation_detail.dart';
import '../../domain/entities/stock_item.dart';

class QuotationPrintPage extends StatefulWidget {
  const QuotationPrintPage({super.key, required this.detail});

  final QuotationDetail detail;

  @override
  State<QuotationPrintPage> createState() => _QuotationPrintPageState();
}

class _QuotationPrintPageState extends State<QuotationPrintPage> {
  String _companyName = '';
  String _companyAddress = '';
  String _gstNumber = '';

  @override
  void initState() {
    super.initState();
    _loadCompany();
  }

  Future<void> _loadCompany() async {
    final result = await Injection.quotations.companyProfile(AppSession.clientCode);
    if (!mounted) return;
    if (result case Success(:final data)) {
      setState(() {
        _companyName = data.name;
        _companyAddress = data.address;
        _gstNumber = data.gst;
      });
    }
  }

  String _pick(StockItem item, List<String> keys, [String fallback = '']) {
    for (final key in keys) {
      final value = item.extras[key];
      if (value != null && value.trim().isNotEmpty && value.trim().toLowerCase() != 'null') {
        return value.trim();
      }
    }
    return fallback;
  }

  double _amount(StockItem item) {
    return double.tryParse(
          _pick(item, const ['itemamt', 'itemamount', 'totalitemamount', 'amount'], '0'),
        ) ??
        0;
  }

  double get _taxable => widget.detail.items.fold<double>(0, (sum, item) => sum + _amount(item));

  double get _gst => widget.detail.gstApplied ? _taxable * 0.03 : 0;

  double get _net {
    final saved = double.tryParse('${widget.detail.source['TotalNetAmount'] ?? ''}');
    if (saved != null && saved > 0) return saved;
    return _taxable + _gst;
  }

  String _date() {
    final raw = '${widget.detail.source['CreatedOn'] ?? widget.detail.source['QuotationDate'] ?? ''}'.trim();
    final parsed = DateTime.tryParse(raw);
    final date = parsed ?? DateTime.now();
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    final day = date.day;
    final suffix = switch (day) {
      1 || 21 || 31 => 'st',
      2 || 22 => 'nd',
      3 || 23 => 'rd',
      _ => 'th',
    };
    return '$day$suffix ${months[date.month - 1]} ${date.year}';
  }

  @override
  Widget build(BuildContext context) {
    final detail = widget.detail;
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: AppColors.charcoal,
        foregroundColor: Colors.white,
        title: const Text('Quotation'),
        actions: const [
          Icon(Icons.print, color: Colors.white),
          SizedBox(width: 12),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 28),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _companyName.isEmpty ? 'Quotation' : _companyName,
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.goldText),
                ),
                if (_companyAddress.isNotEmpty) ...[
                  const SizedBox(height: 5),
                  Text(_companyAddress, style: const TextStyle(fontSize: 12, color: Colors.grey)),
                ],
                if (_gstNumber.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text('GSTN: $_gstNumber', style: const TextStyle(fontSize: 12, color: Colors.grey)),
                ],
                const SizedBox(height: 4),
                Text('Created Date: ${_date()}', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
                const SizedBox(height: 4),
                Text(
                  'Customer Name : ${detail.customer.name}',
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
                ),
                const SizedBox(height: 4),
                Text(
                  'Quotation No : ${detail.number}',
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
                ),
                if (detail.customer.mobile.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    'Phone No : ${detail.customer.mobile}',
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
                  ),
                ],
              ],
            ),
          ),
          Container(
            width: double.infinity,
            color: const Color(0xFFF5F5F5),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: const Text('Item Details', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
          ),
          if (detail.items.isEmpty)
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text('No items added', style: TextStyle(color: Colors.grey)),
            )
          else
            for (var index = 0; index < detail.items.length; index++) _itemCard(detail.items[index], index + 1),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                if (_taxable > 0) _moneyRow('Taxable Amount :', _taxable),
                if (detail.gstApplied && _taxable > 0) ...[
                  const SizedBox(height: 8),
                  const Align(
                    alignment: Alignment.centerLeft,
                    child: Text('Total GST (3%):', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                  ),
                  const SizedBox(height: 4),
                  _moneyRow('CGST 1.5%:', _gst / 2, size: 11),
                  const SizedBox(height: 4),
                  _moneyRow('SGST 1.5%:', _gst / 2, size: 11),
                ],
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                  decoration: BoxDecoration(
                    border: Border.all(color: AppColors.goldText),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Row(
                    children: [
                      const Expanded(
                        child: Text('Total Net Amount:', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                      ),
                      Text(
                        _net.toStringAsFixed(2),
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppColors.goldText),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _moneyRow(String label, double amount, {double size = 12}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: TextStyle(fontSize: size)),
        Text(amount.toStringAsFixed(2), style: TextStyle(fontSize: size, fontWeight: FontWeight.w500)),
      ],
    );
  }

  Widget _itemCard(StockItem item, int number) {
    final name = _pick(item, const ['designname', 'productname', 'description'], item.name);
    final title = name.isEmpty ? (item.itemCode.isEmpty ? 'Item $number' : item.itemCode) : name;
    return Container(
      margin: const EdgeInsets.fromLTRB(8, 8, 8, 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey.shade300),
        borderRadius: BorderRadius.circular(6),
        color: Colors.white,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _column('Item', title),
              _column('HSN', _pick(item, const ['hsncode', 'hsn']), align: CrossAxisAlignment.center),
              _column('Pieces', _pick(item, const ['pieces', 'pcs'], '1'), align: CrossAxisAlignment.end),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              _column('Gr Wt', _pick(item, const ['grosswt', 'grossweight'], item.gross.isEmpty ? '0' : item.gross)),
              _column(
                'Stone Wt',
                '${_pick(item, const ['stonewt', 'stoneweight'], '0.000')} cts',
                align: CrossAxisAlignment.center,
              ),
              _column(
                'Net Wt',
                _pick(item, const ['netwt', 'netweight'], item.net.isEmpty ? '0' : item.net),
                align: CrossAxisAlignment.end,
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              _column('Rate/Gm', _pick(item, const ['rate', 'metalrate'], '0')),
              _column(
                'Stone Amt',
                _pick(item, const ['stoneamt', 'stoneamount'], '0'),
                align: CrossAxisAlignment.center,
              ),
              _column('Purity', _pick(item, const ['purity']), align: CrossAxisAlignment.end),
            ],
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: Text(
              'Item Amt  ${_amount(item).toStringAsFixed(2)}',
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.goldText),
            ),
          ),
        ],
      ),
    );
  }

  Widget _column(String label, String value, {CrossAxisAlignment align = CrossAxisAlignment.start}) {
    return Expanded(
      child: Column(
        crossAxisAlignment: align,
        children: [
          Text(label, style: TextStyle(fontSize: 10, color: Colors.grey.shade600, fontWeight: FontWeight.w500)),
          Text(value, style: const TextStyle(fontSize: 12), textAlign: align == CrossAxisAlignment.end ? TextAlign.end : TextAlign.start),
        ],
      ),
    );
  }
}
