class StockItem {
  const StockItem({
    required this.itemCode,
    required this.name,
    this.rfid = '',
    this.gross = '',
    this.net = '',
    this.design = '',
    this.extras = const {},
  });

  final String itemCode;
  final String name;
  final String rfid;
  final String gross;
  final String net;
  final String design;

  /// Extra labelled-stock values, keyed without spaces or punctuation.
  final Map<String, String> extras;

  String get identity => itemCode.isEmpty ? rfid : itemCode;
}
