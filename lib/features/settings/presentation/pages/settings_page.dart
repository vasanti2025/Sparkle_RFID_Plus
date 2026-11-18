import 'dart:io';

import 'package:flutter/material.dart';

import '../../../../core/constants/app_strings.dart';
import '../../../../core/di/injection.dart';
import '../../../../core/locale/feature_strings.dart';
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
        const SizedBox(height: 12),
        _tile(
          title: tx('language', 'Language'),
          subtitle: tx(_settings.language, _settings.language == 'hi' ? 'हिन्दी' : _settings.language == 'ar' ? 'العربية' : 'English'),
          onTap: _chooseLanguage,
        ),
        const SizedBox(height: 12),
        _tile(
          title: tx('sheetUrl', 'Sheet URL'),
          subtitle: _settings.sheetUrl.isEmpty ? tx('setSheetUrl', 'Set the Google Sheet URL') : _settings.sheetUrl,
          onTap: _editSheet,
        ),
      ],
    );
  }

  Widget _tile({required String title, required String subtitle, required VoidCallback onTap}) {
    return Material(
      color: AppColors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: const BorderSide(color: AppColors.cardBorder),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.fromLTRB(16, 6, 12, 6),
        title: Text(title, style: _text(size: AppTypography.body, weight: FontWeight.w700)),
        subtitle: Text(subtitle, maxLines: 2, overflow: TextOverflow.ellipsis, style: _text(size: AppTypography.label, color: AppColors.muted)),
        trailing: const Icon(Icons.chevron_right, color: AppColors.muted),
        onTap: onTap,
      ),
    );
  }

  Future<void> _chooseLanguage() async {
    var selected = _settings.language;
    final next = await showDialog<String>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setSheet) => AlertDialog(
          backgroundColor: AppColors.white,
          title: Text(tx('selectLanguage', 'Select language'), style: const TextStyle(color: AppColors.charcoal, fontWeight: FontWeight.w700)),
          content: RadioGroup<String>(
            groupValue: selected,
            onChanged: (value) => setSheet(() => selected = value ?? selected),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final code in const ['en', 'hi', 'ar'])
                  RadioListTile<String>(
                    value: code,
                    activeColor: AppColors.goldText,
                    title: Text(tx(code == 'en' ? 'english' : code == 'hi' ? 'hindi' : 'arabic', code == 'en' ? 'English' : code == 'hi' ? 'हिन्दी' : 'العربية')),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: Text(tx('cancel', 'Cancel'))),
            TextButton(
              onPressed: () => Navigator.pop(context, selected),
              child: Text(tx('save', 'Save'), style: const TextStyle(color: AppColors.goldText)),
            ),
          ],
        ),
      ),
    );
    if (next == null) return;
    await _settings.setLanguage(next);
  }

  Future<void> _editSheet() async {
    final field = TextEditingController(text: _settings.sheetUrl);
    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.white,
        title: Text(tx('sheetUrl', 'Sheet URL'), style: const TextStyle(color: AppColors.charcoal, fontWeight: FontWeight.w700)),
        content: TextField(
          controller: field,
          decoration: InputDecoration(hintText: tx('setSheetUrl', 'Set the Google Sheet URL')),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text(tx('cancel', 'Cancel'))),
          TextButton(onPressed: () => Navigator.pop(context, true), child: Text(tx('save', 'Save'), style: const TextStyle(color: AppColors.goldText))),
        ],
      ),
    );
    if (saved == true) await _settings.setSheetUrl(field.text);
    field.dispose();
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
