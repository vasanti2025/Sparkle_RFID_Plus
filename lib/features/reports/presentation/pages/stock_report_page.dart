import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../../../core/constants/app_strings.dart';
import '../../../../core/di/injection.dart';
import '../../../../core/locale/feature_strings.dart';
import '../../../../core/session/app_session.dart';
import '../../../../core/theme/app_colors.dart';
import '../../data/stock_report_api.dart';
import '../../data/stock_report_parse.dart';
import '../report_chrome.dart';
import 'stock_report_batch_page.dart';
import 'stock_report_items_page.dart';

class StockReportPage extends StatefulWidget {
  const StockReportPage({super.key});

  @override
  State<StockReportPage> createState() => _StockReportPageState();
}

class _StockReportPageState extends State<StockReportPage> {
  final _api = StockReportApi();
  final _sessions = <ReportSession>[];
  final _visible = <ReportSession>[];
  final _branches = <({int id, String name})>[];
  final _tree = <ReportTreeNode>[];
  final _open = <String>{};

  var _batchMode = true;
  var _loadingSessions = false;
  var _loadingReport = false;
  var _exporting = false;
  var _sessionsReady = false;
  var _reportReady = false;
  var _exported = false;
  String? _error;
  String? _reportError;
  String? _consolidatedBody;
  DateTime _reportDate = DateTime.now();
  int? _filterBranchId;
  DateTime? _filterFrom;
  DateTime? _filterTo;
  Timer? _exportTimer;

  @override
  void initState() {
    super.initState();
    final today = DateTime.now();
    _reportDate = DateTime(today.year, today.month, today.day);
    Injection.settings.addListener(_onLanguage);
    unawaited(_loadSessions());
    unawaited(_loadConsolidated());
    unawaited(_loadBranches());
  }

  void _onLanguage() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    Injection.settings.removeListener(_onLanguage);
    _exportTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadBranches() async {
    final code = AppSession.clientCode.trim();
    if (code.isEmpty) return;
    try {
      final rows = await _api.branches(code);
      if (!mounted) return;
      setState(() {
        _branches
          ..clear()
          ..addAll(rows);
      });
    } catch (_) {}
  }

  Future<void> _loadSessions() async {
    final code = AppSession.clientCode.trim();
    if (code.isEmpty) {
      setState(() => _error = tx('reportSignIn', AppStrings.reportSignIn));
      return;
    }
    setState(() {
      _loadingSessions = _sessions.isEmpty;
      _error = null;
    });
    try {
      final body = await _api.sessions(code);
      final rows = body.trim().isEmpty ? const <ReportSession>[] : await readReport(body, parseSessions);
      if (!mounted) return;
      setState(() {
        _sessions
          ..clear()
          ..addAll(rows);
        _sessionsReady = true;
        _applyFilter();
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = tx('reportLoadFailed', AppStrings.reportLoadFailed));
    } finally {
      if (mounted) setState(() => _loadingSessions = false);
    }
  }

  Future<void> _loadConsolidated() async {
    final code = AppSession.clientCode.trim();
    if (code.isEmpty) {
      setState(() => _reportError = tx('reportSignIn', AppStrings.reportSignIn));
      return;
    }
    final date = reportIso(_reportDate);
    setState(() {
      _loadingReport = true;
      _reportError = null;
    });
    try {
      final body = await _api.consolidated(clientCode: code, reportDate: date);
      final tree = body.trim().isEmpty ? const <ReportTreeNode>[] : await readReport(body, parseReportTree);
      if (!mounted) return;
      setState(() {
        _consolidatedBody = body;
        _open.clear();
        _tree
          ..clear()
          ..addAll(tree);
        _reportReady = true;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _reportError = tx('reportLoadFailed', AppStrings.reportLoadFailed));
    } finally {
      if (mounted) setState(() => _loadingReport = false);
    }
  }

  void _applyFilter() {
    _visible
      ..clear()
      ..addAll(_sessions.where((session) {
        if (_filterBranchId != null && session.branchId != _filterBranchId) return false;
        if (_filterFrom == null && _filterTo == null) return true;
        final key = reportDateKey(session.startedOn);
        final from = _filterFrom == null ? '' : reportIso(_filterFrom!);
        final to = _filterTo == null ? '9999-12-31' : reportIso(_filterTo!);
        return key.compareTo(from) >= 0 && key.compareTo(to) <= 0;
      }));
  }

  Future<void> _openFilter() async {
    final result = await showModalBottomSheet<_FilterResult>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
      builder: (context) => _FilterSheet(
        branches: _branches,
        branchId: _filterBranchId,
        from: _filterFrom ?? _reportDate,
        to: _filterTo ?? _reportDate,
      ),
    );
    if (result == null || !mounted) return;
    setState(() {
      if (result.reset) {
        _filterBranchId = null;
        _filterFrom = null;
        _filterTo = null;
      } else {
        _filterBranchId = result.branchId;
        _filterFrom = result.from;
        _filterTo = result.to;
      }
      _applyFilter();
    });
  }

  Future<void> _openDate() async {
    final picked = await showModalBottomSheet<DateTime>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
      builder: (context) => _DateSheet(initial: _reportDate),
    );
    if (picked == null || !mounted) return;
    setState(() => _reportDate = DateTime(picked.year, picked.month, picked.day));
    await _loadConsolidated();
  }

