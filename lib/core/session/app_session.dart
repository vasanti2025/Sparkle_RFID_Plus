/// Signed-in account used by quotation API calls.
class AppSession {
  AppSession._();

  static String clientCode = '';
  static String userId = '';
  static String token = '';
  static int branchId = 0;
  static String branchName = '';

  static void apply({
    required String clientCode,
    required String userId,
    required String token,
    int branchId = 0,
    String branchName = '',
  }) {
    AppSession.clientCode = clientCode.trim();
    AppSession.userId = userId.trim();
    AppSession.token = token.trim();
    AppSession.branchId = branchId;
    AppSession.branchName = branchName.trim();
  }

  static void clear() {
    clientCode = '';
    userId = '';
    token = '';
    branchId = 0;
    branchName = '';
  }
}
