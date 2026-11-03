import 'package:flutter/material.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/constants/app_strings.dart';
import '../../../../core/constants/asset_paths.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../auth/presentation/pages/login_page.dart';

class SplashPage extends StatefulWidget {
  const SplashPage({super.key});

  @override
  State<SplashPage> createState() => _SplashPageState();
}

class _SplashPageState extends State<SplashPage> {
  @override
  void initState() {
    super.initState();
    Future<void>.delayed(AppConstants.splashDuration, () {
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(builder: (_) => const LoginPage()),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return const ColoredBox(
      color: AppColors.black,
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
        final logoW = (constraints.maxWidth * 0.58).clamp(160.0, 260.0);
        return Stack(
          fit: StackFit.expand,
          children: [
            const CustomPaint(painter: _SplashRingsPainter()),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 12),
              child: Column(
                children: [
                  const Spacer(flex: 5),
                  Image.asset(
                    AssetPaths.splashLogo,
                    width: logoW,
                    fit: BoxFit.contain,
                    filterQuality: FilterQuality.high,
                  ),
                  const SizedBox(height: 18),
                  Text(
                    AppStrings.everyPieceMatters,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontFamily: 'Inter',
                      fontFamilyFallback: <String>[],
                      color: AppColors.splashBody,
                      fontSize: AppTypography.body,
                      fontWeight: FontWeight.w400,
                      height: 1.35,
                      decoration: TextDecoration.none,
                    ),
                  ),
                  Text(
                    AppStrings.makeEveryMomentCount,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontFamily: 'Inter',
                      fontFamilyFallback: <String>[],
                      color: AppColors.champagne,
                      fontSize: AppTypography.body,
                      fontWeight: FontWeight.w600,
                      height: 1.35,
                      decoration: TextDecoration.none,
                    ),
                  ),
                  const Spacer(flex: 6),
                  Text(
                    AppStrings.intelligentJewelleryOperations,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontFamily: 'Inter',
                      fontFamilyFallback: <String>[],
                      color: AppColors.splashMuted,
                      fontSize: AppTypography.brandSubtitle,
                      fontWeight: FontWeight.w400,
                      height: 1.45,
                      decoration: TextDecoration.none,
                    ),
                  ),
                  Text(
                    AppStrings.companyName,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontFamily: 'Inter',
                      fontFamilyFallback: <String>[],
                      color: AppColors.splashMuted,
                      fontSize: AppTypography.brandSubtitle,
                      fontWeight: FontWeight.w400,
                      height: 1.45,
                      decoration: TextDecoration.none,
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

class _SplashRingsPainter extends CustomPainter {
  const _SplashRingsPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height * 0.40);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = const Color(0x18FFFFFF);
    final base = size.shortestSide;
    canvas.drawCircle(center, base * 0.34, paint);
    canvas.drawCircle(center, base * 0.50, paint);
  }

  @override
  bool shouldRepaint(covariant _SplashRingsPainter oldDelegate) => false;
}
