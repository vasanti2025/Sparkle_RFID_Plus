import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/constants/app_strings.dart';
import '../../../../core/di/injection.dart';
import '../../../../core/session/app_session.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/result.dart';
import '../../../inventory/data/inventory_stock.dart';
import '../../../quotation/domain/entities/customer_record.dart';
import '../../data/page_layout.dart';

class DeliveryChallanPage extends StatefulWidget {
  const DeliveryChallanPage({super.key});

  @override
  State<DeliveryChallanPage> createState() => _DeliveryChallanPageState();
}

class _DeliveryChallanPageState extends State<DeliveryChallanPage> {
  static const _surface = Color(0xFFFAF9F7);
  static const _ink = Color(0xFF20201E);

  final _api = PageLayoutApi();
  final _values = <String, TextEditingController>{};
  final _checks = <String, bool>{};
  final _choices = <String, List<String>>{};
  var _loading = true;
  String? _error;
  List<PageModule> _modules = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final controller in _values.values) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final modules = await _api.load();
      final choices = await _choiceLists(modules);
      for (final module in modules) {
        for (final control in module.controls) {
          if (control.kind.contains('check') || control.kind.contains('bool') || control.kind.contains('switch')) {
            _checks.putIfAbsent(control.key, () => false);
          } else {
            _values.putIfAbsent(control.key, TextEditingController.new);
          }
        }
      }
      _choices
        ..clear()
        ..addAll(choices);
      if (!mounted) return;
      setState(() {
        _modules = modules;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = '$error'.replaceFirst('Bad state: ', '').replaceFirst('StateError: ', '');
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final title = _modules.length == 1 && _modules.first.displayName.isNotEmpty
        ? _modules.first.displayName
        : AppStrings.deliveryChallan;
    return Scaffold(
      backgroundColor: _surface,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 6, 8, 6),
              child: Row(
                children: [
                  IconButton(
                    onPressed: () => Navigator.of(context).maybePop(),
                    icon: const Icon(Icons.arrow_back, size: 21, color: _ink),
                  ),
                  Expanded(
                    child: Text(title, style: _text(size: 21, weight: FontWeight.w600)),
                  ),
                ],
              ),
            ),
            Expanded(child: _body()),
          ],
        ),
      ),
    );
  }

  Widget _body() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.goldText));
    }
    if (_error != null) {
      return _message(_error == 'Sign in to load this form.' ? AppStrings.signInForLayout : AppStrings.layoutCouldNotLoad, _load);
    }
    final visible = _modules.where((module) => module.enabled && module.controls.isNotEmpty).toList();
    if (visible.isEmpty) {
      final disabled = _modules.any((module) => !module.enabled);
      return _message(disabled ? AppStrings.pageNotEnabled : AppStrings.noFieldsOnPage, _load);
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        for (final module in visible) ...[
          if (_modules.length > 1 && module.displayName.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Text(module.displayName, style: _text(size: 16, weight: FontWeight.w700)),
            ),
          for (final place in _places(module.controls))
            _placeBlock(
              place,
              module.controls.where((control) => _slot(control.place) == place).toList(),
            ),
        ],
      ],
    );
  }

  Widget _field(PageControl control) {
    if (control.kind.contains('check') || control.kind.contains('bool') || control.kind.contains('switch')) {
      return SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: Text(control.label, style: _text(size: 14, weight: FontWeight.w600)),
        value: _checks[control.key] ?? false,
        activeThumbColor: AppColors.goldText,
        onChanged: control.readOnly ? null : (value) => setState(() => _checks[control.key] = value),
      );
    }
    if (control.kind.contains('drop')) {
      return _dropdown(control);
    }
    if (control.kind.contains('date')) {
      return _date(control);
    }
    return _textField(control);
  }

  List<String> _optionsFor(PageControl control) => _choices[control.key] ?? control.options;

  Widget _dropdown(PageControl control) {
    final controller = _values[control.key]!;
    final options = _optionsFor(control);
    return TextField(
      controller: controller,
      readOnly: true,
      onTap: control.readOnly ? null : () => _pickOption(control, options),
      decoration: _decoration(control).copyWith(
        suffixIcon: const Icon(Icons.arrow_drop_down, color: AppColors.muted),
      ),
    );
  }

  Future<void> _pickOption(PageControl control, List<String> options) async {
    final picked = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: _surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(23))),
      builder: (context) => _OptionSheet(title: control.label, options: options),
    );
    if (picked == null || !mounted) return;
    setState(() => _values[control.key]!.text = picked);
  }

  Widget _placeBlock(String place, List<PageControl> controls) {
    final fields = [
      for (final control in controls)
        Padding(padding: const EdgeInsets.only(bottom: 12), child: _field(control)),
    ];
    if (place == 'top') {
      return Container(
        margin: const EdgeInsets.only(bottom: 16),
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 2),
        decoration: BoxDecoration(
          color: const Color(0xFFF5EEDF),
          borderRadius: BorderRadius.circular(15),
          border: Border.all(color: const Color(0xFFDDCBA5)),
        ),
        child: Column(children: fields),
      );
    }
    return Column(children: fields);
  }

  Future<Map<String, List<String>>> _choiceLists(List<PageModule> modules) async {
    final lists = <String, List<String>>{};
    final needsLookup = modules.expand((module) => module.controls).where((control) => control.kind.contains('drop')).toList();
    if (needsLookup.isEmpty) return lists;
    await InventoryStock.instance.load();
    CustomerIndex? customers;
    if (Injection.ready && AppSession.clientCode.isNotEmpty) {
      final result = await Injection.quotations.loadCustomers(AppSession.clientCode);
      if (result case Success(:final data)) customers = data;
    }
    final stock = InventoryStock.instance;
    final purities = <String>{
      for (final piece in stock.pieces)
        if ((piece.purity ?? '').trim().isNotEmpty) piece.purity!.trim(),
    }.toList()
      ..sort();
    for (final control in needsLookup) {
      if (control.options.isNotEmpty) {
        lists[control.key] = control.options;
        continue;
      }
      final name = '${control.key} ${control.label}'.toLowerCase();
      lists[control.key] = switch (name) {
        _ when name.contains('customer') => customers?.records.map((record) => record.name).toList() ?? const [],
        _ when name.contains('categor') => stock.categories,
        _ when name.contains('product') => stock.products,
        _ when name.contains('design') => stock.designs,
        _ when name.contains('purity') => purities,
        _ when name.contains('counter') => stock.counters,
        _ when name.contains('box') => stock.boxes,
        _ when name.contains('packet') => stock.packets,
        _ when name.contains('branch') || name.contains('exhibition') => stock.branches,
        _ => const <String>[],
      };
    }
    return lists;
  }

  Widget _date(PageControl control) {
    final controller = _values[control.key]!;
    return TextField(
      controller: controller,
      readOnly: true,
      onTap: control.readOnly
          ? null
          : () async {
              final now = DateTime.now();
              final picked = await showDatePicker(
                context: context,
                initialDate: now,
                firstDate: DateTime(now.year - 5),
                lastDate: DateTime(now.year + 5),
              );
              if (picked == null) return;
              final month = picked.month.toString().padLeft(2, '0');
              final day = picked.day.toString().padLeft(2, '0');
              setState(() => controller.text = '${picked.year}-$month-$day');
            },
      decoration: _decoration(control).copyWith(suffixIcon: const Icon(Icons.calendar_today, size: 18)),
    );
  }

  Widget _textField(PageControl control, {IconData? icon}) {
    final controller = _values[control.key]!;
    final numeric = control.kind.contains('number') ||
        control.kind.contains('decimal') ||
        control.kind.contains('amount');
    return TextField(
      controller: controller,
      readOnly: control.readOnly,
      keyboardType: numeric ? const TextInputType.numberWithOptions(decimal: true) : TextInputType.text,
      inputFormatters: numeric ? [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))] : null,
      minLines: control.kind.contains('area') || control.kind.contains('multiline') ? 3 : 1,
      maxLines: control.kind.contains('area') || control.kind.contains('multiline') ? 4 : 1,
      decoration: _decoration(control).copyWith(
        suffixIcon: icon == null ? null : Icon(icon, color: AppColors.muted),
      ),
    );
  }

  InputDecoration _decoration(PageControl control) {
    return InputDecoration(
      labelText: control.label,
      hintText: control.placeholder.isEmpty ? null : control.placeholder,
      filled: true,
      fillColor: AppColors.white,
      labelStyle: _text(size: 13, color: AppColors.muted),
      border: _border(AppColors.fieldBorder),
      enabledBorder: _border(AppColors.fieldBorder),
      focusedBorder: _border(const Color(0xFF967431)),
    );
  }

  List<String> _places(List<PageControl> controls) {
    const order = ['top', 'middle', 'bottom'];
    final found = controls.map((control) => _slot(control.place)).toSet();
    final sorted = [
      for (final place in order)
        if (found.contains(place)) place,
      for (final place in found)
        if (!order.contains(place) && place.isNotEmpty) place,
    ];
    if (sorted.isEmpty) sorted.add('middle');
    return sorted;
  }

  String _slot(String place) => place.isEmpty ? 'middle' : place;

  Widget _message(String message, VoidCallback onRetry) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(message, textAlign: TextAlign.center, style: _text(size: 14, color: AppColors.muted, height: 1.4)),
            const SizedBox(height: 14),
            TextButton(onPressed: onRetry, child: const Text('Try again')),
          ],
        ),
      ),
    );
  }
}

