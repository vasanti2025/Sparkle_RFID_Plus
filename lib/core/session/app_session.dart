/// Signed-in account used by quotation API calls.
class AppSession {
  AppSession._();

  static String clientCode = '';
  static String userId = '';
  static String token = '';

  static void apply({
    required String clientCode,
    required String userId,
    required String token,
  }) {
    AppSession.clientCode = clientCode.trim();
    AppSession.userId = userId.trim();
    AppSession.token = token.trim();
  }

  static void clear() {
    clientCode = '';
    userId = '';
    token = '';
  }
}
