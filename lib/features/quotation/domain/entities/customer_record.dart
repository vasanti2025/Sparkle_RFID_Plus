class CustomerRecord {
  const CustomerRecord({
    required this.id,
    required this.name,
    required this.mobile,
    this.email = '',
  });

  final int id;
  final String name;
  final String mobile;
  final String email;
}

/// Compact name index. Search stops after [limit] hits so a large
/// customer list does not build a widget for every row.
class CustomerIndex {
  CustomerIndex(List<CustomerRecord> records)
    : records = List<CustomerRecord>.unmodifiable(records),
      _names = records.map((record) => record.name.toLowerCase()).toList(),
      _mobiles = records.map((record) => record.mobile).toList();

  final List<CustomerRecord> records;
  final List<String> _names;
  final List<String> _mobiles;

  List<CustomerRecord> search(String query, {int limit = 40}) {
    final needle = query.trim().toLowerCase();
    if (needle.isEmpty) {
      if (records.length <= limit) return records;
      return records.sublist(0, limit);
    }
    final matches = <CustomerRecord>[];
    for (var i = 0; i < records.length; i++) {
      if (_names[i].contains(needle) || _mobiles[i].contains(query.trim())) {
        matches.add(records[i]);
        if (matches.length == limit) break;
      }
    }
    return matches;
  }

  CustomerIndex add(CustomerRecord record) {
    return CustomerIndex([...records, record]);
  }
}
