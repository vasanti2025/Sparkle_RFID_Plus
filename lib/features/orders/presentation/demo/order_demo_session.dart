import '../../../../core/constants/app_strings.dart';

class OrderPiece {
  OrderPiece({
    required this.id,
    required this.name,
    required this.rfid,
    this.grossMg,
    this.netMg,
    this.fwMg,
    this.totalMg,
    this.packingMg,
    this.branch,
  });

  final String id;
  final String name;
  final String rfid;
  int? grossMg;
  int? netMg;
  int? fwMg;
  int? totalMg;
  int? packingMg;
  String? branch;

  OrderPiece copy() => OrderPiece(
    id: id,
    name: name,
    rfid: rfid,
    grossMg: grossMg,
    netMg: netMg,
    fwMg: fwMg,
    totalMg: totalMg,
    packingMg: packingMg,
    branch: branch,
  );
}

class OrderDetails {
  OrderDetails({
    this.branch = 'B1-Deepikaspk',
    this.exhibition = '',
    this.remark = '',
    this.purity = '',
    this.size = '',
    this.length = '',
    this.colour = 'Yellow Gold',
    this.screw = 'Type 1',
    this.polish = 'High Polish',
    this.fine = '',
    this.wastage = '',
    this.orderDate = '2026-09-19',
    this.deliveryDate = '2026-09-26',
  });

  String branch;
  String exhibition;
  String remark;
  String purity;
  String size;
  String length;
  String colour;
  String screw;
  String polish;
  String fine;
  String wastage;
  String orderDate;
  String deliveryDate;

  OrderDetails copy() => OrderDetails(
    branch: branch,
    exhibition: exhibition,
    remark: remark,
    purity: purity,
    size: size,
    length: length,
    colour: colour,
    screw: screw,
    polish: polish,
    fine: fine,
    wastage: wastage,
    orderDate: orderDate,
    deliveryDate: deliveryDate,
  );
}

class DemoOrder {
  DemoOrder({
    this.id,
    this.customer = '',
    List<OrderPiece>? items,
    OrderDetails? details,
    this.gst = false,
    this.dirty = false,
  }) : items = items ?? [],
       details = details ?? OrderDetails();

  String? id;
  String customer;
  List<OrderPiece> items;
  OrderDetails details;
  bool gst;
  bool dirty;

  DemoOrder copy() => DemoOrder(
    id: id,
    customer: customer,
    items: items.map((item) => item.copy()).toList(),
    details: details.copy(),
    gst: gst,
    dirty: dirty,
  );
}

class OrderTotals {
  const OrderTotals({
    required this.count,
    required this.gross,
    required this.net,
    required this.fw,
  });

  final int count;
  final int? gross;
  final int? net;
  final int? fw;
}

class OrderDemoSession {
  OrderDemoSession() {
    catalog = _catalogue();
    orders = [
      _saved('DEMO-001', 'Madhuri', ['ST6']),
      _saved('DEMO-002', 'Madhuri', ['GNK53']),
      _saved('DEMO-003', 'Demo customer', ['GR5']),
    ];
  }

  static final instance = OrderDemoSession();

  late final List<OrderPiece> catalog;
  final customers = <String>['Madhuri', 'Demo customer'];
  late final List<DemoOrder> orders;
  DemoOrder? draft;
  String query = '';
  String view = 'orders';
  String dateField = 'orderDate';
  String from = '';
  String to = '';

  List<DemoOrder> get visible {
    return orders.where((order) {
      final haystack = '${order.id} ${order.customer}'.toLowerCase();
      if (!haystack.contains(query.trim().toLowerCase())) return false;
      final date = dateField == 'deliveryDate'
          ? order.details.deliveryDate
          : order.details.orderDate;
      if (from.isNotEmpty && date.compareTo(from) < 0) return false;
      if (to.isNotEmpty && date.compareTo(to) > 0) return false;
      return true;
    }).toList();
  }

  void startNew() {
    draft = DemoOrder();
  }

  void startEdit(String id) {
    final order = orders.cast<DemoOrder?>().firstWhere(
      (item) => item?.id == id,
      orElse: () => null,
    );
    draft = order?.copy() ?? DemoOrder();
    draft?.dirty = false;
  }

  bool addItem(String id) {
    final current = draft;
    if (current == null) return false;
    final piece = _find(id);
    if (piece == null || current.items.any((item) => item.id == piece.id)) {
      return false;
    }
    current.items.add(piece.copy());
    current.dirty = true;
    return true;
  }

  void removeItem(String id) {
    final current = draft;
    if (current == null) return;
    final before = current.items.length;
    current.items.removeWhere((item) => item.id == id);
    if (current.items.length != before) current.dirty = true;
  }

