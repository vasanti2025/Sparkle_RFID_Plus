import 'dart:async';

import 'package:flutter/material.dart';
import 'package:rfid_flutter_android/rfid_flutter_android.dart';

import '../../../../core/constants/app_strings.dart';
import '../../../../core/di/injection.dart';
import '../../../../core/rfid/rfid_service.dart';
import '../../../../core/rfid/scan_sound.dart';
import '../../../../core/session/app_session.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/result.dart';
import '../../../inventory/data/inventory_stock.dart';
import '../../../inventory/domain/inventory_catalog.dart';
import '../../../quotation/domain/entities/customer_record.dart';
import '../../data/sample_api.dart';

class SamplePage extends StatefulWidget {
  const SamplePage({super.key, required this.incoming});

  final bool incoming;

  @override
  State<SamplePage> createState() => _SamplePageState();
}

class _SamplePageState extends State<SamplePage> {
  static const _surface = Color(0xFFFAF9F7);
  static const _ink = Color(0xFF20201E);
  static const _muted = Color(0xFF6D6B66);

  final _api = SampleApi();
  final _customerQuery = TextEditingController();
  final _returnDate = TextEditingController();
  final _description = TextEditingController();
  final _selected = <String>{};
  final _returned = <String>{};
  CustomerIndex? _customers;
  CustomerRecord? _customer;
  List<SampleOutRecord> _open = const [];
  SampleOutRecord? _out;
  var _loading = true;
  var _saving = false;
  var _scanning = false;
  StreamSubscription<List<RfidTagInfo>>? _tags;

  @override
  void initState() {
    super.initState();
    final today = DateTime.now();
    _returnDate.text = '${today.year}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}';
    _customerQuery.addListener(() {
      if (_customer != null && _customerQuery.text != _customer!.name) {
        _customer = null;
      }
      if (mounted) setState(() {});
    });
    unawaited(_load());
  }

  @override
  void dispose() {
    _tags?.cancel();
    unawaited(RfidService.instance.stopIfRunning());
    unawaited(ScanSound.stopAll());
    _customerQuery.dispose();
    _returnDate.dispose();
    _description.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    await InventoryStock.instance.load();
    if (!widget.incoming && Injection.ready && AppSession.clientCode.isNotEmpty) {
      final result = await Injection.quotations.loadCustomers(AppSession.clientCode);
      if (result case Success(:final data)) _customers = data;
    }
    if (widget.incoming) {
      try {
        final records = await _api.sampleOuts();
        _open = records.where((record) => record.open && record.items.isNotEmpty).toList();
      } catch (_) {
        _open = const [];
      }
    }
    if (mounted) setState(() => _loading = false);
  }

  void _toast(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _toggleScan() async {
    if (_scanning) {
      await RfidService.instance.stopIfRunning();
      await ScanSound.stopAll();
      if (mounted) setState(() => _scanning = false);
      return;
    }
    setState(() => _scanning = true);
    _tags ??= RfidService.instance.tagStream.listen(_onTags);
    final blocked = await RfidService.instance.init();
    if (!mounted) return;
    if (blocked != null) {
      setState(() => _scanning = false);
      _toast(blocked);
      return;
    }
    await RfidService.instance.setInventoryMode(kEpcInventoryMode);
    final error = await RfidService.instance.startInventory();
    if (!mounted) return;
    if (error != null) {
      setState(() => _scanning = false);
      _toast(error);
      return;
    }
    unawaited(ScanSound.startInventory());
  }

  void _onTags(List<RfidTagInfo> batch) {
    if (!_scanning) return;
    var changed = false;
    for (final tag in batch) {
      final id = InventoryStock.instance.match(tag.epc.isNotEmpty ? tag.epc : tag.tid);
      if (widget.incoming) {
        final code = _matchIssue(tag.epc, tag.tid, id);
        if (code == null || !_returned.add(code)) continue;
      } else {
        if (id == null || !_selected.add(id)) continue;
      }
      changed = true;
      unawaited(ScanSound.beep());
    }
    if (changed && mounted) setState(() {});
  }

  String? _matchIssue(String epc, String tid, String? itemId) {
    final needles = [epc, tid, itemId ?? ''].map(_norm).where((value) => value.isNotEmpty).toSet();
    for (final item in _out?.items ?? const <Map<String, dynamic>>[]) {
      final code = '${item['ItemCode'] ?? ''}'.trim();
      final keys = [code, '${item['RFIDCode'] ?? ''}', '${item['TIDNumber'] ?? ''}'].map(_norm);
      if (keys.any(needles.contains)) return code;
    }
    return null;
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);
    String? error;
    try {
      if (widget.incoming) {
        final record = _out;
        if (record == null) {
          error = AppStrings.chooseSampleOut;
        } else {
          error = await _api.saveIn(record: record, returnedCodes: _returned);
        }
      } else {
        final customer = _customer;
        if (customer == null) {
          error = AppStrings.chooseCustomer;
        } else {
          final pieces = InventoryStock.instance.pieces.where((piece) => _selected.contains(piece.id)).toList();
          error = await _api.saveOut(
            customerId: customer.id,
            customerName: customer.name,
            returnDate: _returnDate.text.trim(),
            description: _description.text.trim(),
            pieces: pieces,
          );
        }
      }
    } catch (failure) {
      error = failure.toString();
    }
    if (!mounted) return;
    setState(() => _saving = false);
    if (error != null) {
      _toast(error);
      return;
    }
    _selected.clear();
    _returned.clear();
    _toast(widget.incoming ? AppStrings.sampleUpdated : AppStrings.sampleSaved);
    if (widget.incoming) await _load();
    if (mounted) setState(() => _out = null);
  }

