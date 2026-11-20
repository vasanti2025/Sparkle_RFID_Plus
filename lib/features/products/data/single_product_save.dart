import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../../core/constants/app_constants.dart';
import '../../../core/network/api_host.dart';
import '../../../core/constants/app_strings.dart';
import '../../../core/session/app_session.dart';
import '../presentation/demo/product_demo_session.dart';

class SingleProductSaveResult {
  const SingleProductSaveResult({this.error, this.imageSaved = false, this.imageUrl = ''});

  final String? error;
  final bool imageSaved;
  final String imageUrl;
}

/// Saves one product with [InsertLabelledStock], then the photo with
/// [UploadImagesByClientCode], the same pair the previous app uses.
Future<SingleProductSaveResult> saveSingleProduct({
  required ProductDraft draft,
  required String imagePath,
}) async {
  final clientCode = AppSession.clientCode.trim();
  if (clientCode.isEmpty) {
    return const SingleProductSaveResult(error: AppStrings.signInToSaveProduct);
  }
  try {
    final masters = await _masters(clientCode);
    final sku = _sku(masters.skus, draft.sku, draft.vendor);
    final categoryId = _prefer(sku?['CategoryId'], _matchId(masters.categories, draft.category, const ['CategoryName', 'Name']));
    final productId = _prefer(sku?['ProductId'], _matchId(masters.products, draft.name, const ['ProductName', 'Name']));
    final designId = _prefer(sku?['DesignId'], _matchId(masters.designs, draft.design, const ['DesignName', 'Name']));
    final purityId = _prefer(sku?['PurityId'], _matchId(masters.purities, draft.purity, const ['PurityName', 'Name']));
    final vendorId = _matchId(masters.vendors, draft.vendor, const ['VendorName', 'Name']);
    final branchId = _prefer(sku?['BranchId'], AppSession.branchId);
    final employeeId = _prefer(sku?['EmployeeId'], AppSession.employeeId);

    var images = '';
    final photo = imagePath.trim();
    if (photo.isNotEmpty) {
      final uploaded = await _uploadImage(clientCode, draft.id.trim(), photo);
      if (uploaded.error != null) return SingleProductSaveResult(error: uploaded.error);
      images = uploaded.url;
    }

    final payload = <String, dynamic>{
      'CategoryId': categoryId,
      'ProductId': productId,
      'DesignId': designId,
      'VendorId': vendorId,
      'PurityId': purityId,
      'RFIDCode': draft.rfid.trim(),
      'ItemCode': draft.id.trim(),
      'HUIDCode': '',
      'HSNCode': '',
      'Quantity': '1',
      'TotalWeight': 0.0,
      'PackingWeight': 0.0,
      'GrossWt': draft.gross.trim(),
      'TotalStoneWeight': draft.stone.trim(),
      'NetWt': draft.net.trim(),
      'Pieces': '',
      'MakingPercentage': draft.makingPercent.trim(),
      'MakingPerGram': draft.makingGram.trim(),
      'MakingFixedAmt': draft.fixedMaking.trim(),
      'MakingFixedWastage': draft.fixedWastage.trim(),
      'MRP': '',
      'ClipWeight': '',
      'ClipQuantity': '',
      'ProductCode': draft.id.trim(),
      'Featured': '',
      'ProductTitle': draft.name.trim(),
      'Description': '',
      'Gender': '',
      'DiamondWeight': draft.diamond.trim(),
      'Stones': <dynamic>[],
      'StoneWeight': draft.stone.trim(),
      'StoneAmount': draft.stoneAmount.trim(),
      'BranchName': AppSession.branchName,
      'BranchId': branchId,
      'PurityName': draft.purity.trim(),
      'TotalStoneAmount': draft.stoneAmount.trim(),
      'TotalStonePieces': '',
      'ClientCode': clientCode,
      'EmployeeCode': employeeId,
      'CompanyId': 0,
      'MetalId': 0,
      'WarehouseId': 0,
      'TIDNumber': draft.epc.trim().toUpperCase(),
      'TotalDiamondWeight': draft.diamond.trim(),
      'TotalDiamondAmount': draft.diamondAmount.trim(),
      'Images': images,
      'Status': 'Active',
    };
    final error = await _insert(payload);
    if (error != null) return SingleProductSaveResult(error: error);
    return SingleProductSaveResult(imageSaved: images.isNotEmpty, imageUrl: images);
  } catch (_) {
    return const SingleProductSaveResult(error: AppStrings.couldNotSaveProduct);
  }
}

int _prefer(Object? primary, int fallback) {
  final value = _asInt(primary);
  return value > 0 ? value : fallback;
}

int _asInt(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString() ?? '') ?? 0;
}

class _Masters {
  const _Masters(this.categories, this.products, this.designs, this.purities, this.vendors, this.skus);

  final List<dynamic> categories;
  final List<dynamic> products;
  final List<dynamic> designs;
  final List<dynamic> purities;
  final List<dynamic> vendors;
  final List<dynamic> skus;
}

