class QuotationField {
  const QuotationField({
    required this.key,
    required this.label,
    required this.placeholder,
    required this.place,
    required this.priority,
    required this.type,
    this.readOnly = false,
    this.suffix = '',
  });

  final String key;
  final String label;
  final String placeholder;
  final String place;
  final int priority;
  final String type;
  final bool readOnly;
  final String suffix;

  String get token => _token('$key $label');

  String get keyToken => _token(key);

  String get labelToken => _token(label);

  bool get isAction {
    final kind = type.toLowerCase();
    final slot = place.toLowerCase();
    if (kind.contains('button') || slot == 'button') return true;
    return _isWord(keyToken, _actions) || _isWord(labelToken, _actions);
  }

  bool get isChrome {
    return _isChrome(keyToken) || _isChrome(labelToken);
  }

  bool get isGstLabel {
    final name = '$keyToken $labelToken';
    return name.contains('gst') && !name.contains('amt') && !name.contains('amount');
  }

  bool get showsAsValue {
    final kind = type.toLowerCase();
    final slot = place.toLowerCase();
    return readOnly ||
        kind.contains('read') ||
        kind.contains('label') ||
        kind.contains('display') ||
        slot == 'top' ||
        slot == 'header';
  }

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

  static const _actions = {
    'cancel',
    'save',
    'scan',
    'submit',
    'close',
    'back',
    'ok',
  };

  static bool _isWord(String value, Set<String> words) {
    if (words.contains(value)) return true;
    final bare = value.startsWith('btn') ? value.substring(3) : value;
    return words.contains(bare);
  }

  static bool _isChrome(String value) {
    if (value.isEmpty) return false;
    return value.contains('summary') ||
        value == 'qty' ||
        value == 'quantity' ||
        value == 'total' ||
        value.contains('gst') ||
        value.contains('totalwithgst');
  }

  static String _token(String value) =>
      value.toLowerCase().replaceAll(RegExp('[^a-z0-9]'), '');
}
