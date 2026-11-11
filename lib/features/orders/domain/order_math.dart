import '../../quotation/domain/entities/stock_item.dart';
import '../../quotation/domain/quotation_math.dart';

/// Labelled-stock line for an order, matching RFID_Flutter `OrderViewModel._buildOrderItem`.
///
/// Metal = net x rate. Rate is today's purity rate when one is available.
/// Making = per gram + fixed making + net x making % + fixed wastage.
/// Per gram is added as an amount, not multiplied by net.
/// Item = stone + diamond + metal + making, or MRP when MRP is above zero.
StockItem priceOrderSelection(StockItem item, {double purityRate = 0}) {
  final extras = _copy(item);
  final gross = _first(item.gross, _read(extras, const ['grosswt', 'grossweight']));
  final stoneWeight = _read(extras, const ['stonewt', 'stoneweight', 'totalstoneweight']);
  final diamondWeight = _read(extras, const ['diamondwt', 'diamondweight', 'totaldiamondweight']);
  var net = _first(item.net, _read(extras, const ['netwt', 'netweight']));
  if (net <= 0) net = gross - stoneWeight - diamondWeight;
  if (net < 0) net = 0;
  final stockRate = _read(extras, const ['rate', 'ratepergram', 'metalrate', 'goldrate', 'todaysrate']);
  final rate = purityRate > 0 ? purityRate : stockRate;
  final metal = net * rate;
  final making = _read(extras, const ['makingpergram']) +
      _read(extras, const ['makingfixedamt', 'fixmaking', 'makingfixed']) +
      (net * _read(extras, const ['makingpercent', 'makingpercentage']) / 100) +
      _read(extras, const ['makingfixedwastage', 'fixwastage']);
  final stone = _read(extras, const ['stoneamt', 'stoneamount', 'totalstoneamount']);
  final diamond = _read(extras, const ['diamondamt', 'diamondamount', 'totaldiamondamount']);
  final hallmark = _read(extras, const ['hallmarkamt', 'hallmarkamount']);
  final mrp = _read(extras, const ['mrp']);
  final amount = mrp > 0 ? mrp : stone + diamond + metal + making;
  _writeAmounts(
    extras,
    gross: gross,
    net: net,
    rate: rate,
    metal: metal,
    making: making,
    stone: stone,
    diamond: diamond,
    hallmark: hallmark,
    amount: amount,
    fineWeight: net * _read(extras, const ['makingpercent', 'makingpercentage']) / 100,
  );
  if (_read(extras, const ['totalwt', 'totalweight']) <= 0 && gross > 0) {
    extras['totalwt'] = _weight(gross);
  }
  extras.putIfAbsent('pieces', () => '1');
  extras.putIfAbsent('quantity', () => '1');
  return _item(item, extras, gross: gross, net: net);
}

/// Gross, net, and fine weight for an edited order line.
///
/// With a total weight, gross is total minus packing unless gross itself is
/// being edited. Net is gross minus stone weight minus diamond weight.
({double gross, double net, double fine}) orderWeightEdit({
  required double total,
  required double packing,
  required double gross,
  required double stone,
  required double diamond,
  required double finePercent,
  required double wastagePercent,
  required bool lockGross,
}) {
  final nextGross = !lockGross && total > 0 ? _clamp(total - packing) : _clamp(gross);
  final net = _clamp(nextGross - stone - diamond);
  return (
    gross: nextGross,
    net: net,
    fine: net * (finePercent + wastagePercent) / 100,
  );
}

double orderExtraNumber(Map<String, String> extras, List<String> keys) => _read(extras, keys);

/// Recalculates an order line the way RFID_Flutter recalculates the order details.
///
/// Gross follows total weight minus packing when a total weight is present.
/// Net = gross - stone weight - diamond weight.
/// Amount = MRP, or net x rate + hallmark + stone amount + diamond amount.
StockItem priceOrderEdit(StockItem item, {bool lockGross = false}) {
  final extras = _copy(item);
  final total = _read(extras, const ['totalwt', 'totalweight']);
  final packing = _read(extras, const ['packingwt', 'packingweight']);
  final typedGross = _first(item.gross, _read(extras, const ['grosswt', 'grossweight']));
  final stoneWeight = _read(extras, const ['stonewt', 'stoneweight', 'totalstoneweight']);
  final diamondWeight = _read(extras, const ['diamondwt', 'diamondweight', 'totaldiamondweight']);
  final finePercent = _read(extras, const ['fineper', 'finepercentage']);
  final wastagePercent = _read(extras, const ['wastage', 'makingpercent', 'makingpercentage']);
  final weights = orderWeightEdit(
    total: total,
    packing: packing,
    gross: typedGross,
    stone: stoneWeight,
    diamond: diamondWeight,
    finePercent: finePercent,
    wastagePercent: wastagePercent,
    lockGross: lockGross,
  );
  final gross = weights.gross;
  final net = weights.net;
  final rate = _read(extras, const ['rate', 'ratepergram', 'metalrate', 'goldrate', 'todaysrate']);
  final hallmark = _read(extras, const ['hallmarkamt', 'hallmarkamount']);
  final stone = _read(extras, const ['stoneamt', 'stoneamount', 'totalstoneamount']);
  final diamond = _read(extras, const ['diamondamt', 'diamondamount', 'totaldiamondamount']);
  final mrp = _read(extras, const ['mrp']);
  final amount = mrp > 0 ? mrp : (net * rate) + hallmark + stone + diamond;
  final making = _read(extras, const ['makingamt', 'makingamount']);
  extras['stonewt'] = _weight(stoneWeight);
  extras['diamondwt'] = _weight(diamondWeight);
  extras['packingwt'] = _weight(packing);
  if (total > 0) extras['totalwt'] = _weight(total);
  _writeAmounts(
    extras,
    gross: gross,
    net: net,
    rate: rate,
    metal: net * rate,
    making: making,
    stone: stone,
    diamond: diamond,
    hallmark: hallmark,
    amount: amount,
    fineWeight: weights.fine,
  );
  return _item(item, extras, gross: gross, net: net);
}

