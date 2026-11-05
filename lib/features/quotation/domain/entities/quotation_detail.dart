import 'customer_record.dart';
import 'stock_item.dart';

class QuotationDetail {
  const QuotationDetail({
    required this.id,
    required this.number,
    required this.customer,
    required this.items,
    required this.gstApplied,
    required this.source,
  });

  final int id;
  final String number;
  final CustomerRecord customer;
  final List<StockItem> items;
  final bool gstApplied;
  final Map<String, dynamic> source;
}
