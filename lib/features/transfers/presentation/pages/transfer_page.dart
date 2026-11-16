import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:rfid_flutter_android/rfid_flutter_android.dart';

import '../../../../core/constants/app_strings.dart';
import '../../../../core/rfid/rfid_service.dart';
import '../../../../core/rfid/scan_sound.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../inventory/data/inventory_stock.dart';
import '../../../inventory/domain/inventory_catalog.dart';
import '../../data/stock_transfer.dart';

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

  final _api = StockTransferApi();
  final _query = TextEditingController();
  final _selected = <String>{};
  var _loading = true;
  var _sending = false;
  var _capturing = false;
  var _single = false;
  var _onlySelected = false;
  var _shown = 60;
  List<TransferTypeOption> _types = const [];
  TransferTypeOption? _type;
  String _from = '';
  String _to = '';
  StreamSubscription<List<RfidTagInfo>>? _tags;
  Timer? _singleTimer;

  @override
  void initState() {
    super.initState();
    _query.addListener(() {
      if (mounted) setState(() => _shown = 60);
    });
    unawaited(_load());
  }

  @override
  void dispose() {
    _singleTimer?.cancel();
    _tags?.cancel();
    unawaited(RfidService.instance.stopIfRunning());
    unawaited(ScanSound.stopAll());
    _query.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    await InventoryStock.instance.load();
    try {
      _types = await _api.types();
    } catch (_) {
      _types = const [];
    }
    if (!mounted) return;
    setState(() => _loading = false);
  }

  (String, String)? get _ends => _type?.ends;

  List<InventoryPiece> get _atSource {
    final ends = _ends;
    if (ends == null || _from.isEmpty) return InventoryStock.instance.pieces;
    return InventoryStock.instance.pieces.where((item) {
      return (_place(item, ends.$1) ?? '').toLowerCase() == _from.toLowerCase();
    }).toList();
  }

  List<InventoryPiece> get _matched {
    final query = _query.text.trim().toLowerCase();
    final pool = _onlySelected
        ? InventoryStock.instance.pieces.where((item) => _selected.contains(item.id)).toList()
        : _atSource;
    if (query.isEmpty) return pool;
    return pool.where((item) {
      return item.id.toLowerCase().contains(query) ||
          item.name.toLowerCase().contains(query) ||
          (item.rfid ?? '').toLowerCase().contains(query);
    }).toList();
  }

  List<InventoryPiece> get _chosen {
    return InventoryStock.instance.pieces.where((item) => _selected.contains(item.id)).toList();
  }

  String? _place(InventoryPiece item, String kind) {
    return switch (kind) {
      'counter' => item.counter,
      'box' => item.box,
      'packet' => item.packet,
      'branch' => item.branch,
      _ => null,
    };
  }

  void _toast(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _stopScan() async {
    _singleTimer?.cancel();
    _capturing = false;
    _single = false;
    await RfidService.instance.stopIfRunning();
    await ScanSound.stopAll();
  }

  Future<void> _toggleScan({required bool single}) async {
    if (_capturing) {
      await _stopScan();
      if (mounted) setState(() {});
      return;
    }
    if (_loading) {
      _toast(AppStrings.pleaseWaitItemsLoading);
      return;
    }
    if (_atSource.isEmpty) {
      _toast(AppStrings.noPiecesHere);
      return;
    }
    setState(() {
      _capturing = true;
      _single = single;
    });
    _tags ??= RfidService.instance.tagStream.listen(_onTags);
    final blocked = await RfidService.instance.init();
    if (!mounted) return;
    if (blocked != null) {
      setState(() {
        _capturing = false;
        _single = false;
      });
      _toast(blocked);
      return;
    }
    await RfidService.instance.stopIfRunning();
    await RfidService.instance.setInventoryMode(kEpcInventoryMode);
    final error = await RfidService.instance.startInventory();
    if (!mounted) return;
    if (error != null) {
      setState(() {
        _capturing = false;
        _single = false;
      });
      _toast(error);
      return;
    }
    if (single) {
      _singleTimer = Timer(const Duration(seconds: 2), () {
        if (mounted && _single) {
          unawaited(_stopScan().then((_) {
            if (mounted) setState(() {});
          }));
        }
      });
    } else {
      unawaited(ScanSound.startInventory());
    }
  }

  void _onTags(List<RfidTagInfo> batch) {
    if (!_capturing) return;
    final allowed = _atSource.map((item) => item.id).toSet();
    var added = false;
    for (final tag in batch) {
      final id = InventoryStock.instance.match(tag.epc.isNotEmpty ? tag.epc : tag.tid);
      if (id == null || !allowed.contains(id) || !_selected.add(id)) continue;
      added = true;
      unawaited(ScanSound.beep());
      if (_single) {
        unawaited(_stopScan());
        break;
      }
    }
    if (added && mounted) setState(() {});
  }

  void _present(String title, Widget body) {
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
          padding: EdgeInsets.fromLTRB(22, 0, 22, 20 + MediaQuery.viewInsetsOf(context).bottom),
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
                      child: Text(title, style: _text(size: 20, weight: FontWeight.w600, letterSpacing: -0.6)),
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
          _menuRow(AppStrings.scanOne, Icons.center_focus_strong, () {
            Navigator.pop(context);
            unawaited(_toggleScan(single: true));
          }),
          _menuRow(AppStrings.gscan, Icons.crop_free, () {
            Navigator.pop(context);
            unawaited(_toggleScan(single: false));
          }),
          _menuRow(AppStrings.transferList, Icons.list_alt, () {
            Navigator.pop(context);
            _openList();
          }),
          _menuRow(AppStrings.clearSelectedPieces, Icons.restart_alt, _clear),
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
                  _selected.clear();
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

  void _openList() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: _surface,
      barrierColor: const Color(0x70151410),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(23)),
      ),
      builder: (context) => _TransferList(api: _api, types: _types),
    );
  }

  void _route() {
    if (_types.isEmpty) {
      _toast(AppStrings.noTransferTypes);
      return;
    }
    _present(
      AppStrings.chooseTransferRoute,
      _RouteForm(
        types: _types,
        type: _type,
        from: _from,
        to: _to,
        onApply: (type, from, to) {
          Navigator.pop(context);
          final sourceChanged = _type?.id != type.id || _from != from;
          if (sourceChanged && _selected.isNotEmpty) {
            _confirmSource(type, from, to);
            return;
          }
          setState(() {
            _type = type;
            _from = from;
            _to = to;
            _shown = 60;
          });
        },
      ),
    );
  }

  void _confirmSource(TransferTypeOption type, String from, String to) {
    _present(
      AppStrings.changeTheSource,
      Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(AppStrings.sourceChangeWarning(_selected.length), style: _text(size: 13, color: _muted, height: 1.5)),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(child: _secondary(AppStrings.keep, () => Navigator.pop(context))),
              const SizedBox(width: 8),
              Expanded(
                child: _filled(AppStrings.changeSource, () {
                  Navigator.pop(context);
                  setState(() {
                    _selected.clear();
                    _type = type;
                    _from = from;
                    _to = to;
                  });
                }),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _selectVisible() {
    final rows = _matched.take(_shown).toList();
    if (rows.isEmpty) return;
    final all = rows.every((piece) => _selected.contains(piece.id));
    setState(() {
      for (final piece in rows) {
        if (all) {
          _selected.remove(piece.id);
        } else {
          _selected.add(piece.id);
        }
      }
    });
  }

  Future<void> _review() async {
    if (_type == null || _from.isEmpty || _to.isEmpty) {
      _toast(AppStrings.validRoute);
      _route();
      return;
    }
    final ends = _ends;
    if (ends != null && ends.$1 == ends.$2 && _from.toLowerCase() == _to.toLowerCase()) {
      _toast(AppStrings.sourceDestDifferent);
      return;
    }
    final items = _chosen;
    if (items.isEmpty) {
      _toast(AppStrings.selectOnePiece);
      return;
    }
    if (items.every((item) => item.stockId <= 0)) {
      _toast(AppStrings.missingStockId);
      return;
    }
    final branchMove = _type!.id == 15 || (ends?.$1 == 'branch' && ends?.$2 == 'branch');
    var people = const <TransferEmployee>[];
    if (branchMove) {
      try {
        people = await _api.employees();
      } catch (_) {
        people = const [];
      }
    }
    if (!mounted) return;
    final gross = items.fold<int>(0, (sum, item) => sum + item.milligrams);
    final net = items.fold<int>(0, (sum, item) => sum + (item.netMilligrams ?? 0));
    final remarks = TextEditingController();
    String employee = people.isEmpty ? '' : people.first.id;
    _present(
      AppStrings.reviewTransfer,
      StatefulBuilder(
        builder: (context, setSheet) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _routeCard(editing: false),
              _reviewRow(AppStrings.selectedPieces, '${items.length}'),
              _reviewRow(AppStrings.grossWeight, '${InventoryCatalog.grams(gross)} g'),
              _reviewRow(AppStrings.netWeight, '${InventoryCatalog.grams(net)} g'),
              const SizedBox(height: 8),
              TextField(
                controller: remarks,
                decoration: InputDecoration(
                  labelText: AppStrings.remarks,
                  filled: true,
                  fillColor: AppColors.white,
                  border: _border(const Color(0xFFD5CBBC), 10),
                ),
              ),
              if (branchMove) ...[
                const SizedBox(height: 10),
                if (people.isEmpty)
                  TextField(
                    decoration: InputDecoration(
                      labelText: AppStrings.receivingEmployee,
                      filled: true,
                      fillColor: AppColors.white,
                      border: _border(const Color(0xFFD5CBBC), 10),
                    ),
                    onChanged: (value) => employee = value.trim(),
                  )
                else
                  DropdownButtonFormField<String>(
                    initialValue: employee,
                    items: [
                      for (final person in people)
                        DropdownMenuItem(value: person.id, child: Text(person.name)),
                    ],
                    onChanged: (value) => setSheet(() => employee = value ?? employee),
                    decoration: InputDecoration(
                      labelText: AppStrings.receivingEmployee,
                      filled: true,
                      fillColor: AppColors.white,
                      border: _border(const Color(0xFFD5CBBC), 10),
                    ),
                  ),
              ],
              const SizedBox(height: 8),
              Text(AppStrings.reviewTransferNote, style: _text(size: 12, color: _note, height: 1.4)),
              const SizedBox(height: 14),
              _filled(AppStrings.confirmTransfer, () => _send(remarks.text, employee)),
            ],
          );
        },
      ),
    );
  }

  Future<void> _send(String remarks, String employee) async {
    if (_sending || _type == null) return;
    setState(() => _sending = true);
    String? error;
    try {
      error = await _api.submit(
        type: _type!,
        fromName: _from,
        toName: _to,
        pieces: _chosen,
        remarks: remarks.trim(),
        transferToEmployee: employee,
      );
    } catch (failure) {
      if (mounted) _toast(failure.toString());
      if (mounted) setState(() => _sending = false);
      return;
    }
    if (!mounted) return;
    setState(() => _sending = false);
    if (error != null) {
      _toast(error);
      return;
    }
    final count = _selected.length;
    final route = '$_from → $_to';
    _selected.clear();
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
            decoration: BoxDecoration(color: const Color(0xFFEDE6D6), borderRadius: BorderRadius.circular(18)),
            child: const Icon(Icons.check, color: Color(0xFF87652A)),
          ),
          const SizedBox(height: 12),
          Text('$count ${AppStrings.pieces}\n$route', style: _text(size: 14, weight: FontWeight.w600, height: 1.4)),
          const SizedBox(height: 8),
          Text(AppStrings.recordedInDemo, style: _text(size: 12, color: _note, height: 1.4)),
          const SizedBox(height: 14),
          _filled(AppStrings.returnToStock, () => Navigator.pop(context)),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _openList();
            },
            child: const Text(AppStrings.viewTransferList),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final chosen = _chosen;
    final gross = chosen.fold<int>(0, (sum, item) => sum + item.milligrams);
    final rows = _matched;
    final visible = rows.take(_shown).toList();
    final allVisible = visible.isNotEmpty && visible.every((piece) => _selected.contains(piece.id));
    return PopScope(
      canPop: true,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) unawaited(_stopScan());
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
                            style: _text(size: 10, weight: FontWeight.w600, color: const Color(0xFF80745B), letterSpacing: 0.5),
                          ),
                          const Spacer(),
                          _tag(AppStrings.liveStock),
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
                      _tabs(chosen.length, _atSource.length),
                      if (_loading) ...[
                        const SizedBox(height: 18),
                        const Center(child: CircularProgressIndicator(strokeWidth: 2)),
                      ] else ...[
                        if (_capturing) ...[
                          const SizedBox(height: 8),
                          Text(
                            AppStrings.listeningForPieces,
                            style: _text(size: 12, weight: FontWeight.w600, color: const Color(0xFF8A682B)),
                          ),
                        ],
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(child: Text(AppStrings.tickOrScan, style: _text(size: 10, color: const Color(0xFF847860)))),
                            TextButton(
                              onPressed: visible.isEmpty ? null : _selectVisible,
                              child: Text(allVisible ? AppStrings.clearVisible : AppStrings.selectVisible),
                            ),
                          ],
                        ),
                        if (visible.isEmpty)
                          _empty(
                            _onlySelected ? AppStrings.noSelectedPieces : AppStrings.noPiecesHere,
                            _onlySelected ? AppStrings.switchToAllStock : AppStrings.checkSource,
                          )
                        else
                          for (final piece in visible) _stockRow(piece),
                        if (rows.length > visible.length)
                          TextButton(
                            onPressed: () => setState(() => _shown += 60),
                            child: Text('${AppStrings.showMoreItems} (${rows.length - visible.length})'),
                          ),
                      ],
                    ],
                  ),
                ),
                _footer(chosen.length, gross),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _header() {
    return DecoratedBox(
      decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: _headLine))),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(4, 6, 4, 6),
        child: Row(
          children: [
            IconButton(
              tooltip: AppStrings.home,
              onPressed: () {
                unawaited(_stopScan());
                Navigator.of(context).maybePop();
              },
              icon: const Icon(Icons.arrow_back, size: 21, color: _ink),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(AppStrings.stockTransfer, style: _text(size: 21, weight: FontWeight.w600, letterSpacing: -0.7)),
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
    final ends = _ends;
    final title = _type?.name ?? AppStrings.chooseTransferRoute;
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
                  title.toUpperCase(),
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
              Expanded(child: _placeLabel(ends == null ? AppStrings.fromDate : ends.$1, _from.isEmpty ? AppStrings.chooseSource : _from)),
              const Icon(Icons.arrow_right_alt, color: Color(0xFF917C53)),
              Expanded(child: _placeLabel(ends == null ? AppStrings.toDate : ends.$2, _to.isEmpty ? AppStrings.chooseDestination : _to)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _placeLabel(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label.toUpperCase(), style: _text(size: 9, color: const Color(0xFF826537), letterSpacing: 0.4)),
        const SizedBox(height: 2),
        Text(value, style: _text(size: 14, weight: FontWeight.w700)),
      ],
    );
  }

  Widget _tabs(int selectedCount, int stockCount) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(color: const Color(0xFFEEEAE1), borderRadius: BorderRadius.circular(10)),
      child: Row(
        children: [
          _tab(AppStrings.allStock, stockCount, !_onlySelected, false),
          _tab(AppStrings.selectedScope, selectedCount, _onlySelected, true),
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
          onTap: () => setState(() {
            _onlySelected = onlySelected;
            _shown = 60;
          }),
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

  Widget _stockRow(InventoryPiece piece) {
    final on = _selected.contains(piece.id);
    return Padding(
      padding: const EdgeInsets.only(bottom: 9),
      child: Material(
        color: on ? const Color(0xFFFAF5E9) : AppColors.white,
        borderRadius: BorderRadius.circular(11),
        child: InkWell(
          borderRadius: BorderRadius.circular(11),
          onTap: () => setState(() {
            if (on) {
              _selected.remove(piece.id);
            } else {
              _selected.add(piece.id);
            }
          }),
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
                    child: Checkbox(value: on, activeColor: const Color(0xFF8A682C), onChanged: (_) {}),
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
                        '${AppStrings.grossWeight} ${InventoryCatalog.grams(piece.milligrams)} g\n${AppStrings.netWeight} ${InventoryCatalog.grams(piece.netMilligrams ?? 0)} g',
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

  Widget _footer(int count, int gross) {
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
                    TextSpan(text: InventoryCatalog.grams(gross), style: _text(size: 12, weight: FontWeight.w700)),
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
                  onPressed: _sending ? null : () => _toggleScan(single: false),
                  icon: Icon(_capturing && !_single ? Icons.pause : Icons.crop_free, size: 18),
                  label: Text(_capturing && !_single ? AppStrings.pause : AppStrings.scan),
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
                  onPressed: count == 0 || _sending ? null : _review,
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
          Text(AppStrings.nothingMoves, textAlign: TextAlign.center, style: _text(size: 9, color: _note)),
        ],
      ),
    );
  }

  Widget _reviewRow(String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Color(0xFFE7DFD0)))),
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
      decoration: BoxDecoration(color: const Color(0xFFF4EFE4), borderRadius: BorderRadius.circular(7)),
      child: Text(name.isEmpty ? '?' : name[0], style: _text(size: 14, weight: FontWeight.w700, color: _gold)),
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
    required this.types,
    required this.type,
    required this.from,
    required this.to,
    required this.onApply,
  });

  final List<TransferTypeOption> types;
  final TransferTypeOption? type;
  final String from;
  final String to;
  final void Function(TransferTypeOption type, String from, String to) onApply;

  @override
  State<_RouteForm> createState() => _RouteFormState();
}

