class QuotationField {
  const QuotationField({
    required this.key,
    required this.label,
    required this.placeholder,
    required this.place,
    required this.priority,
    required this.type,
  });

  final String key;
  final String label;
  final String placeholder;
  final String place;
  final int priority;
  final String type;

  bool get isCustomer =>
      key.toLowerCase().contains('customer') ||
      label.toLowerCase().contains('customer');

  bool get isItemLookup => _lookupKeys.contains(key.toLowerCase()) ||
      label.toLowerCase().contains('rfid') ||
      label.toLowerCase().contains('item code') ||
      label.toLowerCase().contains('tag');

  static const _lookupKeys = {
    'itemcode',
    'rfidcode',
    'tidnumber',
    'tagnumber',
    'tagno',
  };
}
