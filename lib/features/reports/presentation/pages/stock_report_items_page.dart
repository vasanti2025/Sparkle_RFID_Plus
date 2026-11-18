import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../../../core/constants/app_strings.dart';
import '../../../../core/theme/app_colors.dart';
import '../../data/stock_report_parse.dart';
import '../report_chrome.dart';

class StockReportItemsPage extends StatefulWidget {
  const StockReportItemsPage({
    required this.title,
    required this.dateLabel,
    required this.body,
    required this.branchId,
    required this.branchName,
    super.key,
  });

  final String title;
  final String dateLabel;
  final String body;
  final int branchId;
  final String branchName;

  @override
  State<StockReportItemsPage> createState() => _StockReportItemsPageState();
}

class _StockReportItemsPageState extends State<StockReportItemsPage> {
  final _search = TextEditingController();
  final _rows = <ItemRow>[];
  List<int> _indexes = const [];
  Timer? _debounce;
  Timer? _exportTimer;
  var _loading = true;
  var _searching = false;
  var _exporting = false;
  var _exported = false;
  String? _error;
  int _query = 0;

  @override
  void initState() {
    super.initState();
    _search.addListener(_onSearch);
    unawaited(_load());
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _exportTimer?.cancel();
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final args = <String, Object?>{
        'body': widget.body,
        'branchId': widget.branchId,
        'branchName': widget.branchName,
        'type': 'TOTAL',
      };
      final rows = widget.body.length <= 1800000 ? extractBranchItems(args) : await compute(extractBranchItems, args);
      if (!mounted) return;
      setState(() {
        _rows
          ..clear()
          ..addAll(rows);
        _indexes = List<int>.generate(_rows.length, (index) => index);
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = AppStrings.reportLoadFailed;
      });
    }
  }

  void _onSearch() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () async {
      final query = _search.text.trim().toLowerCase();
      final token = ++_query;
      if (mounted) setState(() => _searching = query.isNotEmpty);
      final found = <int>[];
      if (query.isEmpty) {
        found.addAll(List<int>.generate(_rows.length, (index) => index));
      } else {
        for (var index = 0; index < _rows.length; index++) {
          final row = _rows[index];
          final text = '${row.item} ${row.rfid} ${row.category} ${row.product} ${row.net} ${row.status}'.toLowerCase();
          if (text.contains(query)) found.add(index);
          if (index % 4000 == 0) await Future<void>.delayed(Duration.zero);
        }
      }
      if (!mounted || token != _query) return;
      setState(() {
        _indexes = found;
        _searching = false;
      });
    });
  }

  Future<void> _export() async {
    if (_exporting || widget.body.trim().isEmpty) return;
    setState(() => _exporting = true);
    try {
      final dir = await getApplicationDocumentsDirectory();
      final safe = widget.branchName.replaceAll(RegExp(r'[^\w\-]+'), '_');
      final path = '${dir.path}/BranchReport_$safe.csv';
      await compute(writeConsolidatedCsv, <String, Object?>{
        'body': widget.body,
        'path': path,
        'branchId': widget.branchId,
        'branchName': widget.branchName,
      });
      await Share.shareXFiles(
        [XFile(path, mimeType: 'text/csv', name: 'BranchReport_$safe.csv')],
        subject: widget.title,
      );
      if (!mounted) return;
      _exportTimer?.cancel();
      setState(() => _exported = true);
      _exportTimer = Timer(const Duration(seconds: 3), () {
        if (mounted) setState(() => _exported = false);
      });
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text(AppStrings.reportLoadFailed)));
      }
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.white,
      body: SafeArea(
        child: Stack(
          children: [
            Column(
              children: [
                ReportHeader(title: widget.title, subtitle: widget.dateLabel, onDownload: () => unawaited(_export())),
                if (_loading || _exporting)
                  const LinearProgressIndicator(minHeight: 2, color: AppColors.goldText, backgroundColor: Colors.transparent),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                  child: Row(
                    children: [
                      const Expanded(
                        child: Text(AppStrings.totalItems, style: TextStyle(color: AppColors.charcoal, fontSize: 16, fontWeight: FontWeight.w700)),
                      ),
                      Text(
                        '${_indexes.length}',
                        style: const TextStyle(color: AppColors.charcoal, fontSize: 20, fontWeight: FontWeight.w700),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: ReportSearch(controller: _search, searching: _searching),
                ),
                const SizedBox(height: 8),
                Expanded(child: _table()),
              ],
            ),
            if (_exported) const Positioned(left: 16, right: 16, bottom: 16, child: ExportBanner()),
          ],
        ),
      ),
    );
  }

  Widget _table() {
    if (_loading) return const SizedBox.shrink();
    if (_error != null) return Center(child: Text(_error!, style: const TextStyle(color: AppColors.muted)));
    return LayoutBuilder(
      builder: (context, constraints) {
        final view = constraints.maxWidth;
        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: SizedBox(
            width: view + _extraWidth,
            child: Column(
              children: [
                _ItemHead(view: view),
                Expanded(child: _list(view)),
              ],
            ),
          ),
        );
      },
    );
  }

  static const _extraWidth = 192.0;

  Widget _list(double view) {
    if (_indexes.isEmpty) {
      return const Center(child: Text(AppStrings.noReportForDate, style: TextStyle(color: AppColors.muted)));
    }
    return ListView.builder(
      itemCount: _indexes.length,
      itemExtent: 44,
      addAutomaticKeepAlives: false,
      padding: const EdgeInsets.only(bottom: 16),
      itemBuilder: (context, index) {
        final row = _rows[_indexes[index]];
        return DecoratedBox(
          decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: reportLine))),
          child: Row(
            children: [
              SizedBox(
                width: view,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  child: Row(
                    children: [
                      _ReportCell(row.item, flex: 3),
                      _ReportCell(row.rfid, flex: 3),
                      _ReportCell(row.category, flex: 3),
                      _ReportCell(row.product, flex: 3),
                      _ReportCell(row.gross, flex: 2),
                    ],
                  ),
                ),
              ),
              _FixedCell(row.net),
              _FixedCell(row.status, last: true),
            ],
          ),
        );
      },
    );
  }
}

