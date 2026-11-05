import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:sunmi_printer_plus/sunmi_printer_plus.dart';

import '../domain/entities/quotation_detail.dart';
import '../domain/entities/stock_item.dart';
import '../domain/quotation_math.dart';

class PrintCopy {
  const PrintCopy({
    required this.detail,
    required this.companyName,
    required this.companyAddress,
    required this.gstNumber,
    required this.gstFraction,
  });

  final QuotationDetail detail;
  final String companyName;
  final String companyAddress;
  final String gstNumber;
  final double gstFraction;

  List<LinePrice> get lines => [
    for (final item in detail.items)
      priceLine(item, applyGst: detail.gstApplied, gstFraction: gstFraction),
  ];

  double get taxable => lines.where((line) => !line.mrp).fold(0, (sum, line) => sum + line.item);

  double get gst => lines.where((line) => !line.mrp).fold(0, (sum, line) => sum + line.gst);

  double get mrpTotal => lines.where((line) => line.mrp).fold(0, (sum, line) => sum + line.total);

  double get net => taxable + gst + mrpTotal;
}

Future<void> printQuotationPdf(PrintCopy copy) async {
  final document = _quotationPdfDocument(copy);
  await Printing.layoutPdf(name: 'Quotation ${copy.detail.number}', onLayout: (_) => document.save());
}

pw.Document _quotationPdfDocument(PrintCopy copy) {
  final document = pw.Document();
  document.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4.landscape,
      margin: const pw.EdgeInsets.fromLTRB(18, 20, 18, 20),
      build: (context) => [
        pw.Text(
          copy.companyName.isEmpty ? 'Quotation' : copy.companyName,
          style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold),
        ),
        if (copy.companyAddress.isNotEmpty) pw.Text(copy.companyAddress, style: const pw.TextStyle(fontSize: 10)),
        if (copy.gstNumber.isNotEmpty) pw.Text('GSTN: ${copy.gstNumber}', style: const pw.TextStyle(fontSize: 10)),
        pw.SizedBox(height: 8),
        pw.Text('Customer Name : ${copy.detail.customer.name}'),
        pw.Text('Quotation No : ${copy.detail.number}'),
        if (copy.detail.customer.mobile.isNotEmpty) pw.Text('Phone No : ${copy.detail.customer.mobile}'),
        pw.SizedBox(height: 12),
        pw.Text('Item Details', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
        pw.SizedBox(height: 6),
        _pdfItemsTable(copy),
        pw.SizedBox(height: 10),
        if (copy.mrpTotal > 0) _pdfMoney('MRP Items Total', copy.mrpTotal),
        if (copy.taxable > 0) _pdfMoney('Taxable Amount', copy.taxable),
        if (copy.detail.gstApplied && copy.taxable > 0) ...[
          _pdfMoney('CGST 1.5%', copy.gst / 2),
          _pdfMoney('SGST 1.5%', copy.gst / 2),
        ],
        pw.Divider(),
        _pdfMoney('Total Net Amount', copy.net),
      ],
    ),
  );
  return document;
}

pw.Widget _pdfMoney(String label, double amount) {
  return pw.Row(
    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
    children: [
      pw.Text(label),
      pw.Text(amount.toStringAsFixed(2)),
    ],
  );
}

const _pdfHeaders = [
  '#',
  'Item',
  'HSN',
  'Pcs',
  'Purity',
  'Gr Wt',
  'St Wt',
  'Net Wt',
  'Dia Wt',
  'Dia Pcs',
  'Dia Amt',
  'Rate',
  'St Amt',
  'Metal',
  'Making',
  'Taxable',
  'GST',
  'Total',
];

pw.Widget _pdfItemsTable(PrintCopy copy) {
  final rows = <List<String>>[
    for (var index = 0; index < copy.detail.items.length; index++)
      _pdfRow(copy.detail.items[index], copy.lines[index], index + 1),
  ];
  return pw.TableHelper.fromTextArray(
    headers: _pdfHeaders,
    data: rows,
    border: pw.TableBorder.all(color: PdfColors.grey400, width: 0.4),
    headerStyle: pw.TextStyle(
      fontSize: 7,
      fontWeight: pw.FontWeight.bold,
      color: PdfColors.white,
    ),
    headerDecoration: const pw.BoxDecoration(color: PdfColor.fromInt(0xFF20201F)),
    headerAlignment: pw.Alignment.center,
    cellStyle: const pw.TextStyle(fontSize: 7),
    cellAlignment: pw.Alignment.center,
    cellAlignments: const {1: pw.Alignment.centerLeft},
    cellPadding: const pw.EdgeInsets.symmetric(horizontal: 2, vertical: 3),
    headerPadding: const pw.EdgeInsets.symmetric(horizontal: 2, vertical: 4),
    oddRowDecoration: const pw.BoxDecoration(color: PdfColor.fromInt(0xFFF9F8F6)),
    columnWidths: {
      0: const pw.FixedColumnWidth(18),
      1: const pw.FlexColumnWidth(2.2),
      2: const pw.FixedColumnWidth(40),
      3: const pw.FixedColumnWidth(26),
      4: const pw.FixedColumnWidth(38),
      5: const pw.FixedColumnWidth(36),
      6: const pw.FixedColumnWidth(36),
      7: const pw.FixedColumnWidth(36),
      8: const pw.FixedColumnWidth(36),
      9: const pw.FixedColumnWidth(40),
      10: const pw.FixedColumnWidth(42),
      11: const pw.FixedColumnWidth(36),
      12: const pw.FixedColumnWidth(42),
      13: const pw.FixedColumnWidth(42),
      14: const pw.FixedColumnWidth(42),
      15: const pw.FixedColumnWidth(46),
      16: const pw.FixedColumnWidth(32),
      17: const pw.FixedColumnWidth(44),
    },
  );
}

