import 'package:flutter/widgets.dart';

import '../../../core/di/injection.dart';
import 'pages/order_list_page.dart';
import 'pages/orders_page.dart';

/// POS on uses the permission-driven order list. POS off keeps the Sparkle screen.
Widget ordersScreen() {
  if (Injection.settings.enablePos) return const OrderListPage();
  return const OrdersPage();
}
