import 'dart:io';

import 'package:flutter/material.dart';

import '../../../../core/constants/app_strings.dart';
import '../../../../core/di/injection.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../settings_controller.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  late final SettingsController _settings;

  @override
  void initState() {
    super.initState();
    _settings = Injection.settings;
    _settings.addListener(_sync);
  }

  void _sync() {
    if (!mounted) return;
    setState(() {});
  }

  @override
  void dispose() {
    _settings.removeListener(_sync);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
      children: [
        Text(
          AppStrings.settings,
          style: _text(size: AppTypography.heading, weight: FontWeight.w700),
        ),
        const SizedBox(height: 16),
        Material(
          color: AppColors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
            side: const BorderSide(color: AppColors.cardBorder),
          ),
          child: SwitchListTile(
            contentPadding: const EdgeInsets.fromLTRB(16, 8, 12, 8),
            title: Text(
              AppStrings.enablePos,
              style: _text(size: AppTypography.body, weight: FontWeight.w700),
            ),
            subtitle: Text(
              AppStrings.enablePosHint,
              style: _text(size: AppTypography.label, color: AppColors.muted),
            ),
            value: _settings.enablePos,
            activeThumbColor: AppColors.white,
            activeTrackColor: AppColors.goldText,
            onChanged: _settings.setEnablePos,
          ),
        ),
        const SizedBox(height: 12),
        Material(
          color: AppColors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
            side: const BorderSide(color: AppColors.cardBorder),
          ),
          child: SwitchListTile(
            contentPadding: const EdgeInsets.fromLTRB(16, 8, 12, 8),
            title: Text(
              AppStrings.localWifiMode,
              style: _text(size: AppTypography.body, weight: FontWeight.w700),
            ),
            subtitle: Text(
              AppStrings.localWifiModeHint,
              style: _text(size: AppTypography.label, color: AppColors.muted),
            ),
            value: _settings.localWifiMode,
            activeThumbColor: AppColors.white,
            activeTrackColor: AppColors.goldText,
            onChanged: (value) async {
              final messenger = ScaffoldMessenger.of(context);
              if (value && await _wifiAddress() == null) {
                if (!mounted) return;
                messenger.showSnackBar(
                  const SnackBar(content: Text(AppStrings.localWifiNeedNetwork)),
                );
                return;
              }
              await _settings.setLocalWifiMode(value);
              if (!mounted || value) return;
              messenger.showSnackBar(
                const SnackBar(content: Text(AppStrings.onlineModeOn)),
              );
            },
          ),
        ),
      ],
    );
  }
}

Future<String?> _wifiAddress() async {
  try {
    final interfaces = await NetworkInterface.list();
    for (final interface in interfaces) {
      for (final address in interface.addresses) {
        if (address.type != InternetAddressType.IPv4 || address.isLoopback) continue;
        final ip = address.address.trim();
        if (ip.isEmpty || ip == '0.0.0.0') continue;
        return ip;
      }
    }
  } catch (_) {}
  return null;
}

TextStyle _text({
  required double size,
  FontWeight weight = FontWeight.w400,
  Color color = AppColors.charcoal,
}) {
  return TextStyle(
    fontFamily: 'Inter',
    fontFamilyFallback: const <String>[],
    fontSize: size,
    fontWeight: weight,
    color: color,
  );
}
