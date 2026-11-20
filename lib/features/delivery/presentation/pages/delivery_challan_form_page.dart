import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/di/injection.dart';
import '../../../../core/rfid/rfid_service.dart';
import '../../../delivery/data/delivery_challan_api.dart';
import '../../../../core/session/app_session.dart';
import '../../../../core/utils/result.dart';
import '../../../inventory/data/inventory_stock.dart';
import '../../../quotation/domain/entities/customer_record.dart';
import '../../../quotation/domain/entities/stock_item.dart';
import '../../data/page_layout.dart';
import '../challan_theme.dart';

class DeliveryChallanFormPage extends StatefulWidget {
  const DeliveryChallanFormPage({
    super.key,
    this.challanId = 0,
    this.challanNo = '',
    this.customerName = '',
    this.editing = false,
    this.fields = const {},
    this.lines = const [],
  });

  final int challanId;
  final String challanNo;
  final String customerName;
  final bool editing;
  final Map<String, String> fields;
  final List<Map<String, String>> lines;

  @override
  State<DeliveryChallanFormPage> createState() => _DeliveryChallanFormPageState();
}

class _DeliveryChallanFormPageState extends State<DeliveryChallanFormPage> {
  final _api = PageLayoutApi();
  final _customer = TextEditingController();
  final _lookup = TextEditingController();
  final _tableScroll = ScrollController();
  final _tray = RfidTrayScan();
  CustomerRecord? _customerRecord;
  final _values = <String, TextEditingController>{};
  final _checks = <String, bool>{};
  final _choices = <String, List<String>>{};
  final _lines = <Map<String, String>>[];
  CustomerIndex _customers = CustomerIndex(const []);
  var _loading = true;
  String? _error;
  var _gst = true;
  var _scanning = false;
  var _saving = false;
  var _seenTags = 0;
  var _power = 30;
  List<PageControl> _controls = const [];

  @override
  void initState() {
    super.initState();
    _customer.text = widget.customerName;
    _lines.addAll(widget.lines.map(Map<String, String>.from));
    _load();
  }

