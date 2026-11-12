import 'dart:async';

import '../../../core/di/injection.dart';
import '../../products/domain/entities/stored_record.dart';
import '../domain/inventory_catalog.dart';

/// Labelled stock kept on the device, indexed for a fast RFID match.
class InventoryStock {
  InventoryStock._();

  static final InventoryStock instance = InventoryStock._();

  var ready = false;
  List<InventoryPiece> pieces = const [];
  List<String> categories = const [];
  List<String> products = const [];
  List<String> designs = const [];
  List<String> counters = const [];
  List<String> boxes = const [];
  List<String> branches = const [];
  List<String> exhibitions = const [];

  final Map<String, InventoryPiece> _byId = {};
  final Map<String, String> _keyToId = {};

  Future<void> load() async {
    try {
      await _read();
    } finally {
      ready = true;
    }
  }

  Future<void> _read() async {
    final products = await _pages(StoredRecord.kindProduct);
    final tags = await _pages(StoredRecord.kindRfid);
    final pieces = <InventoryPiece>[];
    _byId.clear();
    _keyToId.clear();
    for (final record in products) {
      final piece = _piece(record);
      if (piece == null) continue;
      pieces.add(piece);
      _byId[piece.id] = piece;
      _index(piece.id, piece.id);
      _index(piece.id, piece.rfid);
      _index(piece.id, piece.epc);
      _index(piece.id, piece.tid);
      _index(piece.id, record.barcode);
    }
    for (final tag in tags) {
      final barcode = tag.barcode ?? tag.itemCode;
      final owner = barcode == null ? null : _keyToId[_norm(barcode)];
      if (owner == null) continue;
      _index(owner, tag.rfid);
      _index(owner, tag.itemCode);
    }
    this.pieces = pieces;
    categories = _distinct(pieces.map((item) => item.category));
    this.products = _distinct(pieces.map((item) => item.product));
    designs = _distinct(pieces.map((item) => item.design));
    counters = _distinct(pieces.map((item) => item.counter));
    boxes = _distinct(pieces.map((item) => item.box));
    branches = _distinct(
      pieces.where((item) => (item.branchType ?? '').toLowerCase() != 'exhibition').map((item) => item.branch),
    );
    exhibitions = _distinct(
      pieces.where((item) => (item.branchType ?? '').toLowerCase() == 'exhibition').map((item) => item.branch),
    );
  }

  List<String> places(String mode) {
    return switch (mode) {
      'Counter' => counters,
      'Box' => boxes,
      'Branch' => branches,
      'Exhibition' => exhibitions,
      _ => const ['All labelled stock'],
    };
  }

  List<InventoryPiece> select({
    required String mode,
    required String scope,
    required Set<String> categoriesSelected,
    required Set<String> productsSelected,
    required Set<String> designsSelected,
  }) {
    bool allows(String? value, Set<String> selected, List<String> all) {
      if (all.isEmpty) return true;
      if (value == null || value.isEmpty) return selected.length == all.length;
      return selected.contains(value);
    }

    return pieces.where((item) {
      if (!_inPlace(item, mode, scope)) return false;
      return allows(item.category, categoriesSelected, categories) &&
          allows(item.product, productsSelected, products) &&
          allows(item.design, designsSelected, designs);
    }).toList();
  }

  InventoryPiece? byId(String id) => _byId[id];

  /// Returns the item id for a reader EPC or TID. Unknown tags return null.
  String? match(String raw) {
    final key = _norm(raw);
    if (key.isEmpty) return null;
    final direct = _keyToId[key];
    if (direct != null) return direct;
    final stripped = _strip(key);
    if (stripped != key) return _keyToId[stripped];
    return null;
  }

  bool known(String raw) => match(raw) != null;

  bool _inPlace(InventoryPiece item, String mode, String scope) {
    final value = switch (mode) {
      'Counter' => item.counter,
      'Box' => item.box,
      'Branch' => item.branch,
      'Exhibition' => item.branch,
      _ => scope,
    };
    if (mode == 'Display') return true;
    return (value ?? '').toLowerCase() == scope.toLowerCase();
  }

  void _index(String id, String? raw) {
    final key = _norm(raw ?? '');
    if (key.isEmpty) return;
    _keyToId[key] = id;
    final stripped = _strip(key);
    if (stripped.isNotEmpty && stripped != key) _keyToId[stripped] = id;
  }

  Future<List<StoredRecord>> _pages(String kind) async {
    final all = <StoredRecord>[];
    const size = 800;
    for (var offset = 0; ; offset += size) {
      final page = await Injection.searchStoredRecords(
        kind: kind,
        limit: size,
        offset: offset,
      );
      all.addAll(page);
      if (page.length < size) break;
      await Future<void>.delayed(Duration.zero);
    }
    return all;
  }

  InventoryPiece? _piece(StoredRecord record) {
    final json = record.payload;
    final id = record.itemCode ?? _text(json, const ['ItemCode', 'itemCode']);
    if (id == null || id.isEmpty) return null;
    final gross = _grams(json, const ['GrossWt', 'grossWt', 'GrossWeight', 'grossWeight', 'TotalGwt']);
    final net = _grams(json, const ['NetWt', 'netWt', 'NetWeight', 'netWeight']);
    return InventoryPiece(
      id: id,
      category: _text(json, const ['CategoryName', 'categoryName']) ?? 'Uncategorised',
      product: record.name ?? _text(json, const ['ProductName', 'productName']),
      design: _text(json, const ['DesignName', 'designName']),
      milligrams: gross,
      rfid: record.rfid ?? _text(json, const ['RFIDCode', 'Rfid', 'rfid']),
      epc: _text(json, const ['EPC', 'epc', 'Epc']),
      tid: _text(json, const ['TidValue', 'TIDNumber', 'TidNumber']),
      netMilligrams: net == 0 ? null : net,
      purity: _text(json, const ['PurityName', 'Purity', 'purity']),
      weightKnown: gross > 0,
      counter: _text(json, const ['CounterName', 'counterName']),
      box: _text(json, const ['BoxName', 'boxName']),
      branch: _text(json, const ['BranchName', 'branchName']),
      branchType: _text(json, const ['BranchType', 'branchType']),
    );
  }

  List<String> _distinct(Iterable<String?> values) {
    final set = <String>{};
    for (final value in values) {
      final text = value?.trim() ?? '';
      if (text.isNotEmpty) set.add(text);
    }
    final list = set.toList()..sort();
    return list;
  }

  String? _text(Map<String, dynamic> json, List<String> keys) {
    for (final key in keys) {
      final value = json[key]?.toString().trim();
      if (value != null && value.isNotEmpty && value.toLowerCase() != 'null') return value;
    }
    return null;
  }

  int _grams(Map<String, dynamic> json, List<String> keys) {
    final raw = _text(json, keys);
    final value = double.tryParse(raw ?? '');
    if (value == null || value <= 0) return 0;
    return (value * 1000).round();
  }

  String _norm(String raw) => raw.trim().toUpperCase().replaceAll(' ', '');

  String _strip(String key) {
    var text = key;
    if (text.length > 2 && text.startsWith('00')) text = text.substring(2);
    if (text.length > 2 && text.endsWith('00')) text = text.substring(0, text.length - 2);
    return text;
  }
}

int signalBars(String rssi) {
  final value = double.tryParse(rssi.trim());
  if (value == null) return 3;
  final clamped = value.clamp(-85, -35);
  return (((clamped + 85) / 5).round()).clamp(1, 10);
}
