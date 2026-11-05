class AppPreferences {
  const AppPreferences({required this.enablePos});

  final bool enablePos;

  static const empty = AppPreferences(enablePos: false);

  AppPreferences copyWith({bool? enablePos}) {
    return AppPreferences(enablePos: enablePos ?? this.enablePos);
  }
}
