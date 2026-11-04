import '../../../../core/constants/app_strings.dart';

class ProductDraft {
  String id = '';
  String epc = '';
  String vendor = '';
  String sku = '';
  String rfid = '';
  String category = '';
  String name = '';
  String design = '';
  String purity = '';
  String gross = '';
  String stone = '';
  String diamond = '';
  String net = '';
  String makingGram = '';
  String makingPercent = '';
  String fixedMaking = '';
  String fixedWastage = '';
  String stoneAmount = '';
  String diamondAmount = '';
}

class BulkPiece {
  BulkPiece({this.id = '', this.rfid = '', this.epc = ''});

  String id;
  String rfid;
  String epc;
}

class CataloguePiece {
  CataloguePiece({
    required this.id,
    required this.name,
    this.epc = '',
    this.rfid = '',
    this.category = '',
    this.design = '',
    this.purity = '',
    this.vendor = '',
    this.sku = '',
    this.grossMg,
    this.netMg,
    this.origin = 'reference',
  });

  final String id;
  final String name;
  final String epc;
  final String rfid;
  final String category;
  final String design;
  final String purity;
  final String vendor;
  final String sku;
  final int? grossMg;
  final int? netMg;
  final String origin;
}

class SyncActivity {
  const SyncActivity({required this.methodId, required this.count});

  final String methodId;
  final int count;
}

class SyncMethod {
  const SyncMethod({required this.id, required this.name, required this.copy});

  final String id;
  final String name;
  final String copy;
}

class ProductDemoSession {
  ProductDemoSession() : items = _seed();

  static final instance = ProductDemoSession();

  static const methods = <SyncMethod>[
    SyncMethod(
      id: 'data',
      name: AppStrings.syncData,
      copy: AppStrings.syncDataCopy,
    ),
    SyncMethod(
      id: 'sheet',
      name: AppStrings.syncSheet,
      copy: AppStrings.syncSheetCopy,
    ),
    SyncMethod(
      id: 'upload',
      name: AppStrings.uploadData,
      copy: AppStrings.uploadDataCopy,
    ),
  ];

  final List<CataloguePiece> items;
  final masters = <String, List<String>>{
    'category': ['GOLD'],
    'name': ['Necklace', 'Ring', 'Thali', 'Brooch', 'Bangles'],
    'design': [
      'Abstract',
      'Fancy Ring',
      'FANCY',
      'Solid bangles',
      'HALF SRONE& PLAIN',
    ],
    'purity': ['18K', '22K'],
  };

  String query = '';
  String filter = 'all';
  ProductDraft? draft;
  String bulkCategory = '';
  String bulkName = '';
  String bulkDesign = '';
  final List<BulkPiece> bulkRows = [];
  bool dirty = false;
  String mode = 'single';
  String? syncMethod;
  String syncPhase = 'idle';
  int syncDone = 0;
  int syncTotal = 0;
  final List<SyncActivity> history = [];

  List<CataloguePiece> get visible {
    final needle = query.trim().toLowerCase();
    return items.where((item) {
      final haystack = '${item.id} ${item.name} ${item.rfid} ${item.epc}'
          .toLowerCase();
      final matchesQuery = haystack.contains(needle);
      final matchesFilter = filter != 'local' || item.origin == 'manual';
      return matchesQuery && matchesFilter;
    }).toList();
  }

  SyncMethod? methodById(String? id) {
    for (final method in methods) {
      if (method.id == id) return method;
    }
    return null;
  }

  List<String> validateSingle(
    ProductDraft input, {
    List<CataloguePiece> extra = const [],
  }) {
    final id = input.id.trim().toUpperCase();
    final epc = input.epc.trim().toUpperCase();
    final rfid = input.rfid.trim().toUpperCase();
    final errors = <String>[];
    if (id.isEmpty) errors.add(AppStrings.enterItemCode);
    if (input.category.trim().isEmpty) errors.add(AppStrings.chooseACategory);
    if (input.name.trim().isEmpty) errors.add(AppStrings.chooseAProduct);
    if (input.design.trim().isEmpty) errors.add(AppStrings.chooseADesign);
    final pool = [...items, ...extra];
    if (id.isNotEmpty && pool.any((item) => item.id.toUpperCase() == id)) {
      errors.add(AppStrings.itemCodeUsed);
    }
    if (epc.isNotEmpty && pool.any((item) => item.epc.toUpperCase() == epc)) {
      errors.add(AppStrings.epcUsed);
    }
    if (rfid.isNotEmpty &&
        pool.any((item) => item.rfid.toUpperCase() == rfid)) {
      errors.add(AppStrings.rfidUsed);
    }
    if (epc.isNotEmpty && !RegExp(r'^[A-F0-9]+$').hasMatch(epc)) {
      errors.add(AppStrings.epcHex);
    }
    const numeric = <(String, String)>[
      ('gross', AppStrings.grossWeightG),
      ('stone', AppStrings.stoneWeight),
      ('diamond', AppStrings.diamondWeight),
      ('net', AppStrings.netWeightG),
      ('makingGram', AppStrings.makingPerGram),
      ('makingPercent', AppStrings.makingPercentLabel),
      ('fixedMaking', AppStrings.fixedMaking),
      ('fixedWastage', AppStrings.fixedWastage),
      ('stoneAmount', AppStrings.stoneAmount),
      ('diamondAmount', AppStrings.diamondAmount),
    ];
    for (final (key, label) in numeric) {
      final raw = _numeric(input, key);
      if (raw.isEmpty) continue;
      final value = num.tryParse(raw);
      if (value == null || value < 0) {
        errors.add('${AppStrings.checkValue} $label. ${AppStrings.nonNegative}');
      }
    }
    final gross = num.tryParse(input.gross.trim());
    final net = num.tryParse(input.net.trim());
    if (input.gross.trim().isNotEmpty &&
        input.net.trim().isNotEmpty &&
        gross != null &&
        net != null &&
        net > gross) {
      errors.add(AppStrings.netExceedsGross);
    }
    return errors.toSet().toList();
  }

