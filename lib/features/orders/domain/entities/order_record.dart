class OrderRecord {
  const OrderRecord({
    required this.id,
    required this.number,
    required this.customerName,
    required this.amount,
    required this.source,
  });

  final int id;
  final String number;
  final String customerName;
  final String amount;
  final Map<String, dynamic> source;

  String get searchText =>
      '${number.toLowerCase()} ${customerName.toLowerCase()} ${amount.toLowerCase()}';
}
