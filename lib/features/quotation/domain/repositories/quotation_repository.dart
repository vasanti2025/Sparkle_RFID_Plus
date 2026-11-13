import '../../../../core/utils/result.dart';
import '../entities/customer_record.dart';
import '../entities/quotation_detail.dart';
import '../entities/quotation_draft.dart';
import '../entities/quotation_field.dart';
import '../entities/quotation_summary.dart';
import '../entities/stock_item.dart';

abstract class QuotationRepository {
  Future<Result<CustomerIndex>> loadCustomers(String clientCode);

  Future<Result<CustomerRecord>> addCustomer({
    required String clientCode,
    required String name,
    required String mobile,
    required String email,
    String pan = '',
    String gst = '',
    String street = '',
    String city = '',
    String state = '',
    String country = '',
    int branchId = 0,
  });

  Future<Result<List<({int id, String name})>>> loadBranches(String clientCode);

  Future<Result<List<StockItem>>> searchStock({
    required String clientCode,
    required String query,
    int pageNumber = 1,
  });

  Future<void> warmLabeledStock(String clientCode, void Function() onRows);

  List<StockItem> labeledStockMatching(String clientCode, String query);

  Future<List<StockItem>> stockForTags(
    String clientCode,
    List<String> codes, {
    List<List<String>> tags = const [],
  });

  Future<void> warmQuotations(
    String clientCode,
    void Function() onRows, {
    bool refresh = false,
  });

  List<QuotationSummary> quotationsMatching(String clientCode, String query);

  Future<Result<QuotationDetail>> loadQuotation({
    required String clientCode,
    required int id,
  });

  Future<Result<String>> saveQuotation({
    required String clientCode,
    required CustomerRecord customer,
    required List<StockItem> items,
    required bool gstApplied,
    required double gstRate,
    int id = 0,
    String number = '',
    Map<String, dynamic> source = const {},
  });

  void rememberQuotationCustomer({
    required String number,
    required String customerName,
  });

  Future<Result<bool>> deleteQuotation({
    required String clientCode,
    required int id,
  });

  Future<Result<({String name, String address, String gst})>> companyProfile(
    String clientCode,
  );

  Future<Result<List<QuotationField>>> loadPosFields({
    required String clientCode,
    required String userId,
    String? pageName,
  });

  List<QuotationDraft> get drafts;

  void saveDraft(QuotationDraft draft);
}
