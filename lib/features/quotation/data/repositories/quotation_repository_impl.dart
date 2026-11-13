import 'dart:async';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/error/exceptions.dart';
import '../../../../core/error/failures.dart';
import '../../../../core/utils/result.dart';
import '../../domain/entities/customer_record.dart';
import '../../domain/entities/quotation_detail.dart';
import '../../domain/entities/quotation_draft.dart';
import '../../domain/entities/quotation_field.dart';
import '../../domain/entities/quotation_summary.dart';
import '../../domain/entities/stock_item.dart';
import '../../domain/repositories/quotation_repository.dart';
import '../catalogues.dart';
import '../datasources/quotation_remote_data_source.dart';

class QuotationRepositoryImpl implements QuotationRepository {
  QuotationRepositoryImpl(this._remote)
    : stock = LabeledStockIndex(_remote),
      quotations = QuotationListIndex(_remote);

  final QuotationRemoteDataSource _remote;
  final LabeledStockIndex stock;
  final QuotationListIndex quotations;
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
    String pan = '',
    String gst = '',
    String street = '',
    String city = '',
    String state = '',
    String country = '',
    int branchId = 0,
  }) {
    return _guard(
      () => _remote.addCustomer(
        clientCode: clientCode,
        name: name,
        mobile: mobile,
        email: email,
        pan: pan,
        gst: gst,
        street: street,
        city: city,
        state: state,
        country: country,
        branchId: branchId,
      ),
    );
  }

  @override
  Future<Result<List<({int id, String name})>>> loadBranches(String clientCode) {
    return _guard(() => _remote.loadBranches(clientCode));
  }

  @override
  Future<Result<CustomerIndex>> loadCustomers(String clientCode) {
    return _guard(() => _remote.loadCustomers(clientCode));
  }

  @override
  void rememberQuotationCustomer({
    required String number,
    required String customerName,
  }) {
    quotations.remember(number: number, customerName: customerName);
  }

  @override
  Future<Result<bool>> deleteQuotation({
    required String clientCode,
    required int id,
  }) {
    return _guard(() async {
      await _remote.deleteQuotation(clientCode: clientCode, id: id);
      quotations.remove(id);
      return true;
    });
  }

  @override
  Future<Result<({String name, String address, String gst})>> companyProfile(
    String clientCode,
  ) {
    return _guard(() => _remote.companyProfile(clientCode));
  }

  @override
  Future<Result<List<QuotationField>>> loadPosFields({
    required String clientCode,
    required String userId,
    String? pageName,
  }) {
    return _guard(
      () => _remote.loadPosFields(
        clientCode: clientCode,
        userId: userId,
        pageName: pageName ?? AppConstants.quotationPageName,
      ),
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

  @override
  Future<void> warmLabeledStock(String clientCode, void Function() onRows) {
    return stock.warm(clientCode, onRows);
  }

  @override
  List<StockItem> labeledStockMatching(String clientCode, String query) {
    if (!stock.readyFor(clientCode)) return const [];
    return stock.filter(query);
  }

  @override
  Future<List<StockItem>> stockForTags(
    String clientCode,
    List<String> codes, {
    List<List<String>> tags = const [],
  }) async {
    if (clientCode.isEmpty || codes.isEmpty) return const [];
    if (stock.clientCode != clientCode || stock.rows.isEmpty) {
      unawaited(stock.warm(clientCode, () {}));
      final deadline = DateTime.now().add(const Duration(seconds: 8));
      while (stock.clientCode == clientCode && stock.rows.isEmpty && DateTime.now().isBefore(deadline)) {
        await Future<void>.delayed(const Duration(milliseconds: 200));
      }
    }
    final found = <String, StockItem>{
      if (stock.clientCode == clientCode)
        for (final item in stock.findTags(codes)) item.identity: item,
    };
    final matched = <String>{
      for (final tag in tags)
        if (tag.any((code) => found.values.any((item) => stock.matchesTag(item, code)))) ...tag,
    };
    final pending = codes.where((code) {
      if (matched.contains(code)) return false;
      return found.values.every((item) => !stock.matchesTag(item, code));
    }).take(40);
    for (final code in pending) {
      for (final key in scanLookupKeys(code)) {
        final result = await searchStock(clientCode: clientCode, query: key);
        if (result case Success(:final data)) {
          for (final item in data) {
            if (!stock.matchesTag(item, code)) continue;
            found[item.identity] = item;
            break;
          }
        }
        if (found.values.any((item) => stock.matchesTag(item, code))) break;
      }
    }
    return found.values.toList();
  }

  @override
  Future<void> warmQuotations(
    String clientCode,
    void Function() onRows, {
    bool refresh = false,
  }) {
    return quotations.warm(clientCode, onRows, refresh: refresh);
  }

  @override
  List<QuotationSummary> quotationsMatching(String clientCode, String query) {
    if (quotations.clientCode != clientCode) return const [];
    return quotations.filter(query);
  }

  @override
  Future<Result<QuotationDetail>> loadQuotation({
    required String clientCode,
    required int id,
  }) {
    return _guard(() => _remote.quotationDetail(clientCode: clientCode, id: id));
  }

  @override
  Future<Result<String>> saveQuotation({
    required String clientCode,
    required CustomerRecord customer,
    required List<StockItem> items,
    required bool gstApplied,
    required double gstRate,
    int id = 0,
    String number = '',
    Map<String, dynamic> source = const {},
  }) {
    return _guard(
      () => _remote.saveQuotation(
        clientCode: clientCode,
        customer: customer,
        items: items,
        gstApplied: gstApplied,
        gstRate: gstRate,
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
