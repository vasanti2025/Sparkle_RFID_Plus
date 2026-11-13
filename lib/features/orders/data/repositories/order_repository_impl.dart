import '../../../../core/error/exceptions.dart';
import '../../../../core/error/failures.dart';
import '../../../../core/utils/result.dart';
import '../../../quotation/domain/entities/customer_record.dart';
import '../../../quotation/domain/entities/quotation_detail.dart';
import '../../../quotation/domain/entities/stock_item.dart';
import '../../domain/entities/order_record.dart';
import '../../domain/repositories/order_repository.dart';
import '../datasources/order_remote_data_source.dart';
import '../order_list_index.dart';

class OrderRepositoryImpl implements OrderRepository {
  OrderRepositoryImpl(this._remote) : orders = OrderListIndex(_remote);

  final OrderRemoteDataSource _remote;
  final OrderListIndex orders;

  @override
  Future<void> warmOrders(
    String clientCode,
    void Function() onRows, {
    bool refresh = false,
  }) {
    return orders.warm(clientCode, onRows, refresh: refresh);
  }

  @override
  List<OrderRecord> ordersMatching(String clientCode, String query) {
    if (orders.clientCode != clientCode) return const [];
    return orders.filter(query);
  }

  @override
  QuotationDetail? detailFor(int id) {
    final row = orders.find(id);
    if (row == null) return null;
    return _remote.detailFrom(row);
  }

  @override
  void rememberCustomer({required String number, required String customerName}) {
    orders.remember(number: number, customerName: customerName);
  }

  @override
  Future<Map<String, double>> dailyRates(String clientCode) {
    return _remote.dailyRates(clientCode);
  }

  @override
  Future<Result<bool>> deleteOrder({
    required String clientCode,
    required int id,
  }) {
    return _guard(() async {
      await _remote.deleteOrder(clientCode: clientCode, id: id);
      orders.remove(id);
      return true;
    });
  }

  @override
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
  }) {
    return _guard(
      () => _remote.saveOrder(
        clientCode: clientCode,
        customer: customer,
        items: items,
        gstApplied: gstApplied,
        gstRate: gstRate,
        discount: discount,
        orderDate: orderDate,
        deliveryDate: deliveryDate,
        id: id,
        number: number,
        source: source,
      ),
    );
  }

  Future<Result<T>> _guard<T>(Future<T> Function() action) async {
    try {
      return Success(await action());
    } on ServerException catch (error) {
      return Error(ServerFailure(error.message));
    } catch (error) {
      return Error(ServerFailure(error.toString()));
    }
  }
}
