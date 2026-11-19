import 'package:flutter/widgets.dart';

import '../../../core/di/injection.dart';
import 'pages/quotation_list_page.dart';
import 'pages/sparkle_quotation_page.dart';

/// POS on keeps the current quotation list and POS form.
/// POS off opens the Sparkle quotation screen.
Widget quotationScreen() {
  if (Injection.settings.enablePos) return const QuotationListPage();
  return const SparkleQuotationPage();
}
