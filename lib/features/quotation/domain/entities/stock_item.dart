class StockItem {
  const StockItem({
    required this.itemCode,
    required this.name,
    this.rfid = '',
    this.gross = '',
    this.net = '',
    this.design = '',
  });

  final String itemCode;
  final String name;
  final String rfid;
  final String gross;
  final String net;
  final String design;

  String get identity => itemCode.isEmpty ? rfid : itemCode;
}
