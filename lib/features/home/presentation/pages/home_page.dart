import 'package:flutter/material.dart';

import '../../../../core/constants/app_strings.dart';
import '../../../../core/constants/asset_paths.dart';
import '../../../../core/di/injection.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../quotation/presentation/pages/pos_quotation_page.dart';
import '../../../quotation/presentation/pages/sparkle_quotation_page.dart';
import '../../../settings/presentation/pages/settings_page.dart';
import '../../../find/presentation/pages/find_jewellery_page.dart';
import '../../../inventory/presentation/pages/inventory_page.dart';
import '../../../orders/presentation/pages/orders_page.dart';
import '../../../products/presentation/pages/products_page.dart';
import '../../../tools/presentation/workspace_flow.dart';
import '../../../transfers/presentation/pages/transfer_page.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final List<CurvedAnimation> _reveals;
  var _tab = 0;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    _reveals = List<CurvedAnimation>.generate(8, (index) {
      final start = index * 0.08;
      return CurvedAnimation(
        parent: _controller,
        curve: Interval(
          start,
          (start + 0.42).clamp(0, 1),
          curve: Curves.easeOutCubic,
        ),
      );
    });
    _controller.forward();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _controller.value = 1;
    }
  }

  @override
  void dispose() {
    for (final reveal in _reveals) {
      reveal.dispose();
    }
    _controller.dispose();
    super.dispose();
  }

  Widget _reveal(int index, Widget child) {
    return AnimatedBuilder(
      animation: _reveals[index],
      child: child,
      builder: (context, child) {
        final t = _reveals[index].value;
        return Opacity(
          opacity: t,
          child: Transform.translate(
            offset: Offset(0, (1 - t) * 18),
            child: child,
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.homeSurface,
      body: SafeArea(
        child: Column(
          children: [
            Expanded(child: _tab == 3 ? const SettingsPage() : _homeBody()),
            _HomeNavigation(
              selectedIndex: _tab,
              onSelected: (index) => setState(() => _tab = index),
            ),
          ],
        ),
      ),
    );
  }

  Widget _homeBody() {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _reveal(0, const _HomeHeader()),
          const SizedBox(height: 16),
          _reveal(1, const _ReaderStatus()),
          const SizedBox(height: 16),
          _reveal(2, const _PrimaryActions()),
          const SizedBox(height: 12),
          _reveal(3, const _ProductsRow()),
          const SizedBox(height: 20),
          _reveal(4, const _SectionTitle()),
          const SizedBox(height: 12),
          _reveal(
            5,
            _ToolGrid(
              onQuotations: () {
                final page = Injection.settings.enablePos
                    ? const PosQuotationPage()
                    : const SparkleQuotationPage();
                Navigator.of(context).push(
                  MaterialPageRoute<void>(builder: (_) => page),
                );
              },
            ),
          ),
          const SizedBox(height: 12),
          _reveal(6, const _MoveActions()),
        ],
      ),
    );
  }
}

class _HomeHeader extends StatelessWidget {
  const _HomeHeader();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Image.asset(
            AssetPaths.loginLogo,
            width: 44,
            height: 44,
            fit: BoxFit.cover,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                AppStrings.brandName,
                style: _text(size: 12, weight: FontWeight.w700),
              ),
              Text(
                AppStrings.home,
                style: _text(
                  size: AppTypography.heading,
                  weight: FontWeight.w700,
                  height: 1.1,
                ),
              ),
            ],
          ),
        ),
        SizedBox(
          width: AppTypography.minTouch,
          height: AppTypography.minTouch,
          child: IconButton(
            onPressed: () => showAccountSheet(context),
            tooltip: AppStrings.yourAccount,
            icon: Container(
              width: 40,
              height: 40,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: AppColors.fieldBorder),
              ),
              child: const Icon(
                Icons.person_outline,
                size: 22,
                color: AppColors.charcoal,
              ),
            ),
            constraints: const BoxConstraints(
              minWidth: AppTypography.minTouch,
              minHeight: AppTypography.minTouch,
            ),
          ),
        ),
      ],
    );
  }
}

