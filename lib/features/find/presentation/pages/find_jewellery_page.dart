import 'dart:async';

import 'package:flutter/material.dart';
import 'package:rfid_flutter_android/rfid_flutter_android.dart';

import '../../../../core/constants/app_strings.dart';
import '../../../../core/rfid/rfid_service.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../inventory/data/inventory_stock.dart';

enum _FindStep { ask, searching, verify }

Future<void> showFindJewellery(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: const Color(0xFFFAF9F7),
    barrierColor: const Color(0x70151410),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(23)),
    ),
    builder: (context) => const _FindJewellerySheet(),
  );
}

class _FindJewellerySheet extends StatefulWidget {
  const _FindJewellerySheet();

  @override
  State<_FindJewellerySheet> createState() => _FindJewellerySheetState();
}

class _FindJewellerySheetState extends State<_FindJewellerySheet> {
  static const _ink = Color(0xFF20201E);
  static const _muted = Color(0xFF6D6B66);
  static const _pill = Color(0xFFEFEBE2);
  static const _pillInk = Color(0xFF706247);
  static const _bar = Color(0xFFDCD7CA);
  static const _barOn = Color(0xFFB08630);
  static const _barFound = Color(0xFF35724D);
  static const _symbolFill = Color(0xFFEDE6D6);
  static const _symbolInk = Color(0xFF87652A);
  static const _fieldLine = Color(0xFFDCD8D0);

  final _target = TextEditingController();
  var _step = _FindStep.ask;
  var _error = '';
  var _strong = false;
  var _arming = false;
  var _bars = 0;
  Timer? _pulse;
  StreamSubscription<List<RfidTagInfo>>? _tags;

  @override
  void dispose() {
    _pulse?.cancel();
    _tags?.cancel();
    unawaited(RfidService.instance.stopIfRunning());
    _target.dispose();
    super.dispose();
  }

  void _close() => Navigator.of(context).pop();

  Future<void> _start() async {
    final value = _target.text.trim();
    if (value.isEmpty) {
      setState(() => _error = AppStrings.chooseTargetFirst);
      return;
    }
    setState(() {
      _error = '';
      _strong = false;
      _bars = 1;
      _arming = true;
      _step = _FindStep.searching;
    });
    _pulse?.cancel();
    _pulse = Timer.periodic(const Duration(milliseconds: 140), (_) {
      if (!mounted || !_arming) return;
      setState(() => _bars = _bars >= 4 ? 1 : _bars + 1);
    });
    await InventoryStock.instance.load();
    final blocked = await RfidService.instance.init();
    if (!mounted) return;
    if (blocked != null) {
      _pulse?.cancel();
      setState(() {
        _arming = false;
        _step = _FindStep.ask;
        _error = blocked;
      });
      return;
    }
    await RfidService.instance.stopIfRunning();
    await RfidService.instance.setInventoryMode(kEpcInventoryMode);
    _tags ??= RfidService.instance.tagStream.listen(_onFindTags);
    final error = await RfidService.instance.startInventory();
    if (!mounted) return;
    _pulse?.cancel();
    setState(() => _arming = false);
    if (error != null) {
      setState(() {
        _step = _FindStep.ask;
        _error = error;
      });
    }
  }

