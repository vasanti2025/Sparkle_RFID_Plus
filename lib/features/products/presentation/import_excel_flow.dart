import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/di/injection.dart';
import '../../../core/locale/feature_strings.dart';
import '../../../core/theme/app_colors.dart';
import '../data/product_sheet_import.dart';

class ImportExcelFlow {
  ImportExcelFlow._();

  static Future<void> start(BuildContext context) async {
    final picked = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => _ChooseFileDialog(onPick: () => Navigator.pop(context, true), onClose: () => Navigator.pop(context, false)),
    );
    if (picked != true || !context.mounted) return;
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['xlsx', 'xls'],
      withData: false,
    );
    if (!context.mounted) return;
    if (result == null || result.files.isEmpty) return start(context);
    final path = result.files.first.path;
    if (path == null || path.isEmpty || !await File(path).exists()) {
      if (context.mounted) _toast(context, tx('couldNotReadFile', 'Could not read the file'));
      return;
    }
    if (!context.mounted) return;
    final table = await _busy(context, tx('importingExcelData', 'Importing Excel Data'), () async {
      final bytes = await File(path).readAsBytes();
      return parseExcelTableAsync(bytes);
    });
    if (!context.mounted || table == null) return;
    if (table.headers.isEmpty) {
      _toast(context, tx('noHeadersInExcel', 'The file has no headers'));
      return start(context);
    }
    await _mapAndImport(context, table);
  }

  static Future<void> startSheet(BuildContext context) async {
    final raw = Injection.settings.sheetUrl;
    final id = sheetIdFrom(raw);
    if (id == null) {
      _toast(context, tx('pleaseAddValidSheetUrl', 'Add a valid Sheet URL / ID in Settings'));
      return;
    }
    final url = sheetCsvUrl(id);
    final table = await _busy(context, tx('fetchingSheetHeaders', 'Fetching sheet headers…'), () async {
      final response = await http.get(Uri.parse(url)).timeout(const Duration(minutes: 3));
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw const HttpException('sheet');
      }
      final text = utf8.decode(response.bodyBytes, allowMalformed: true);
      return parseCsvTable(text);
    });
    if (!context.mounted) return;
    if (table == null || table.headers.isEmpty) {
      _toast(context, tx('failedToFetchSheetHeaders', 'Could not fetch the sheet headers'));
      return;
    }
    await _mapAndImport(context, table);
  }

  static Future<void> _mapAndImport(BuildContext context, SheetTable table) async {
    final mapping = await showDialog<Map<String, String>>(
      context: context,
      barrierDismissible: false,
      builder: (context) => _MappingDialog(columns: table.headers),
    );
    if (mapping == null || !context.mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => _ImportProgressPage(table: table, mapping: mapping)),
    );
  }

  static Future<T?> _busy<T>(BuildContext context, String message, Future<T> Function() work) async {
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) => PopScope(
        canPop: false,
        child: AlertDialog(
          backgroundColor: AppColors.white,
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(color: AppColors.charcoal),
              const SizedBox(height: 16),
              Text(message, textAlign: TextAlign.center, style: const TextStyle(color: AppColors.charcoal, fontWeight: FontWeight.w700)),
            ],
          ),
        ),
      ),
    );
    try {
      await Future<void>.delayed(Duration.zero);
      final value = await work();
      if (context.mounted) Navigator.of(context, rootNavigator: true).pop();
      return value;
    } catch (_) {
      if (context.mounted) Navigator.of(context, rootNavigator: true).pop();
      return null;
    }
  }

  static void _toast(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }
}

class _ChooseFileDialog extends StatelessWidget {
  const _ChooseFileDialog({required this.onPick, required this.onClose});

