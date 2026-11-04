import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/constants/app_strings.dart';
import '../../domain/entities/product_sync_progress.dart';

abstract class ProductRemoteDataSource {
  Stream<ProductSyncProgress> sync({
    required String token,
    required String clientCode,
    required int roleId,
    required List<int> branchIds,
    required Directory directory,
  });
}

class ProductRemoteDataSourceImpl implements ProductRemoteDataSource {
  ProductRemoteDataSourceImpl({Dio? dio})
    : _dio =
          dio ??
          Dio(
            BaseOptions(
              baseUrl: AppConstants.apiBaseUrl,
              connectTimeout: const Duration(seconds: 60),
              receiveTimeout: const Duration(minutes: 10),
              sendTimeout: const Duration(minutes: 2),
            ),
          );

  final Dio _dio;

  @override
  Stream<ProductSyncProgress> sync({
    required String token,
    required String clientCode,
    required int roleId,
    required List<int> branchIds,
    required Directory directory,
  }) {
    final controller = StreamController<ProductSyncProgress>();
    unawaited(
      _run(
        controller: controller,
        token: token,
        clientCode: clientCode,
        roleId: roleId,
        branchIds: branchIds,
        directory: directory,
      ),
    );
    return controller.stream;
  }

  Future<void> _run({
    required StreamController<ProductSyncProgress> controller,
    required String token,
    required String clientCode,
    required int roleId,
    required List<int> branchIds,
    required Directory directory,
  }) async {
    var lastEmit = 0;

    void emit(ProductSyncProgress progress, {bool force = false}) {
      if (controller.isClosed) return;
      final now = DateTime.now().millisecondsSinceEpoch;
      if (!force && now - lastEmit < 160) return;
      lastEmit = now;
      controller.add(progress);
    }

    try {
      emit(
        const ProductSyncProgress(message: AppStrings.syncingRfid, fraction: 0),
        force: true,
      );
      try {
        await _download(
          path: AppConstants.rfidSyncPath,
          file: File('${directory.path}/rfid.json'),
          token: token,
          body: {'ClientCode': clientCode},
          onProgress: (received, total) {
            final fraction = total > 0 ? (received / total) * 0.15 : null;
            emit(
              ProductSyncProgress(
                message: AppStrings.syncingRfid,
                fraction: fraction,
                received: received,
                total: total,
              ),
            );
          },
        );
      } catch (_) {
        // RFID tags are optional. Labelled stock is the product download.
      }
      emit(
        const ProductSyncProgress(
          message: AppStrings.downloadingProducts,
          fraction: 0.15,
        ),
        force: true,
      );
      await _download(
        path: AppConstants.productSyncPath,
        file: File('${directory.path}/labelled_stocks.json'),
        token: token,
        body: {
          'ClientCode': clientCode,
          'RoleId': roleId,
          'ReturnAll': true,
          if (roleId != 1 && branchIds.isNotEmpty) 'branchIds': branchIds,
        },
        onProgress: (received, total) {
          final fraction = total > 0 ? 0.15 + (received / total) * 0.85 : null;
          emit(
            ProductSyncProgress(
              message: total > 0
                  ? AppStrings.downloadingProducts
                  : '${AppStrings.downloadingProducts} ${_size(received)}',
              fraction: fraction,
              received: received,
              total: total,
            ),
          );
        },
      );
      emit(
        const ProductSyncProgress(
          message: AppStrings.syncComplete,
          fraction: 1,
          completed: true,
        ),
        force: true,
      );
    } on DioException catch (error) {
      emit(
        ProductSyncProgress(
          message: _dioMessage(error),
          fraction: 0,
          failed: true,
        ),
        force: true,
      );
    } catch (_) {
      emit(
        const ProductSyncProgress(
          message: AppStrings.syncFailed,
          fraction: 0,
          failed: true,
        ),
        force: true,
      );
    } finally {
      await controller.close();
    }
  }

  Future<void> _download({
    required String path,
    required File file,
    required String token,
    required Map<String, dynamic> body,
    required void Function(int received, int total) onProgress,
  }) async {
    try {
      await _dio.download(
        path,
        file.path,
        data: body,
        options: Options(
          method: 'POST',
          headers: {
            Headers.contentTypeHeader: Headers.jsonContentType,
            if (token.isNotEmpty) 'Authorization': 'Bearer $token',
          },
        ),
        onReceiveProgress: onProgress,
      );
    } catch (_) {
      if (await file.exists()) {
        await file.delete();
      }
      rethrow;
    }
  }

  String _dioMessage(DioException error) {
    if (error.type == DioExceptionType.connectionError ||
        error.type == DioExceptionType.unknown) {
      return AppStrings.noInternet;
    }
    if (error.type == DioExceptionType.connectionTimeout ||
        error.type == DioExceptionType.receiveTimeout ||
        error.type == DioExceptionType.sendTimeout) {
      return AppStrings.connectionTimedOut;
    }
    return AppStrings.syncFailed;
  }

  String _size(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    }
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}
