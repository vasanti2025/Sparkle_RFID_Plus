import 'package:flutter/material.dart';

import 'splash_screen.dart';

void main() {
  runApp(const SparkleRfidPlusApp());
}

class SparkleRfidPlusApp extends StatelessWidget {
  const SparkleRfidPlusApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Sparkle RFID Plus',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        scaffoldBackgroundColor: const Color(0xFFF6F5F2),
      ),
      home: const SplashScreen(),
    );
  }
}