class _ReaderStatus extends StatelessWidget {
  const _ReaderStatus();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Icon(
          Icons.wifi_tethering,
          size: 15,
          color: AppColors.statusReady,
        ),
        const SizedBox(width: 6),
        Text(
          AppStrings.readerReady,
          style: _text(
            size: AppTypography.label,
            weight: FontWeight.w600,
            color: AppColors.statusReady,
          ),
        ),
        const Spacer(),
        Text(
          AppStrings.demoWorkspace,
          style: _text(size: AppTypography.label, color: AppColors.muted),
        ),
      ],
    );
  }
}

class _PrimaryActions extends StatelessWidget {
  const _PrimaryActions();

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: _ActionCard(
            background: AppColors.charcoal,
            icon: Icons.crop_free,
            iconColor: AppColors.goldText,
            title: AppStrings.checkStock,
            titleColor: AppColors.white,
            subtitle: AppStrings.checkStockHint,
            subtitleColor: AppColors.white.withValues(alpha: 0.72),
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute<void>(builder: (_) => const InventoryPage()),
              );
            },
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _ActionCard(
            background: AppColors.findSurface,
            icon: Icons.search,
            iconColor: AppColors.goldText,
            title: AppStrings.findJewellery,
            titleColor: AppColors.charcoal,
            subtitle: AppStrings.findJewelleryHint,
            subtitleColor: AppColors.muted,
            onTap: () => showFindJewellery(context),
          ),
        ),
      ],
    );
  }
}

class _ActionCard extends StatelessWidget {
  const _ActionCard({
    required this.background,
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.titleColor,
    required this.subtitle,
    required this.subtitleColor,
    required this.onTap,
  });

  final Color background;
  final IconData icon;
  final Color iconColor;
  final String title;
  final Color titleColor;
  final String subtitle;
  final Color subtitleColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(22),
    );
    return Material(
      color: background,
      shape: shape,
      child: InkWell(
        onTap: onTap,
        customBorder: shape,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 148),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 18, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(icon, color: iconColor, size: 28),
                const SizedBox(height: 28),
                Text(
                  title,
                  style: _text(
                    size: 18,
                    weight: FontWeight.w700,
                    color: titleColor,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: _text(
                    size: AppTypography.label,
                    color: subtitleColor,
                    height: 1.3,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ProductsRow extends StatelessWidget {
  const _ProductsRow();

  @override
  Widget build(BuildContext context) {
    const shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.all(Radius.circular(18)),
      side: BorderSide(color: AppColors.cardBorder),
    );
    return Material(
      color: AppColors.white,
      shape: shape,
      child: InkWell(
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute<void>(builder: (_) => const ProductsPage()),
        ),
        customBorder: shape,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 72),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              children: [
                const Icon(
                  Icons.diamond_outlined,
                  color: AppColors.goldText,
                  size: 26,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        AppStrings.products,
                        style: _text(
                          size: AppTypography.body,
                          weight: FontWeight.w700,
                        ),
                      ),
                      Text(
                        AppStrings.productsHint,
                        style: _text(
                          size: AppTypography.label,
                          color: AppColors.muted,
                        ),
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right, color: AppColors.muted),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(
          AppStrings.createAndMove,
          style: _text(size: AppTypography.body, weight: FontWeight.w700),
        ),
        const Spacer(),
        Text(
          AppStrings.yourDailyWork,
          style: _text(size: AppTypography.label, color: AppColors.muted),
        ),
      ],
    );
  }
}

class _ToolGrid extends StatelessWidget {
  const _ToolGrid({required this.onQuotations});

  final VoidCallback onQuotations;

  static const _tools = <(String, IconData)>[
    (AppStrings.orders, Icons.receipt_long_outlined),
    (AppStrings.quotations, Icons.description_outlined),
    (AppStrings.estimations, Icons.calculate_outlined),
    (AppStrings.grn, Icons.inventory_2_outlined),
    (AppStrings.transfers, Icons.swap_horiz),
    (AppStrings.reports, Icons.show_chart),
  ];

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: _tools.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
        childAspectRatio: 1.05,
      ),
      itemBuilder: (context, index) {
        final (label, icon) = _tools[index];
        const shape = RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(18)),
          side: BorderSide(color: AppColors.cardBorder),
        );
        return Material(
          color: AppColors.white,
          shape: shape,
          child: InkWell(
            onTap: () => _openTool(context, label),
            customBorder: shape,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, color: AppColors.goldText, size: 26),
                const SizedBox(height: 10),
                Text(
                  label,
                  textAlign: TextAlign.center,
                  style: _text(
                    size: AppTypography.label,
                    weight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _MoveActions extends StatelessWidget {
  const _MoveActions();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _MoveButton(
            label: AppStrings.sampleIn,
            background: AppColors.chipSurface,
            foreground: AppColors.charcoal,
            onTap: () => showModulePreview(context, AppStrings.sampleIn),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _MoveButton(
            label: AppStrings.sampleOut,
            background: AppColors.chipSurface,
            foreground: AppColors.charcoal,
            onTap: () => showModulePreview(context, AppStrings.sampleOut),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _MoveButton(
            label: AppStrings.allTools,
            background: AppColors.chipSurface,
            foreground: AppColors.charcoal,
            onTap: () => showAllTools(context),
          ),
        ),
      ],
    );
  }
}

class _MoveButton extends StatelessWidget {
  const _MoveButton({
    required this.label,
    required this.background,
    required this.foreground,
    required this.onTap,
  });

  final String label;
  final Color background;
  final Color foreground;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: background,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          constraints: const BoxConstraints(minHeight: AppTypography.minTouch),
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(16)),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: _text(
              size: AppTypography.label,
              weight: FontWeight.w600,
              color: foreground,
            ),
          ),
        ),
      ),
    );
  }
}

