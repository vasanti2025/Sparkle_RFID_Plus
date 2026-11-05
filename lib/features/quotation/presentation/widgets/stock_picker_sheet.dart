import 'package:flutter/material.dart';

import '../../../../core/di/injection.dart';
import '../../../../core/theme/app_colors.dart';
import '../../domain/entities/stock_item.dart';

Future<StockItem?> showStockPicker({
  required BuildContext context,
  required String clientCode,
  String initialQuery = '',
}) {
  return showModalBottomSheet<StockItem>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.homeSurface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (context) => _StockPicker(clientCode: clientCode, initialQuery: initialQuery),
  );
}

class _StockPicker extends StatefulWidget {
  const _StockPicker({required this.clientCode, required this.initialQuery});

  final String clientCode;
  final String initialQuery;

  @override
  State<_StockPicker> createState() => _StockPickerState();
}

class _StockPickerState extends State<_StockPicker> {
  late final TextEditingController _query;
  List<StockItem> _items = const [];
  var _waitingForFirst = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _query = TextEditingController(text: widget.initialQuery);
    final cached = Injection.quotations.labeledStockMatching(
      widget.clientCode,
      _query.text,
    );
    if (cached.isNotEmpty) {
      _items = cached;
      _waitingForFirst = false;
    }
    if (widget.clientCode.trim().isEmpty) {
      _waitingForFirst = false;
      _error = 'Sign in to load labelled stock.';
      return;
    }
    Injection.quotations.warmLabeledStock(widget.clientCode.trim(), _showRows).catchError((_) {
      if (!mounted || _items.isNotEmpty) return;
      setState(() {
        _waitingForFirst = false;
        _error = 'Labelled stock could not be loaded.';
      });
    });
  }

  void _showRows() {
    if (!mounted) return;
    setState(() {
      _items = Injection.quotations.labeledStockMatching(widget.clientCode, _query.text);
      _waitingForFirst = false;
      _error = null;
    });
  }

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final height = MediaQuery.sizeOf(context).height * 0.72;
    return SizedBox(
      height: height,
      child: Column(
        children: [
          const SizedBox(height: 10),
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: AppColors.fieldBorder,
              borderRadius: BorderRadius.circular(4),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: TextField(
              controller: _query,
              autofocus: widget.initialQuery.isEmpty,
              decoration: const InputDecoration(
                hintText: 'RFID or item code',
                prefixIcon: Icon(Icons.search),
              ),
              onChanged: (_) => _showRows(),
            ),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(_error!, style: const TextStyle(color: AppColors.goldText)),
            ),
          Expanded(
            child: _waitingForFirst && _items.isEmpty
                ? const Center(child: CircularProgressIndicator(color: AppColors.goldText))
                : ListView.builder(
                    itemCount: _items.length,
                    itemBuilder: (context, index) {
                      final item = _items[index];
                      return ListTile(
                        title: Text('${item.itemCode} · ${item.name.isEmpty ? 'Piece' : item.name}'),
                        subtitle: Text(
                          'RFID ${item.rfid.isEmpty ? 'not linked' : item.rfid}'
                          '${item.gross.isEmpty ? '' : ' · Gross ${item.gross} g'}',
                        ),
                        trailing: const Icon(Icons.add),
                        onTap: () => Navigator.pop(context, item),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
