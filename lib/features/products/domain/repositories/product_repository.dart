import '../../../auth/domain/entities/user.dart';
import '../entities/product_sync_progress.dart';
import '../entities/stored_record.dart';

abstract class ProductRepository {
  Stream<ProductSyncProgress> syncProducts(User user);

  Future<List<StoredRecord>> searchStored({
    String kind = StoredRecord.kindProduct,
    String query = '',
    int limit = 50,
    int offset = 0,
  });

  Future<List<StoredRecord>> restoreStored({
    String kind = StoredRecord.kindProduct,
    int limit = 100,
    int offset = 0,
  });

  Future<int> storedCount({String kind = StoredRecord.kindProduct});

  Future<int> exportStoredCsv(String path, {void Function(int written)? onProgress});

  Future<Map<String, String>> storedRfidMap();

  Future<int> importProducts(List<Map<String, dynamic>> items, {void Function(int written)? onProgress});

  Future<int> saveBulkProducts(List<Map<String, dynamic>> items);
}