class _RouteFormState extends State<_RouteForm> {
  late TransferTypeOption _type;
  late String _from;
  late String _to;
  String? _error;

  @override
  void initState() {
    super.initState();
    _type = widget.type ?? widget.types.first;
    final places = _places(_type);
    _from = places.$1.contains(widget.from) ? widget.from : (places.$1.isEmpty ? '' : places.$1.first);
    _to = places.$2.contains(widget.to) ? widget.to : (places.$2.isEmpty ? '' : places.$2.first);
  }

  (List<String>, List<String>) _places(TransferTypeOption type) {
    final ends = type.ends;
    if (ends == null) return (const [], const []);
    String title(String kind) => kind.isEmpty ? kind : '${kind[0].toUpperCase()}${kind.substring(1)}';
    return (InventoryStock.instance.places(title(ends.$1)), InventoryStock.instance.places(title(ends.$2)));
  }

  void _changeType(TransferTypeOption type) {
    final places = _places(type);
    setState(() {
      _type = type;
      _from = places.$1.isEmpty ? '' : places.$1.first;
      _to = places.$2.length > 1 && places.$1.isNotEmpty && places.$2.first == _from ? places.$2[1] : (places.$2.isEmpty ? '' : places.$2.first);
      _error = null;
    });
  }

  void _apply() {
    final ends = _type.ends;
    if (_from.isEmpty || _to.isEmpty) {
      setState(() => _error = AppStrings.validRoute);
      return;
    }
    if (ends != null && ends.$1 == ends.$2 && _from == _to) {
      setState(() => _error = AppStrings.differentDestination);
      return;
    }
    widget.onApply(_type, _from, _to);
  }