  Future<void> _exportConsolidated({int branchId = 0, String branchName = ''}) async {
    final body = _consolidatedBody;
    if (body == null || body.trim().isEmpty || _exporting) return;
    setState(() => _exporting = true);
    try {
      final dir = await getApplicationDocumentsDirectory();
      final name = branchName.trim().isEmpty ? 'all' : branchName.replaceAll(RegExp(r'[^\w\-]+'), '_');
      final path = '${dir.path}/ConsolidatedReport_${reportIso(_reportDate)}_$name.csv';
      await compute(writeConsolidatedCsv, <String, Object?>{
        'body': body,
        'path': path,
        'branchId': branchId,
        'branchName': branchName,
      });
      await Share.shareXFiles(
        [XFile(path, mimeType: 'text/csv', name: path.split(Platform.pathSeparator).last)],
        subject: tx('stockVerification', AppStrings.stockVerification),
      );
      _showExported();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tx('reportLoadFailed', AppStrings.reportLoadFailed))));
      }
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  void _showExported() {
    _exportTimer?.cancel();
    setState(() => _exported = true);
    _exportTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) setState(() => _exported = false);
    });
  }

  void _switchMode(bool batch) {
    setState(() => _batchMode = batch);
    if (!batch && !_reportReady && !_loadingReport) unawaited(_loadConsolidated());
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: featureDirection,
      child: Scaffold(
      backgroundColor: AppColors.white,
      body: SafeArea(
        child: Stack(
          children: [
            Column(
              children: [
                ReportHeader(
                  title: tx('stockVerification', AppStrings.stockVerification),
                  onDownload: _batchMode || _consolidatedBody == null ? null : () => unawaited(_exportConsolidated()),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                  child: Row(
                    children: [
                      Expanded(child: _modeSwitch()),
                      const SizedBox(width: 8),
                      if (_batchMode)
                        ReportIconPlate(icon: Icons.filter_alt_outlined, onTap: () => unawaited(_openFilter()))
                      else
                        _dateChip(),
                    ],
                  ),
                ),
                if (_loadingSessions || _loadingReport || _exporting)
                  const Padding(
                    padding: EdgeInsets.only(top: 8),
                    child: LinearProgressIndicator(minHeight: 2, color: AppColors.goldText, backgroundColor: Colors.transparent),
                  ),
                Expanded(child: _batchMode ? _batchList() : _summaryList()),
              ],
            ),
            if (_exported)
              const Positioned(left: 16, right: 16, bottom: 16, child: ExportBanner()),
          ],
        ),
      ),
      ),
    );
  }

  Widget _modeSwitch() {
    return Container(
      height: 44,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(color: const Color(0xFFF3F0EA), borderRadius: BorderRadius.circular(14)),
      child: Row(
        children: [
          _mode(tx('batchWise', AppStrings.batchWise), _batchMode, () => _switchMode(true)),
          _mode(tx('consolidated', AppStrings.consolidated), !_batchMode, () => _switchMode(false)),
        ],
      ),
    );
  }

  Widget _mode(String label, bool selected, VoidCallback onTap) {
    return Expanded(
      child: Material(
        color: selected ? AppColors.charcoal : Colors.transparent,
        borderRadius: BorderRadius.circular(11),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(11),
          child: Center(
            child: Text(
              label,
              style: TextStyle(
                color: selected ? AppColors.white : AppColors.charcoal,
                fontWeight: FontWeight.w600,
                fontSize: 13,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _dateChip() {
    return Material(
      color: AppColors.white,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: () => unawaited(_openDate()),
        borderRadius: BorderRadius.circular(12),
        child: Container(
          height: 44,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(12), border: Border.all(color: reportLine)),
          child: Row(
            children: [
              Text(reportDayLabel(_reportDate), style: const TextStyle(color: AppColors.charcoal, fontSize: 12, fontWeight: FontWeight.w600)),
              const SizedBox(width: 4),
              const Icon(Icons.calendar_today_outlined, size: 14, color: AppColors.muted),
            ],
          ),
        ),
      ),
    );
  }

  Widget _batchList() {
    if (_error != null && _sessions.isEmpty) return _message(_error!, retry: _loadSessions);
    if (_loadingSessions && _sessions.isEmpty) return const Center(child: CircularProgressIndicator(color: AppColors.charcoal));
    if (_sessionsReady && _visible.isEmpty) return _message(tx('noBatches', AppStrings.noBatches), retry: _loadSessions);
    return LayoutBuilder(
      builder: (context, constraints) {
        final view = constraints.maxWidth;
        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: SizedBox(
            width: view + _batchExtraWidth,
            child: Column(
              children: [
                _batchHead(view),
                Expanded(
                  child: ListView.builder(
                    padding: const EdgeInsets.only(top: 4, bottom: 24),
                    itemCount: _visible.length,
                    addAutomaticKeepAlives: false,
                    itemBuilder: (context, index) {
                      final session = _visible[index];
                      return _BatchTile(
                        session: session,
                        viewWidth: view,
                        onTap: () {
                          final id = session.scanBatchId.trim();
                          if (id.isEmpty) return;
                          Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => StockReportBatchPage(scanBatchId: id)));
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  static const _batchExtraWidth = 160.0;

  Widget _batchHead(double view) {
    const style = TextStyle(color: AppColors.charcoal, fontSize: 12, fontWeight: FontWeight.w700);
    return ColoredBox(
      color: reportCanvas,
      child: SizedBox(
        height: 36,
        child: Row(
          children: [
            SizedBox(width: view, child: _visibleBatchHead(style)),
            SizedBox(width: 72, child: Text(tx('reportMatch', AppStrings.reportMatch), textAlign: TextAlign.right, style: style)),
            SizedBox(
              width: 88,
              child: Padding(
                padding: EdgeInsets.only(right: 16),
                child: Text(tx('unmatched', AppStrings.unmatched), textAlign: TextAlign.right, style: style),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _visibleBatchHead(TextStyle style) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          Expanded(flex: 4, child: Text(tx('branch', AppStrings.branch), style: style)),
          Expanded(flex: 5, child: Text(tx('startEnd', AppStrings.startEnd), style: style)),
          Expanded(flex: 3, child: Text(tx('totalQty', AppStrings.totalQty), textAlign: TextAlign.right, style: style)),
        ],
      ),
    );
  }

  Widget _summaryList() {
    if (_reportError != null && _tree.isEmpty) return _message(_reportError!, retry: _loadConsolidated);
    if (_loadingReport && _tree.isEmpty) return const Center(child: CircularProgressIndicator(color: AppColors.charcoal));
    if (_reportReady && _tree.isEmpty) return _message(tx('noReportForDate', AppStrings.noReportForDate), retry: _loadConsolidated);
    final lines = _treeLines();
    return Column(
      children: [
        _summaryHead(),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            itemCount: lines.length,
            itemBuilder: (context, index) {
              final line = lines[index];
              return _SummaryTile(
                line: line,
                open: _open.contains(line.key),
                onToggle: line.node.children.isEmpty
                    ? null
                    : () => setState(() {
                          if (!_open.add(line.key)) _open.remove(line.key);
                        }),
                onCount: (type) => _openItems(line, type),
              );
            },
          ),
        ),
      ],
    );
  }

  void _openItems(_TreeLine line, String type) {
    final body = _consolidatedBody;
    if (body == null || body.isEmpty) return;
    final title = line.node.name.isEmpty ? tx('branch', AppStrings.branch) : line.node.name;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => StockReportItemsPage(
          title: title,
          dateLabel: reportDayLabel(_reportDate),
          body: body,
          branchId: line.branchId,
          branchName: line.branchName,
          categoryId: line.categoryId,
          productId: line.productId,
          designId: line.designId,
          type: type,
        ),
      ),
    );
  }

  List<_TreeLine> _treeLines() {
    final lines = <_TreeLine>[];
    void add(
      ReportTreeNode node,
      int depth,
      int branchId,
      String branchName,
      int categoryId,
      int productId,
      int designId,
      String key,
    ) {
      lines.add(
        _TreeLine(
          key: key,
          node: node,
          depth: depth,
          branchId: branchId,
          branchName: branchName,
          categoryId: categoryId,
          productId: productId,
          designId: designId,
        ),
      );
      if (!_open.contains(key)) return;
      for (var index = 0; index < node.children.length; index++) {
        final child = node.children[index];
        final childKey = '$key/$index';
        if (depth == 0) {
          add(child, 1, node.id, node.name, child.id, 0, 0, childKey);
        } else if (depth == 1) {
          add(child, 2, branchId, branchName, categoryId, child.id, 0, childKey);
        } else if (depth == 2) {
          add(child, 3, branchId, branchName, categoryId, productId, child.id, childKey);
        }
      }
    }

    for (var index = 0; index < _tree.length; index++) {
      final branch = _tree[index];
      add(branch, 0, branch.id, branch.name, 0, 0, 0, 'b$index');
    }
    return lines;
  }

  Widget _summaryHead() {
    const style = TextStyle(color: AppColors.charcoal, fontSize: 12, fontWeight: FontWeight.w700);
    return ColoredBox(
      color: reportCanvas,
      child: Padding(
        padding: EdgeInsets.fromLTRB(16, 10, 16, 10),
        child: Row(
          children: [
            Expanded(flex: 4, child: Text(tx('branch', AppStrings.branch), style: style)),
            Expanded(flex: 2, child: Text(tx('reportTotal', AppStrings.reportTotal), textAlign: TextAlign.right, style: style)),
            Expanded(flex: 2, child: Text(tx('matched', AppStrings.matched), textAlign: TextAlign.right, style: style)),
            Expanded(flex: 3, child: Text(tx('unmatched', AppStrings.unmatched), textAlign: TextAlign.right, style: style)),
          ],
        ),
      ),
    );
  }

  Widget _message(String text, {required Future<void> Function() retry}) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(text, style: const TextStyle(color: AppColors.muted)),
          TextButton(onPressed: () => unawaited(retry()), child: Text(tx('tryAgain', AppStrings.tryAgain))),
        ],
      ),
    );
  }
}

class _BatchTile extends StatelessWidget {
  const _BatchTile({required this.session, required this.viewWidth, required this.onTap});

  final ReportSession session;
  final double viewWidth;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: reportLine))),
        child: Row(
          children: [
            SizedBox(width: viewWidth, child: _visible()),
            SizedBox(
              width: 72,
              child: Text('${session.matchQty}', textAlign: TextAlign.right, style: const TextStyle(color: reportMatchedText, fontWeight: FontWeight.w700, fontSize: 12)),
            ),
            SizedBox(
              width: 88,
              child: Padding(
                padding: const EdgeInsets.only(right: 16),
                child: Text('${session.unmatchQty}', textAlign: TextAlign.right, style: const TextStyle(color: reportUnmatchedText, fontWeight: FontWeight.w700, fontSize: 12)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _visible() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          Expanded(
            flex: 4,
            child: Text(
              session.branchName.isEmpty ? '—' : session.branchName,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: AppColors.charcoal, fontWeight: FontWeight.w700, fontSize: 12),
            ),
          ),
          Expanded(
            flex: 5,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Start: ${reportStamp(session.startedOn)}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: AppColors.muted, fontSize: 11)),
                Text('End: ${reportStamp(session.endedOn)}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: AppColors.muted, fontSize: 11)),
              ],
            ),
          ),
          Expanded(
            flex: 3,
            child: Text(
              '${session.totalQty}',
              textAlign: TextAlign.right,
              style: const TextStyle(color: AppColors.charcoal, fontWeight: FontWeight.w700, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }
}

class _TreeLine {
  const _TreeLine({
    required this.key,
    required this.node,
    required this.depth,
    required this.branchId,
    required this.branchName,
    required this.categoryId,
    required this.productId,
    required this.designId,
  });

  final String key;
  final ReportTreeNode node;
  final int depth;
  final int branchId;
  final String branchName;
  final int categoryId;
  final int productId;
  final int designId;
}

class _SummaryTile extends StatelessWidget {
  const _SummaryTile({required this.line, required this.open, required this.onToggle, required this.onCount});

  final _TreeLine line;
  final bool open;
  final VoidCallback? onToggle;
  final ValueChanged<String> onCount;

  @override
  Widget build(BuildContext context) {
    const number = TextStyle(color: AppColors.charcoal, fontWeight: FontWeight.w700, fontSize: 12);
    final node = line.node;
    const nameStyle = TextStyle(color: AppColors.charcoal, fontWeight: FontWeight.w700, fontSize: 12);
    return Container(
      decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: reportLine))),
      child: Row(
        children: [
          Expanded(
            flex: 4,
            child: InkWell(
              onTap: onToggle,
              child: Padding(
                padding: EdgeInsets.fromLTRB(line.depth * 14, 14, 0, 14),
                child: Row(
                  children: [
                    SizedBox(
                      width: 18,
                      child: Icon(
                        onToggle == null ? Icons.circle : (open ? Icons.keyboard_arrow_down : Icons.keyboard_arrow_right),
                        size: onToggle == null ? 6 : 18,
                        color: onToggle == null ? AppColors.muted : AppColors.charcoal,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        node.name.isEmpty ? '—' : node.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: nameStyle,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Expanded(flex: 2, child: _count('${node.total}', () => onCount('TOTAL'), number)),
          Expanded(flex: 2, child: _count('${node.matched}', () => onCount('MATCHED'), number)),
          Expanded(flex: 3, child: _count('${node.unmatched}', () => onCount('UNMATCHED'), number)),
        ],
      ),
    );
  }

  Widget _count(String text, VoidCallback onTap, TextStyle style) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 14),
        child: Text(text, textAlign: TextAlign.right, style: style),
      ),
    );
  }
}

class _FilterResult {
  const _FilterResult({required this.reset, this.branchId, this.from, this.to});

  final bool reset;
  final int? branchId;
  final DateTime? from;
  final DateTime? to;
}

class _FilterSheet extends StatefulWidget {
  const _FilterSheet({
    required this.branches,
    required this.branchId,
    required this.from,
    required this.to,
  });

  final List<({int id, String name})> branches;
  final int? branchId;
  final DateTime from;
  final DateTime to;

  @override
  State<_FilterSheet> createState() => _FilterSheetState();
}

class _FilterSheetState extends State<_FilterSheet> {
  late int? _branchId = widget.branchId;
  late DateTime _from = widget.from;
  late DateTime _to = widget.to;

  Future<void> _pick(bool from) async {
    final picked = await showModalBottomSheet<DateTime>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
      builder: (context) => _DateSheet(initial: from ? _from : _to),
    );
    if (picked == null) return;
    setState(() {
      if (from) {
        _from = picked;
        if (_to.isBefore(_from)) _to = picked;
      } else if (!picked.isBefore(_from)) {
        _to = picked;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(tx('filterReports', AppStrings.filterReports), style: const TextStyle(color: AppColors.charcoal, fontSize: 18, fontWeight: FontWeight.w700)),
                ),
                IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close, color: AppColors.charcoal)),
              ],
            ),
            const SizedBox(height: 8),
            Text(tx('branch', AppStrings.branch), style: TextStyle(color: AppColors.muted, fontSize: 12)),
            const SizedBox(height: 6),
            DropdownButtonFormField<int?>(
              initialValue: _branchId,
              isExpanded: true,
              decoration: _fieldDecoration(),
              items: [
                DropdownMenuItem<int?>(value: null, child: Text(tx('allBranches', AppStrings.allBranches))),
                for (final branch in widget.branches)
                  DropdownMenuItem<int?>(value: branch.id, child: Text(branch.name, overflow: TextOverflow.ellipsis)),
              ],
              onChanged: (value) => setState(() => _branchId = value),
            ),
            const SizedBox(height: 14),
            Text(tx('reportFromDate', AppStrings.reportFromDate), style: TextStyle(color: AppColors.muted, fontSize: 12)),
            const SizedBox(height: 6),
            _dateBox(reportDayLabel(_from), () => unawaited(_pick(true))),
            const SizedBox(height: 14),
            Text(tx('reportToDate', AppStrings.reportToDate), style: TextStyle(color: AppColors.muted, fontSize: 12)),
            const SizedBox(height: 6),
            _dateBox(reportDayLabel(_to), () => unawaited(_pick(false))),
            const SizedBox(height: 18),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context, const _FilterResult(reset: true)),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.charcoal,
                      side: const BorderSide(color: reportLine),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: Text(tx('reset', AppStrings.reset)),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton(
                    onPressed: () => Navigator.pop(
                      context,
                      _FilterResult(reset: false, branchId: _branchId, from: _from, to: _to),
                    ),
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.charcoal,
                      foregroundColor: AppColors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: Text(tx('applyFilters', AppStrings.applyFilters)),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _dateBox(String label, VoidCallback onTap) {
    return Material(
      color: AppColors.white,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          height: 48,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(12), border: Border.all(color: reportLine)),
          child: Row(
            children: [
              Expanded(child: Text(label, style: const TextStyle(color: AppColors.charcoal))),
              const Icon(Icons.calendar_today_outlined, size: 16, color: AppColors.muted),
            ],
          ),
        ),
      ),
    );
  }
}

InputDecoration _fieldDecoration() {
  return InputDecoration(
    filled: true,
    fillColor: AppColors.white,
    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: reportLine)),
    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: reportLine)),
  );
}

