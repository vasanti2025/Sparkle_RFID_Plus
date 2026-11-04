import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/constants/app_strings.dart';
import '../../../../core/constants/asset_paths.dart';
import '../../../../core/di/injection.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../auth/domain/entities/user.dart';
import '../../../auth/presentation/pages/login_page.dart';
import '../../../home/presentation/pages/home_page.dart';

class SplashPage extends StatefulWidget {
  const SplashPage({super.key});

  @override
  State<SplashPage> createState() => _SplashPageState();
}

class _SplashPageState extends State<SplashPage> {
  Future<User?> _restoredUser() async {
    if (!Injection.ready) return null;
    try {
      return await Injection.restoreSession();
    } catch (_) {
      return null;
    }
  }

  @override
  void initState() {
    super.initState();
    Future<void>.delayed(AppConstants.splashDuration, () async {
      if (!mounted) return;
      SystemChrome.setSystemUIOverlayStyle(_lightScreenOverlay);
      final user = await _restoredUser();
      if (!mounted) return;
      if (user != null) {
        unawaited(Injection.productSync.start(user));
        Navigator.of(context).pushReplacement(
          MaterialPageRoute<void>(builder: (_) => const HomePage()),
        );
        return;
      }
      Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(builder: (_) => const LoginPage()),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return const AnnotatedRegion<SystemUiOverlayStyle>(
      value: _splashOverlay,
      child: ColoredBox(
        color: AppColors.black,
        child: SafeArea(child: _SplashBody()),
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
        return Padding(
          padding: EdgeInsets.fromLTRB(24, 0, 24, 12),
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
        );
      },
    );
  }
}

const _splashOverlay = SystemUiOverlayStyle(
  statusBarColor: Color(0x00000000),
  statusBarIconBrightness: Brightness.light,
  statusBarBrightness: Brightness.dark,
  systemNavigationBarColor: AppColors.black,
  systemNavigationBarIconBrightness: Brightness.light,
);

const _lightScreenOverlay = SystemUiOverlayStyle(
  statusBarColor: Color(0x00000000),
  statusBarIconBrightness: Brightness.dark,
  statusBarBrightness: Brightness.light,
  systemNavigationBarColor: AppColors.white,
  systemNavigationBarIconBrightness: Brightness.dark,
);
