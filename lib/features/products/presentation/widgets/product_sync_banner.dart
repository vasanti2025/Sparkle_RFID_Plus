import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../../core/constants/app_strings.dart';
import '../../../../core/di/injection.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../product_sync_controller.dart';

class ProductSyncBanner extends StatefulWidget {
  const ProductSyncBanner({super.key});

  @override
  State<ProductSyncBanner> createState() => _ProductSyncBannerState();
}

class _ProductSyncBannerState extends State<ProductSyncBanner>
    with TickerProviderStateMixin {
  late final AnimationController _slide;
  late final AnimationController _motion;
  ProductSyncController? _sync;

  @override
  void initState() {
    super.initState();
    _slide = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 420),
    );
    _motion = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    )..repeat();
    if (Injection.ready) {
      _sync = Injection.productSync;
      _sync!.addListener(_onSync);
    }
  }

  void _onSync() {
    final sync = _sync;
    if (sync == null || !mounted) return;
    if (sync.visible) {
      _slide.forward();
    } else {
      _slide.reverse();
    }
    setState(() {});
  }

  @override
  void dispose() {
    _sync?.removeListener(_onSync);
    _slide.dispose();
    _motion.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final sync = _sync;
    if (sync == null) return const SizedBox.shrink();
    final progress = sync.progress;
    final fraction = progress?.fraction;
    final failed = progress?.failed ?? false;
    final completed = progress?.completed ?? false;
    final percent = fraction == null ? null : (fraction * 100).round();

    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0, -1.25),
          end: Offset.zero,
        ).animate(CurvedAnimation(parent: _slide, curve: Curves.easeOutCubic)),
        child: SafeArea(
          bottom: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
            child: Material(
              color: AppColors.charcoal,
              elevation: 10,
              shadowColor: const Color(0x66000000),
              borderRadius: BorderRadius.circular(16),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        _LeadingIcon(
                          motion: _motion,
                          failed: failed,
                          completed: completed,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                completed
                                    ? AppStrings.syncComplete
                                    : failed
                                    ? AppStrings.syncFailed
                                    : AppStrings.syncingProducts,
                                style: const TextStyle(
                                  fontFamily: 'Inter',
                                  color: AppColors.white,
                                  fontSize: AppTypography.label,
                                  fontWeight: FontWeight.w600,
                                  decoration: TextDecoration.none,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                progress?.message ?? AppStrings.syncingProducts,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontFamily: 'Inter',
                                  color: AppColors.splashBody,
                                  fontSize: AppTypography.brandSubtitle,
                                  fontWeight: FontWeight.w400,
                                  decoration: TextDecoration.none,
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (failed) ...[
                          const SizedBox(width: 8),
                          TextButton(
                            onPressed: sync.retry,
                            style: TextButton.styleFrom(
                              foregroundColor: AppColors.charcoal,
                              backgroundColor: AppColors.champagne,
                              minimumSize: const Size(64, 36),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                              ),
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                            ),
                            child: const Text(
                              AppStrings.retry,
                              style: TextStyle(
                                fontFamily: 'Inter',
                                fontSize: AppTypography.brandSubtitle,
                                fontWeight: FontWeight.w700,
                                decoration: TextDecoration.none,
                              ),
                            ),
                          ),
                        ] else if (percent != null) ...[
                          const SizedBox(width: 8),
                          Text(
                            '$percent%',
                            style: const TextStyle(
                              fontFamily: 'Inter',
                              color: AppColors.champagne,
                              fontSize: AppTypography.label,
                              fontWeight: FontWeight.w700,
                              decoration: TextDecoration.none,
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 10),
                    _ProgressTrack(
                      motion: _motion,
                      fraction: fraction,
                      failed: failed,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _LeadingIcon extends StatelessWidget {
  const _LeadingIcon({
    required this.motion,
    required this.failed,
    required this.completed,
  });

  final Animation<double> motion;
  final bool failed;
  final bool completed;

  @override
  Widget build(BuildContext context) {
    final icon = completed
        ? Icons.check_rounded
        : failed
        ? Icons.error_outline
        : Icons.arrow_downward_rounded;
    final color = failed ? AppColors.error : AppColors.champagne;
    return Container(
      width: 36,
      height: 36,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: const Color(0x22FFFFFF),
        borderRadius: BorderRadius.circular(10),
      ),
      child: completed || failed
          ? Icon(icon, size: 20, color: color)
          : AnimatedBuilder(
              animation: motion,
              builder: (context, child) {
                final dy = math.sin(motion.value * math.pi * 2) * 3;
                return Transform.translate(offset: Offset(0, dy), child: child);
              },
              child: Icon(icon, size: 20, color: color),
            ),
    );
  }
}

class _ProgressTrack extends StatelessWidget {
  const _ProgressTrack({
    required this.motion,
    required this.fraction,
    required this.failed,
  });

  final Animation<double> motion;
  final double? fraction;
  final bool failed;

  @override
  Widget build(BuildContext context) {
    final fill = failed ? AppColors.error : AppColors.champagne;
    return ClipRRect(
      borderRadius: BorderRadius.circular(99),
      child: SizedBox(
        height: 4,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth;
            if (fraction != null) {
              return Stack(
                children: [
                  const ColoredBox(
                    color: Color(0x33FFFFFF),
                    child: SizedBox.expand(),
                  ),
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 240),
                    curve: Curves.easeOut,
                    width: width * fraction!.clamp(0, 1),
                    color: fill,
                  ),
                ],
              );
            }
            return AnimatedBuilder(
              animation: motion,
              builder: (context, _) {
                final travel = (motion.value * 1.4) - 0.4;
                return Stack(
                  children: [
                    const ColoredBox(
                      color: Color(0x33FFFFFF),
                      child: SizedBox.expand(),
                    ),
                    Positioned(
                      left: travel * width,
                      child: Container(
                        width: width * 0.38,
                        height: 4,
                        color: fill,
                      ),
                    ),
                  ],
                );
              },
            );
          },
        ),
      ),
    );
  }
}
