import '../../../../core/utils/result.dart';
import '../../../quotation/domain/entities/customer_record.dart';
import '../../../quotation/domain/entities/quotation_detail.dart';
import '../../../quotation/domain/entities/stock_item.dart';
import '../entities/order_record.dart';

abstract class OrderRepository {
  Future<void> warmOrders(
    String clientCode,
    void Function() onRows, {
    bool refresh = false,
  });

  List<OrderRecord> ordersMatching(String clientCode, String query);

  QuotationDetail? detailFor(int id);

  void rememberCustomer({required String number, required String customerName});

  Future<Map<String, double>> dailyRates(String clientCode);

  Future<Result<bool>> deleteOrder({
    required String clientCode,
    required int id,
  });

  Future<Result<String>> saveOrder({
    required String clientCode,
    required CustomerRecord customer,
    required List<StockItem> items,
    required bool gstApplied,
    required double gstRate,
    double discount = 0,
    DateTime? orderDate,
    DateTime? deliveryDate,
    int id = 0,
    String number = '',
    Map<String, dynamic> source = const {},
  });
}
