abstract final class AppConstants {
  static const splashDuration = Duration(seconds: 1);

  /// Same QA host used by the POS app.
  static const qaBaseUrl = 'https://qa-rfid-api.sparklerfid.net';

  static const getAllCustomers = '/api/ClientOnboarding/GetAllCustomer';
  static const addCustomer = '/api/ClientOnboarding/AddCustomer';
  static const getAllLabeledStock = '/api/ProductMaster/GetAllLabeledStock';
  static const userPermissions =
      '/api/RoleManagement/GetAllUserPermissions-Optimized';

  static const quotationPageName = 'mob_quotation';
  static const stockPageSize = 30;
  static const customerResultLimit = 40;

  /// Static QA session until login is wired.
  static const qaClientCode = 'LS000580';
  static const qaUserId = '3766';
  static const qaToken =
      'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiJNdWtlc2giLCJqdGkiOiI2Yzk5OGI1ZS0wMmQ4LTQwOGUtYTA0MC1lMmJiZWI3NmMwYTYiLCJDbGllbnRDb2RlIjoiTFMwMDA1ODAiLCJleHAiOjE3OTM4MjAxNDgsImlzcyI6Ijk4Nzk4ODc2NzU3NjU2NjU0NjU0IiwiYXVkIjoiSW5mb0Bsb3lhbHN0cmluZy5jb20ifQ.uFo83-l0jC0D7un1M22FJ7YVIlhMkNp0lEtYNrK2Bdg';
}