  @override
  Widget build(BuildContext context) {
    final places = _places(_type);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DropdownButtonFormField<int>(
          initialValue: _type.id,
          items: [
            for (final type in widget.types) DropdownMenuItem(value: type.id, child: Text(type.name)),
          ],
          onChanged: (id) {
            final next = widget.types.where((type) => type.id == id).firstOrNull;
            if (next != null) _changeType(next);
          },
          decoration: InputDecoration(
            labelText: AppStrings.transferType,
            filled: true,
            fillColor: AppColors.white,
            border: _border(const Color(0xFFD5CBBC), 10),
          ),
        ),
        const SizedBox(height: 12),
        if (places.$1.isEmpty || places.$2.isEmpty)
          Text(AppStrings.syncBeforeTransfer, style: _text(size: 12, color: const Color(0xFF817866), height: 1.4))
        else ...[
          DropdownButtonFormField<String>(
            initialValue: _from,
            items: [for (final place in places.$1) DropdownMenuItem(value: place, child: Text(place))],
            onChanged: (value) => setState(() => _from = value ?? _from),
            decoration: InputDecoration(
              labelText: AppStrings.fromDate,
              filled: true,
              fillColor: AppColors.white,
              border: _border(const Color(0xFFD5CBBC), 10),
            ),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: _to,
            items: [for (final place in places.$2) DropdownMenuItem(value: place, child: Text(place))],
            onChanged: (value) => setState(() => _to = value ?? _to),
            decoration: InputDecoration(
              labelText: AppStrings.toDate,
              filled: true,
              fillColor: AppColors.white,
              border: _border(const Color(0xFFD5CBBC), 10),
            ),
          ),
        ],
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
}

class _TransferList extends StatefulWidget {
  const _TransferList({required this.api, required this.types});

