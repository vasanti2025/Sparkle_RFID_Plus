import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../../../core/constants/app_strings.dart';
import '../../../../core/session/app_session.dart';
import '../../../../core/theme/app_colors.dart';
import '../../data/stock_report_api.dart';
import '../../data/stock_report_parse.dart';
import '../report_chrome.dart';

class StockReportBatchPage extends StatefulWidget {
  const StockReportBatchPage({required this.scanBatchId, super.key});

  final String scanBatchId;

  @override
  State<StockReportBatchPage> createState() => _StockReportBatchPageState();
}

class _StockReportBatchPageState extends State<StockReportBatchPage> {
  final _api = StockReportApi();
  final _search = TextEditingController();
  final _matched = <BatchRow>[];
  final _unmatched = <BatchRow>[];
  List<int> _matchedIndex = const [];
  List<int> _unmatchedIndex = const [];
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
    final code = AppSession.clientCode.trim();
    if (code.isEmpty) {
      setState(() {
        _loading = false;
        _error = AppStrings.reportSignIn;
      });
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final body = await _api.batchDetails(clientCode: code, scanBatchId: widget.scanBatchId);
      final details = body.trim().isEmpty
          ? const BatchDetails(matched: [], unmatched: [])
          : await readReport(body, parseBatchDetails);
      if (!mounted) return;
      setState(() {
        _matched
          ..clear()
          ..addAll(details.matched);
        _unmatched
          ..clear()
          ..addAll(details.unmatched);
        _matchedIndex = List<int>.generate(_matched.length, (index) => index);
        _unmatchedIndex = List<int>.generate(_unmatched.length, (index) => index);
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
      final matched = await _indexes(_matched, query, (row) => '${row.item} ${row.product} ${row.branch} ${row.category} ${row.rfid}');
      final unmatched = await _indexes(_unmatched, query, (row) => '${row.item} ${row.product} ${row.branch} ${row.category} ${row.rfid}');
      if (!mounted || token != _query) return;
      setState(() {
        _matchedIndex = matched;
        _unmatchedIndex = unmatched;
        _searching = false;
      });
    });
  }

  Future<List<int>> _indexes(List<BatchRow> rows, String query, String Function(BatchRow row) text) async {
    if (query.isEmpty) return List<int>.generate(rows.length, (index) => index);
    final found = <int>[];
    for (var index = 0; index < rows.length; index++) {
      if (text(rows[index]).toLowerCase().contains(query)) found.add(index);
      if (index % 4000 == 0) await Future<void>.delayed(Duration.zero);
    }
    return found;
  }

