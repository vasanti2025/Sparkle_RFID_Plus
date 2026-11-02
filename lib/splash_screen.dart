import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'login_screen.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    Future<void>.delayed(const Duration(milliseconds: 1600), () {
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(builder: (_) => const LoginScreen()),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return const ColoredBox(
      color: Color(0xFF000000),
      child: SafeArea(
        child: _SplashBody(),
      ),
    );
  }
}

class _SplashBody extends StatelessWidget {
  const _SplashBody();

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth;
        final h = constraints.maxHeight;
        final logoW = math.min(w * 0.52, math.min(200.0, h * 0.36));
        return Stack(
          children: [
            Positioned(
              left: 0,
              right: 0,
              top: (h - logoW) / 2,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Image.asset(
                    'assets/branding/LS_logo.jpg',
                    width: logoW,
                    height: logoW,
                    fit: BoxFit.contain,
                    filterQuality: FilterQuality.medium,
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    'Every piece matters.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Color(0xFFD9D6CE),
                      fontSize: 16,
                      height: 1.4,
                    ),
                  ),
                  const Text(
                    'Make every moment count.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Color(0xFFE6C477),
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),
            const Positioned(
              left: 16,
              right: 16,
              bottom: 16,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Intelligent Jewellery Operations',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Color(0xFF96938C),
                      fontSize: 12,
                      height: 1.45,
                    ),
                  ),
                  Text(
                    'Loyal String International Pvt Ltd.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Color(0xFF96938C),
                      fontSize: 12,
                      height: 1.45,
                    ),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}
