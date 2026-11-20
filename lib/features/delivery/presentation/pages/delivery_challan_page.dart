import 'package:flutter/material.dart';

import '../../data/delivery_challan_api.dart';
import '../../data/page_layout.dart';
import '../challan_theme.dart';
import 'delivery_challan_form_page.dart';

class DeliveryChallanPage extends StatefulWidget {
  const DeliveryChallanPage({super.key});

  @override
  State<DeliveryChallanPage> createState() => _DeliveryChallanPageState();
}

class _DeliveryChallanPageState extends State<DeliveryChallanPage> {
  final _search = TextEditingController();
  var _loading = true;
  String? _error;
  List<ChallanRecord> _rows = const [];
  List<PageControl> _listColumns = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final rows = await DeliveryChallanApi().load();
      final modules = await PageLayoutApi().load();
      final columns = [
        for (final module in modules)
          for (final control in module.controls)
            if (control.place == 'list' && !control.hidden) control,
      ]..sort((a, b) => a.priority.compareTo(b.priority));
      if (!mounted) return;
      setState(() {
        _rows = rows;
        _listColumns = columns;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = '$error'.replaceFirst('Exception: ', '');
        _loading = false;
      });
    }
  }

  List<ChallanRecord> get _shown {
    final needle = _search.text.trim().toLowerCase();
    if (needle.isEmpty) return _rows;
    return _rows
        .where(
          (row) =>
              row.number.toLowerCase().contains(needle) ||
              row.customer.toLowerCase().contains(needle),
        )
        .toList();
  }

  Future<void> _openForm({ChallanRecord? row}) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => DeliveryChallanFormPage(
          challanId: row?.id ?? 0,
          challanNo: row?.number ?? '',
          customerName: row?.customer ?? '',
          editing: row != null,
          fields: row?.fields ?? const {},
          lines: row?.items ?? const [],
        ),
      ),
    );
    if (mounted) _load();
  }

  @override
  Widget build(BuildContext context) {
    final rows = _shown;
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        elevation: 0,
        backgroundColor: challanHeader,
        foregroundColor: Colors.white,
        title: const Text(
          'Delivery Challan List',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
        ),
        actions: [
          IconButton(onPressed: () => _openForm(), icon: const Icon(Icons.add)),
          IconButton(onPressed: _load, icon: const Icon(Icons.refresh)),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
            child: TextField(
              controller: _search,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                hintText: 'Search Challan No or Customer Name...',
                prefixIcon: const Icon(Icons.search, size: 20),
                isDense: true,
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
              ),
            ),
          ),
          const Divider(height: 1),
          if (_loading) const LinearProgressIndicator(minHeight: 2, color: Color(0xFF5231A7)),
          Expanded(
            child: _error != null && rows.isEmpty
                ? _center(_error!, onRetry: _load)
                : rows.isEmpty
                ? _center(_loading ? 'Loading challans' : 'No challans found')
                : ListView.builder(
                    itemCount: rows.length + 1,
                    itemBuilder: (context, index) {
                      if (index == 0) return _ListHeader(_listColumns);
                      final row = rows[index - 1];
                      return _ListLine(
                        serial: index,
                        columns: _listColumns,
                        row: row,
                        onEdit: () => _openForm(row: row),
                        onPrint: () {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('Print challan ${row.number}')),
                          );
                        },
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _ListHeader extends StatelessWidget {
  const _ListHeader(this.columns);

  final List<PageControl> columns;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: challanHeader,
      child: SizedBox(
        height: 36,
        child: Row(
          children: [
            for (final column in columns) _HeadCell(column.label, flex: _listFlex(column)),
          ],
        ),
      ),
    );
  }
}

class _ListLine extends StatelessWidget {
  const _ListLine({
    required this.serial,
    required this.columns,
    required this.row,
    required this.onEdit,
    required this.onPrint,
  });

  final int serial;
  final List<PageControl> columns;
  final ChallanRecord row;
  final VoidCallback onEdit;
  final VoidCallback onPrint;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Color(0xFFE6E6E6))),
      ),
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          for (final column in columns)
            _isActionColumn(column)
                ? Expanded(
                    flex: _listFlex(column),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        _rowIcon(Icons.edit, onEdit),
                        _rowIcon(Icons.print, onPrint),
                      ],
                    ),
                  )
                : _BodyCell(
                    _listValue(column, row, serial),
                    flex: _listFlex(column),
                    align: column.key == 'customerName' ? TextAlign.left : TextAlign.center,
                  ),
        ],
      ),
    );
  }
}

class _HeadCell extends StatelessWidget {
  const _HeadCell(this.label, {required this.flex});

  final String label;
  final int flex;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      flex: flex,
      child: Text(
        label,
        textAlign: TextAlign.center,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700),
      ),
    );
  }
}

class _BodyCell extends StatelessWidget {
  const _BodyCell(this.label, {required this.flex, this.align = TextAlign.center});

  final String label;
  final int flex;
  final TextAlign align;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      flex: flex,
      child: Text(
        label.isEmpty ? '—' : label,
        textAlign: align,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: 12, color: challanInk),
      ),
    );
  }
}

int _listFlex(PageControl column) {
  if (column.key == 'serial') return 2;
  if (column.key == 'customerName') return 5;
  if (_isActionColumn(column)) return 3;
  return 3;
}

bool _isActionColumn(PageControl column) {
  return column.isAction || column.key == 'actions' || column.label.toLowerCase() == 'actions';
}

String _listValue(PageControl column, ChallanRecord row, int serial) {
  final name = '${column.key} ${column.label}'.toLowerCase();
  if (column.key == 'serial' || name.contains('s.no') || name.contains('sno')) return '$serial';
  if (name.contains('customer')) return row.customer;
  if (name.contains('date')) return row.date;
  if (name.contains('challan')) return row.number;
  return row.fields[column.key] ?? '';
}

Widget _rowIcon(IconData icon, VoidCallback onTap) {
  return SizedBox(
    width: 28,
    height: 28,
    child: IconButton(
      padding: EdgeInsets.zero,
      visualDensity: VisualDensity.compact,
      style: IconButton.styleFrom(
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        padding: EdgeInsets.zero,
        minimumSize: const Size(28, 28),
        fixedSize: const Size(28, 28),
      ),
      onPressed: onTap,
      icon: Icon(icon, size: 16),
    ),
  );
}

Widget _center(String message, {VoidCallback? onRetry}) {
  return Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(message, textAlign: TextAlign.center),
          if (onRetry != null) ...[
            const SizedBox(height: 12),
            TextButton(onPressed: onRetry, child: const Text('Try again')),
          ],
        ],
      ),
    ),
  );
}

