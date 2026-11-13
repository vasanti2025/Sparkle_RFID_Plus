import 'entities/stock_item.dart';

/// One quotation line priced the same way as Sparkle POS.
///
/// Metal = net weight x rate.
/// Making = per gram x net + fixed making + metal x making % + wastage x rate.
/// Item = stone + diamond + metal + making.
/// GST is added on rate items. An MRP already includes GST.
class LinePrice {
  const LinePrice({
    required this.net,
    required this.metal,
    required this.making,
    required this.stone,
    required this.diamond,
    required this.item,
    required this.gst,
    required this.total,
    required this.mrp,
  });

  final double net;
  final double metal;
  final double making;
  final double stone;
  final double diamond;
  final double item;
  final double gst;
  final double total;
  final bool mrp;

  String money(double value) => value.toStringAsFixed(2);

  String weight(double value) => value.toStringAsFixed(3);
}

LinePrice priceLine(
  StockItem item, {
  required bool applyGst,
  required double gstFraction,
}) {
  final gross = _firstNum(item.gross, _num(item, const ['grosswt', 'grossweight']));
  final stoneWeight = _num(item, const ['stonewt', 'stoneweight']);
  final diamondWeight = _num(item, const ['diamondwt', 'diamondweight']);
  var net = _num(item, const ['netwt', 'netweight']);
  if (net <= 0 && item.net.trim().isNotEmpty) {
    net = double.tryParse(item.net.replaceAll(',', '').trim()) ?? 0;
  }
  if (net <= 0) {
    net = gross - stoneWeight - diamondWeight;
  }
  if (net < 0) net = 0;

  final rate = _num(item, const ['rate', 'metalrate', 'goldrate']);
  final mrpValue = _num(item, const ['mrp']);
  // Sparkle POS treats any MRP above zero as an MRP line. GST is already inside it.
  if (mrpValue > 0) {
    return LinePrice(
      net: net,
      metal: 0,
      making: 0,
      stone: 0,
      diamond: 0,
      item: mrpValue,
      gst: 0,
      total: mrpValue,
      mrp: true,
    );
  }

  final metal = net * rate;
  final perGram = _num(item, const ['makingpergram']);
  final percent = _num(item, const ['makingpercent', 'makingpercentage']);
  final fixedMaking = _num(item, const ['makingfixedamt', 'fixmaking']);
  final wastage = _num(item, const ['makingfixedwastage', 'fixwastage']);
  final hasBreakdown = perGram > 0 || percent > 0 || fixedMaking > 0 || wastage > 0;
  double making;
  if (hasBreakdown) {
    final wastageAmount = rate > 0 ? wastage * rate : wastage;
    making = (net * perGram) + fixedMaking + (metal * (percent / 100)) + wastageAmount;
  } else {
    final perGramCharge = _num(item, const ['making', 'makingcharge', 'makingplus']);
    making = perGramCharge > 0
        ? net * perGramCharge
        : _num(item, const ['makingamt', 'makingamount', 'makingcharg']);
  }
  final stone = _num(item, const ['stoneamt', 'stoneamount', 'totalstoneamount']);
  final diamond = _num(item, const ['diamondamt', 'diamondamount', 'totaldiamondamount']);
  var itemAmount = stone + diamond + metal + making;
  if (itemAmount == 0) {
    itemAmount = _num(item, const ['itemamt', 'itemamount', 'totalitemamount', 'amount']);
  }
  final gst = applyGst ? itemAmount * gstFraction : 0.0;
  return LinePrice(
    net: net,
    metal: metal,
    making: making,
    stone: stone,
    diamond: diamond,
    item: itemAmount,
    gst: gst,
    total: itemAmount + gst,
    mrp: false,
  );
}

/// Fills net weight and the line amounts for a quotation item.
///
/// Net weight is gross minus stone weight minus diamond weight when a gross
/// weight is present, unless the user is editing net weight itself.
/// A purity rate is used only when one is supplied.
StockItem priceQuotationEdit(
  StockItem item, {
  bool lockNet = false,
  double purityRate = 0,
}) {
  final extras = Map<String, String>.from(item.extras);
  final gross = _firstNum(item.gross, _num(item, const ['grosswt', 'grossweight']));
  final stoneWeight = _num(item, const ['stonewt', 'stoneweight', 'totalstoneweight']);
  final diamondWeight = _num(item, const ['diamondwt', 'diamondweight', 'totaldiamondweight']);
  var net = _num(item, const ['netwt', 'netweight', 'nwt', 'netwtgm']);
  if (net <= 0 && item.net.trim().isNotEmpty) {
    net = double.tryParse(item.net.replaceAll(',', '').trim()) ?? 0;
  }
  if (!lockNet && gross > 0) {
    net = gross - stoneWeight - diamondWeight;
  }
  if (net < 0) net = 0;
  final netText = net.toStringAsFixed(3);
  extras['netwt'] = netText;
  extras['netweight'] = netText;
  if (purityRate > 0) {
    final rateText = purityRate.toStringAsFixed(2);
    extras['rate'] = rateText;
    extras['metalrate'] = rateText;
    extras['goldrate'] = rateText;
    extras['todaysrate'] = rateText;
  }
  final next = StockItem(
    itemCode: item.itemCode,
    name: item.name,
    rfid: item.rfid,
    gross: gross > 0 ? gross.toStringAsFixed(3) : item.gross,
    net: netText,
    design: item.design,
    extras: extras,
  );
  return withLinePrice(next, priceLine(next, applyGst: false, gstFraction: 0));
}

StockItem withLinePrice(StockItem item, LinePrice line) {
  final extras = Map<String, String>.from(item.extras);
  extras['netwt'] = line.weight(line.net);
  extras['netweight'] = extras['netwt']!;
  extras['metalamt'] = line.money(line.metal);
  extras['metalamount'] = line.money(line.metal);
  extras['makingamt'] = line.money(line.making);
  extras['makingamount'] = line.money(line.making);
  extras['makingcharg'] = line.money(line.making);
  extras['stoneamt'] = line.money(line.stone);
  extras['diamondamt'] = line.money(line.diamond);
  extras['itemamt'] = line.money(line.mrp ? line.total : line.item);
  extras['totalitemamount'] = extras['itemamt']!;
  return StockItem(
    itemCode: item.itemCode,
    name: item.name,
    rfid: item.rfid,
    gross: item.gross,
    net: line.weight(line.net),
    design: item.design,
    extras: extras,
  );
}

double _num(StockItem item, List<String> keys) {
  for (final key in keys) {
    final raw = item.extras[key];
    if (raw == null) continue;
    final value = double.tryParse(raw.replaceAll(',', '').trim());
    if (value != null) return value;
  }
  return 0;
}

double _firstNum(String raw, double fallback) {
  final value = double.tryParse(raw.replaceAll(',', '').trim());
  if (value != null && value != 0) return value;
  return fallback;
}
