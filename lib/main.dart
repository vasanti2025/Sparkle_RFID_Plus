import 'package:flutter/material.dart';

import 'app.dart';
import 'core/di/injection.dart';
import 'core/locale/app_language.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await AppLanguage.instance.load();
  await Injection.init();
  runApp(const SparkleRfidPlusApp());
}