  final VoidCallback onPick;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: featureDirection,
      child: AlertDialog(
        backgroundColor: AppColors.white,
        title: Text(tx('chooseExcelFile', 'Choose an Excel file'), style: const TextStyle(color: AppColors.charcoal, fontWeight: FontWeight.w700)),
        content: Text(tx('importExcelHint', 'Choose a file, map the columns, then import.'), style: const TextStyle(color: AppColors.muted)),
        actions: [
          TextButton(onPressed: onClose, child: Text(tx('cancel', 'Cancel'))),
          FilledButton(
            onPressed: onPick,
            style: FilledButton.styleFrom(backgroundColor: AppColors.charcoal),
            child: Text(tx('importExcel', 'Import Excel')),
          ),
        ],
      ),
    );
  }
}

class _MappingDialog extends StatefulWidget {
  const _MappingDialog({required this.columns});

  final List<String> columns;

  @override
  State<_MappingDialog> createState() => _MappingDialogState();
}

class _MappingDialogState extends State<_MappingDialog> {
  final _mapping = <String, String>{};
  final _name = TextEditingController();
  var _templates = <String, Map<String, String>>{};
  String? _selected;
  String? _status;
  var _error = false;
  var _syncing = false;

  @override
  void initState() {
    super.initState();
    _name.addListener(_onName);
    unawaited(_load());
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('import_mapping_templates');
    final decoded = raw == null || raw.isEmpty ? null : jsonDecode(raw);
    final templates = <String, Map<String, String>>{};
    if (decoded is Map) {
      for (final entry in decoded.entries) {
        final value = entry.value;
        if (value is! Map) continue;
        templates[entry.key.toString()] = value.map((key, item) => MapEntry(key.toString(), item.toString()));
      }
    }
    if (!mounted) return;
    setState(() => _templates = templates);
    final last = prefs.getString('last_import_template');
    if (last != null) _apply(last, announce: false);
    if (_mapping.isEmpty) _fillStandardColumns();
  }

  void _fillStandardColumns() {
    final lookup = <String, String>{};
    for (final column in widget.columns) {
      lookup[_columnKey(column)] = column;
    }
    final used = <String>{};
    final next = <String, String>{};
    for (final key in importFieldKeys) {
      final label = importFieldLabels[key] ?? key;
      final column = lookup[_columnKey(label)] ?? lookup[_columnKey(key)];
      if (column == null || used.contains(column)) continue;
      used.add(column);
      next[key] = column;
    }
    if (next.isEmpty || !mounted) return;
    setState(() => _mapping.addAll(next));
  }

  String _columnKey(String value) => value.trim().toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');

  @override
  void dispose() {
    _name.removeListener(_onName);
    _name.dispose();
    super.dispose();
  }

  void _onName() {
    if (!mounted || _syncing) return;
    if (_name.text.trim() == (_selected ?? '')) return;
    setState(() {
      _selected = null;
      _mapping.clear();
      _status = null;
    });
  }

  void _apply(String name, {bool announce = true}) {
    final saved = _templates[name];
    if (saved == null) return;
    final lookup = <String, String>{};
    for (final column in widget.columns) {
      lookup[column] = column;
      lookup[column.trim().toLowerCase()] = column;
    }
    final used = <String>{};
    final next = <String, String>{};
    for (final entry in saved.entries) {
      if (!importFieldKeys.contains(entry.key)) continue;
      final column = lookup[entry.value] ?? lookup[entry.value.trim().toLowerCase()];
      if (column == null || used.contains(column)) continue;
      used.add(column);
      next[entry.key] = column;
    }
    _syncing = true;
    setState(() {
      _mapping
        ..clear()
        ..addAll(next);
      _selected = next.isEmpty ? null : name;
      if (next.isNotEmpty) _name.text = name;
      if (announce) {
        _error = next.isEmpty;
        _status = next.isEmpty ? tx('noMatchingColumnsInFile', 'No matching columns in this file') : tx('templateApplied', 'Template applied');
      }
    });
    _syncing = false;
  }

