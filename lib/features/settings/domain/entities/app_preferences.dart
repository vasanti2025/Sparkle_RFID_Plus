class AppPreferences {
  const AppPreferences({
    required this.enablePos,
    this.localWifiMode = false,
    this.language = 'en',
    this.sheetUrl = '',
  });

  final bool enablePos;

  /// On: Scan to Desktop serves the list on this device. Off: save goes online.
  final bool localWifiMode;

  /// en, hi, or ar. Used by Scan to Desktop, Reports, and Data tools.
  final String language;

  final String sheetUrl;

  static const empty = AppPreferences(enablePos: false);

  AppPreferences copyWith({bool? enablePos, bool? localWifiMode, String? language, String? sheetUrl}) {
    return AppPreferences(
      enablePos: enablePos ?? this.enablePos,
      localWifiMode: localWifiMode ?? this.localWifiMode,
      language: language ?? this.language,
      sheetUrl: sheetUrl ?? this.sheetUrl,
    );
  }
}
