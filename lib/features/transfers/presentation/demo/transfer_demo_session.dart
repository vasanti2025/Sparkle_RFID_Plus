import '../../../../core/constants/app_strings.dart';

class TransferPiece {
  const TransferPiece({
    required this.id,
    required this.name,
    required this.rfid,
    required this.grossMg,
    required this.netMg,
  });

  final String id;
  final String name;
  final String rfid;
  final int? grossMg;
  final int? netMg;
}

class DemoTransfer {
  const DemoTransfer({
    required this.id,
    required this.from,
    required this.to,
    required this.ids,
    required this.gross,
    required this.net,
  });

  final String id;
  final String from;
  final String to;
  final List<String> ids;
  final int? gross;
  final int? net;
}

class TransferDemoSession {
  TransferDemoSession() {
    catalog = _catalogue();
    for (final entry in places.entries) {
      for (final place in entry.value) {
        locations['${entry.key}:$place'] = <String>[];
      }
    }
    locations['Packet:Packet A'] = catalog.take(6).map((piece) => piece.id).toList();
  }

  static final instance = TransferDemoSession();

  static const routes = <(String, String)>[
    ('Packet', 'Packet'),
    ('Packet', 'Box'),
    ('Packet', 'Display'),
    ('Packet', 'Salesman'),
    ('Box', 'Box'),
    ('Box', 'Packet'),
  ];

  static const places = <String, List<String>>{
    'Packet': ['Packet A', 'Packet B'],
    'Box': ['Box A', 'Box B'],
    'Display': ['Display A', 'Display B'],
    'Salesman': ['Salesman A', 'Salesman B'],
  };

  late final List<TransferPiece> catalog;
  final locations = <String, List<String>>{};
  final transfers = <DemoTransfer>[];
  final selected = <String>{};
  int route = 1;
  String from = 'Packet A';
  String to = 'Box B';
  String query = '';
  bool onlySelected = false;

  (String, String) get kinds => routes[route];

  List<TransferPiece> available() {
    final ids = locations['${kinds.$1}:$from'] ?? const <String>[];
    return [for (final id in ids) ?_byId(id)];
  }

  List<TransferPiece> chosen() {
    final here = available();
    return here.where((piece) => selected.contains(piece.id)).toList();
  }

  List<TransferPiece> shown() {
    final needle = query.trim().toLowerCase();
    return available().where((piece) {
      final haystack = '${piece.id} ${piece.name}'.toLowerCase();
      if (!haystack.contains(needle)) return false;
      if (onlySelected && !selected.contains(piece.id)) return false;
      return true;
    }).toList();
  }

  bool toggle(String id, bool on) {
    if (available().every((piece) => piece.id != id)) return false;
    if (on) {
      selected.add(id);
    } else {
      selected.remove(id);
    }
    return true;
  }

  void applyRoute(int nextRoute, String nextFrom, String nextTo) {
    final previous = '${kinds.$1}:$from';
    final nextKey = '${routes[nextRoute].$1}:$nextFrom';
    final keep = previous == nextKey ? Set<String>.of(selected) : <String>{};
    route = nextRoute;
    from = nextFrom;
    to = nextTo;
    final allowed = available().map((piece) => piece.id).toSet();
    selected
      ..clear()
      ..addAll(keep.where(allowed.contains));
  }

  TransferPiece? nextUnread() {
    for (final piece in available()) {
      if (piece.rfid.isNotEmpty && !selected.contains(piece.id)) return piece;
    }
    return null;
  }

  List<String> errors() {
    final fromPlaces = places[kinds.$1] ?? const <String>[];
    final toPlaces = places[kinds.$2] ?? const <String>[];
    final messages = <String>[];
    if (!fromPlaces.contains(from) || !toPlaces.contains(to)) {
      messages.add(AppStrings.validRoute);
    } else if ('${kinds.$1}:$from' == '${kinds.$2}:$to') {
      messages.add(AppStrings.sourceDestDifferent);
    }
    if (selected.isEmpty) messages.add(AppStrings.selectOnePiece);
    final here = available().map((piece) => piece.id).toSet();
    if (selected.any((id) => !here.contains(id))) {
      messages.add(AppStrings.stockChanged);
    }
    return messages;
  }

  DemoTransfer? confirm() {
    if (errors().isNotEmpty) return null;
    final items = chosen();
    final totals = weightOf(items);
    final ids = items.map((piece) => piece.id).toList();
    final source = '${kinds.$1}:$from';
    final destination = '${kinds.$2}:$to';
    locations[source] = [
      for (final id in locations[source] ?? const <String>[])
        if (!ids.contains(id)) id,
    ];
    final merged = <String>[...(locations[destination] ?? const <String>[])];
    for (final id in ids) {
      if (!merged.contains(id)) merged.add(id);
    }
    locations[destination] = merged;
    final record = DemoTransfer(
      id: 'DEMO-T${(transfers.length + 1).toString().padLeft(3, '0')}',
      from: from,
      to: to,
      ids: ids,
      gross: totals.$1,
      net: totals.$2,
    );
    transfers.insert(0, record);
    selected.clear();
    return record;
  }

  TransferPiece? _byId(String id) {
    for (final piece in catalog) {
      if (piece.id == id) return piece;
    }
    return null;
  }

  static (int?, int?) weightOf(List<TransferPiece> items) {
    int? sum(int? Function(TransferPiece piece) pick) {
      if (items.any((piece) => pick(piece) == null)) return null;
      return items.fold<int>(0, (total, piece) => total + (pick(piece) ?? 0));
    }

    return (sum((piece) => piece.grossMg), sum((piece) => piece.netMg));
  }

  static String grams(int? milligrams) {
    if (milligrams == null) return '—';
    final fixed = (milligrams / 1000).toStringAsFixed(3);
    final parts = fixed.split('.');
    final whole = parts[0];
    final grouped = StringBuffer();
    for (var i = 0; i < whole.length; i++) {
      if (i > 0 && (whole.length - i) % 3 == 0) grouped.write(',');
      grouped.write(whole[i]);
    }
    return '${grouped.toString()}.${parts[1]}';
  }

  static List<TransferPiece> _catalogue() {
    TransferPiece necklace(String id) => TransferPiece(
      id: id,
      name: 'Necklace',
      rfid: 'DEMO-$id',
      grossMg: 57974,
      netMg: 57974,
    );
    return [
      for (final id in ['GNK54', 'GNK53', 'GNK52', 'GNK51', 'GNK50', 'GNK49'])
        necklace(id),
      const TransferPiece(
        id: 'ST6',
        name: 'Thali',
        rfid: 'DEMO-ST6',
        grossMg: 50000,
        netMg: 50000,
      ),
      const TransferPiece(
        id: 'GR5',
        name: 'Ring',
        rfid: 'DEMO-GR5',
        grossMg: 0,
        netMg: null,
      ),
    ];
  }
}
