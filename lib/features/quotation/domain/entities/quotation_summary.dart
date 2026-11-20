class QuotationSummary {
  const QuotationSummary({
    required this.id,
    required this.number,
    required this.customerName,
    required this.amount,
    this.branch = '',
    this.date = '',
    this.pieces = 0,
    this.gross = '',
    this.net = '',
  });

  final int id;
  final String number;
  final String customerName;
  final String amount;
  final String branch;
  final String date;
  final int pieces;
  final String gross;
  final String net;

  String get searchText =>
      '${number.toLowerCase()} ${customerName.toLowerCase()} ${amount.toLowerCase()} ${branch.toLowerCase()} ${date.toLowerCase()}';
}
