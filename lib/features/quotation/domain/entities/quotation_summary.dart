class QuotationSummary {
  const QuotationSummary({
    required this.id,
    required this.number,
    required this.customerName,
    required this.amount,
  });

  final int id;
  final String number;
  final String customerName;
  final String amount;

  String get searchText =>
      '${number.toLowerCase()} ${customerName.toLowerCase()} ${amount.toLowerCase()}';
}