  void _showRecords() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: _surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(23))),
      builder: (context) => _RecordList(api: _api, incoming: widget.incoming),
    );
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.incoming ? AppStrings.sampleIn : AppStrings.sampleOut;
    return Scaffold(
      backgroundColor: _surface,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 6, 4, 6),
              child: Row(
                children: [
                  IconButton(
                    onPressed: () => Navigator.of(context).maybePop(),
                    icon: const Icon(Icons.arrow_back, size: 21, color: _ink),
                  ),
                  Expanded(child: Text(title, style: _text(size: 21, weight: FontWeight.w600))),
                  IconButton(
                    onPressed: _showRecords,
                    icon: const Icon(Icons.list_alt, size: 21, color: _ink),
                  ),
                ],
              ),
            ),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
                  : ListView(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                      children: widget.incoming ? _incoming() : _outgoing(),
                    ),
            ),
            _footer(),
          ],
        ),
      ),
    );
  }

  List<Widget> _outgoing() {
    final matches = _customers?.search(_customerQuery.text) ?? const <CustomerRecord>[];
    final chosen = InventoryStock.instance.pieces.where((piece) => _selected.contains(piece.id));
    final pieces = InventoryStock.instance.pieces.take(40);
    return [
      TextField(
        controller: _customerQuery,
        decoration: _field(AppStrings.searchCustomer),
      ),
      if (_customer != null)
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text(_customer!.name, style: _text(size: 14, weight: FontWeight.w700)),
        )
      else
        for (final customer in matches.take(6))
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(customer.name, style: _text(size: 13, weight: FontWeight.w600)),
            subtitle: Text(customer.mobile, style: _text(size: 12, color: _muted)),
            onTap: () => setState(() {
              _customer = customer;
              _customerQuery.text = customer.name;
            }),
          ),
      const SizedBox(height: 8),
      TextField(controller: _returnDate, decoration: _field(AppStrings.returnDate)),
      const SizedBox(height: 8),
      TextField(controller: _description, decoration: _field(AppStrings.description)),
      const SizedBox(height: 12),
      Text('${AppStrings.selectedPieces}: ${_selected.length}', style: _text(size: 12, color: _muted)),
      const SizedBox(height: 8),
      for (final piece in {...chosen, ...pieces}) _pieceRow(piece),
    ];
  }

  List<Widget> _incoming() {
    return [
      OutlinedButton(
        onPressed: _pickOut,
        child: Text(_out == null ? AppStrings.chooseSampleOut : '${_out!.number} · ${_out!.customerName}'),
      ),
      const SizedBox(height: 12),
      if (_out == null)
        Text(AppStrings.noOpenSamples, style: _text(size: 13, color: _muted))
      else
        for (final item in _out!.items) _issueRow(item),
    ];
  }

  Future<void> _pickOut() async {
    if (_open.isEmpty) {
      _toast(AppStrings.noOpenSamples);
      return;
    }
    final picked = await showModalBottomSheet<SampleOutRecord>(
      context: context,
      backgroundColor: _surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(23))),
      builder: (context) {
        return ListView(
          children: [
            for (final record in _open)
              ListTile(
                title: Text('${record.number} · ${record.customerName}', style: _text(size: 14, weight: FontWeight.w600)),
                subtitle: Text('${record.items.length} ${AppStrings.pieces}', style: _text(size: 12, color: _muted)),
                onTap: () => Navigator.pop(context, record),
              ),
          ],
        );
      },
    );
    if (picked != null && mounted) {
      setState(() {
        _out = picked;
        _returned.clear();
      });
    }
  }

  Widget _pieceRow(InventoryPiece piece) {
    final on = _selected.contains(piece.id);
    return CheckboxListTile(
      contentPadding: EdgeInsets.zero,
      value: on,
      activeColor: const Color(0xFF8A682C),
      onChanged: (_) => setState(() {
        if (on) {
          _selected.remove(piece.id);
        } else {
          _selected.add(piece.id);
        }
      }),
      title: Text('${piece.id} · ${piece.name}', style: _text(size: 13, weight: FontWeight.w600)),
      subtitle: Text('${InventoryCatalog.grams(piece.milligrams)} g', style: _text(size: 12, color: _muted)),
    );
  }

  Widget _issueRow(Map<String, dynamic> item) {
    final code = '${item['ItemCode'] ?? ''}'.trim();
    final on = _returned.contains(code);
    return CheckboxListTile(
      contentPadding: EdgeInsets.zero,
      value: on,
      activeColor: const Color(0xFF8A682C),
      onChanged: (_) => setState(() {
        if (on) {
          _returned.remove(code);
        } else {
          _returned.add(code);
        }
      }),
      title: Text('$code · ${item['ProductName'] ?? ''}', style: _text(size: 13, weight: FontWeight.w600)),
      subtitle: Text('${item['GrossWt'] ?? ''} g', style: _text(size: 12, color: _muted)),
    );
  }

  Widget _footer() {
    final count = widget.incoming ? _returned.length : _selected.length;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
      decoration: const BoxDecoration(
        color: AppColors.white,
        border: Border(top: BorderSide(color: Color(0xFFE3DDD1))),
      ),
      child: Row(
        children: [
          Expanded(
            child: FilledButton.icon(
              onPressed: _saving ? null : _toggleScan,
              icon: Icon(_scanning ? Icons.pause : Icons.crop_free, size: 18),
              label: Text(_scanning ? AppStrings.pause : AppStrings.scan),
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFFEEE5D1),
                foregroundColor: const Color(0xFF85652C),
                minimumSize: const Size.fromHeight(52),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: FilledButton(
              onPressed: count == 0 || _saving ? null : _save,
              style: FilledButton.styleFrom(
                backgroundColor: _ink,
                foregroundColor: AppColors.white,
                minimumSize: const Size.fromHeight(52),
              ),
              child: Text(widget.incoming ? AppStrings.sampleIn : AppStrings.sampleOut),
            ),
          ),
        ],
      ),
    );
  }

  InputDecoration _field(String label) {
    return InputDecoration(
      labelText: label,
      filled: true,
      fillColor: AppColors.white,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
    );
  }
}

