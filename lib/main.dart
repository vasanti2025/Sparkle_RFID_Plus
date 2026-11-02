import 'package:flutter/material.dart';

import 'app.dart';
import 'core/di/injection.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Injection.init();
  runApp(const SparkleRfidPlusApp());
}