class _HomeNavigation extends StatelessWidget {
  const _HomeNavigation({
    required this.selectedIndex,
    required this.onSelected,
  });

  final int selectedIndex;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    const labelStyle = TextStyle(
      fontFamily: 'Inter',
      fontFamilyFallback: <String>[],
      fontSize: 12,
      fontWeight: FontWeight.w600,
    );
    return NavigationBarTheme(
      data: NavigationBarThemeData(
        backgroundColor: AppColors.white,
        indicatorColor: AppColors.white,
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return labelStyle.copyWith(
            color: selected ? AppColors.goldText : AppColors.muted,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
          );
        }),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return IconThemeData(
            color: selected ? AppColors.goldText : AppColors.muted,
            size: 24,
          );
        }),
      ),
      child: NavigationBar(
        selectedIndex: selectedIndex,
        onDestinationSelected: onSelected,
        height: 64,
        onDestinationSelected: (index) {
          if (index == 1) {
            Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const ProductsPage()),
            );
          } else if (index == 2) {
            showAllTools(context);
          } else if (index == 3) {
            showSettingsSheet(context);
          }
        },
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home),
            label: AppStrings.home,
          ),
          NavigationDestination(
            icon: Icon(Icons.diamond_outlined),
            label: AppStrings.products,
          ),
          NavigationDestination(
            icon: Icon(Icons.grid_view_rounded),
            label: AppStrings.tools,
          ),
          NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            label: AppStrings.settings,
          ),
        ],
      ),
    );
  }
}

void _openTool(BuildContext context, String label) {
  switch (label) {
    case AppStrings.orders:
      Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => const OrdersPage()),
      );
    case AppStrings.transfers:
      Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => const TransferPage()),
      );
    default:
      showModulePreview(context, label);
  }
}

TextStyle _text({
  required double size,
  FontWeight weight = FontWeight.w400,
  Color color = AppColors.charcoal,
  double? height,
}) {
  return TextStyle(
    fontFamily: 'Inter',
    fontFamilyFallback: const <String>[],
    fontSize: size,
    fontWeight: weight,
    color: color,
    height: height,
    decoration: TextDecoration.none,
  );
}
