/// Signed-in account used by quotation API calls.
class AppSession {
  AppSession._();

  static String clientCode = '';
  static String userId = '';
  static String token = '';
  static int branchId = 0;
  static int branchNo = 0;
  static int employeeId = 0;
  static String branchName = '';

  static void apply({
    required String clientCode,
    required String userId,
    required String token,
    int? branchId,
    int? branchNo,
    int? employeeId,
    String branchName = '',
  }) {
    AppSession.clientCode = clientCode.trim();
    AppSession.userId = userId.trim();
    AppSession.branchName = branchName.trim();
    AppSession.token = token.trim();
    if (branchId != null) AppSession.branchId = branchId;
    if (branchNo != null) AppSession.branchNo = branchNo;
    if (employeeId != null) AppSession.employeeId = employeeId;
  }

  static void clear() {
    clientCode = '';
    userId = '';
    token = '';
    branchId = 0;
    branchNo = 0;
    employeeId = 0;
    branchName = '';
  }
}