  @override
  void dispose() {
    _customer.dispose();
    _lookup.dispose();
    _tray.cancel();
    _tableScroll.dispose();
    for (final controller in _values.values) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final modules = await _api.load();
      final choices = await _choiceLists(modules);
      for (final module in modules) {
        for (final control in module.controls) {
          if (_isCheck(control)) {
            _checks.putIfAbsent(control.key, () => _gst);
          } else if (!control.isAction) {
            final controller = _values.putIfAbsent(control.key, TextEditingController.new);
            final preset = widget.fields[control.key];
            if (preset != null && controller.text.isEmpty) controller.text = preset;
          }
        }
      }
      if (Injection.ready && AppSession.clientCode.isNotEmpty) {
        final customers = await Injection.quotations.loadCustomers(AppSession.clientCode);
        if (customers case Success(:final data)) {
          _customers = data;
          if (widget.customerName.isNotEmpty) {
            for (final customer in data.records) {
              if (customer.name == widget.customerName) {
                _customerRecord = customer;
                break;
              }
            }
          }
        }
        await Injection.quotations.warmLabeledStock(AppSession.clientCode, () {});
      }
      if (!mounted) return;
      setState(() {
        _controls = [for (final module in modules) ...module.controls];
        _choices
          ..clear()
          ..addAll(choices);
        _loading = false;
        final gst = _firstWhere(_isGst);
        if (gst != null) _gst = _checks[gst.key] ?? true;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = '$error'.replaceFirst('Bad state: ', '').replaceFirst('StateError: ', '');
        _loading = false;
      });
    }
  }

  List<PageControl> get _columns {
    final columns = _controls.where(_isColumn).toList();
    const preferred = ['item name', 'item code', 'gross', 'net'];
    columns.sort((a, b) {
      final ai = _rank(a, preferred);
      final bi = _rank(b, preferred);
      if (ai != bi) return ai.compareTo(bi);
      return a.priority.compareTo(b.priority);
    });
    return columns;
  }

  List<PageControl> get _dialogFields => _controls.where(_isDialogField).toList();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      resizeToAvoidBottomInset: false,
      appBar: AppBar(
        elevation: 0,
        backgroundColor: challanHeader,
        foregroundColor: Colors.white,
        title: Text(
          widget.editing ? 'Edit Delivery Challan' : 'Create Delivery Challan',
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 16),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: PopupMenuButton<int>(
              tooltip: 'Reader power',
              onSelected: (value) async {
                setState(() => _power = value);
                await RfidService.instance.setPower(value);
              },
              itemBuilder: (context) => [
                for (final power in const [5, 10, 20, 30])
                  PopupMenuItem(value: power, child: Text('$power')),
              ],
              child: Container(
                width: 36,
                height: 36,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  '$_power',
                  style: const TextStyle(color: Color(0xFFD32940), fontWeight: FontWeight.w800),
                ),
              ),
            ),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFF5231A7)))
          : Column(
              children: [
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                    child: Text(_error!, style: const TextStyle(color: Color(0xFF9B3A3A))),
                  ),
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
                    children: [
                      _customerField(),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(child: _lookupField()),
                          const SizedBox(width: 8),
                          Expanded(child: _fieldsButton()),
                        ],
                      ),
                      const SizedBox(height: 12),
                      _table(),
                    ],
                  ),
                ),
                _totals(),
                _bottomBar(),
              ],
            ),
    );
  }

  Widget _customerField() {
    return TextField(
      controller: _customer,
      readOnly: true,
      onTap: _pickCustomer,
      decoration: _box('Customer name').copyWith(
        prefixIcon: const Icon(Icons.search, size: 20),
        suffixIcon: _customer.text.isEmpty
            ? IconButton(onPressed: _openProfile, icon: const Icon(Icons.person_add_alt_1))
            : IconButton(
                onPressed: () => setState(() => _customer.clear()),
                icon: const Icon(Icons.close),
              ),
      ),
    );
  }

  Widget _lookupField() {
    return TextField(
      controller: _lookup,
      textInputAction: TextInputAction.done,
      onSubmitted: (_) => _addLookup(),
      decoration: _box('RFID / Itemcode').copyWith(
        suffixIcon: IconButton(
          onPressed: _scanOne,
          icon: const Icon(Icons.qr_code_scanner, size: 18),
        ),
      ),
    );
  }

  Widget _fieldsButton() {
    return OutlinedButton.icon(
      style: OutlinedButton.styleFrom(
        foregroundColor: challanInk,
        side: const BorderSide(color: Color(0xFFD32940)),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
      onPressed: _openFields,
      icon: const Icon(Icons.tune, size: 18),
      label: const Text('Challan Fields', overflow: TextOverflow.ellipsis),
    );
  }

  Widget _table() {
    final columns = _columns;
    final headers = [
      'S.No',
      if (columns.isEmpty) ...['Item Name', 'Item Code', 'Gross Wt', 'Net Wt'] else ...columns.map((control) => control.label),
      'Action',
    ];
    const columnWidth = 96.0;
    Widget cell(String value, {bool header = false, double width = columnWidth}) {
      return SizedBox(
        width: width,
        child: Text(
          value.isEmpty ? '—' : value,
          textAlign: TextAlign.center,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: header ? Colors.white : challanInk,
          ),
        ),
      );
    }

    final values = columns.isEmpty
        ? const ['name', 'code', 'gross', 'net']
        : [for (final column in columns) column.key];
    final width = headers.length * columnWidth;

    return Column(
      children: [
        SingleChildScrollView(
        controller: _tableScroll,
        scrollDirection: Axis.horizontal,
        child: SizedBox(
          width: width,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ColoredBox(
                color: challanHeader,
                child: SizedBox(
                  height: 34,
                  width: width,
                  child: Row(children: [for (final header in headers) cell(header, header: true)]),
                ),
              ),
              if (_lines.isEmpty)
                const SizedBox(
                  height: 72,
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Padding(
                      padding: EdgeInsets.symmetric(horizontal: 16),
                      child: Text('Scan or enter an item', style: TextStyle(color: Colors.grey)),
                    ),
                  ),
                )
              else
                for (var index = 0; index < _lines.length; index++)
                  Container(
                    width: width,
                    color: index.isEven ? const Color(0xFFF4F4F4) : Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Row(
                      children: [
                        cell('${index + 1}'),
                        for (final key in values) cell(_lines[index][key] ?? ''),
                        SizedBox(
                          width: columnWidth,
                          child: IconButton(
                            padding: EdgeInsets.zero,
                            visualDensity: VisualDensity.compact,
                            constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                            onPressed: () => setState(() => _lines.removeAt(index)),
                            icon: const Icon(Icons.delete, color: Colors.red, size: 18),
                          ),
                        ),
                      ],
                    ),
                  ),
            ],
          ),
        ),
        ),
        const SizedBox(height: 6),
        _TableScrollTrack(controller: _tableScroll),
      ],
    );
  }

  Widget _totals() {
    final gross = _sum('gross');
    final net = _sum('net');
    return Column(
      children: [
        Container(
          color: challanHeader,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            children: [
              const Expanded(child: Text('Total', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700))),
              Expanded(child: Text('${_lines.length}', textAlign: TextAlign.center, style: const TextStyle(color: Colors.white))),
              Expanded(child: Text(gross.toStringAsFixed(3), textAlign: TextAlign.center, style: const TextStyle(color: Colors.white))),
              Expanded(child: Text(net.toStringAsFixed(3), textAlign: TextAlign.center, style: const TextStyle(color: Colors.white))),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
          child: Row(
            children: [
              Checkbox(
                value: _gst,
                activeColor: challanHeader,
                checkColor: Colors.white,
                side: const BorderSide(color: challanHeader, width: 1.6),
                onChanged: (value) => setState(() => _gst = value ?? false),
              ),
              const Text('GST 3.00%', style: TextStyle(fontWeight: FontWeight.w600)),
              const Spacer(),
              Text('Total Amount:  ₹${_amount().toStringAsFixed(2)}', style: const TextStyle(fontWeight: FontWeight.w700)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _bottomBar() {
    return Material(
      elevation: 8,
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 64,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _nav(Icons.save_outlined, widget.editing ? 'Update' : 'Save', _save),
              _nav(Icons.list, 'List', () => Navigator.pop(context)),
              _scanButton(),
              _nav(Icons.qr_code_2, _scanning ? 'Stop $_seenTags' : 'Gscan', _toggleGscan),
              _nav(Icons.refresh, 'Reset', _reset),
            ],
          ),
        ),
      ),
    );
  }

  Widget _nav(IconData icon, String label, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      child: SizedBox(
        width: 58,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 20, color: challanInk),
            const SizedBox(height: 2),
            Text(label, style: const TextStyle(fontSize: 11)),
          ],
        ),
      ),
    );
  }

  Widget _scanButton() {
    return InkWell(
      onTap: _scanOne,
      customBorder: const CircleBorder(),
      child: Container(
        width: 58,
        height: 58,
        decoration: const BoxDecoration(shape: BoxShape.circle, color: challanHeader),
        child: const Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.qr_code_scanner, color: Colors.white, size: 22),
            Text('Scan', style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700)),
          ],
        ),
      ),
    );
  }

  Future<void> _pickCustomer() async {
    final selected = await showModalBottomSheet<CustomerRecord>(
      context: context,
      isScrollControlled: true,
      builder: (context) => _CustomerSearchSheet(index: _customers, onCreate: _openProfile),
    );
    if (selected == null || !mounted) return;
    setState(() {
      _customerRecord = selected;
      _customer.text = selected.name;
    });
  }

  Future<void> _openProfile() async {
    final created = await showDialog<CustomerRecord>(
      context: context,
      builder: (context) => const _CustomerProfileDialog(),
    );
    if (created == null || !mounted) return;
    setState(() {
      _customerRecord = created;
      _customer.text = created.name;
      _customers = _customers.add(created);
    });
  }

  Future<void> _openFields() async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => _FieldsDialog(
        fields: _dialogFields,
        values: _values,
        choices: _choices,
      ),
    );
    if (saved == true && mounted) setState(() {});
  }

  Future<void> _scanOne() async {
    if (_scanning) {
      _scanning = false;
      _tray.cancel();
    }
    final typed = _lookup.text.trim();
    if (typed.isNotEmpty) {
      await _addCodes([typed]);
      return;
    }
    await RfidService.instance.setPower(_power);
    final read = await RfidService.instance.readOneEpc();
    if (!mounted) return;
    if (read.epc == null || read.epc!.isEmpty) {
      _toast(read.error ?? 'No tag found');
      return;
    }
    await _addCodes([read.epc!]);
  }

  Future<void> _toggleGscan() async {
    if (_scanning) {
      _scanning = false;
      _tray.cancel();
      if (mounted) setState(() {});
      return;
    }
    setState(() {
      _scanning = true;
      _seenTags = 0;
    });
    await RfidService.instance.setPower(_power);
    while (mounted && _scanning) {
      final read = await _tray.collect(
        fast: true,
        onCount: (count) {
          if (mounted) setState(() => _seenTags = count);
        },
      );
      if (!mounted || !_scanning) break;
      if (read.error != null && read.codes.isEmpty) {
        _toast(read.error!);
        break;
      }
      if (read.codes.isNotEmpty) await _addCodes(read.codes, tags: read.tags);
    }
    if (mounted) setState(() => _scanning = false);
  }

  void _addLookup() => _addCodes([_lookup.text.trim()]);

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _addCodes(List<String> codes, {List<List<String>> tags = const []}) async {
    final usable = [for (final code in codes) code.trim()].where((code) => code.isNotEmpty).toList();
    if (usable.isEmpty || !Injection.ready || AppSession.clientCode.isEmpty) return;
    List<StockItem> matches;
    if (tags.isEmpty && usable.length == 1) {
      matches = Injection.quotations.labeledStockMatching(AppSession.clientCode, usable.first);
      if (matches.isEmpty) {
        final result = await Injection.quotations.searchStock(clientCode: AppSession.clientCode, query: usable.first);
        matches = result is Success<List<StockItem>> ? result.data : const [];
      }
    } else {
      matches = await Injection.quotations.stockForTags(AppSession.clientCode, usable, tags: tags);
    }
    if (!mounted) return;
    var added = 0;
    setState(() {
      for (final item in matches) {
        final identity = item.identity;
        final already = _lines.any((line) {
          final code = line['itemCode'] ?? line['code'] ?? '';
          final rfid = line['lineRfid'] ?? line['rfid'] ?? '';
          return code == identity || (item.rfid.isNotEmpty && rfid == item.rfid);
        });
        if (already) continue;
        _lines.add(_lineFrom(item, usable.first));
        added++;
      }
      _lookup.clear();
    });
    if (added == 0) {
      _toast(matches.isEmpty ? 'Item not found in stock' : 'Already on this challan');
    }
  }

  Map<String, String> _lineFrom(StockItem item, String code) {
    final line = <String, String>{
      'name': item.name,
      'code': item.itemCode.isNotEmpty ? item.itemCode : code,
      'gross': item.gross,
      'net': item.net,
      'amount': item.extras['totalitemamount'] ?? item.extras['amount'] ?? '',
      'itemCode': item.itemCode,
      'lineRfid': item.rfid,
    };
    for (final column in _columns) {
      line[column.key] = _valueFor(column, item, code);
    }
    return line;
  }

  void _reset() {
    setState(() {
      _lines.clear();
      _lookup.clear();
      _customer.clear();
      _customerRecord = null;
      _gst = true;
      for (final controller in _values.values) {
        controller.clear();
      }
    });
  }

  Future<void> _save() async {
    if (_saving) return;
    if (_customer.text.trim().isEmpty) {
      _toast('Choose a customer');
      return;
    }
    if (_lines.isEmpty) {
      _toast('Add at least one item');
      return;
    }
    setState(() => _saving = true);
    try {
      final message = await DeliveryChallanApi().save(
        editing: widget.editing,
        challanId: widget.challanId,
        customerId: _customerRecord?.id ?? 0,
        customerName: _customer.text.trim(),
        gstOn: _gst,
        date: _values['date']?.text.trim() ?? '',
        branchName: _values['branch']?.text.trim() ?? '',
        salesman: _values['salesman']?.text.trim() ?? '',
        challanNo: widget.challanNo,
        items: _lines,
      );
      if (!mounted) return;
      _toast(message);
      Navigator.pop(context, true);
    } catch (error) {
      _toast('$error'.replaceFirst('Bad state: ', '').replaceFirst('StateError: ', ''));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  double _sum(String token) {
    var total = 0.0;
    for (final line in _lines) {
      for (final entry in line.entries) {
        if (!entry.key.toLowerCase().contains(token)) continue;
        total += double.tryParse(entry.value) ?? 0;
        break;
      }
    }
    return total;
  }

  double _amount() {
    var total = 0.0;
    for (final line in _lines) {
      final raw = line['amount'] ?? line['totalAmount'] ?? '';
      total += double.tryParse(raw) ?? 0;
    }
    if (!_gst) return total;
    return total + (total * 0.03);
  }

  PageControl? _firstWhere(bool Function(PageControl control) test) {
    for (final control in _controls) {
      if (test(control)) return control;
    }
    return null;
  }
}

bool _isCheck(PageControl control) {
  return control.kind.contains('check') || control.kind.contains('bool') || control.kind.contains('switch');
}

bool _isGst(PageControl control) {
  final name = '${control.key} ${control.label}'.toLowerCase();
  return name.contains('gst');
}

bool _isCustomer(PageControl control) => '${control.key} ${control.label}'.toLowerCase().contains('customer');

bool _isLookup(PageControl control) {
  if (control.readOnly) return false;
  final name = '${control.key} ${control.label}'.toLowerCase();
  return name.contains('rfid') || name.contains('itemcode') || name.contains('item code');
}

bool _isFieldsButton(PageControl control) {
  return '${control.key} ${control.label}'.toLowerCase().contains('challan field');
}

bool _isTotal(PageControl control) {
  final name = '${control.key} ${control.label}'.toLowerCase();
  return name.contains('total');
}

bool _isColumn(PageControl control) {
  if (control.place == 'list') return false;
  if (control.isAction || _isCheck(control) || _isGst(control) || _isCustomer(control)) return false;
  if (_isLookup(control) || _isFieldsButton(control) || _isTotal(control)) return false;
  return control.readOnly;
}

bool _isDialogField(PageControl control) {
  if (control.place == 'list') return false;
  if (control.isAction || control.readOnly || _isCheck(control)) return false;
  if (_isCustomer(control) || _isLookup(control) || _isFieldsButton(control) || _isGst(control)) return false;
  return true;
}

int _rank(PageControl control, List<String> preferred) {
  final name = '${control.key} ${control.label}'.toLowerCase();
  for (var index = 0; index < preferred.length; index++) {
    if (name.contains(preferred[index])) return index;
  }
  return preferred.length + control.priority;
}

String _valueFor(PageControl control, StockItem? item, String code) {
  final name = '${control.key} ${control.label}'.toLowerCase();
  if (item == null) {
    if (name.contains('code') || name.contains('rfid')) return code;
    return '';
  }
  if (name.contains('name')) return item.name;
  if (name.contains('code')) return item.itemCode;
  if (name.contains('gross')) return item.gross;
  if (name.contains('net')) return item.net;
  if (name.contains('rfid')) return item.rfid;
  for (final entry in item.extras.entries) {
    if (name.replaceAll(RegExp('[^a-z0-9]'), '').contains(entry.key)) return entry.value;
  }
  return '';
}

InputDecoration _box(String hint) {
  return InputDecoration(
    hintText: hint,
    isDense: true,
    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
  );
}

class _TableScrollTrack extends StatefulWidget {
  const _TableScrollTrack({required this.controller});

  final ScrollController controller;

  @override
  State<_TableScrollTrack> createState() => _TableScrollTrackState();
}

class _TableScrollTrackState extends State<_TableScrollTrack> {
  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_tick);
    WidgetsBinding.instance.addPostFrameCallback((_) => _tick());
  }

  @override
  void dispose() {
    widget.controller.removeListener(_tick);
    super.dispose();
  }

  void _tick() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    if (!controller.hasClients || !controller.position.hasContentDimensions) {
      return const SizedBox(height: 6);
    }
    final position = controller.position;
    final max = position.maxScrollExtent;
    if (max <= 0) return const SizedBox(height: 6);
    final viewport = position.viewportDimension;
    final thumb = (viewport / (viewport + max) * viewport).clamp(28.0, viewport);
    final left = (viewport - thumb) * (position.pixels / max);
    return SizedBox(
      height: 6,
      child: Stack(
        children: [
          Positioned(
            left: left,
            top: 1,
            width: thumb,
            height: 4,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: const Color(0xFF8A8A8A),
                borderRadius: BorderRadius.circular(4),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _FieldsDialog extends StatefulWidget {
  const _FieldsDialog({required this.fields, required this.values, required this.choices});

  final List<PageControl> fields;
  final Map<String, TextEditingController> values;
  final Map<String, List<String>> choices;

  @override
  State<_FieldsDialog> createState() => _FieldsDialogState();
}

class _FieldsDialogState extends State<_FieldsDialog> {
  @override
  Widget build(BuildContext context) {
    final fields = widget.fields.isEmpty ? const <PageControl>[] : widget.fields;
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 28),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.72),
        child: Column(
          children: [
            Container(
              height: 52,
              padding: const EdgeInsets.symmetric(horizontal: 14),
              decoration: const BoxDecoration(
                color: Color(0xFF3A3A3A),
                borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
              ),
              child: const Row(
                children: [
                  Icon(Icons.edit_note, color: Colors.white),
                  SizedBox(width: 8),
                  Text('Delivery Challan Fields', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  for (final field in fields) ...[
                    _dialogField(field),
                    const SizedBox(height: 10),
                  ],
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Row(
                children: [
                  Expanded(child: OutlinedButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel'))),
                  const SizedBox(width: 12),
                  Expanded(
                    child: DecoratedBox(
                      decoration: BoxDecoration(gradient: challanGradient, borderRadius: BorderRadius.circular(8)),
                      child: TextButton(
                        onPressed: () => Navigator.pop(context, true),
                        child: const Text('Confirm', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
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

  Widget _dialogField(PageControl field) {
    final controller = widget.values[field.key];
    if (controller == null) return const SizedBox.shrink();
    final options = widget.choices[field.key] ?? field.options;
    if (field.kind.contains('date') || field.label.toLowerCase().contains('date')) {
      return _labeled(
        field.label,
        TextField(
          controller: controller,
          readOnly: true,
          onTap: () async {
            final now = DateTime.now();
            final picked = await showDatePicker(
              context: context,
              initialDate: now,
              firstDate: DateTime(now.year - 5),
              lastDate: DateTime(now.year + 5),
            );
            if (picked == null) return;
            final day = picked.day.toString().padLeft(2, '0');
            final month = picked.month.toString().padLeft(2, '0');
            setState(() => controller.text = '$day-$month-${picked.year}');
          },
          decoration: _box(field.placeholder.isEmpty ? field.label : field.placeholder).copyWith(
            suffixIcon: const Icon(Icons.calendar_today, size: 18),
          ),
        ),
      );
    }
    if (options.isNotEmpty || field.kind.contains('drop') || field.label.toLowerCase().contains('salesman') || field.label.toLowerCase().contains('branch')) {
      return _labeled(
        field.label,
        TextField(
          controller: controller,
          readOnly: true,
          onTap: () async {
            final picked = await showModalBottomSheet<String>(
              context: context,
              builder: (context) => _OptionList(title: field.label, options: options),
            );
            if (picked == null) return;
            setState(() => controller.text = picked);
          },
          decoration: _box(controller.text.isEmpty ? 'Select ${field.label}' : controller.text).copyWith(
            suffixIcon: const Icon(Icons.arrow_drop_down),
          ),
        ),
      );
    }
    return _labeled(
      field.label,
      TextField(
        controller: controller,
        keyboardType: field.kind.contains('number') || field.label.contains('%')
            ? const TextInputType.numberWithOptions(decimal: true)
            : TextInputType.text,
        inputFormatters: field.label.contains('%') ? [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))] : null,
        decoration: _box(field.placeholder.isEmpty ? field.label : field.placeholder),
      ),
    );
  }

  Widget _labeled(String label, Widget child) {
    return Row(
      children: [
        SizedBox(width: 110, child: Text(label, style: const TextStyle(fontWeight: FontWeight.w600))),
        Expanded(child: child),
      ],
    );
  }
}

class _CustomerProfileDialog extends StatefulWidget {
  const _CustomerProfileDialog();

  @override
  State<_CustomerProfileDialog> createState() => _CustomerProfileDialogState();
}

class _CustomerProfileDialogState extends State<_CustomerProfileDialog> {
  final _name = TextEditingController();
  final _mobile = TextEditingController();
  final _email = TextEditingController();
  final _pan = TextEditingController();
  final _gst = TextEditingController();
  final _street = TextEditingController();
  final _city = TextEditingController();
  String _country = 'India';
  String _state = 'Maharashtra';

  @override
  void dispose() {
    _name.dispose();
    _mobile.dispose();
    _email.dispose();
    _pan.dispose();
    _gst.dispose();
    _street.dispose();
    _city.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.78),
        child: Column(
          children: [
            Container(
              height: 52,
              padding: const EdgeInsets.symmetric(horizontal: 14),
              decoration: const BoxDecoration(
                color: Color(0xFF3A3A3A),
                borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
              ),
              child: const Row(
                children: [
                  Icon(Icons.person_add_alt_1, color: Colors.white, size: 18),
                  SizedBox(width: 8),
                  Text('Customer Profile', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  _gap(_name, 'Name'),
                  _gap(_mobile, 'Mobile'),
                  _gap(_email, 'Email'),
                  _gap(_pan, 'PAN Number'),
                  _gap(_gst, 'GST Number'),
                  _gap(_street, 'Street Address'),
                  Row(
                    children: [
                      Expanded(child: _menu(_country, const ['India'], (value) => setState(() => _country = value))),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _menu(
                          _state,
                          const ['Maharashtra', 'Gujarat', 'Rajasthan', 'Delhi', 'Karnataka'],
                          (value) => setState(() => _state = value),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  _gap(_city, 'City'),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Row(
                children: [
                  Expanded(child: OutlinedButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel'))),
                  const SizedBox(width: 12),
                  Expanded(
                    child: DecoratedBox(
                      decoration: BoxDecoration(gradient: challanGradient, borderRadius: BorderRadius.circular(8)),
                      child: TextButton(
                        onPressed: () async {
                          final name = _name.text.trim();
                          if (name.isEmpty || !Injection.ready || AppSession.clientCode.isEmpty) return;
                          try {
                            final result = await Injection.quotations.addCustomer(
                              clientCode: AppSession.clientCode,
                              name: name,
                              mobile: _mobile.text.trim(),
                              email: _email.text.trim(),
                              pan: _pan.text.trim(),
                              gst: _gst.text.trim(),
                              street: _street.text.trim(),
                              city: _city.text.trim(),
                              state: _state,
                              country: _country,
                            );
                            if (!context.mounted) return;
                            switch (result) {
                              case Success(:final data):
                                Navigator.pop(context, data);
                              case Error(:final failure):
                                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(failure.message)));
                            }
                          } catch (error) {
                            if (!context.mounted) return;
                            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$error')));
                          }
                        },
                        child: const Text('Save', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
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

  Widget _gap(TextEditingController controller, String hint) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: TextField(controller: controller, decoration: _box(hint).copyWith(fillColor: const Color(0xFFF6F6F6), filled: true)),
    );
  }

  Widget _menu(String value, List<String> options, ValueChanged<String> onChanged) {
    return DropdownButtonFormField<String>(
      isExpanded: true,
      initialValue: value,
      items: [
        for (final option in options)
          DropdownMenuItem(value: option, child: Text(option, overflow: TextOverflow.ellipsis)),
      ],
      onChanged: (next) {
        if (next != null) onChanged(next);
      },
      decoration: _box(''),
    );
  }
}

class _CustomerSearchSheet extends StatelessWidget {
  const _CustomerSearchSheet({required this.index, required this.onCreate});

  final CustomerIndex index;
  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: MediaQuery.sizeOf(context).height * 0.6,
      child: Column(
        children: [
          ListTile(
            title: const Text('Customers', style: TextStyle(fontWeight: FontWeight.w700)),
            trailing: TextButton(onPressed: () {
              Navigator.pop(context);
              onCreate();
            }, child: const Text('New')),
          ),
          Expanded(
            child: ListView(
              children: [
                for (final customer in index.records.take(40))
                  ListTile(
                    title: Text(customer.name),
                    subtitle: Text(customer.mobile),
                    onTap: () => Navigator.pop(context, customer),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _OptionList extends StatelessWidget {
  const _OptionList({required this.title, required this.options});

  final String title;
  final List<String> options;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: ListView(
        children: [
          ListTile(title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700))),
          if (options.isEmpty)
            const ListTile(title: Text('No options loaded'))
          else
            for (final option in options)
              ListTile(title: Text(option), onTap: () => Navigator.pop(context, option)),
        ],
      ),
    );
  }
}

Future<Map<String, List<String>>> _choiceLists(List<PageModule> modules) async {
  final lists = <String, List<String>>{};
  final needsLookup = modules.expand((module) => module.controls).where((control) => control.kind.contains('drop') || _isDialogField(control)).toList();
  if (needsLookup.isEmpty) return lists;
  await InventoryStock.instance.load();
  final stock = InventoryStock.instance;
  for (final control in needsLookup) {
    if (control.options.isNotEmpty) {
      lists[control.key] = control.options;
      continue;
    }
    final name = '${control.key} ${control.label}'.toLowerCase();
    lists[control.key] = switch (name) {
      _ when name.contains('branch') => stock.branches,
      _ when name.contains('sales') => stock.counters,
      _ => const <String>[],
    };
  }
  return lists;
}
