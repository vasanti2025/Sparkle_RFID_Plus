class ProductSyncProgress {
  const ProductSyncProgress({
    required this.message,
    this.fraction,
    this.received = 0,
    this.total = 0,
    this.completed = false,
    this.failed = false,
  });

  final String message;
  final double? fraction;
  final int received;
  final int total;
  final bool completed;
  final bool failed;
}
