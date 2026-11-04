import 'dart:convert';

class SyncJsonStream {
  SyncJsonStream({this.topLevelArray = false});

  final bool topLevelArray;

  bool _inItemsArray = false;
  bool _totalCountEmitted = false;
  bool _inString = false;
  bool _escape = false;
  int _braceCount = 0;
  final StringBuffer _carry = StringBuffer();
  final StringBuffer _headerBuffer = StringBuffer();

  Future<void> addChunk(
    String chunk, {
    void Function(int total)? onTotal,
    required Future<void> Function(Map<String, dynamic> item) onItem,
  }) async {
    if (!_inItemsArray) {
      if (topLevelArray) {
        await _enterTopLevelArray(chunk, onItem);
        return;
      }
      _headerBuffer.write(chunk);
      var header = _headerBuffer.toString();
      if (header.length > 65536) {
        header = header.substring(header.length - 32768);
        _headerBuffer
          ..clear()
          ..write(header);
      }
      if (!_totalCountEmitted && header.contains('TotalCount')) {
        final match = RegExp(r'"TotalCount"\s*:\s*(\d+)').firstMatch(header);
        final total = int.tryParse(match?.group(1) ?? '');
        if (total != null) {
          _totalCountEmitted = true;
          onTotal?.call(total);
        }
      }
      var itemsIndex = header.indexOf('"Items"');
      if (itemsIndex < 0) itemsIndex = header.indexOf('"items"');
      if (itemsIndex >= 0) {
        final bracket = header.indexOf('[', itemsIndex);
        if (bracket >= 0) {
          _inItemsArray = true;
          final remaining = header.substring(bracket + 1);
          _headerBuffer.clear();
          await _processItems(remaining, onItem);
        }
      }
      return;
    }
    await _processItems(chunk, onItem);
  }

  Future<void> _enterTopLevelArray(
    String chunk,
    Future<void> Function(Map<String, dynamic> item) onItem,
  ) async {
    for (var i = 0; i < chunk.length; i++) {
      final code = chunk.codeUnitAt(i);
      if (code == 32 || code == 9 || code == 10 || code == 13) continue;
      if (code == 91) {
        _inItemsArray = true;
        await _processItems(chunk.substring(i + 1), onItem);
      }
      return;
    }
  }

  Future<void> _processItems(
    String chunk,
    Future<void> Function(Map<String, dynamic> item) onItem,
  ) async {
    final length = chunk.length;
    var copyStart = _braceCount >= 1 ? 0 : -1;
    for (var i = 0; i < length; i++) {
      final code = chunk.codeUnitAt(i);
      if (_escape) {
        _escape = false;
        continue;
      }
      if (code == 92) {
        _escape = true;
        continue;
      }
      if (code == 34) {
        _inString = !_inString;
        continue;
      }
      if (_inString) continue;
      if (code == 123) {
        if (_braceCount == 0) {
          copyStart = i;
          _carry.clear();
        }
        _braceCount++;
      } else if (code == 125) {
        if (_braceCount <= 0) continue;
        _braceCount--;
        if (_braceCount == 0 && copyStart >= 0) {
          final slice = chunk.substring(copyStart, i + 1);
          final itemText = _carry.isEmpty
              ? slice
              : '${_carry.toString()}$slice';
          _carry.clear();
          copyStart = -1;
          await _emit(itemText, onItem);
        }
      } else if (code == 93 && _braceCount == 0) {
        _inItemsArray = false;
        return;
      }
    }
    if (_braceCount >= 1 && copyStart >= 0) {
      _carry.write(chunk.substring(copyStart));
    }
  }

  Future<void> _emit(
    String itemText,
    Future<void> Function(Map<String, dynamic> item) onItem,
  ) async {
    try {
      final decoded = jsonDecode(itemText);
      if (decoded is Map<String, dynamic>) {
        await onItem(decoded);
      } else if (decoded is Map) {
        await onItem(Map<String, dynamic>.from(decoded));
      }
    } on FormatException {
      return;
    }
  }
}