class _RecordList extends StatefulWidget {
  const _RecordList({required this.api, required this.incoming});

  final SampleApi api;
  final bool incoming;

  @override
  State<_RecordList> createState() => _RecordListState();
}

class _RecordListState extends State<_RecordList> {
  var _loading = true;
  String? _error;
  List<SampleOutRecord> _outs = const [];
  List<SampleInRecord> _ins = const [];

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    try {
      if (widget.incoming) {
        _ins = await widget.api.sampleIns();
      } else {
        _outs = await widget.api.sampleOuts();
      }
    } catch (error) {
      _error = error.toString();
    }
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: MediaQuery.sizeOf(context).height * 0.7,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(22, 16, 22, 16),
        child: _loading
            ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
            : _error != null
                ? Text(_error!, style: _text(size: 13, color: const Color(0xFF964A32)))
                : ListView(
                    children: [
                      Text(AppStrings.sampleList, style: _text(size: 18, weight: FontWeight.w700)),
                      const SizedBox(height: 10),
                      if (widget.incoming)
                        for (final record in _ins)
                          ListTile(
                            contentPadding: EdgeInsets.zero,
                            title: Text('${record.itemCode} · ${record.name}', style: _text(size: 13, weight: FontWeight.w600)),
                            subtitle: Text('${record.sampleOutNo} · ${record.customerName}', style: _text(size: 12, color: const Color(0xFF6D6B66))),
                          )
                      else
                        for (final record in _outs)
                          ListTile(
                            contentPadding: EdgeInsets.zero,
                            title: Text('${record.number} · ${record.customerName}', style: _text(size: 13, weight: FontWeight.w600)),
                            subtitle: Text('${record.items.length} ${AppStrings.pieces} · ${record.date}', style: _text(size: 12, color: const Color(0xFF6D6B66))),
                          ),
                    ],
                  ),
      ),
    );
  }
}

String _norm(String value) => value.trim().toUpperCase().replaceAll(' ', '').replaceAll('-', '');

TextStyle _text({
  required double size,
  FontWeight weight = FontWeight.w400,
  Color color = const Color(0xFF20201F),
}) {
  return TextStyle(
    fontFamily: 'Inter',
    fontFamilyFallback: const <String>[],
    fontSize: size,
    fontWeight: weight,
    color: color,
    decoration: TextDecoration.none,
  );
}
