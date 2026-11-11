abstract final class AppConstants {
  static const splashDuration = Duration(seconds: 1);

  /// Same QA host used by the POS app.
  static const qaBaseUrl = 'https://qa-rfid-api.sparklerfid.net';

  static const getAllCustomers = '/api/ClientOnboarding/GetAllCustomer';
  static const addCustomer = '/api/ClientOnboarding/AddCustomer';
  static const getAllLabeledStock = '/api/ProductMaster/GetAllLabeledStock';
  static const getAllQuotation = '/api/Order/GetAllQuotation';
  static const addQuotation = '/api/Order/AddQuotation';
  static const updateQuotation = '/api/Order/UpdateQuotation';
  static const deleteQuotation = '/api/Order/DeleteQuotation';
  static const getQuotationById = '/api/Order/GetQuotationById';
  static const lastQuotationNo = '/api/Order/LastQuotationNo';
  static const companyDetails = '/api/ClientOnboarding/GetAllCompanyDetails';
  static const userPermissions =
      '/api/RoleManagement/GetAllUserPermissions-Optimized';

  static const quotationPageName = 'mob_quotation';
  static const orderPageName = 'new_custom_order';
  static const getAllOrders = '/api/Order/GetAllOrders';
  static const addCustomOrder = '/api/Order/AddCustomOrder';
  static const updateCustomOrder = '/api/Order/UpdateCustomOrder';
  static const deleteCustomOrder = '/api/Order/DeleteCustomOrder';
  static const lastOrderNo = '/api/Order/LastOrderNo';
  static const stockPageSize = 40;
  static const stockBulkSize = 15000;
  static const quotationListPageSize = 40;
  static const customerResultLimit = 40;

  //static const apiBaseUrl = 'https://rrgold.loyalstring.co.in/';
  static const loginPath = '/api/ClientOnboarding/ClientOnboardingLogin';
  static const rfidSyncPath = '/api/ProductMaster/GetAllRFID';
  static const productSyncPath =
      '/api/ProductMaster/branch-labelled-stocks/search';
}
