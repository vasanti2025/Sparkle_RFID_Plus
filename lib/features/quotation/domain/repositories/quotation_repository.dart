import '../../../../core/utils/result.dart';
import '../entities/customer_record.dart';
import '../entities/quotation_draft.dart';
import '../entities/quotation_field.dart';
import '../entities/stock_item.dart';

abstract class QuotationRepository {
  Future<Result<CustomerIndex>> loadCustomers(String clientCode);

  Future<Result<CustomerRecord>> addCustomer({
    required String clientCode,
    required String name,
    required String mobile,
    required String email,
  });

  Future<Result<List<StockItem>>> searchStock({
    required String clientCode,
    required String query,
    int pageNumber = 1,
  });

  Future<Result<List<QuotationField>>> loadPosFields({
    required String clientCode,
    required String userId,
  });

  List<QuotationDraft> get drafts;

  void saveDraft(QuotationDraft draft);
}