  bool _saved() {
    final name = _name.text.trim();
    final saved = _templates[name];
    if (name.isEmpty || saved == null) return false;
    final current = {for (final entry in _mapping.entries) if (entry.value.trim().isNotEmpty) entry.key: entry.value};
    if (current.length != saved.length) return false;
    for (final entry in current.entries) {
      if (saved[entry.key] != entry.value) return false;
    }
    return true;
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    if (name.isEmpty) {
      setState(() {
        _error = true;
        _status = tx('enterTemplateNameFirst', 'Enter a template name first');
      });
      return;
    }
    if (_mapping.isEmpty) {
      setState(() {
        _error = true;
        _status = tx('mapColumnsToSaveTemplate', 'Map columns before saving a template');
      });
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    _templates[name] = Map<String, String>.from(_mapping);
    await prefs.setString('import_mapping_templates', jsonEncode(_templates));
    await prefs.setString('last_import_template', name);
    if (!mounted) return;
    _syncing = true;
    setState(() {
      _selected = name;
      _name.text = name;
      _error = false;
      _status = tx('templateSaved', 'Template saved');
    });
    _syncing = false;
  }

  void _import() {
    if (_mapping.isEmpty) {
      setState(() {
        _error = true;
        _status = tx('mapColumnsToSaveTemplate', 'Map columns before saving a template');
      });
      return;
    }
    if (!_saved()) {
      setState(() {
        _error = true;
        _status = tx('saveTemplateBeforeImport', 'Save the template before import');
      });
      return;
    }
    Navigator.pop(context, Map<String, String>.from(_mapping));
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final used = _mapping.values.where((value) => value.isNotEmpty).toSet();
    return Directionality(
      textDirection: featureDirection,
      child: Dialog(
        backgroundColor: AppColors.white,
        insetPadding: const EdgeInsets.fromLTRB(12, 24, 12, 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: SizedBox(
          width: media.size.width,
          height: media.size.height * 0.86,
          child: Column(
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                decoration: const BoxDecoration(
                  color: AppColors.charcoal,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(tx('tableView', 'Table view'), style: const TextStyle(color: AppColors.white, fontSize: 18, fontWeight: FontWeight.w700)),
                    Text(tx('selectTableViewFields', 'Match the main fields to the sheet columns'), style: const TextStyle(color: AppColors.champagne, fontSize: 12)),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
                child: Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        initialValue: _selected != null && _templates.containsKey(_selected) ? _selected : null,
                        isExpanded: true,
                        decoration: InputDecoration(hintText: tx('selectMappingTemplateHint', 'Select a template'), isDense: true),
                        items: [
                          for (final name in _templates.keys) DropdownMenuItem(value: name, child: Text(name, overflow: TextOverflow.ellipsis)),
                        ],
                        onChanged: (name) {
                          if (name != null) _apply(name);
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: _name,
                        decoration: InputDecoration(hintText: tx('enterTemplateName', 'Template name'), isDense: true),
                      ),
                    ),
                    const SizedBox(width: 8),
                    FilledButton(
                      onPressed: _save,
                      style: FilledButton.styleFrom(backgroundColor: AppColors.charcoal),
                      child: Text(tx('save', 'Save')),
                    ),
                  ],
                ),
              ),
              if (_status != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 6, 12, 0),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(_status!, style: TextStyle(color: _error ? const Color(0xFFB91C1C) : const Color(0xFF15803D), fontSize: 12)),
                  ),
                ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
                child: Row(
                  children: [
                    Expanded(child: Text(tx('mainFields', 'Main fields'), style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.charcoal))),
                    Expanded(child: Text(tx('selectSheetFields', 'Select sheet fields'), style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.charcoal))),
                  ],
                ),
              ),
              Expanded(
                child: ListView.builder(
                  itemCount: importFieldKeys.length,
                  itemExtent: 52,
                  itemBuilder: (context, index) {
                    final key = importFieldKeys[index];
                    final selected = _mapping[key] ?? '';
                    final options = widget.columns.where((column) => column == selected || !used.contains(column)).toList();
                    return Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: Row(
                        children: [
                          Expanded(child: Text(tx('field_$key', importFieldLabels[key] ?? key), maxLines: 1, overflow: TextOverflow.ellipsis)),
                          const SizedBox(width: 8),
                          Expanded(
                            child: DropdownButton<String>(
                              isExpanded: true,
                              value: selected.isEmpty ? null : selected,
                              hint: const Text('—'),
                              items: [
                                for (final column in options) DropdownMenuItem(value: column, child: Text(column, overflow: TextOverflow.ellipsis)),
                              ],
                              onChanged: (value) => setState(() {
                                if (value == null || value.isEmpty) {
                                  _mapping.remove(key);
                                } else {
                                  _mapping[key] = value;
                                }
                              }),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(onPressed: () => Navigator.pop(context), child: Text(tx('cancel', 'Cancel'))),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton(
                        onPressed: _import,
                        style: FilledButton.styleFrom(backgroundColor: AppColors.charcoal),
                        child: Text(tx('import', 'Import')),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ImportProgressPage extends StatefulWidget {
  const _ImportProgressPage({required this.table, required this.mapping});

  final SheetTable table;
  final Map<String, String> mapping;

  @override
  State<_ImportProgressPage> createState() => _ImportProgressPageState();
}

class _ImportProgressPageState extends State<_ImportProgressPage> {
  var _done = 0;
  var _total = 0;
  var _failed = const <String>[];
  var _finished = false;

  @override
  void initState() {
    super.initState();
    unawaited(_run());
  }

  Future<void> _run() async {
    final rfid = Injection.ready ? await Injection.productRepository.storedRfidMap() : const <String, String>{};
    final built = await compute(buildImportedItems, <String, Object?>{
      'rows': widget.table.rows,
      'mapping': widget.mapping,
      'rfid': rfid,
    });
    if (!mounted) return;
    setState(() => _total = built.total);
    final written = await Injection.productRepository.importProducts(
      built.items,
      onProgress: (count) {
        if (mounted) setState(() => _done = count);
      },
    );
    if (!mounted) return;
    setState(() {
      _done = written;
      _failed = built.failed;
      _finished = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    final progress = _total == 0 ? null : (_done / _total).clamp(0.0, 1.0);
    return Directionality(
      textDirection: featureDirection,
      child: Scaffold(
        backgroundColor: AppColors.white,
        body: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (!_finished) const CircularProgressIndicator(color: AppColors.charcoal),
                  if (_finished) Icon(_failed.isEmpty ? Icons.check_circle_outline : Icons.warning_amber_rounded, size: 72, color: _failed.isEmpty ? const Color(0xFF15803D) : const Color(0xFFB45309)),
                  const SizedBox(height: 16),
                  Text(
                    _finished
                        ? (_failed.isEmpty ? tx('importSuccessful', 'Import successful') : tx('importWithErrors', 'Import finished with skipped rows'))
                        : tx('importingExcelData', 'Importing Excel Data'),
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: AppColors.charcoal, fontWeight: FontWeight.w700, fontSize: 16),
                  ),
                  const SizedBox(height: 12),
                  LinearProgressIndicator(value: progress, minHeight: 8, color: AppColors.goldText, backgroundColor: const Color(0xFFE9E3D7)),
                  const SizedBox(height: 8),
                  Text('$_done / $_total ${tx('fieldsImported', 'fields imported')}', style: const TextStyle(color: AppColors.charcoal)),
                  if (_finished) ...[
                    const SizedBox(height: 16),
                    FilledButton(
                      onPressed: () => Navigator.pop(context),
                      style: FilledButton.styleFrom(backgroundColor: AppColors.charcoal, minimumSize: const Size.fromHeight(44)),
                      child: Text(tx('done', 'Done')),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

void unawaited(Future<void> future) {}
