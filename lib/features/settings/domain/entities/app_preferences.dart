class AppPreferences {
  const AppPreferences({
    required this.enablePos,
    required this.clientCode,
    required this.userId,
  });

  final bool enablePos;
  final String clientCode;
  final String userId;

  static const empty = AppPreferences(
    enablePos: false,
    clientCode: '',
    userId: '',
  );

  AppPreferences copyWith({
    bool? enablePos,
    String? clientCode,
    String? userId,
  }) {
    return AppPreferences(
      enablePos: enablePos ?? this.enablePos,
      clientCode: clientCode ?? this.clientCode,
      userId: userId ?? this.userId,
    );
  }
}