class _ReportCell extends StatelessWidget {
  const _ReportCell(this.text, {required this.flex});

  final String text;
  final int flex;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      flex: flex,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Text(
          text.isEmpty ? '—' : text,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(color: AppColors.charcoal, fontSize: 11),
        ),
      ),
    );
  }
}

class _FixedCell extends StatelessWidget {
  const _FixedCell(this.text, {this.last = false});

  final String text;
  final bool last;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 96,
      child: Padding(
        padding: EdgeInsets.only(right: last ? 16 : 8),
        child: Text(
          text.isEmpty ? '—' : text,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.right,
          style: const TextStyle(color: AppColors.charcoal, fontSize: 11),
        ),
      ),
    );
  }
}

class _HeadCell extends StatelessWidget {
  const _HeadCell(this.text, {required this.flex});

  final String text;
  final int flex;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      flex: flex,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Text(text, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: AppColors.muted, fontSize: 11, fontWeight: FontWeight.w600)),
      ),
    );
  }
}

class _ItemHead extends StatelessWidget {
  const _ItemHead({required this.view});

  final double view;

  @override
  Widget build(BuildContext context) {
    const style = TextStyle(color: AppColors.muted, fontSize: 11, fontWeight: FontWeight.w600);
    return ColoredBox(
      color: reportCanvas,
      child: SizedBox(
        height: 36,
        child: Row(
          children: [
            SizedBox(
              width: view,
              child: const Padding(
                padding: EdgeInsets.symmetric(horizontal: 10),
                child: Row(
                  children: [
                    _HeadCell('Item', flex: 3),
                    _HeadCell('RFID', flex: 3),
                    _HeadCell(AppStrings.category, flex: 3),
                    _HeadCell(AppStrings.product, flex: 3),
                    _HeadCell(AppStrings.grossWeightShort, flex: 2),
                  ],
                ),
              ),
            ),
            const SizedBox(
              width: 96,
              child: Padding(
                padding: EdgeInsets.only(right: 8),
                child: Text(AppStrings.netWeightShort, textAlign: TextAlign.right, style: style),
              ),
            ),
            const SizedBox(
              width: 96,
              child: Padding(
                padding: EdgeInsets.only(right: 16),
                child: Text(AppStrings.itemStatus, textAlign: TextAlign.right, style: style),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
