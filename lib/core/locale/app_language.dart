import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// English, Hindi, and Arabic for the order and quotation screens.
class AppLanguage extends ChangeNotifier {
  AppLanguage._();

  static final AppLanguage instance = AppLanguage._();

  static const supported = ['en', 'hi', 'ar'];

  String code = 'en';

  bool get isArabic => code == 'ar';

  TextDirection get direction => isArabic ? TextDirection.rtl : TextDirection.ltr;

  String get shortLabel => switch (code) {
        'hi' => 'हि',
        'ar' => 'ع',
        _ => 'EN',
      };

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString('oq_language') ?? 'en';
    if (supported.contains(saved)) code = saved;
  }

  Future<void> setCode(String value) async {
    if (!supported.contains(value) || value == code) return;
    code = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('oq_language', value);
  }
}

/// Wraps an order or quotation screen so a language change rebuilds it.
class OrderQuotationScope extends StatelessWidget {
  const OrderQuotationScope({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: AppLanguage.instance,
      builder: (context, _) {
        return Directionality(
          textDirection: AppLanguage.instance.direction,
          child: child,
        );
      },
    );
  }
}

