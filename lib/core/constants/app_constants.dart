abstract final class AppConstants {
  static const splashDuration = Duration(seconds: 1);

  /// Same QA host used by the POS app.
  static const qaBaseUrl = 'https://qa-rfid-api.sparklerfid.net';

  static const getAllCustomers = '/api/ClientOnboarding/GetAllCustomer';
  static const addCustomer = '/api/ClientOnboarding/AddCustomer';
  static const getAllBranchMaster = '/api/ClientOnboarding/GetAllBranchMaster';
  static const getAllLabeledStock = '/api/ProductMaster/GetAllLabeledStock';
  static const getAllDailyRate = '/api/ProductMaster/GetAllDailyRate';
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
  static const orderPageName = 'mob_order';
  static const orderPageName = 'new_custom_order';

  static const deliveryPageName = 'mob_delivery_chalan';
  static const getAllDeliveryChallan = '/api/Invoice/GetAllDeliveryChallan';
  static const addDeliveryChallan = '/api/Invoice/AddDeliveryChallan';
  static const updateDeliveryChallan = '/api/Invoice/UpdateDeliveryChallan';
  static const lastChallanNo = '/api/Invoice/GetLastChallanNo';
  static const getAllOrders = '/api/Order/GetAllOrders';
  static const addCustomOrder = '/api/Order/AddCustomOrder';
  static const updateCustomOrder = '/api/Order/UpdateCustomOrder';
  static const deleteCustomOrder = '/api/Order/DeleteCustomOrder';
  static const lastOrderNo = '/api/Order/LastOrderNo';
  static const stockPageSize = 40;
  static const stockBulkSize = 15000;
  static const quotationListPageSize = 40;
  static const customerResultLimit = 40;

  static const loginPath = '/api/ClientOnboarding/ClientOnboardingLogin';
  static const rfidSyncPath = '/api/ProductMaster/GetAllRFID';
  static const addStockVerification =
      '/api/ProductMaster/AddStockVerificationBySession';
  static const stockTransferTypes = '/api/ProductMaster/GetStockTransferTypes';
  static const addStockTransfer = '/api/ProductMaster/AddStockTransfer';
  static const allStockTransfers = '/api/ProductMaster/GetAllStockTransfers';
  static const cancelStockTransfer =
      '/api/ProductMaster/CancelStockTransferMasterDetails';
  static const approveStockTransfer = '/api/ProductMaster/ApproveStockTransfer';
  static const allSampleOut = '/api/Transaction/GetAllCustomerIssue';
  static const lastSampleOutNo = '/api/Transaction/GetCustLastSampleOutNo';
  static const addSampleOut = '/api/Transaction/AddCustomerIssue';
  static const updateSampleOut = '/api/Transaction/UpdateCustomerIssue';
  static const allSampleIn = '/api/Transaction/GetAllIssueItemDetails';
  static const productSyncPath =
      '/api/ProductMaster/branch-labelled-stocks/search';

  static const getAllRfidDetails = '/api/RFIDDevice/GetAllRFIDDetails';
  static const addRfidScans = '/api/RFIDDevice/AddRFID';
  static const deleteRfidByDevice = '/api/RFIDDevice/DeleteRFIDByClientAndDevice';
  static const updateDeviceUsers = '/api/ClientOnboarding/UpdateMultipleUser';
  static const stockVerificationSessions =
      '/api/ProductMaster/GetAllStockVerificationBySession';
  static const consolidatedStockReport =
      '/api/ProductMaster/GetConsolidationStockVerificationReport';
  static const insertLabelledStock = '/api/ProductMaster/InsertLabelledStock';
  static const uploadProductImage = '/api/ProductMaster/UploadImagesByClientCode';
  static const getAllCategory = '/api/ProductMaster/GetAllCategory';
  static const getAllProductMaster = '/api/ProductMaster/GetAllProductMaster';
  static const getAllDesign = '/api/ProductMaster/GetAllDesign';
  static const getAllPurity = '/api/ProductMaster/GetAllPurity';
  static const getAllPartyDetails = '/api/ProductMaster/GetAllPartyDetails';
  static const getAllSku = '/api/ProductMaster/GetAllSKU';
}
