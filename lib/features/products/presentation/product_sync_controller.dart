import 'package:flutter/foundation.dart';

import '../../../core/constants/app_strings.dart';
import '../../auth/domain/entities/user.dart';
import '../domain/entities/product_sync_progress.dart';
import '../domain/usecases/sync_products.dart';

class ProductSyncController extends ChangeNotifier {
  ProductSyncController(this._syncProducts);

  final SyncProducts _syncProducts;

  ProductSyncProgress? progress;
  bool visible = false;
  bool _running = false;
  User? _user;

  Future<void> start(User user) async {
    if (_running || user.clientCode.isEmpty) return;
    _user = user;
    _running = true;
    visible = true;
    progress = const ProductSyncProgress(
      message: AppStrings.syncingProducts,
      fraction: 0,
    );
    notifyListeners();
    try {
      await for (final event in _syncProducts(user)) {
        progress = event;
        notifyListeners();
      }
    } catch (_) {
      progress = const ProductSyncProgress(
        message: AppStrings.syncFailed,
        fraction: 0,
        failed: true,
      );
      notifyListeners();
    }
    _running = false;
    if (_user == null) {
      visible = false;
      notifyListeners();
      return;
    }
    if (progress?.failed == true) {
      notifyListeners();
      return;
    }
    await Future<void>.delayed(const Duration(milliseconds: 1400));
    visible = false;
    notifyListeners();
  }

  void retry() {
    final user = _user;
    if (user == null || _running) return;
    start(user);
  }

  void abandon() {
    _user = null;
    visible = false;
    notifyListeners();
  }
}