  final StockTransferApi api;
  final List<TransferTypeOption> types;

  @override
  State<_TransferList> createState() => _TransferListState();
}

class _TransferListState extends State<_TransferList> {
  var _out = true;
  var _loading = true;
  var _busy = false;
  String? _error;
  List<TransferRecord> _records = const [];

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      _records = await widget.api.list(requestType: _out ? 'Out' : 'In');
    } catch (error) {
      _error = error.toString();
      _records = const [];
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _cancel(TransferRecord record) async {
    setState(() => _busy = true);
    try {
      final message = await widget.api.cancel(record.id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message ?? AppStrings.transferUpdated)));
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$error')));
      }
    }
    if (mounted) await _load();
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _decide(TransferRecord record, List<TransferLine> lines, int status) async {
    setState(() => _busy = true);
    try {
      final message = await widget.api.decide(lines: lines, requestType: record.requestType, status: status);
      if (status == 1) {
        await widget.api.moveApproved(record: record, lines: lines);
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message ?? AppStrings.transferUpdated)));
        Navigator.pop(context);
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$error')));
      }
    }
    if (mounted) {
      setState(() => _busy = false);
      await _load();
    }
  }

  void _open(TransferRecord record) {
    final picked = <int>{for (final line in record.lines) if (line.approveId > 0 && (line.status ?? 0) == 0) line.approveId};
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFFFAF9F7),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(23))),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setSheet) {
            return Padding(
              padding: const EdgeInsets.fromLTRB(22, 16, 22, 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('${record.typeName} · ${record.id}', style: _text(size: 16, weight: FontWeight.w700)),
                  const SizedBox(height: 6),
                  Text('${record.from} → ${record.to}', style: _text(size: 12, color: const Color(0xFF6D6B66))),
                  const SizedBox(height: 12),
                  for (final line in record.lines)
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      value: picked.contains(line.approveId),
                      activeColor: const Color(0xFF8A682C),
                      onChanged: line.approveId <= 0
                          ? null
                          : (value) => setSheet(() {
                              if (value ?? false) {
                                picked.add(line.approveId);
                              } else {
                                picked.remove(line.approveId);
                              }
                            }),
                      title: Text('${line.itemCode} · ${line.name}', style: _text(size: 13, weight: FontWeight.w600)),
                      subtitle: Text(line.gross.isEmpty ? '' : '${line.gross} g', style: _text(size: 11)),
                    ),
                  if (record.selfApproval) ...[
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: FilledButton(
                            onPressed: _busy
                                ? null
                                : () {
                                    final lines = record.lines.where((line) => picked.contains(line.approveId)).toList();
                                    if (lines.isEmpty) return;
                                    Navigator.pop(context);
                                    unawaited(_decide(record, lines, 1));
                                  },
                            child: const Text(AppStrings.approve),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: OutlinedButton(
                            onPressed: _busy
                                ? null
                                : () {
                                    final lines = record.lines.where((line) => picked.contains(line.approveId)).toList();
                                    if (lines.isEmpty) return;
                                    Navigator.pop(context);
                                    unawaited(_decide(record, lines, 2));
                                  },
                            child: const Text(AppStrings.reject),
                          ),
                        ),
                      ],
                    ),
                  ],
                  if (record.pending > 0) ...[
                    const SizedBox(height: 8),
                    TextButton(
                      onPressed: _busy
                          ? null
                          : () {
                              Navigator.pop(context);
                              unawaited(_cancel(record));
                            },
                      child: const Text(AppStrings.cancelTransfer),
                    ),
                  ],
                ],
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final height = MediaQuery.sizeOf(context).height * 0.82;
    return SizedBox(
      height: height,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(22, 12, 22, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(AppStrings.transferList, style: _text(size: 20, weight: FontWeight.w600)),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(child: _side(AppStrings.outgoing, _out, () => _switch(true))),
                const SizedBox(width: 8),
                Expanded(child: _side(AppStrings.incoming, !_out, () => _switch(false))),
              ],
            ),
            const SizedBox(height: 12),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
                  : _error != null
                      ? Text(_error!, style: _text(size: 13, color: const Color(0xFF964A32)))
                      : _records.isEmpty
                          ? Text(AppStrings.transfersAppearHere, style: _text(size: 13, color: const Color(0xFF6D6B66)))
                          : ListView(
                              children: [
                                for (final record in _records)
                                  InkWell(
                                    onTap: () => _open(record),
                                    child: Container(
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
                                          Text('${record.typeName} · ${record.id}', style: _text(size: 14, weight: FontWeight.w700)),
                                          const SizedBox(height: 4),
                                          Text(
                                            '${record.from} → ${record.to}\nP:${record.pending}  A:${record.approved}  R:${record.rejected}',
                                            style: _text(size: 12, color: const Color(0xFF6D6B66), height: 1.4),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                              ],
                            ),
            ),
          ],
        ),
      ),
    );
  }

  void _switch(bool out) {
    if (_out == out) return;
    setState(() => _out = out);
    unawaited(_load());
  }

  Widget _side(String label, bool active, VoidCallback onTap) {
    return Material(
      color: active ? AppColors.white : const Color(0xFFEEEAE1),
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Container(
          alignment: Alignment.center,
          constraints: const BoxConstraints(minHeight: 40),
          child: Text(label, style: _text(size: 13, weight: FontWeight.w600)),
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
