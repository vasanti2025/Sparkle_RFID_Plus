import 'dart:convert';

import '../../quotation/domain/entities/quotation_field.dart';

/// Temporary order-screen permissions. The order form reads this instead of
/// GetAllUserPermissions until the live response is ready to replace it.
const orderStaticPermissionJson = r'''
[
  {
    "Modules": [
      {
        "PageName": "mob_order",
        "PageDisplayName": "Order",
        "PagePermission": "enable",
        "Create": true,
        "Edit": true,
        "Delete": true,
        "Full": true,
        "isMobView": true,
        "PageControls": [
          {"Id": 950087, "key": "customerName", "label": "Customer Name", "placeholder": "", "priority": 1, "type": "dropdown", "visibility": "ReadWrite", "place": "top"},
          {"Id": 950094, "key": "category", "label": "Category", "placeholder": "", "priority": 1, "type": "dropdown", "visibility": "ReadWrite", "place": "middle"},
          {"Id": 950095, "key": "product", "label": "Product", "placeholder": "", "priority": 2, "type": "dropdown", "visibility": "ReadWrite", "place": "middle"},
          {"Id": 950096, "key": "design", "label": "Design", "placeholder": "", "priority": 3, "type": "dropdown", "visibility": "ReadWrite", "place": "middle"},
          {"Id": 950210, "key": "Pieces", "label": "Pieces", "placeholder": "", "priority": 4, "type": "number", "visibility": "ReadWrite", "place": "middle"},
          {"Id": 950097, "key": "purity", "label": "Purity", "placeholder": "", "priority": 5, "type": "dropdown", "visibility": "ReadWrite", "place": "middle"},
          {"Id": 950089, "key": "branchId", "label": "Branch", "placeholder": "", "priority": 6, "type": "dropdown", "visibility": "ReadWrite", "place": "middle"},
          {"Id": 950098, "key": "grossWt", "label": "Gross Wt", "placeholder": "", "priority": 7, "type": "number", "visibility": "ReadWrite", "place": "middle"},
          {"Id": 950129, "key": "PackingWt", "label": "Packing Wt", "placeholder": "", "priority": 8, "type": "number", "visibility": "ReadWrite", "place": "middle"},
          {"Id": 950099, "key": "stoneWt", "label": "Stone Wt", "placeholder": "", "priority": 9, "type": "number", "visibility": "ReadWrite", "place": "middle"},
          {"Id": 950100, "key": "diamondWt", "label": "Diamond Wt", "placeholder": "", "priority": 10, "type": "number", "visibility": "ReadWrite", "place": "middle"},
          {"Id": 950101, "key": "netWt", "label": "Net Wt", "placeholder": "", "priority": 11, "type": "number", "visibility": "ReadOnly", "place": "middle"},
          {"Id": 950110, "key": "fixedWt", "label": "Fixed Wt", "placeholder": "", "priority": 12, "type": "number", "visibility": "ReadWrite", "place": "middle"},
          {"Id": 950120, "key": "sampleWt", "label": "Sample Wt", "placeholder": "", "priority": 13, "type": "number", "visibility": "ReadWrite", "place": "middle"},
          {"Id": 950128, "key": "TotalWt", "label": "Total Wt", "placeholder": "", "priority": 14, "type": "number", "visibility": "Hidden", "place": "middle"},
          {"Id": 950106, "key": "ratePerGram", "label": "Rate/Gm", "placeholder": "", "priority": 15, "type": "number", "visibility": "ReadWrite", "place": "middle"},
          {"Id": 950107, "key": "makingPerGram", "label": "Making/Gm", "placeholder": "", "priority": 16, "type": "number", "visibility": "ReadWrite", "place": "middle"},
          {"Id": 950109, "key": "makingPercentage", "label": "Making %", "placeholder": "", "priority": 17, "type": "number", "visibility": "ReadWrite", "place": "middle"},
          {"Id": 950108, "key": "fixedMaking", "label": "Fixed Making", "placeholder": "", "priority": 18, "type": "number", "visibility": "ReadWrite", "place": "middle"},
          {"Id": 950115, "key": "totalMakingAmount", "label": "Making Amount", "placeholder": "", "priority": 19, "type": "number", "visibility": "ReadOnly", "place": "middle"},
          {"Id": 950114, "key": "stoneAmount", "label": "Stone Amount", "placeholder": "", "priority": 20, "type": "number", "visibility": "ReadWrite", "place": "middle"},
          {"Id": 950111, "key": "diamondPieces", "label": "Diamond Pieces", "placeholder": "", "priority": 21, "type": "number", "visibility": "ReadWrite", "place": "middle"},
          {"Id": 950112, "key": "diamondRate", "label": "Diamond Rate", "placeholder": "", "priority": 22, "type": "number", "visibility": "ReadWrite", "place": "middle"},
          {"Id": 950113, "key": "diamondAmount", "label": "Diamond Amount", "placeholder": "", "priority": 23, "type": "number", "visibility": "ReadWrite", "place": "middle"},
          {"Id": 950225, "key": "metalAmount", "label": "Metal Amount", "placeholder": "", "priority": 24, "type": "number", "visibility": "ReadOnly", "place": "middle"},
          {"Id": 950226, "key": "itemAmount", "label": "Item Amount", "placeholder": "", "priority": 25, "type": "number", "visibility": "ReadOnly", "place": "middle"},
          {"Id": 950117, "key": "screwType", "label": "Screw Type", "placeholder": "", "priority": 26, "type": "dropdown", "visibility": "ReadWrite", "place": "middle"},
          {"Id": 950104, "key": "color", "label": "Types of Color", "placeholder": "", "priority": 27, "type": "dropdown", "visibility": "ReadWrite", "place": "middle"},
          {"Id": 950118, "key": "polish", "label": "Polish Type", "placeholder": "", "priority": 28, "type": "dropdown", "visibility": "ReadWrite", "place": "middle"},
          {"Id": 950119, "key": "rhodium", "label": "Rhodium", "placeholder": "", "priority": 29, "type": "dropdown", "visibility": "ReadWrite", "place": "middle"},
          {"Id": 950121, "key": "remarks", "label": "Remarks", "placeholder": "", "priority": 30, "type": "input", "visibility": "ReadWrite", "place": "middle"},
          {"Id": 950116, "key": "totalItemAmount", "label": "Total Item Amount", "placeholder": "", "priority": 31, "type": "number", "visibility": "ReadOnly", "place": "middle"},
          {"Id": 950091, "key": "orderDate", "label": "Order Date", "placeholder": "", "priority": 32, "type": "date", "visibility": "ReadWrite", "place": "middle"},
          {"Id": 950092, "key": "deliveryDate", "label": "Delivery Date", "placeholder": "", "priority": 33, "type": "date", "visibility": "ReadWrite", "place": "middle"},
          {"Id": 950160, "key": "itemDetails", "label": "Item Details", "placeholder": "", "priority": 1, "type": "text", "visibility": "ReadOnly", "place": "summarytable"},
          {"Id": 950161, "key": "grossWt", "label": "Gross Wt", "placeholder": "", "priority": 2, "type": "number", "visibility": "ReadOnly", "place": "summarytable"},
          {"Id": 950162, "key": "stoneWt", "label": "Stone Wt", "placeholder": "", "priority": 3, "type": "number", "visibility": "ReadOnly", "place": "summarytable"},
          {"Id": 950163, "key": "diamondWt", "label": "Dia Wt", "placeholder": "", "priority": 4, "type": "number", "visibility": "ReadOnly", "place": "summarytable"},
          {"Id": 950164, "key": "netWt", "label": "Net Wt", "placeholder": "", "priority": 5, "type": "number", "visibility": "ReadOnly", "place": "summarytable"},
          {"Id": 950165, "key": "quantity", "label": "Qty", "placeholder": "", "priority": 6, "type": "number", "visibility": "ReadOnly", "place": "summarytable"},
          {"Id": 950166, "key": "receiveStone", "label": "Rec Stone", "placeholder": "", "priority": 7, "type": "number", "visibility": "ReadOnly", "place": "summarytable"},
          {"Id": 950167, "key": "receiveDiamond", "label": "Rec Diamond", "placeholder": "", "priority": 8, "type": "number", "visibility": "ReadOnly", "place": "summarytable"},
          {"Id": 950168, "key": "ratePerGram", "label": "Rate/Gm", "placeholder": "", "priority": 9, "type": "number", "visibility": "ReadOnly", "place": "summarytable"},
          {"Id": 950170, "key": "itemAmount", "label": "Item Amt", "placeholder": "", "priority": 10, "type": "number", "visibility": "ReadOnly", "place": "summarytable"},
          {"Id": 950193, "key": "taxableAmount", "label": "Taxable Amount", "placeholder": "", "priority": 1, "type": "number", "visibility": "ReadOnly", "place": "paymentsummary"},
          {"Id": 950194, "key": "isGst", "label": "GST", "placeholder": "", "priority": 2, "type": "checkbox", "visibility": "ReadWrite", "place": "paymentsummary"},
          {"Id": 950195, "key": "gstAmount", "label": "GST Amount", "placeholder": "", "priority": 3, "type": "number", "visibility": "ReadOnly", "place": "paymentsummary"},
          {"Id": 950198, "key": "discount", "label": "Discount", "placeholder": "", "priority": 4, "type": "number", "visibility": "ReadWrite", "place": "paymentsummary"},
          {"Id": 950199, "key": "totalAmount", "label": "Total Amount", "placeholder": "", "priority": 5, "type": "number", "visibility": "ReadOnly", "place": "paymentsummary"}
        ]
      }
    ]
  }
]
''';

