import 'dart:convert';

/// Decodes an order list off the UI isolate.
List<Map<String, dynamic>> parseOrderRows(String raw) {
  if (raw.trim().isEmpty) return const [];
  return _rows(jsonDecode(raw), 0);
}

List<Map<String, dynamic>> _rows(dynamic body, int depth) {
  if (depth > 4 || body == null) return const [];
  if (body is List) {
    return [
      for (final row in body)
        if (row is Map) Map<String, dynamic>.from(row),
    ];
  }
  if (body is Map) {
    for (final key in const [
      'data',
      'Data',
      'items',
      'Items',
      'result',
      'Result',
      'orders',
      'Orders',
      'CustomOrders',
    ]) {
      final nested = body[key];
      if (nested is List || nested is Map) {
        final rows = _rows(nested, depth + 1);
        if (rows.isNotEmpty) return rows;
      }
    }
  }
  return const [];
}
