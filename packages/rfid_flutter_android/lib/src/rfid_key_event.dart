/// Key event class <br/>
/// 按键事件类 <br/>
class RfidKeyEvent {
  // ignore: constant_identifier_names
  static const int ACTION_DOWN = 0;
  // ignore: constant_identifier_names
  static const int ACTION_UP = 1;

  /// The key code <br/>
  /// 按键码 <br/>
  final int keyCode;

  /// The key code name <br/>
  /// 按键码名称 <br/>
  final String keyCodeName;

  /// The action type, like down, up, etc. <br/>
  /// 按键动作类型，如按下、抬起等 <br/>
  final int action;

  /// Whether the key is down <br/>
  /// 是否为按下事件 <br/>
  bool isKeyDown() {
    return action == ACTION_DOWN;
  }

  /// Whether the key is up <br/>
  /// 是否为抬起事件 <br/>
  bool isKeyUp() {
    return action == ACTION_UP;
  }

  static RfidKeyEvent? fromMap(dynamic data) {
    if (data == null) return null;

    try {
      final Map<String, dynamic> map = data is Map<String, dynamic> ? data : Map<String, dynamic>.from(data as Map);
      return RfidKeyEvent(
        map['keyCode'],
        map['keyCodeName'] ?? '',
        map['action'] ?? 0,
      );
    } catch (e) {
      // print('KeyEvent.fromMap error: $e');
      return null;
    }
  }

  @override
  String toString() {
    return 'KeyEvent(keyCode: $keyCode, keyCodeName: $keyCodeName, action: $action)';
  }

  RfidKeyEvent(this.keyCode, this.keyCodeName, this.action);
}