  List<String> orderErrors(DemoOrder order) {
    final errors = <String>[];
    if (order.customer.trim().isEmpty) errors.add(AppStrings.chooseACustomer);
    if (order.items.isEmpty) errors.add(AppStrings.addAtLeastOne);
    if (order.details.branch.trim().isEmpty) errors.add(AppStrings.chooseBranch);
    final delivery = order.details.deliveryDate;
    final placed = order.details.orderDate;
    if (delivery.isNotEmpty && placed.isNotEmpty && delivery.compareTo(placed) < 0) {
      errors.add(AppStrings.deliveryBeforeOrder);
    }
    return errors;
  }

  List<String> detailErrors(OrderDetails details) {
    final errors = <String>[];
    if (details.branch.trim().isEmpty) errors.add(AppStrings.chooseBranch);
    if (details.orderDate.isNotEmpty &&
        details.deliveryDate.isNotEmpty &&
        details.deliveryDate.compareTo(details.orderDate) < 0) {
      errors.add(AppStrings.deliveryBeforeOrder);
    }
    final fine = num.tryParse(details.fine);
    if (details.fine.isNotEmpty && (fine == null || fine < 0 || fine > 100)) {
      errors.add(AppStrings.fineRange);
    }
    final wastage = num.tryParse(details.wastage);
    if (details.wastage.isNotEmpty && (wastage == null || wastage < 0)) {
      errors.add(AppStrings.wastageNegative);
    }
    return errors;
  }

  DemoOrder? save() {
    final current = draft;
    if (current == null) return null;
    if (orderErrors(current).isNotEmpty) return null;
    final record = current.copy()..dirty = false;
    if (record.id == null) {
      final next = orders.fold<int>(0, (maxId, order) {
        final number = int.tryParse(order.id?.split('-').elementAtOrNull(1) ?? '') ?? 0;
        return number > maxId ? number : maxId;
      });
      record.id = 'DEMO-${(next + 1).toString().padLeft(3, '0')}';
    }
    final index = orders.indexWhere((order) => order.id == record.id);
    if (index < 0) {
      orders.insert(0, record);
    } else {
      orders[index] = record;
    }
    draft = record.copy();
    return record;
  }

  OrderPiece? nextUnread() {
    final current = draft;
    if (current == null) return null;
    for (final piece in catalog) {
      if (piece.rfid.isNotEmpty &&
          current.items.every((item) => item.id != piece.id)) {
        return piece;
      }
    }
    return null;
  }

  static OrderTotals totals(List<OrderPiece> items) {
    int? sum(int? Function(OrderPiece item) pick) {
      if (items.any((item) => pick(item) == null)) return null;
      return items.fold<int>(0, (total, item) => total + (pick(item) ?? 0));
    }

    return OrderTotals(
      count: items.length,
      gross: sum((item) => item.grossMg),
      net: sum((item) => item.netMg),
      fw: sum((item) => item.fwMg),
    );
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

  static String formatDate(String iso) {
    if (iso.isEmpty) return AppStrings.notSet;
    final parts = iso.split('-');
    if (parts.length != 3) return iso;
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    final month = int.tryParse(parts[1]) ?? 1;
    return '${parts[2]} ${months[(month - 1).clamp(0, 11)]} ${parts[0]}';
  }

  OrderPiece? _find(String id) {
    final needle = id.toLowerCase();
    for (final piece in catalog) {
      if (piece.id.toLowerCase() == needle || piece.rfid.toLowerCase() == needle) {
        return piece;
      }
    }
    return null;
  }

  DemoOrder _saved(String id, String customer, List<String> pieceIds) {
    return DemoOrder(
      id: id,
      customer: customer,
      items: [
        for (final pieceId in pieceIds)
          if (_find(pieceId) != null) _find(pieceId)!.copy(),
      ],
    );
  }

  static List<OrderPiece> _catalogue() {
    OrderPiece necklace(String id) => OrderPiece(
      id: id,
      name: 'Necklace',
      rfid: 'DEMO-$id',
      grossMg: 57974,
      netMg: 57974,
      fwMg: 0,
    );
    return [
      for (final id in ['GNK54', 'GNK53', 'GNK52', 'GNK51', 'GNK50', 'GNK49'])
        necklace(id),
      OrderPiece(
        id: 'ST6',
        name: 'Thali',
        rfid: 'DEMO-ST6',
        grossMg: 50000,
        netMg: 50000,
        fwMg: 0,
      ),
      OrderPiece(
        id: 'GR5',
        name: 'Ring',
        rfid: 'DEMO-GR5',
        grossMg: 0,
        totalMg: 5000,
        packingMg: 5000,
      ),
    ];
  }
}
