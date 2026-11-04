import 'package:flutter/material.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/di/injection.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/result.dart';
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
  var _loading = false;
  var _page = 1;
  var _hasMore = false;
  var _searchGeneration = 0;
  String? _error;

  @override
  void initState() {
    super.initState();
    _query = TextEditingController(text: widget.initialQuery);
    _search(reset: true);
  }

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  Future<void> _search({required bool reset}) async {
    if (widget.clientCode.trim().isEmpty) {
      setState(() => _error = 'Add a client code in Settings to search QA stock.');
      return;
    }
    final generation = ++_searchGeneration;
    final page = reset ? 1 : _page + 1;
    setState(() {
      _loading = true;
      _error = null;
      if (reset) _items = const [];
    });
    final result = await Injection.quotations.searchStock(
      clientCode: widget.clientCode.trim(),
      query: _query.text.trim(),
      pageNumber: page,
    );
    if (!mounted || generation != _searchGeneration) return;
    switch (result) {
      case Success(:final data):
        setState(() {
          _page = page;
          _items = reset ? data : [..._items, ...data];
          _hasMore = data.length >= AppConstants.stockPageSize;
          _loading = false;
        });
      case Error(:final failure):
        setState(() {
          _loading = false;
          _error = failure.message;
        });
    }
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
              onSubmitted: (_) => _search(reset: true),
            ),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(_error!, style: const TextStyle(color: AppColors.goldText)),
            ),
          Expanded(
            child: ListView.builder(
              itemCount: _items.length + (_hasMore || _loading ? 1 : 0),
              itemBuilder: (context, index) {
                if (index >= _items.length) {
                  if (_loading) {
                    return const Padding(
                      padding: EdgeInsets.all(16),
                      child: Center(child: CircularProgressIndicator()),
                    );
                  }
                  return TextButton(
                    onPressed: () => _search(reset: false),
                    child: const Text('Show more items'),
                  );
                }
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
