import 'package:flutter_test/flutter_test.dart';
import 'package:sparkle_rfid_plus/features/delivery/data/delivery_challan_api.dart';
import 'package:sparkle_rfid_plus/features/delivery/data/page_layout.dart';

void main() {
  test('permissions response builds the delivery page controls', () {
    final modules = pageModulesFrom({
      'PageName': 'mob_delivery_chalan',
      'PageDisplayName': 'Delivery Challan',
      'PagePermission': 'Enable',
      'PageControls': [
        {
          'Id': 5,
          'key': 'branch',
          'label': 'Branch',
          'type': 'dropdown',
          'visibility': 'ReadWrite',
          'place': 'top',
          'priority': 5,
          'options': ['Pune', 'Mumbai'],
        },
        {
          'Id': 11,
          'key': 'itemName',
          'label': 'Item Name',
          'type': 'label',
          'visibility': 'Read',
          'place': 'middle',
          'priority': 11,
        },
        {
          'Id': 27,
          'key': 'serial',
          'label': 'S.No',
          'type': 'label',
          'visibility': 'Read',
          'place': 'list',
          'priority': 27,
        },
      ],
    });

    expect(modules, hasLength(1));
    expect(modules.single.pageName, 'mob_delivery_chalan');
    expect(modules.single.controls.map((control) => control.key), ['branch', 'itemName', 'serial']);
    expect(modules.single.controls.first.options, ['Pune', 'Mumbai']);
  });

  test('challan list response maps server fields onto page control keys', () {
    final rows = challansFrom([
      {
        'ChallanNo': '1',
        'CreatedOn': '2026-07-24T10:00:00',
        'CustomerName': 'Vaibhav Vaibhav_jewellers',
        'BranchName': 'Pune',
        'SoldBy': 'Amit',
        'ChallanDetails': [
          {
            'ProductName': 'GOLD ORNAME',
            'ItemCode': 'DGO133',
            'Quantity': '1',
            'GrossWt': '2.100',
            'NetWt': '2.100',
            'Amount': '2100',
            'RFIDCode': 'E200001',
          },
        ],
      },
    ]);

    expect(rows, hasLength(1));
    expect(rows.single.number, '1');
    expect(rows.single.date, '24-07-2026');
    expect(rows.single.customer, 'Vaibhav Vaibhav_jewellers');
    expect(rows.single.fields['branch'], 'Pune');
    expect(rows.single.fields['salesman'], 'Amit');
    expect(rows.single.items.single['itemName'], 'GOLD ORNAME');
    expect(rows.single.items.single['itemCode'], 'DGO133');
    expect(rows.single.items.single['grossWt'], '2.100');
    expect(rows.single.items.single['amount'], '2100');
    expect(rows.single.items.single['lineRfid'], 'E200001');
  });
}
