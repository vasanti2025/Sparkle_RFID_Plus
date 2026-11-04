import 'package:flutter/material.dart';

import '../../../../core/constants/app_strings.dart';
import '../../../../core/di/injection.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../domain/entities/app_preferences.dart';
import '../settings_controller.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  late final SettingsController _settings;
  late final TextEditingController _clientCode;
  late final TextEditingController _userId;

  @override
  void initState() {
    super.initState();
    _settings = Injection.settings;
    _clientCode = TextEditingController(text: _settings.preferences.clientCode);
    _userId = TextEditingController(text: _settings.preferences.userId);
    _settings.addListener(_sync);
  }

  void _sync() {
    if (!mounted) return;
    final AppPreferences prefs = _settings.preferences;
    if (_clientCode.text != prefs.clientCode) {
      _clientCode.text = prefs.clientCode;
    }
    if (_userId.text != prefs.userId) {
      _userId.text = prefs.userId;
    }
    setState(() {});
  }

  @override
  void dispose() {
    _settings.removeListener(_sync);
    _clientCode.dispose();
    _userId.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final enabled = _settings.enablePos;
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
            value: enabled,
            activeThumbColor: AppColors.white,
            activeTrackColor: AppColors.goldText,
            onChanged: _settings.setEnablePos,
          ),
        ),
        const SizedBox(height: 16),
        Text(
          AppStrings.connectionForQa,
          style: _text(size: AppTypography.body, weight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        Text(
          'Quotations call https://qa-rfid-api.sparklerfid.net',
          style: _text(size: AppTypography.label, color: AppColors.muted),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _clientCode,
          decoration: const InputDecoration(labelText: AppStrings.clientCode),
          onSubmitted: (_) => _saveConnection(),
          onTapOutside: (_) => _saveConnection(),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _userId,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(labelText: AppStrings.userId),
          onSubmitted: (_) => _saveConnection(),
          onTapOutside: (_) => _saveConnection(),
        ),
      ],
    );
  }

  Future<void> _saveConnection() {
    return _settings.setConnection(
      clientCode: _clientCode.text,
      userId: _userId.text,
    );
  }
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
