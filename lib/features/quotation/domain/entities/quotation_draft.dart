import '../entities/stock_item.dart';

class QuotationDraft {
  QuotationDraft({
    required this.customerName,
    required this.items,
    required this.posMode,
    required this.createdAt,
  });

  final String customerName;
  final List<StockItem> items;
  final bool posMode;
  final DateTime createdAt;
}