class _OptionSheet extends StatefulWidget {
  const _OptionSheet({required this.title, required this.options});

  final String title;
  final List<String> options;

  @override
  State<_OptionSheet> createState() => _OptionSheetState();
}

class _OptionSheetState extends State<_OptionSheet> {
  final _query = TextEditingController();

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final needle = _query.text.trim().toLowerCase();
    final shown = widget.options.where((option) => needle.isEmpty || option.toLowerCase().contains(needle)).take(80).toList();
    final height = MediaQuery.sizeOf(context).height * 0.72;
    return SizedBox(
      height: height,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 14, 18, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(widget.title, style: _text(size: 18, weight: FontWeight.w700)),
            const SizedBox(height: 10),
            TextField(
              controller: _query,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                hintText: AppStrings.search,
                filled: true,
                fillColor: AppColors.white,
                prefixIcon: const Icon(Icons.search, size: 18),
                border: _border(AppColors.fieldBorder),
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: shown.isEmpty
                  ? Center(child: Text(AppStrings.noFieldsOnPage, style: _text(size: 13, color: AppColors.muted)))
                  : ListView(
                      children: [
                        for (final option in shown)
                          ListTile(
                            contentPadding: EdgeInsets.zero,
                            title: Text(option, style: _text(size: 14, weight: FontWeight.w600)),
                            onTap: () => Navigator.pop(context, option),
                          ),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

OutlineInputBorder _border(Color color) {
  return OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: color));
}

TextStyle _text({
  required double size,
  FontWeight weight = FontWeight.w400,
  Color color = const Color(0xFF20201F),
  double? height,
  double? letterSpacing,
}) {
  return TextStyle(
    fontFamily: 'Inter',
    fontFamilyFallback: const <String>[],
    fontSize: size,
    fontWeight: weight,
    color: color,
    height: height,
    letterSpacing: letterSpacing,
    decoration: TextDecoration.none,
  );
}