List<String> _pdfRow(StockItem item, LinePrice line, int number) {
  String pick(List<String> keys, [String fallback = '-']) {
    for (final key in keys) {
      final value = item.extras[key];
      if (value != null && value.trim().isNotEmpty) return value.trim();
    }
    return fallback;
  }

  final name = pick(
    const ['designname', 'productname'],
    item.design.isNotEmpty
        ? item.design
        : (item.name.isNotEmpty ? item.name : (item.itemCode.isEmpty ? 'Item $number' : item.itemCode)),
  );
  return [
    '$number',
    name,
    pick(const ['hsncode', 'hsn']),
    pick(const ['pieces', 'pcs'], '1'),
    pick(const ['purity']),
    pick(const ['grosswt', 'grossweight'], item.gross.isEmpty ? '-' : item.gross),
    pick(const ['stonewt', 'stoneweight'], '0'),
    line.weight(line.net),
    pick(const ['diamondwt', 'diamondweight'], '0'),
    pick(const ['diamondpcs'], '0'),
    line.money(line.diamond),
    pick(const ['rate', 'metalrate', 'goldrate'], '0'),
    line.money(line.stone),
    line.money(line.metal),
    line.money(line.making),
    line.money(line.item),
    line.money(line.gst),
    line.money(line.total),
  ];
}

Future<void> printQuotationOnPos(PrintCopy copy) async {
  try {
    Future<void> line(String text, {bool bold = false, bool center = false}) {
      return SunmiPrinter.printText(
        text,
        style: SunmiTextStyle(
          bold: bold,
          align: center ? SunmiPrintAlign.CENTER : SunmiPrintAlign.LEFT,
          fontSize: bold ? 28 : 22,
        ),
      );
    }

    await line(copy.companyName.isEmpty ? 'QUOTATION' : copy.companyName, bold: true, center: true);
    if (copy.companyAddress.isNotEmpty) await line(copy.companyAddress, center: true);
    if (copy.gstNumber.isNotEmpty) await line('GSTN: ${copy.gstNumber}', center: true);
    await line('--------------------------------');
    await line('Customer: ${copy.detail.customer.name}');
    await line('Quotation: ${copy.detail.number}');
    if (copy.detail.customer.mobile.isNotEmpty) await line('Phone: ${copy.detail.customer.mobile}');
    await line('--------------------------------');
    for (var index = 0; index < copy.detail.items.length; index++) {
      final item = copy.detail.items[index];
      final priced = copy.lines[index];
      final title = item.design.isNotEmpty
          ? item.design
          : (item.name.isNotEmpty ? item.name : item.itemCode);
      await line('${index + 1}. $title', bold: true);
      await line('Gr ${item.gross}  Net ${priced.weight(priced.net)}  Stone ${priced.money(priced.stone)}');
      await line('Metal ${priced.money(priced.metal)}  Making ${priced.money(priced.making)}');
      await line('Taxable ${priced.money(priced.item)}  GST ${priced.money(priced.gst)}');
      await line('Total ${priced.money(priced.total)}', bold: true);
    }
    await line('--------------------------------');
    if (copy.mrpTotal > 0) await line('MRP total ${copy.mrpTotal.toStringAsFixed(2)}');
    await line('Taxable ${copy.taxable.toStringAsFixed(2)}');
    if (copy.detail.gstApplied) {
      await line('CGST ${(copy.gst / 2).toStringAsFixed(2)}');
      await line('SGST ${(copy.gst / 2).toStringAsFixed(2)}');
    }
    await line('NET ${copy.net.toStringAsFixed(2)}', bold: true);
    await SunmiPrinter.lineWrap(3);
    await SunmiPrinter.cutPaper();
  } catch (_) {
    throw Exception('POS printer is not available on this device');
  }
}

Future<String?> askPrintChoice(BuildContext context) {
  return showModalBottomSheet<String>(
    context: context,
    builder: (context) {
      return SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const ListTile(
              title: Text('Print quotation', style: TextStyle(fontWeight: FontWeight.w700)),
            ),
            ListTile(
              leading: const Icon(Icons.picture_as_pdf_outlined),
              title: const Text('PDF'),
              subtitle: const Text('Normal printer'),
              onTap: () => Navigator.pop(context, 'pdf'),
            ),
            ListTile(
              leading: const Icon(Icons.point_of_sale_outlined),
              title: const Text('POS printer'),
              subtitle: const Text('Print on this machine'),
              onTap: () => Navigator.pop(context, 'pos'),
            ),
          ],
        ),
      );
    },
  );
}
