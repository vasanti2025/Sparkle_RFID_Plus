class StoredRecord {
  const StoredRecord({
    required this.kind,
    required this.payload,
    this.itemCode,
    this.rfid,
    this.barcode,
    this.name,
  });

  static const kindProduct = 'product';
  static const kindRfid = 'rfid';

  final String kind;
  final Map<String, dynamic> payload;
  final String? itemCode;
  final String? rfid;
  final String? barcode;
  final String? name;
}