  Future<void> _export() async {
    if (_exporting || (_matched.isEmpty && _unmatched.isEmpty)) return;
    setState(() => _exporting = true);
    try {
      final dir = await getApplicationDocumentsDirectory();
      final safe = widget.scanBatchId.replaceAll(RegExp(r'[^\w\-]+'), '_');
      final file = File('${dir.path}/BatchReport_$safe.csv');
      final sink = file.openWrite();
      sink.writeln('Status,Item Code,Product,Branch,Category,RFID');
      var count = 0;
      Future<void> write(String status, List<BatchRow> rows) async {
        for (final row in rows) {
          sink.writeln([
            status,
            csvCell(row.item),
            csvCell(row.product),
            csvCell(row.branch),
            csvCell(row.category),
            csvCell(row.rfid),
          ].join(','));
          count++;
          if (count % 2500 == 0) await Future<void>.delayed(Duration.zero);
        }
      }

      await write('Matched', _matched);
      await write('Unmatched', _unmatched);
      await sink.flush();
      await sink.close();
      await Share.shareXFiles(
        [XFile(file.path, mimeType: 'text/csv', name: 'BatchReport_$safe.csv')],
        subject: AppStrings.batchDetails,
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
                ReportHeader(
                  title: AppStrings.batchDetails,
                  onDownload: _matched.isEmpty && _unmatched.isEmpty ? null : () => unawaited(_export()),
                ),
                if (_loading || _exporting)
                  const LinearProgressIndicator(minHeight: 2, color: AppColors.goldText, backgroundColor: Colors.transparent),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
                  child: ReportSearch(controller: _search, searching: _searching),
                ),
                Expanded(child: _body()),
              ],
            ),
            if (_exported) const Positioned(left: 16, right: 16, bottom: 16, child: ExportBanner()),
          ],
        ),
      ),
    );
  }

  Widget _body() {
    if (_loading) return const SizedBox.shrink();
    if (_error != null) return Center(child: Text(_error!, style: const TextStyle(color: AppColors.muted)));
    return CustomScrollView(
      slivers: [
        _section(AppStrings.matchedItems, _matchedIndex.length, reportMatchedFill, reportMatchedText),
        if (_matchedIndex.isEmpty)
          const SliverToBoxAdapter(child: _EmptyNote(AppStrings.noMatchedItems))
        else ...[
          const SliverToBoxAdapter(child: _BatchHead()),
          _rows(_matched, _matchedIndex),
        ],
        _section(AppStrings.unmatchedItems, _unmatchedIndex.length, reportUnmatchedFill, reportUnmatchedText),
        if (_unmatchedIndex.isEmpty)
          const SliverToBoxAdapter(child: _EmptyNote(AppStrings.noUnmatchedItems))
        else ...[
          const SliverToBoxAdapter(child: _BatchHead()),
          _rows(_unmatched, _unmatchedIndex),
        ],
        const SliverToBoxAdapter(child: SizedBox(height: 24)),
      ],
    );
  }

  Widget _section(String label, int count, Color fill, Color text) {
    return SliverToBoxAdapter(
      child: Container(
        margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(color: fill, borderRadius: BorderRadius.circular(10)),
        child: Row(
          children: [
            Expanded(child: Text(label, style: TextStyle(color: text, fontWeight: FontWeight.w700))),
            Text('$count', style: TextStyle(color: text, fontWeight: FontWeight.w700)),
          ],
        ),
      ),
    );
  }

  Widget _rows(List<BatchRow> rows, List<int> indexes) {
    return SliverFixedExtentList.builder(
      itemExtent: 42,
      itemCount: indexes.length,
      addAutomaticKeepAlives: false,
      itemBuilder: (context, index) {
        final row = rows[indexes[index]];
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Container(
            height: 42,
            decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: reportLine))),
            child: Row(
              children: [
                _cell(row.item, 3),
                _cell(row.product, 3),
                _cell(row.branch, 3),
                _cell(row.category, 2),
                _cell(row.rfid, 3),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _cell(String text, int flex) {
    return Expanded(
      flex: flex,
      child: Text(
        text.isEmpty ? '—' : text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(color: AppColors.charcoal, fontSize: 11),
      ),
    );
  }
}

class _BatchHead extends StatelessWidget {
  const _BatchHead();

  @override
  Widget build(BuildContext context) {
    const style = TextStyle(color: AppColors.charcoal, fontSize: 11, fontWeight: FontWeight.w700);
    return const ColoredBox(
      color: reportCanvas,
      child: Padding(
        padding: EdgeInsets.fromLTRB(16, 8, 16, 8),
        child: SizedBox(
        height: 28,
        child: Row(
          children: [
            Expanded(flex: 3, child: Text(AppStrings.itemCode, style: style)),
            Expanded(flex: 3, child: Text(AppStrings.product, style: style)),
            Expanded(flex: 3, child: Text(AppStrings.branch, style: style)),
            Expanded(flex: 2, child: Text(AppStrings.category, style: style)),
            Expanded(flex: 3, child: Text('RFID', style: style)),
          ],
        ),
        ),
      ),
    );
  }
}

class _EmptyNote extends StatelessWidget {
  const _EmptyNote(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 18),
      child: Center(child: Text(text, style: const TextStyle(color: AppColors.muted, fontSize: 13))),
    );
  }
}
