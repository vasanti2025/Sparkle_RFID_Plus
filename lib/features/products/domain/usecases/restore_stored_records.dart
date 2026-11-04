import '../entities/stored_record.dart';
import '../repositories/product_repository.dart';

class RestoreStoredRecords {
  const RestoreStoredRecords(this.repository);

  final ProductRepository repository;

  Future<List<StoredRecord>> call({
    String kind = StoredRecord.kindProduct,
    int limit = 100,
    int offset = 0,
  }) {
    return repository.restoreStored(kind: kind, limit: limit, offset: offset);
  }
}
