import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/constants/app_strings.dart';
import '../../../../core/di/injection.dart';
import '../../../../core/error/exceptions.dart';
import '../../../../core/locale/feature_strings.dart';
import '../../../../core/session/app_session.dart';
import '../../../../core/theme/app_colors.dart';
import '../../data/daily_rate_api.dart';

class TodaysRatePage extends StatefulWidget {
  const TodaysRatePage({super.key});

  @override
  State<TodaysRatePage> createState() => _TodaysRatePageState();
}

class _TodaysRatePageState extends State<TodaysRatePage> {
  final _api = DailyRateApi();
  final _rows = <DailyRateRow>[];
  final _controllers = <TextEditingController>[];

  var _loading = true;
  var _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    if (Injection.ready) Injection.settings.addListener(_onLanguage);
    unawaited(_load());
  }

  @override
  void dispose() {
    if (Injection.ready) Injection.settings.removeListener(_onLanguage);
    _clearControllers();
    super.dispose();
  }

  void _onLanguage() {
    if (mounted) setState(() {});
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final code = AppSession.clientCode.trim();
    if (code.isEmpty) {
      setState(() {
        _loading = false;
        _error = tx('signInForRates', AppStrings.signInForRates);
      });
      return;
    }
    try {
      final rows = await _api.load(code);
      if (!mounted) return;
      _replace(rows);
      setState(() => _loading = false);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = _friendly(error, tx('ratesLoadFailed', AppStrings.ratesLoadFailed));
      });
    }
  }

  void _replace(List<DailyRateRow> rows) {
    final previous = List<TextEditingController>.of(_controllers);
    _controllers.clear();
    _rows
      ..clear()
      ..addAll(rows);
    _controllers.addAll(rows.map((row) => TextEditingController(text: row.rate)));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      for (final controller in previous) {
        controller.dispose();
      }
    });
  }

  void _clearControllers() {
    for (final controller in _controllers) {
      controller.dispose();
    }
    _controllers.clear();
  }

  void _onRate(int index, String value) {
    final edited = _rows[index];
    edited.rate = value;
    final baseFine = double.tryParse(edited.finePercentage);
    final newRate = double.tryParse(value);
    if (baseFine == null || baseFine == 0 || newRate == null) return;
    final pure = newRate / (baseFine / 100);
    for (var i = 0; i < _rows.length; i++) {
      if (i == index) continue;
      final other = _rows[i];
      if (other.categoryName.toLowerCase() != edited.categoryName.toLowerCase()) continue;
      if (other.purityId == edited.purityId) continue;
      final fine = double.tryParse(other.finePercentage);
      if (fine == null) continue;
      final next = (pure * (fine / 100)).toStringAsFixed(2);
      other.rate = next;
      if (_controllers[i].text != next) {
        _controllers[i].value = TextEditingValue(
          text: next,
          selection: TextSelection.collapsed(offset: next.length),
        );
      }
    }
  }

  Future<void> _save() async {
    if (_saving || _rows.isEmpty) return;
    for (var i = 0; i < _rows.length && i < _controllers.length; i++) {
      _rows[i].rate = _controllers[i].text.trim();
    }
    setState(() => _saving = true);
    try {
      await _api.save(_rows);
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(tx('ratesUpdated', AppStrings.ratesUpdated))));
      Navigator.pop(context);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(content: Text(_friendly(error, tx('ratesUpdateFailed', AppStrings.ratesUpdateFailed)))),
        );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  String _friendly(Object error, String fallback) {
    final raw = error is ServerException ? error.message : error.toString();
    final lower = raw.toLowerCase();
    if (lower.contains('socket') ||
        lower.contains('clientexception') ||
        lower.contains('failed host') ||
        lower.contains('network')) {
      return tx('noInternet', AppStrings.noInternet);
    }
    if (error is ServerException && raw.isNotEmpty && !raw.startsWith('QA API')) {
      return raw;
    }
    return fallback;
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: featureDirection,
      child: Scaffold(
        backgroundColor: AppColors.homeSurface,
        resizeToAvoidBottomInset: true,
        appBar: AppBar(
          elevation: 0,
          backgroundColor: AppColors.charcoal,
          foregroundColor: AppColors.white,
          title: Text(
            tx('labelTodayRate', AppStrings.labelTodayRate),
            style: _style(size: 18, weight: FontWeight.w600, color: AppColors.white),
          ),
        ),
        body: SafeArea(child: _body()),
      ),
    );
  }

  Widget _body() {
    if (_loading && _rows.isEmpty) {
      return const Center(child: CircularProgressIndicator(color: AppColors.goldText));
    }
    if (_rows.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _error ?? tx('noRatesFound', AppStrings.noRatesFound),
                textAlign: TextAlign.center,
                style: _style(size: 14, color: AppColors.muted),
              ),
              const SizedBox(height: 16),
              TextButton(
                onPressed: _load,
                child: Text(
                  tx('tryAgain', AppStrings.tryAgain),
                  style: _style(size: 14, weight: FontWeight.w600, color: AppColors.goldText),
                ),
              ),
            ],
          ),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Column(
        children: [
          _header(),
          const Divider(height: 1, thickness: 1, color: AppColors.fieldBorder),
          Expanded(
            child: ListView.separated(
              padding: EdgeInsets.zero,
              itemCount: _rows.length,
              separatorBuilder: (_, _) => const Divider(height: 1, color: AppColors.fieldBorder),
              itemBuilder: (context, index) => _row(index),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _saving ? null : () => Navigator.pop(context),
                  icon: const Icon(Icons.close, size: 18),
                  label: Text(tx('cancel', AppStrings.cancel)),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.charcoal,
                    minimumSize: const Size.fromHeight(48),
                    side: const BorderSide(color: AppColors.charcoal),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    textStyle: _style(size: 14, weight: FontWeight.w600),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton.icon(
                  onPressed: _saving ? null : _save,
                  icon: _saving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.white),
                        )
                      : const Icon(Icons.check_circle_outline, size: 18),
                  label: Text(tx('updateRates', AppStrings.updateRates)),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.charcoal,
                    foregroundColor: AppColors.white,
                    minimumSize: const Size.fromHeight(48),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    textStyle: _style(size: 14, weight: FontWeight.w600, color: AppColors.white),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _header() {
    Widget cell(String text, int flex) {
      return Expanded(
        flex: flex,
        child: Text(text, style: _style(size: 14, weight: FontWeight.w700)),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          cell(tx('category', AppStrings.category), 3),
          cell(tx('purity', AppStrings.purity), 2),
          cell(tx('todayRatePerGm', AppStrings.todayRatePerGm), 3),
        ],
      ),
    );
  }

  Widget _row(int index) {
    final row = _rows[index];
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Expanded(flex: 3, child: Text(row.categoryName, style: _style(size: 13, weight: FontWeight.w500))),
          Expanded(flex: 2, child: Text(row.purityName, style: _style(size: 13, weight: FontWeight.w500))),
          Expanded(
            flex: 3,
            child: SizedBox(
              height: 36,
              child: TextField(
                controller: _controllers[index],
                textAlign: TextAlign.center,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                  _SingleDecimalFormatter(),
                ],
                style: _style(size: 13),
                cursorColor: AppColors.charcoal,
                decoration: InputDecoration(
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
                  filled: true,
                  fillColor: AppColors.white,
                  enabledBorder: _border(AppColors.fieldBorder),
                  focusedBorder: _border(AppColors.goldText),
                ),
                onChanged: (value) => _onRate(index, value),
              ),
            ),
          ),
        ],
      ),
    );
  }

  OutlineInputBorder _border(Color color) {
    return OutlineInputBorder(
      borderRadius: BorderRadius.circular(6),
      borderSide: BorderSide(color: color),
    );
  }
}

class _SingleDecimalFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    if (newValue.text.split('.').length > 2) return oldValue;
    return newValue;
  }
}

TextStyle _style({
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
