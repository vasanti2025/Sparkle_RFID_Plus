import '../entities/stored_record.dart';
import '../repositories/product_repository.dart';

class SearchStoredRecords {
  const SearchStoredRecords(this.repository);

  final ProductRepository repository;

  Future<List<StoredRecord>> call({
    String kind = StoredRecord.kindProduct,
    String query = '',
    int limit = 50,
    int offset = 0,
  }) {
    return repository.searchStored(
      kind: kind,
      query: query,
      limit: limit,
      offset: offset,
    );
  }
}