  List<String> validateBulk() {
    final errors = <String>[];
    if (bulkRows.isEmpty) errors.add(AppStrings.addAtLeastOne);
    final seen = <CataloguePiece>[];
    for (var i = 0; i < bulkRows.length; i++) {
      final row = bulkRows[i];
      final draft = ProductDraft()
        ..category = bulkCategory
        ..name = bulkName
        ..design = bulkDesign
        ..id = row.id
        ..rfid = row.rfid
        ..epc = row.epc;
      for (final error in validateSingle(draft, extra: seen)) {
        errors.add('${AppStrings.rowLabel} ${i + 1}: $error');
      }
      seen.add(_pieceFrom(draft));
    }
    return errors;
  }

  CataloguePiece? saveSingle() {
    final current = draft;
    if (current == null) return null;
    final errors = validateSingle(current);
    if (errors.isNotEmpty) return null;
    final record = _pieceFrom(current, origin: 'manual');
    items.insert(0, record);
    draft = null;
    dirty = false;
    return record;
  }

  List<CataloguePiece>? saveBulk() {
    if (validateBulk().isNotEmpty) return null;
    final records = <CataloguePiece>[
      for (final row in bulkRows)
        _pieceFrom(
          ProductDraft()
            ..category = bulkCategory
            ..name = bulkName
            ..design = bulkDesign
            ..id = row.id
            ..rfid = row.rfid
            ..epc = row.epc,
          origin: 'manual',
        ),
    ];
    items.insertAll(0, records);
    bulkRows.clear();
    dirty = false;
    return records;
  }

  bool startSync(String id) {
    if (syncPhase == 'running' || methodById(id) == null) return false;
    syncMethod = id;
    syncPhase = 'running';
    syncDone = 0;
    syncTotal = items.length;
    return true;
  }

  void tickSync() {
    if (syncPhase != 'running') return;
    final step = syncTotal == 0
        ? 1
        : (syncTotal / 4).ceil().clamp(1, syncTotal).toInt();
    syncDone = (syncDone + step).clamp(0, syncTotal).toInt();
    if (syncDone == syncTotal) {
      syncPhase = 'complete';
      history.insert(
        0,
        SyncActivity(methodId: syncMethod ?? 'data', count: syncDone),
      );
    }
  }

  void discardDraft() {
    draft = null;
    bulkRows.clear();
    bulkCategory = '';
    bulkName = '';
    bulkDesign = '';
    dirty = false;
  }

  static String grams(int? milligrams) {
    if (milligrams == null) return '—';
    final fixed = (milligrams / 1000).toStringAsFixed(3);
    final parts = fixed.split('.');
    final whole = parts[0];
    final grouped = StringBuffer();
    for (var i = 0; i < whole.length; i++) {
      final remaining = whole.length - i;
      if (i > 0 && remaining % 3 == 0 && whole[i - 1] != '-') {
        grouped.write(',');
      }
      grouped.write(whole[i]);
    }
    return '${grouped.toString()}.${parts[1]}';
  }

  static String _numeric(ProductDraft input, String key) {
    return switch (key) {
      'gross' => input.gross.trim(),
      'stone' => input.stone.trim(),
      'diamond' => input.diamond.trim(),
      'net' => input.net.trim(),
      'makingGram' => input.makingGram.trim(),
      'makingPercent' => input.makingPercent.trim(),
      'fixedMaking' => input.fixedMaking.trim(),
      'fixedWastage' => input.fixedWastage.trim(),
      'stoneAmount' => input.stoneAmount.trim(),
      'diamondAmount' => input.diamondAmount.trim(),
      _ => '',
    };
  }

  static int? _milligrams(String raw) {
    if (raw.trim().isEmpty) return null;
    final value = num.tryParse(raw.trim());
    if (value == null) return null;
    return (value * 1000).round();
  }

  static CataloguePiece _pieceFrom(ProductDraft input, {String origin = 'manual'}) {
    return CataloguePiece(
      id: input.id.trim().toUpperCase(),
      name: input.name.trim(),
      epc: input.epc.trim().toUpperCase(),
      rfid: input.rfid.trim().toUpperCase(),
      category: input.category.trim(),
      design: input.design.trim(),
      purity: input.purity.trim(),
      vendor: input.vendor.trim(),
      sku: input.sku.trim(),
      grossMg: _milligrams(input.gross),
      netMg: _milligrams(input.net),
      origin: origin,
    );
  }

  static List<CataloguePiece> _seed() {
    CataloguePiece necklace(String id) => CataloguePiece(
      id: id,
      name: 'Necklace',
      grossMg: 57974,
      netMg: 57974,
      rfid: 'DEMO-$id',
    );
    return [
      for (final id in ['GNK54', 'GNK53', 'GNK52', 'GNK51', 'GNK50', 'GNK49'])
        necklace(id),
      CataloguePiece(
        id: 'ST6',
        name: 'Thali',
        grossMg: 50000,
        netMg: 50000,
        rfid: 'DEMO-ST6',
      ),
      CataloguePiece(
        id: 'GR5',
        name: 'Ring',
        grossMg: 0,
        rfid: 'DEMO-GR5',
      ),
    ];
  }
}
