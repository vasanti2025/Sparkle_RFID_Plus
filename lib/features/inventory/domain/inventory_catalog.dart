class InventoryPiece {
  const InventoryPiece({
    required this.id,
    required this.category,
    required this.product,
    required this.design,
    required this.milligrams,
    this.rfid,
    this.epc,
    this.tid,
    this.netMilligrams,
    this.purity,
    this.weightKnown = true,
    this.counter,
    this.box,
    this.branch,
    this.branchType,
  });

  final String id;
  final String? category;
  final String? product;
  final String? design;
  final int milligrams;
  final String? rfid;
  final String? epc;
  final String? tid;
  final int? netMilligrams;
  final String? purity;
  final bool weightKnown;
  final String? counter;
  final String? box;
  final String? branch;
  final String? branchType;

  String get name => product ?? 'Jewellery item';
}

abstract final class InventoryCatalog {
  static const categories = ['GOLD'];
  static const products = [
    'Ring',
    'Bangles',
    'Necklace',
    'Brooch',
    'Gold ornament',
  ];
  static const designs = [
    'Abstract',
    'Fancy Ring',
    'Fancy',
    'Solid bangles',
    'Half stone & plain',
  ];

  static final List<InventoryPiece> items = _build();

  static List<InventoryPiece> selected({
    required Set<String> categoriesSelected,
    required Set<String> productsSelected,
    required Set<String> designsSelected,
  }) {
    bool allows(String? value, Set<String> selected, List<String> all) {
      if (value == null) return selected.length == all.length;
      return selected.contains(value);
    }

    return items
        .where(
          (item) =>
              allows(item.category, categoriesSelected, categories) &&
              allows(item.product, productsSelected, products) &&
              allows(item.design, designsSelected, designs),
        )
        .toList();
  }

  static String grams(int milligrams) {
    final fixed = (milligrams / 1000).toStringAsFixed(3);
    final parts = fixed.split('.');
    final whole = parts[0];
    final grouped = StringBuffer();
    for (var i = 0; i < whole.length; i++) {
      if (i > 0 && (whole.length - i) % 3 == 0) grouped.write(',');
      grouped.write(whole[i]);
    }
    return '${grouped.toString()}.${parts[1]}';
  }

  static List<InventoryPiece> _build() {
    const counts = [86, 64, 58, 28, 41];
    const bases = [6100, 21000, 25500, 8100, 16000];
    final raw = <({String product, String design, int base})>[];
    for (var group = 0; group < products.length; group++) {
      for (var i = 0; i < counts[group]; i++) {
        raw.add((
          product: products[group],
          design: designs[(i + group) % designs.length],
          base: bases[group] + i * 9,
        ));
      }
    }
    final baseTotal = raw.skip(1).fold<int>(0, (sum, item) => sum + item.base);
    var assigned = 11001;
    final weights = <int>[];
    for (var i = 0; i < raw.length; i++) {
      final weight = i == 0
          ? 11001
          : i == 276
          ? 3887583 - assigned
          : (raw[i].base / baseTotal * 3876582).round();
      if (i > 0) assigned += weight;
      weights.add(weight);
    }
    final pieces = <InventoryPiece>[
      for (var i = 0; i < raw.length; i++)
        InventoryPiece(
          id: 'SPK-${(i + 1).toString().padLeft(4, '0')}',
          category: 'GOLD',
          product: raw[i].product,
          design: raw[i].design,
          milligrams: weights[i],
          rfid: 'DEMO-${(i + 1).toString().padLeft(4, '0')}',
        ),
    ];
    const source = [
      ('SM003', 'BS0170'),
      ('SM004', 'BS0153'),
      ('SM005', 'BS0182'),
      ('SM006', 'BS0136'),
      ('SM007', 'BS0180'),
      ('SM008', 'BS0192'),
      ('SM009', 'BS0200'),
      ('SM010', 'BS0159'),
    ];
    for (var i = 0; i < source.length; i++) {
      final current = pieces[i + 1];
      pieces[i + 1] = InventoryPiece(
        id: source[i].$1,
        category: current.category,
        product: source[i].$1 == 'SM007' ? 'Brooch' : null,
        design: 'Abstract',
        milligrams: i < 7 ? 8000 : current.milligrams,
        rfid: source[i].$2,
        epc: source[i].$1 == 'SM007' ? 'E2801191A50300614864EBF5' : null,
        netMilligrams: source[i].$1 == 'SM007' ? 8000 : null,
        purity: source[i].$1 == 'SM007' ? '18K' : null,
        weightKnown: i < 7,
      );
    }
    for (var i = 0; i < 4; i++) {
      final current = pieces[i + 9];
      pieces[i + 9] = InventoryPiece(
        id: ['LS001', 'LS003', 'LS004', 'LS005'][i],
        category: current.category,
        product: null,
        design: null,
        milligrams: current.milligrams,
        weightKnown: false,
      );
    }
    return pieces;
  }
}