dynamic orderStaticPermissionBody() => jsonDecode(orderStaticPermissionJson);

/// Order form controls from the static permission response.
/// Hidden controls are left out. ReadOnly stays read-only.
List<QuotationField> orderStaticFields() {
  final body = orderStaticPermissionBody();
  final fields = <QuotationField>[];
  if (body is! List) return fields;
  for (final entry in body) {
    if (entry is! Map) continue;
    final modules = entry['Modules'];
    if (modules is! List) continue;
    for (final module in modules) {
      if (module is! Map) continue;
      final controls = module['PageControls'];
      if (controls is! List) continue;
      for (final raw in controls) {
        if (raw is! Map) continue;
        final row = Map<String, dynamic>.from(raw);
        final visibility = '${row['visibility'] ?? ''}'.toLowerCase();
        if (visibility == 'hidden' || visibility == 'none') continue;
        final key = '${row['key'] ?? ''}'.trim();
        if (key.isEmpty) continue;
        final priority = row['priority'];
        fields.add(
          QuotationField(
            key: key,
            label: '${row['label'] ?? key}',
            placeholder: '${row['placeholder'] ?? ''}',
            place: '${row['place'] ?? 'middle'}'.toLowerCase(),
            priority: priority is int ? priority : int.tryParse('$priority') ?? 0,
            type: '${row['type'] ?? 'text'}',
            readOnly: visibility == 'readonly' || visibility == 'read',
          ),
        );
      }
    }
  }
  return fields;
}