Future<_Masters> _masters(String clientCode) async {
  final body = {'ClientCode': clientCode};
  final rows = await Future.wait([
    _postList(AppConstants.getAllCategory, body),
    _postList(AppConstants.getAllProductMaster, body),
    _postList(AppConstants.getAllDesign, body),
    _postList(AppConstants.getAllPurity, body),
    _postList(AppConstants.getAllPartyDetails, body),
    _postList(AppConstants.getAllSku, body),
  ]);
  return _Masters(rows[0], rows[1], rows[2], rows[3], rows[4], rows[5]);
}

int _matchId(List<dynamic> rows, String name, List<String> keys) {
  final needle = name.trim().toLowerCase();
  if (needle.isEmpty) return 0;
  for (final row in rows) {
    if (row is! Map) continue;
    for (final key in keys) {
      final value = row[key]?.toString().trim().toLowerCase() ?? '';
      if (value == needle) return _asInt(row['Id'] ?? row['id']);
    }
  }
  return 0;
}

Map<String, dynamic>? _sku(List<dynamic> rows, String sku, String vendor) {
  final needle = sku.trim().toLowerCase();
  if (needle.isEmpty) return null;
  final vendorNeedle = vendor.trim().toLowerCase();
  Map<String, dynamic>? fallback;
  for (final row in rows) {
    if (row is! Map) continue;
    final name = (row['SKU'] ?? row['StockKeepingUnit'])?.toString().trim().toLowerCase() ?? '';
    if (name != needle) continue;
    final mapped = Map<String, dynamic>.from(row);
    if (vendorNeedle.isEmpty) return mapped;
    final raw = row['SKUVendor'];
    final names = <String>[];
    if (raw is Map) names.add(raw['VendorName']?.toString() ?? '');
    if (raw is List) {
      for (final entry in raw) {
        if (entry is Map) names.add(entry['VendorName']?.toString() ?? '');
      }
    }
    if (names.any((value) => value.trim().toLowerCase() == vendorNeedle)) return mapped;
    fallback ??= mapped;
  }
  return fallback;
}

Future<({String? error, String url})> _uploadImage(String clientCode, String itemCode, String filePath) async {
  final request = http.MultipartRequest('POST', Uri.parse('${ApiHost.base}${AppConstants.uploadProductImage}'));
  final token = AppSession.token.trim();
  if (token.isNotEmpty) request.headers['Authorization'] = 'Bearer $token';
  request.fields['ClientCode'] = clientCode;
  request.fields['ItemCode'] = itemCode;
  request.files.add(await http.MultipartFile.fromPath('File', filePath, filename: filePath.split(RegExp(r'[/\\]')).last));
  final sent = await request.send().timeout(const Duration(minutes: 2));
  final body = await sent.stream.bytesToString();
  if (sent.statusCode < 200 || sent.statusCode >= 300) {
    return (error: AppStrings.couldNotSavePhoto, url: '');
  }
  final url = _imageUrl(body);
  if (url.isEmpty) return (error: AppStrings.couldNotSavePhoto, url: '');
  return (error: null, url: url);
}

String _imageUrl(String body) {
  final trimmed = body.trim();
  if (trimmed.isEmpty) return '';
  try {
    final decoded = jsonDecode(trimmed);
    if (decoded is Map) {
      final value = decoded['images'] ?? decoded['Images'];
      return value?.toString().trim() ?? '';
    }
    if (decoded is String) return decoded.trim();
  } catch (_) {
    if (!trimmed.startsWith('{') && !trimmed.startsWith('[')) return trimmed;
  }
  return '';
}

Future<String?> _insert(Map<String, dynamic> payload) async {
  final token = AppSession.token.trim();
  final response = await http
      .post(
        Uri.parse('${ApiHost.base}${AppConstants.insertLabelledStock}'),
        headers: {
          'Content-Type': 'application/json',
          if (token.isNotEmpty) 'Authorization': 'Bearer $token',
        },
        body: jsonEncode([payload]),
      )
      .timeout(const Duration(seconds: 40));
  if (response.statusCode >= 200 && response.statusCode < 300) return null;
  return _serverMessage(response.body) ?? AppStrings.couldNotSaveProduct;
}

String? _serverMessage(String body) {
  try {
    final decoded = jsonDecode(body);
    if (decoded is Map && decoded['Message'] != null) return decoded['Message'].toString();
    if (decoded is List && decoded.isNotEmpty && decoded.first is Map) {
      final message = (decoded.first as Map)['Message'];
      if (message != null) return message.toString();
    }
  } catch (_) {}
  return null;
}

Future<List<dynamic>> _postList(String path, Map<String, dynamic> body) async {
  final token = AppSession.token.trim();
  final response = await http
      .post(
        Uri.parse('${ApiHost.base}$path'),
        headers: {
          'Content-Type': 'application/json',
          if (token.isNotEmpty) 'Authorization': 'Bearer $token',
        },
        body: jsonEncode(body),
      )
      .timeout(const Duration(seconds: 40));
  if (response.statusCode < 200 || response.statusCode >= 300 || response.body.isEmpty) return const [];
  final decoded = jsonDecode(response.body);
  return decoded is List ? decoded : const [];
}
