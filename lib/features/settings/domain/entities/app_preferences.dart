class AppPreferences {
  const AppPreferences({required this.enablePos, this.localWifiMode = false});

  final bool enablePos;

  /// On: Scan to Desktop serves the list on this device. Off: save goes online.
  final bool localWifiMode;

  static const empty = AppPreferences(enablePos: false);

  AppPreferences copyWith({bool? enablePos, bool? localWifiMode}) {
    return AppPreferences(
      enablePos: enablePos ?? this.enablePos,
      localWifiMode: localWifiMode ?? this.localWifiMode,
    );
  }
}
