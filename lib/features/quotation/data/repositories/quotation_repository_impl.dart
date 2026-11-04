import '../../../../core/error/exceptions.dart';
import '../../../../core/error/failures.dart';
import '../../../../core/utils/result.dart';
import '../../domain/entities/customer_record.dart';
import '../../domain/entities/quotation_draft.dart';
import '../../domain/entities/quotation_field.dart';
import '../../domain/entities/stock_item.dart';
import '../../domain/repositories/quotation_repository.dart';
import '../datasources/quotation_remote_data_source.dart';

class QuotationRepositoryImpl implements QuotationRepository {
  QuotationRepositoryImpl(this._remote);

  final QuotationRemoteDataSource _remote;
  final List<QuotationDraft> _drafts = [];

  @override
  List<QuotationDraft> get drafts => List<QuotationDraft>.unmodifiable(_drafts);

  @override
  void saveDraft(QuotationDraft draft) => _drafts.insert(0, draft);

  @override
  Future<Result<CustomerRecord>> addCustomer({
    required String clientCode,
    required String name,
    required String mobile,
    required String email,
  }) {
    return _guard(
      () => _remote.addCustomer(
        clientCode: clientCode,
        name: name,
        mobile: mobile,
        email: email,
      ),
    );
  }

  @override
  Future<Result<CustomerIndex>> loadCustomers(String clientCode) {
    return _guard(() => _remote.loadCustomers(clientCode));
  }

  @override
  Future<Result<List<QuotationField>>> loadPosFields({
    required String clientCode,
    required String userId,
  }) {
    return _guard(
      () => _remote.loadPosFields(clientCode: clientCode, userId: userId),
    );
  }

  @override
  Future<Result<List<StockItem>>> searchStock({
    required String clientCode,
    required String query,
    int pageNumber = 1,
  }) {
    return _guard(
      () => _remote.searchStock(
        clientCode: clientCode,
        query: query,
        pageNumber: pageNumber,
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