/// Amounts already calculated on the order form, used when the order is saved.
LinePrice orderStoredLine(
  StockItem item, {
  required bool applyGst,
  required double gstFraction,
}) {
  final extras = item.extras;
  final net = _first(item.net, _read(extras, const ['netwt', 'netweight']));
  final metal = _read(extras, const ['metalamt', 'metalamount']);
  final making = _read(extras, const ['makingamt', 'makingamount']);
  final stone = _read(extras, const ['stoneamt', 'stoneamount', 'totalstoneamount']);
  final diamond = _read(extras, const ['diamondamt', 'diamondamount', 'totaldiamondamount']);
  final mrp = _read(extras, const ['mrp']);
  var amount = _read(extras, const ['itemamt', 'itemamount', 'totalitemamount', 'amount']);
  if (amount <= 0) amount = mrp > 0 ? mrp : stone + diamond + metal + making;
  final gst = applyGst && mrp <= 0 ? amount * gstFraction : 0.0;
  return LinePrice(
    net: net,
    metal: metal,
    making: making,
    stone: stone,
    diamond: diamond,
    item: amount,
    gst: gst,
    total: amount + gst,
    mrp: mrp > 0,
  );
}

double orderAmount(StockItem item) {
  final amount = _read(item.extras, const ['itemamt', 'itemamount', 'totalitemamount', 'amount']);
  if (amount > 0) return amount;
  final mrp = _read(item.extras, const ['mrp']);
  return mrp;
}

Map<String, String> _copy(StockItem item) {
  final extras = Map<String, String>.from(item.extras);
  _alias(extras, 'totalstoneweight', 'stonewt');
  _alias(extras, 'stoneweight', 'stonewt');
  _alias(extras, 'totaldiamondweight', 'diamondwt');
  _alias(extras, 'diamondweight', 'diamondwt');
  _alias(extras, 'totalstoneamount', 'stoneamt');
  _alias(extras, 'stoneamount', 'stoneamt');
  _alias(extras, 'totaldiamondamount', 'diamondamt');
  _alias(extras, 'diamondamount', 'diamondamt');
  _alias(extras, 'makingpercentage', 'makingpercent');
  _alias(extras, 'fixmaking', 'makingfixedamt');
  _alias(extras, 'makingfixed', 'makingfixedamt');
  _alias(extras, 'fixwastage', 'makingfixedwastage');
  _alias(extras, 'hallmarkamount', 'hallmarkamt');
  _alias(extras, 'ratepergram', 'rate');
  _alias(extras, 'metalrate', 'rate');
  _alias(extras, 'goldrate', 'rate');
  _alias(extras, 'purityname', 'purity');
  _alias(extras, 'totalweight', 'totalwt');
  _alias(extras, 'packingweight', 'packingwt');
  _alias(extras, 'finepercentage', 'fineper');
  return extras;
}

void _alias(Map<String, String> extras, String from, String to) {
  final value = extras[from];
  if (value != null && value.trim().isNotEmpty) extras.putIfAbsent(to, () => value.trim());
}

void _writeAmounts(
  Map<String, String> extras, {
  required double gross,
  required double net,
  required double rate,
  required double metal,
  required double making,
  required double stone,
  required double diamond,
  required double hallmark,
  required double amount,
  required double fineWeight,
}) {
  extras['grosswt'] = _weight(gross);
  extras['netwt'] = _weight(net);
  extras['rate'] = _money(rate);
  extras['todaysrate'] = _money(rate);
  extras['metalamt'] = _money(metal);
  extras['metalamount'] = _money(metal);
  extras['makingamt'] = _money(making);
  extras['makingamount'] = _money(making);
  extras['stoneamt'] = _money(stone);
  extras['diamondamt'] = _money(diamond);
  extras['hallmarkamt'] = _money(hallmark);
  extras['itemamt'] = _money(amount);
  extras['itemamount'] = _money(amount);
  extras['amount'] = _money(amount);
  extras['finepluswt'] = _weight(fineWeight);
}

StockItem _item(StockItem item, Map<String, String> extras, {required double gross, required double net}) {
  return StockItem(
    itemCode: item.itemCode,
    name: item.name,
    rfid: item.rfid,
    gross: _weight(gross),
    net: _weight(net),
    design: item.design,
    extras: extras,
  );
}

double _read(Map<String, String> extras, List<String> keys) {
  for (final key in keys) {
    final value = double.tryParse((extras[key] ?? '').replaceAll(',', '').trim());
    if (value != null) return value;
  }
  return 0;
}

double _first(String raw, double fallback) {
  final value = double.tryParse(raw.replaceAll(',', '').trim());
  if (value != null && value != 0) return value;
  return fallback;
}

double _clamp(double value) => value < 0 ? 0 : value;

String _money(double value) => value.toStringAsFixed(2);

String _weight(double value) => value.toStringAsFixed(3);
