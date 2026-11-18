const productCsvHeader = [
  'Category',
  'Product Name',
  'Design',
  'Item Code',
  'RFID',
  'Gross Weight',
  'Stone Weight',
  'Dust Weight',
  'Net Weight',
  'Purity',
  'Making/Gram',
  'Making %',
  'Fix Making',
  'Fix Wastage',
  'Stone Amount',
  'Dust Amount',
  'SKU',
  'EPC',
  'Vendor',
  'TID',
  'Box',
  'Product Code',
  'Design Code',
];

String productCsvLine(List<String> cells) => cells.map(productCsvCell).join(',');

String productCsvCell(String value) {
  var safe = value;
  if (RegExp(r'^[\s]*[=+\-@]').hasMatch(safe)) safe = "'$safe";
  return '"${safe.replaceAll('"', '""')}"';
}

String productCsvFromPayload(
  Map<String, dynamic> json, {
  String? itemCode,
  String? name,
}) {
  String pick(List<String> keys) {
    for (final key in keys) {
      final value = json[key];
      if (value == null) continue;
      final text = value.toString().trim();
      if (text.isNotEmpty && text.toLowerCase() != 'null') return text;
    }
    return '';
  }

  String exact(List<String> keys) {
    for (final key in keys) {
      if (!json.containsKey(key)) continue;
      final value = json[key];
      if (value == null) return 'null';
      final text = value.toString().trim();
      if (text.toLowerCase() == 'null') return 'null';
      return text;
    }
    return '';
  }

  final code = pick(const ['ItemCode', 'itemCode']);
  final product = pick(const ['ProductName', 'productName', 'ItemName', 'itemName']);
  return productCsvLine([
    pick(const ['CategoryName', 'categoryName']),
    product.isEmpty ? (name ?? '') : product,
    pick(const ['DesignName', 'designName']),
    code.isEmpty ? (itemCode ?? '') : code,
    exact(const ['RFIDCode', 'RfidCode', 'rfidCode', 'RFID', 'Rfid', 'rfid']),
    pick(const ['GrossWt', 'grossWt', 'GrossWeight', 'grossWeight']),
    pick(const ['TotalStoneWeight', 'totalStoneWeight']),
    pick(const ['TotalDiamondWeight', 'totalDiamondWeight']),
    pick(const ['NetWt', 'netWt', 'NetWeight', 'netWeight']),
    pick(const ['PurityName', 'purityName']),
    pick(const ['MakingPerGram', 'makingPerGram']),
    pick(const ['MakingPercentage', 'makingPercentage']),
    pick(const ['MakingFixedAmt', 'makingFixedAmt']),
    pick(const ['MakingFixedWastage', 'makingFixedWastage']),
    pick(const ['TotalStoneAmount', 'totalStoneAmount']),
    pick(const ['TotalDiamondAmount', 'totalDiamondAmount']),
    pick(const ['SKU', 'sku']),
    exact(const ['EPC', 'Epc', 'epc', 'EpcValue', 'epcValue']),
    pick(const ['VendorName', 'vendorName']),
    exact(const ['TIDNumber', 'TidNumber', 'tidNumber', 'TidValue', 'tidValue', 'TID', 'tid']),
    pick(const ['BoxName', 'boxName']),
    pick(const ['ProductCode', 'productCode']),
    pick(const ['DesignCode', 'designCode']),
  ]);
}
