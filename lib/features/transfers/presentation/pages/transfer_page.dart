import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/constants/app_strings.dart';
import '../../../../core/theme/app_colors.dart';
import '../demo/transfer_demo_session.dart';

class TransferPage extends StatefulWidget {
  const TransferPage({super.key});

  @override
  State<TransferPage> createState() => _TransferPageState();
}

class _TransferPageState extends State<TransferPage> {
  static const _surface = Color(0xFFFAF9F7);
  static const _ink = Color(0xFF20201E);
  static const _headLine = Color(0xFFE8E3D9);
  static const _muted = Color(0xFF6D6B66);
  static const _gold = Color(0xFF85652C);
  static const _note = Color(0xFF817866);

  final _session = TransferDemoSession.instance;
  final _query = TextEditingController();
  var _capturing = false;
  var _suspend = false;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _query.text = _session.query;
    _query.addListener(() {
      _session.query = _query.text;
      if (mounted && !_suspend) setState(() {});
    });
  }

  @override
  void dispose() {
    _suspend = true;
    _stopScan();
    _query.dispose();
    super.dispose();
  }

  void _toast(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  void _stopScan() {
    _timer?.cancel();
    _timer = null;
    _capturing = false;
  }

  void _toggleScan() {
    if (_capturing) {
      setState(_stopScan);
      return;
    }
    setState(() => _capturing = true);
    _timer = Timer.periodic(const Duration(milliseconds: 900), (_) {
      if (!mounted) return;
      final next = _session.nextUnread();
      if (next == null) {
        setState(_stopScan);
        _toast(AppStrings.allPiecesRead);
        return;
      }
      setState(() => _session.toggle(next.id, true));
    });
  }

  void _present(String title, Widget body) {
    final wasScanning = _capturing;
    _stopScan();
    if (wasScanning && mounted) setState(() {});
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: _surface,
      barrierColor: const Color(0x70151410),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(23)),
      ),
      builder: (context) {
        return Padding(
          padding: EdgeInsets.fromLTRB(
            22,
            0,
            22,
            20 + MediaQuery.viewInsetsOf(context).bottom,
          ),
          child: SingleChildScrollView(
            child: Column(
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
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        title,
                        style: _text(
                          size: 20,
                          weight: FontWeight.w600,
                          letterSpacing: -0.6,
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close, size: 20),
                    ),
                  ],
                ),
                body,
              ],
            ),
          ),
        );
      },
    );
  }

  void _menu() {
    _present(
      AppStrings.transferOptions,
      Column(
        children: [
          _menuRow(AppStrings.gscan, Icons.crop_free, _gscan),
          _menuRow(AppStrings.transferList, Icons.list_alt, _transferList),
          _menuRow(AppStrings.clearSelectedPieces, Icons.restart_alt, _clear),
        ],
      ),
    );
  }

  void _gscan() {
    Navigator.pop(context);
    _present(
      AppStrings.gscan,
      Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(AppStrings.gscanStays, style: _text(size: 13, color: _muted, height: 1.5)),
          const SizedBox(height: 8),
          Text(AppStrings.gscanNotShown, style: _text(size: 12, color: _note, height: 1.45)),
          const SizedBox(height: 14),
          _filled(AppStrings.backToWorkspace, () => Navigator.pop(context)),
        ],
      ),
    );
  }

  void _transferList() {
    Navigator.pop(context);
    final records = _session.transfers;
    _present(
      AppStrings.transferList,
      records.isEmpty
          ? _empty(AppStrings.noDemoTransfers, AppStrings.confirmedTransfersHere)
          : Column(
              children: [
                for (final record in records)
                  Container(
                    width: double.infinity,
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: AppColors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFFE3DDD1)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(record.id, style: _text(size: 14, weight: FontWeight.w700)),
                        const SizedBox(height: 4),
                        Text(
                          '${record.from} → ${record.to}\n${record.ids.length} ${AppStrings.pieces} · ${AppStrings.grossWeight} ${TransferDemoSession.grams(record.gross)} g',
                          style: _text(size: 12, color: _muted, height: 1.4),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
    );
  }

  void _clear() {
    Navigator.pop(context);
    _present(
      AppStrings.clearThisSelection,
      Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(AppStrings.clearTransferBody, style: _text(size: 13, color: _muted, height: 1.5)),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(child: _secondary(AppStrings.keep, () => Navigator.pop(context))),
              const SizedBox(width: 8),
              Expanded(
                child: _filled(AppStrings.clearPieces, () {
                  _session.selected.clear();
                  Navigator.pop(context);
                  setState(() {});
                }),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _route() {
    _present(
      AppStrings.chooseTransferRoute,
      _RouteForm(
        route: _session.route,
        from: _session.from,
        to: _session.to,
        onApply: (route, from, to) {
          Navigator.pop(context);
          final current = _session.kinds;
          final next = TransferDemoSession.routes[route];
          final sourceChanged = current.$1 != next.$1 || _session.from != from;
          if (sourceChanged && _session.selected.isNotEmpty) {
            _confirmSource(route, from, to);
            return;
          }
          setState(() => _session.applyRoute(route, from, to));
        },
      ),
    );
  }

  void _confirmSource(int route, String from, String to) {
    _present(
      AppStrings.changeTheSource,
      Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            AppStrings.sourceChangeWarning(_session.selected.length),
            style: _text(size: 13, color: _muted, height: 1.5),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(child: _secondary(AppStrings.keep, () => Navigator.pop(context))),
              const SizedBox(width: 8),
              Expanded(
                child: _filled(AppStrings.changeSource, () {
                  Navigator.pop(context);
                  setState(() => _session.applyRoute(route, from, to));
                }),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _selectVisible() {
    final rows = _session.shown();
    if (rows.isEmpty) return;
    final all = rows.every((piece) => _session.selected.contains(piece.id));
    setState(() {
      for (final piece in rows) {
        _session.toggle(piece.id, !all);
      }
    });
  }

  void _review() {
    final messages = _session.errors();
    if (messages.isNotEmpty) {
      _toast(messages.join(' '));
      if (!messages.first.startsWith('Select')) _route();
      return;
    }
    final items = _session.chosen();
    final totals = TransferDemoSession.weightOf(items);
    _present(
      AppStrings.reviewTransfer,
      Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _routeCard(editing: false),
          _reviewRow(AppStrings.selectedPieces, '${items.length}'),
          _reviewRow(
            AppStrings.grossWeight,
            '${TransferDemoSession.grams(totals.$1)} g',
          ),
          _reviewRow(
            AppStrings.netWeight,
            '${TransferDemoSession.grams(totals.$2)} g',
          ),
          const SizedBox(height: 8),
          Text(
            items.map((piece) => '${piece.id} · ${piece.name}').join('\n'),
            style: _text(size: 12, height: 1.5),
          ),
          const SizedBox(height: 8),
          Text(AppStrings.reviewTransferNote, style: _text(size: 12, color: _note, height: 1.4)),
          const SizedBox(height: 14),
          _filled(AppStrings.confirmTransfer, _confirm),
          const SizedBox(height: 8),
          Text(AppStrings.exampleStockOnly, style: _text(size: 12, color: _note, height: 1.4)),
        ],
      ),
    );
  }

  void _confirm() {
    final record = _session.confirm();
    if (record == null) {
      _toast(_session.errors().join(' '));
      return;
    }
    Navigator.pop(context);
    setState(() {});
    _present(
      AppStrings.demoTransferComplete,
      Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            width: 62,
            height: 62,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: const Color(0xFFEDE6D6),
              borderRadius: BorderRadius.circular(18),
            ),
            child: const Icon(Icons.check, color: Color(0xFF87652A)),
          ),
          const SizedBox(height: 12),
          Text(
            '${record.ids.length} ${AppStrings.pieces}\n${record.from} → ${record.to}',
            style: _text(size: 14, weight: FontWeight.w600, height: 1.4),
          ),
          const SizedBox(height: 8),
          Text(
            '${record.id} ${AppStrings.recordedInDemo}',
            style: _text(size: 12, color: _note, height: 1.4),
          ),
          const SizedBox(height: 14),
          _filled(AppStrings.returnToStock, () => Navigator.pop(context)),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _transferListFromSuccess();
            },
            child: const Text(AppStrings.viewTransferList),
          ),
        ],
      ),
    );
  }

  void _transferListFromSuccess() {
    final records = _session.transfers;
    _present(
      AppStrings.transferList,
      records.isEmpty
          ? _empty(AppStrings.noDemoTransfers, AppStrings.confirmedTransfersHere)
          : Column(
              children: [
                for (final record in records)
                  Container(
                    width: double.infinity,
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: AppColors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFFE3DDD1)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(record.id, style: _text(size: 14, weight: FontWeight.w700)),
                        const SizedBox(height: 4),
                        Text(
                          '${record.from} → ${record.to}\n${record.ids.length} ${AppStrings.pieces} · ${AppStrings.grossWeight} ${TransferDemoSession.grams(record.gross)} g',
                          style: _text(size: 12, color: _muted, height: 1.4),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final chosen = _session.chosen();
    final totals = TransferDemoSession.weightOf(chosen);
    final rows = _session.shown();
    final allVisible = rows.isNotEmpty && rows.every((piece) => _session.selected.contains(piece.id));
    return PopScope(
      canPop: true,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) _stopScan();
      },
      child: AnnotatedRegion<SystemUiOverlayStyle>(
        value: const SystemUiOverlayStyle(
          statusBarColor: Color(0x00000000),
          statusBarIconBrightness: Brightness.dark,
          statusBarBrightness: Brightness.light,
          systemNavigationBarColor: _surface,
          systemNavigationBarIconBrightness: Brightness.dark,
        ),
        child: Scaffold(
          backgroundColor: _surface,
          body: SafeArea(
            child: Column(
              children: [
                _header(),
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
                    children: [
                      Row(
                        children: [
                          Text(
                            AppStrings.moveStockClarity,
                            style: _text(
                              size: 10,
                              weight: FontWeight.w600,
                              color: const Color(0xFF80745B),
                              letterSpacing: 0.5,
                            ),
                          ),
                          const Spacer(),
                          _tag(AppStrings.demoData),
                        ],
                      ),
                      const SizedBox(height: 12),
                      _routeCard(editing: true),
                      TextField(
                        controller: _query,
                        style: _text(size: 12),
                        decoration: InputDecoration(
                          hintText: AppStrings.searchItemCode,
                          hintStyle: _text(size: 12, color: const Color(0xFF8C7B57)),
                          prefixIcon: const Icon(Icons.search, size: 18, color: Color(0xFF8C7B57)),
                          filled: true,
                          fillColor: AppColors.white,
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(vertical: 14),
                          border: _border(const Color(0xFFDAD5CA), 12),
                          enabledBorder: _border(const Color(0xFFDAD5CA), 12),
                          focusedBorder: _border(const Color(0xFF967431), 12),
                        ),
                      ),
                      const SizedBox(height: 12),
                      _tabs(chosen.length),
                      if (_capturing) ...[
                        const SizedBox(height: 8),
                        Text(
                          AppStrings.selectingDemoTags,
                          style: _text(size: 12, weight: FontWeight.w600, color: const Color(0xFF8A682B)),
                        ),
                      ],
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: Text(AppStrings.tickOrScan, style: _text(size: 10, color: const Color(0xFF847860))),
                          ),
                          TextButton(
                            onPressed: rows.isEmpty ? null : _selectVisible,
                            child: Text(allVisible ? AppStrings.clearVisible : AppStrings.selectVisible),
                          ),
                        ],
                      ),
                      if (rows.isEmpty)
                        _empty(
                          _session.onlySelected ? AppStrings.noSelectedPieces : AppStrings.noPiecesHere,
                          _session.onlySelected ? AppStrings.switchToAllStock : AppStrings.checkSource,
                        )
                      else
                        for (final piece in rows) _stockRow(piece),
                    ],
                  ),
                ),
                _footer(chosen.length, totals.$1),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _header() {
    return DecoratedBox(
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: _headLine)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(4, 6, 4, 6),
        child: Row(
          children: [
            IconButton(
              tooltip: AppStrings.home,
              onPressed: () {
                _stopScan();
                Navigator.of(context).maybePop();
              },
              icon: const Icon(Icons.arrow_back, size: 21, color: _ink),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    AppStrings.stockTransfer,
                    style: _text(size: 21, weight: FontWeight.w600, letterSpacing: -0.7),
                  ),
                  const SizedBox(height: 4),
                  Text(AppStrings.transferPath, style: _text(size: 10, color: const Color(0xFF787166))),
                ],
              ),
            ),
            IconButton(
              tooltip: AppStrings.moreActions,
              onPressed: _menu,
              icon: const Icon(Icons.more_horiz, size: 21, color: _ink),
            ),
          ],
        ),
      ),
    );
  }

  Widget _routeCard({required bool editing}) {
    final kinds = _session.kinds;
    final fromLabel = editing ? '${AppStrings.fromDate} ${kinds.$1}'.toUpperCase() : AppStrings.fromDate.toUpperCase();
    final toLabel = editing ? '${AppStrings.toDate} ${kinds.$2}'.toUpperCase() : AppStrings.toDate.toUpperCase();
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: const Color(0xFFF5EEDF),
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: const Color(0xFFDDCBA5)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '${kinds.$1.toUpperCase()} TO ${kinds.$2.toUpperCase()}',
                  style: _text(size: 10, weight: FontWeight.w600, color: const Color(0xFF826537), letterSpacing: 0.4),
                ),
              ),
              if (editing)
                TextButton(
                  onPressed: _route,
                  style: TextButton.styleFrom(
                    foregroundColor: const Color(0xFF866526),
                    textStyle: _text(size: 10, color: const Color(0xFF866526)),
                  ),
                  child: const Text(AppStrings.editRoute),
                ),
            ],
          ),
          Row(
            children: [
              Expanded(child: _place(fromLabel, _session.from.isEmpty ? AppStrings.chooseSource : _session.from)),
              const Icon(Icons.arrow_right_alt, color: Color(0xFF917C53)),
              Expanded(child: _place(toLabel, _session.to.isEmpty ? AppStrings.chooseDestination : _session.to)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _place(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: _text(size: 9, color: const Color(0xFF826537), letterSpacing: 0.4),
        ),
        const SizedBox(height: 2),
        Text(value, style: _text(size: 14, weight: FontWeight.w700)),
      ],
    );
  }

  Widget _tabs(int selectedCount) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: const Color(0xFFEEEAE1),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          _tab(AppStrings.allStock, _session.available().length, !_session.onlySelected, false),
          _tab(AppStrings.selectedScope, selectedCount, _session.onlySelected, true),
        ],
      ),
    );
  }

  Widget _tab(String label, int count, bool active, bool onlySelected) {
    return Expanded(
      child: Material(
        color: active ? AppColors.white : const Color(0x00000000),
        borderRadius: BorderRadius.circular(7),
        child: InkWell(
          borderRadius: BorderRadius.circular(7),
          onTap: () => setState(() => _session.onlySelected = onlySelected),
          child: Container(
            alignment: Alignment.center,
            constraints: const BoxConstraints(minHeight: 37),
            child: Text(
              '$label ($count)',
              style: _text(
                size: 11,
                weight: active ? FontWeight.w600 : FontWeight.w400,
                color: active ? const Color(0xFF71531E) : const Color(0xFF7C7059),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _stockRow(TransferPiece piece) {
    final on = _session.selected.contains(piece.id);
    return Padding(
      padding: const EdgeInsets.only(bottom: 9),
      child: Material(
        color: on ? const Color(0xFFFAF5E9) : AppColors.white,
        borderRadius: BorderRadius.circular(11),
        child: InkWell(
          borderRadius: BorderRadius.circular(11),
          onTap: () => setState(() => _session.toggle(piece.id, !on)),
          child: Container(
            constraints: const BoxConstraints(minHeight: 74),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(11),
              border: Border.all(color: on ? const Color(0xFFCBB17A) : const Color(0xFFE2DDD1)),
            ),
            child: Row(
              children: [
                IgnorePointer(
                  child: SizedBox(
                    width: 22,
                    height: 22,
                    child: Checkbox(
                      value: on,
                      activeColor: const Color(0xFF8A682C),
                      onChanged: (_) {},
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                _thumb(piece.name),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('${piece.id} · ${piece.name}', style: _text(size: 13, weight: FontWeight.w700)),
                      Text(
                        '${AppStrings.grossWeight} ${TransferDemoSession.grams(piece.grossMg)} g\n${AppStrings.netWeight} ${TransferDemoSession.grams(piece.netMg)} g',
                        style: _text(size: 11, color: _muted, height: 1.35),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _footer(int count, int? gross) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
      decoration: const BoxDecoration(
        color: AppColors.white,
        border: Border(top: BorderSide(color: Color(0xFFE3DDD1))),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Text.rich(
                TextSpan(
                  style: _text(size: 12),
                  children: [
                    TextSpan(text: '$count', style: _text(size: 12, weight: FontWeight.w700)),
                    TextSpan(text: ' ${AppStrings.selectedScope.toLowerCase()}'),
                  ],
                ),
              ),
              const Spacer(),
              Text.rich(
                TextSpan(
                  style: _text(size: 12),
                  children: [
                    const TextSpan(text: 'Gross '),
                    TextSpan(
                      text: TransferDemoSession.grams(gross),
                      style: _text(size: 12, weight: FontWeight.w700),
                    ),
                    const TextSpan(text: ' g'),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: _toggleScan,
                  icon: Icon(_capturing ? Icons.pause : Icons.crop_free, size: 18),
                  label: Text(_capturing ? AppStrings.pause : AppStrings.scan),
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFFEEE5D1),
                    foregroundColor: const Color(0xFF85652C),
                    side: const BorderSide(color: Color(0xFFDFCEA9)),
                    minimumSize: const Size.fromHeight(52),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: FilledButton.icon(
                  onPressed: count == 0 ? null : _review,
                  icon: const Icon(Icons.arrow_forward, size: 18),
                  label: const Text(AppStrings.reviewTransfer),
                  style: FilledButton.styleFrom(
                    backgroundColor: _ink,
                    foregroundColor: AppColors.white,
                    disabledBackgroundColor: const Color(0xFFD9D4CB),
                    minimumSize: const Size.fromHeight(52),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            AppStrings.nothingMoves,
            textAlign: TextAlign.center,
            style: _text(size: 9, color: _note),
          ),
        ],
      ),
    );
  }

  Widget _reviewRow(String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Color(0xFFE7DFD0))),
      ),
      child: Row(
        children: [
          Expanded(child: Text(label, style: _text(size: 12, color: const Color(0xFF807254)))),
          Text(value, style: _text(size: 12, weight: FontWeight.w600)),
        ],
      ),
    );
  }

  Widget _menuRow(String label, IconData icon, VoidCallback onTap) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(icon, color: const Color(0xFF7B622F), size: 20),
      title: Text(label, style: _text(size: 13, weight: FontWeight.w600)),
      trailing: const Icon(Icons.chevron_right, color: Color(0xFF8F897B), size: 18),
      onTap: onTap,
    );
  }

  Widget _empty(String title, String body) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 28),
      child: Column(
        children: [
          Text(title, textAlign: TextAlign.center, style: _text(size: 16, weight: FontWeight.w700)),
          const SizedBox(height: 6),
          Text(body, textAlign: TextAlign.center, style: _text(size: 12, color: _muted, height: 1.5)),
        ],
      ),
    );
  }

  Widget _thumb(String name) {
    return Container(
      width: 35,
      height: 39,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: const Color(0xFFF4EFE4),
        borderRadius: BorderRadius.circular(7),
      ),
      child: Text(
        name.isEmpty ? '?' : name[0],
        style: _text(size: 14, weight: FontWeight.w700, color: _gold),
      ),
    );
  }

  Widget _tag(String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFFEEE9DD),
        borderRadius: BorderRadius.circular(5),
        border: Border.all(color: const Color(0xFFE3DAC6)),
      ),
      child: Text(label, style: _text(size: 9, color: const Color(0xFF837657), letterSpacing: 0.4)),
    );
  }

  Widget _filled(String label, VoidCallback onPressed) {
    return FilledButton(
      onPressed: onPressed,
      style: FilledButton.styleFrom(
        backgroundColor: _ink,
        foregroundColor: AppColors.white,
        minimumSize: const Size.fromHeight(52),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      child: Text(label),
    );
  }

  Widget _secondary(String label, VoidCallback onPressed) {
    return OutlinedButton(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        foregroundColor: const Color(0xFF755722),
        backgroundColor: const Color(0xFFF2EEE4),
        side: const BorderSide(color: Color(0xFFE3D7BA)),
        minimumSize: const Size.fromHeight(52),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      child: Text(label),
    );
  }
}

class _RouteForm extends StatefulWidget {
  const _RouteForm({
    required this.route,
    required this.from,
    required this.to,
    required this.onApply,
  });

  final int route;
  final String from;
  final String to;
  final void Function(int route, String from, String to) onApply;

  @override
  State<_RouteForm> createState() => _RouteFormState();
}

class _RouteFormState extends State<_RouteForm> {
  late int _route;
  late String _from;
  late String _to;
  String? _error;

  @override
  void initState() {
    super.initState();
    _route = widget.route;
    _from = widget.from;
    _to = widget.to;
  }

  void _changeType(int index) {
    final kinds = TransferDemoSession.routes[index];
    final fromPlaces = TransferDemoSession.places[kinds.$1]!;
    final toPlaces = TransferDemoSession.places[kinds.$2]!;
    setState(() {
      _route = index;
      _from = fromPlaces.first;
      _to = kinds.$1 == kinds.$2 ? toPlaces[1] : toPlaces.first;
      _error = null;
    });
  }

  void _apply() {
    final kinds = TransferDemoSession.routes[_route];
    if (kinds.$1 == kinds.$2 && _from == _to) {
      setState(() => _error = AppStrings.differentDestination);
      return;
    }
    widget.onApply(_route, _from, _to);
  }

  @override
  Widget build(BuildContext context) {
    final kinds = TransferDemoSession.routes[_route];
    final fromPlaces = TransferDemoSession.places[kinds.$1]!;
    final toPlaces = TransferDemoSession.places[kinds.$2]!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _drop(
          AppStrings.transferType,
          _route,
          [
            for (var i = 0; i < TransferDemoSession.routes.length; i++)
              DropdownMenuItem(
                value: i,
                child: Text('${TransferDemoSession.routes[i].$1} to ${TransferDemoSession.routes[i].$2}'),
              ),
          ],
          _changeType,
        ),
        _drop(
          '${AppStrings.fromDate} ${kinds.$1.toLowerCase()}',
          _from,
          [for (final place in fromPlaces) DropdownMenuItem(value: place, child: Text(place))],
          (value) => setState(() => _from = value),
        ),
        _drop(
          '${AppStrings.toDate} ${kinds.$2.toLowerCase()}',
          _to,
          [for (final place in toPlaces) DropdownMenuItem(value: place, child: Text(place))],
          (value) => setState(() => _to = value),
        ),
        Text(AppStrings.routeExamples, style: _text(size: 12, color: const Color(0xFF817866), height: 1.4)),
        if (_error != null) ...[
          const SizedBox(height: 8),
          Text(_error!, style: _text(size: 12, color: const Color(0xFF964A32))),
        ],
        const SizedBox(height: 14),
        FilledButton.icon(
          onPressed: _apply,
          icon: const Icon(Icons.arrow_forward, size: 18),
          label: const Text(AppStrings.useThisRoute),
          style: FilledButton.styleFrom(
            backgroundColor: const Color(0xFF20201E),
            foregroundColor: AppColors.white,
            minimumSize: const Size.fromHeight(52),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
      ],
    );
  }

  Widget _drop<T>(String label, T value, List<DropdownMenuItem<T>> items, ValueChanged<T> onChanged) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: DropdownButtonFormField<T>(
        key: ValueKey('$label-$value'),
        initialValue: value,
        items: items,
        onChanged: (next) {
          if (next != null) onChanged(next);
        },
        decoration: InputDecoration(
          labelText: label,
          filled: true,
          fillColor: AppColors.white,
          border: _border(const Color(0xFFD5CBBC), 10),
          enabledBorder: _border(const Color(0xFFD5CBBC), 10),
          focusedBorder: _border(const Color(0xFF967431), 10),
        ),
      ),
    );
  }
}

OutlineInputBorder _border(Color color, double radius) {
  return OutlineInputBorder(
    borderRadius: BorderRadius.all(Radius.circular(radius)),
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