  void _onFindTags(List<RfidTagInfo> batch) {
    final target = _target.text.trim().toLowerCase();
    if (target.isEmpty) return;
    for (final tag in batch) {
      final id = InventoryStock.instance.match(tag.epc.isNotEmpty ? tag.epc : tag.tid);
      final piece = id == null ? null : InventoryStock.instance.byId(id);
      final epc = tag.epc.toLowerCase();
      final hit = epc == target ||
          (piece != null &&
              (piece.id.toLowerCase() == target ||
                  (piece.rfid ?? '').toLowerCase() == target ||
                  (piece.epc ?? '').toLowerCase() == target));
      if (!hit) continue;
      final bars = signalBars(tag.rssi);
      if (!mounted) return;
      setState(() {
        _arming = false;
        _bars = bars;
        _strong = bars >= 8;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final title = switch (_step) {
      _FindStep.ask => AppStrings.findJewelleryTitle,
      _FindStep.searching => AppStrings.searchingForItem,
      _FindStep.verify => AppStrings.verifyJewellery,
    };
    final bottom = MediaQuery.viewInsetsOf(context).bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(22, 0, 22, 24 + bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 11),
          Center(
            child: Container(
              width: 33,
              height: 4,
              decoration: BoxDecoration(
                color: const Color(0xFFD3CFC6),
                borderRadius: BorderRadius.circular(3),
              ),
            ),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: _text(size: 20, weight: FontWeight.w600, letterSpacing: -0.6),
                ),
              ),
              _CloseButton(onPressed: _close),
            ],
          ),
          if (_step == _FindStep.ask) _ask(),
          if (_step == _FindStep.searching) _searching(),
          if (_step == _FindStep.verify) _verify(),
        ],
      ),
    );
  }

  Widget _ask() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _pillTag(AppStrings.localStock),
        Text(
          AppStrings.chooseProductOrTag,
          style: _text(size: 13, color: _muted, height: 1.65),
        ),
        const SizedBox(height: 18),
        Text(
          AppStrings.productCodeOrEpc,
          style: _text(size: 12, weight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _target,
          autofocus: true,
          style: _text(size: 16),
          cursorColor: _ink,
          onChanged: (_) {
            if (_error.isNotEmpty) setState(() => _error = '');
          },
          decoration: InputDecoration(
            hintText: AppStrings.enterProductOrEpc,
            hintStyle: _text(size: 16, color: const Color(0xFF9A958C)),
            filled: true,
            fillColor: AppColors.white,
            contentPadding: const EdgeInsets.symmetric(horizontal: 15, vertical: 16),
            border: _fieldBorder(_fieldLine),
            enabledBorder: _fieldBorder(_fieldLine),
            focusedBorder: _fieldBorder(const Color(0xFF94702E)),
          ),
        ),
        if (_error.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(
            _error,
            style: _text(size: 12, color: const Color(0xFFA22D32), height: 1.5),
          ),
        ],
        const SizedBox(height: 16),
        _primary(AppStrings.startSearch, _start, icon: Icons.search),
        const SizedBox(height: 12),
        Text(
          AppStrings.signalGuidesSearch,
          style: _text(size: 11, color: const Color(0xFF797366), height: 1.7),
        ),
      ],
    );
  }

  Widget _searching() {
    final active = _bars;
    final color = _strong ? _barFound : _barOn;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _pillTag(_arming ? AppStrings.startingReader : AppStrings.listeningForTag),
        Text.rich(
          TextSpan(
            style: _text(size: 13, color: _muted, height: 1.65),
            children: [
              const TextSpan(text: '${AppStrings.targetLabel}: '),
              TextSpan(
                text: _target.text.trim(),
                style: _text(size: 13, weight: FontWeight.w700, height: 1.65),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: 72,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              for (var i = 0; i < 10; i++)
                Container(
                  width: 14,
                  height: 22 + i * 5.0,
                  margin: const EdgeInsets.symmetric(horizontal: 2.5),
                  decoration: BoxDecoration(
                    color: i < active ? color : _bar,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Text(
          _strong ? AppStrings.strongerTargetSignal : AppStrings.targetSignalDetected,
          textAlign: TextAlign.center,
          style: _text(size: 12, color: _muted),
        ),
        const SizedBox(height: 16),
        if (_arming)
          const Padding(
            padding: EdgeInsets.only(bottom: 12),
            child: LinearProgressIndicator(color: Color(0xFFB08630), backgroundColor: Color(0xFFE8E0D2)),
          ),
        TextButton(
          onPressed: _strong ? () => setState(() => _step = _FindStep.verify) : null,
          style: TextButton.styleFrom(
            foregroundColor: const Color(0xFF716044),
            minimumSize: const Size.fromHeight(48),
            textStyle: _text(size: 12, weight: FontWeight.w600, color: const Color(0xFF716044)),
          ),
          child: const Text(AppStrings.locatedTheItem),
        ),
        Text(
          AppStrings.signalCaution,
          style: _text(size: 11, color: const Color(0xFF797366), height: 1.7),
        ),
      ],
    );
  }

  Widget _verify() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 4),
        Align(
          alignment: Alignment.centerLeft,
          child: Container(
            width: 62,
            height: 62,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: _symbolFill,
              borderRadius: BorderRadius.circular(18),
            ),
            child: const Icon(Icons.check_circle_outline, size: 29, color: _symbolInk),
          ),
        ),
        const SizedBox(height: 16),
        Text(
          AppStrings.verifyPieceNote,
          style: _text(size: 13, color: _muted, height: 1.65),
        ),
        const SizedBox(height: 20),
        _primary(AppStrings.done, _close),
      ],
    );
  }

  Widget _pillTag(String label) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(top: 6, bottom: 14),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        decoration: BoxDecoration(
          color: _pill,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(label, style: _text(size: 10, color: _pillInk)),
      ),
    );
  }

  Widget _primary(String label, VoidCallback onPressed, {IconData? icon}) {
    final style = FilledButton.styleFrom(
      backgroundColor: _ink,
      foregroundColor: AppColors.white,
      elevation: 0,
      minimumSize: const Size.fromHeight(56),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(13)),
      textStyle: _text(size: 15, weight: FontWeight.w600, color: AppColors.white),
    );
    if (icon == null) {
      return FilledButton(onPressed: onPressed, style: style, child: Text(label));
    }
    return FilledButton.icon(
      onPressed: onPressed,
      style: style,
      icon: Icon(icon, size: 19),
      label: Text(label),
    );
  }
}

class _CloseButton extends StatelessWidget {
  const _CloseButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: onPressed,
      tooltip: AppStrings.cancel,
      icon: const Icon(Icons.close, size: 20, color: Color(0xFF20201E)),
      style: IconButton.styleFrom(
        fixedSize: const Size(48, 48),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        side: const BorderSide(color: Color(0xFFB18332), width: 1.5),
      ),
    );
  }
}

OutlineInputBorder _fieldBorder(Color color) {
  return OutlineInputBorder(
    borderRadius: const BorderRadius.all(Radius.circular(12)),
    borderSide: BorderSide(color: color),
  );
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