class _DateSheet extends StatefulWidget {
  const _DateSheet({required this.initial});

  final DateTime initial;

  @override
  State<_DateSheet> createState() => _DateSheetState();
}

class _DateSheetState extends State<_DateSheet> {
  late DateTime _visible = DateTime(widget.initial.year, widget.initial.month);
  late DateTime _selected = DateTime(widget.initial.year, widget.initial.month, widget.initial.day);

  @override
  Widget build(BuildContext context) {
    final today = DateTime.now();
    final first = DateTime(_visible.year, _visible.month);
    final days = DateTime(_visible.year, _visible.month + 1, 0).day;
    final lead = first.weekday % 7;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(tx('selectDate', AppStrings.selectDate), style: const TextStyle(color: AppColors.charcoal, fontSize: 18, fontWeight: FontWeight.w700)),
                ),
                IconButton(
                  onPressed: _visible.year <= 2020 && _visible.month == 1
                      ? null
                      : () => setState(() => _visible = DateTime(_visible.year, _visible.month - 1)),
                  icon: const Icon(Icons.chevron_left, color: AppColors.charcoal),
                ),
                PopupMenuButton<int>(
                  onSelected: (month) => setState(() => _visible = DateTime(_visible.year, month)),
                  itemBuilder: (context) => [
                    for (var month = 1; month <= 12; month++)
                      PopupMenuItem(value: month, child: Text(reportMonths[month - 1])),
                  ],
                  child: Row(
                    children: [
                      Text(
                        '${reportMonths[_visible.month - 1]} ${_visible.year}',
                        style: const TextStyle(color: AppColors.charcoal, fontWeight: FontWeight.w600),
                      ),
                      const Icon(Icons.expand_more, color: AppColors.charcoal),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: _visible.year > today.year || (_visible.year == today.year && _visible.month >= today.month)
                      ? null
                      : () => setState(() => _visible = DateTime(_visible.year, _visible.month + 1)),
                  icon: const Icon(Icons.chevron_right, color: AppColors.charcoal),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                for (final label in const ['S', 'M', 'T', 'W', 'T', 'F', 'S'])
                  Expanded(child: Center(child: Text(label, style: const TextStyle(color: AppColors.muted, fontSize: 12)))),
              ],
            ),
            const SizedBox(height: 8),
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: lead + days,
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 7, mainAxisSpacing: 4),
              itemBuilder: (context, index) {
                if (index < lead) return const SizedBox.shrink();
                final day = index - lead + 1;
                final date = DateTime(_visible.year, _visible.month, day);
                final future = date.isAfter(DateTime(today.year, today.month, today.day));
                final selected = date == _selected;
                return InkWell(
                  onTap: future ? null : () => setState(() => _selected = date),
                  customBorder: const CircleBorder(),
                  child: Center(
                    child: Container(
                      width: 34,
                      height: 34,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(color: selected ? AppColors.charcoal : Colors.transparent, shape: BoxShape.circle),
                      child: Text(
                        '$day',
                        style: TextStyle(
                          color: selected ? AppColors.white : (future ? const Color(0xFFC8C4BC) : AppColors.charcoal),
                          fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: Text(tx('cancel', AppStrings.cancel), style: TextStyle(color: AppColors.charcoal)),
                  ),
                ),
                Expanded(
                  child: FilledButton(
                    onPressed: () => Navigator.pop(context, _selected),
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.charcoal,
                      foregroundColor: AppColors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: Text(tx('applyDate', AppStrings.applyDate)),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
