import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../domain/entities/stock_item.dart';
import '../../domain/quotation_math.dart';

Future<void> showQuotationItemsPopup(
  BuildContext context, {
  required List<StockItem> items,
  required bool gstApplied,
  required double gstFraction,
}) {
  if (items.isEmpty) return Future.value();
  return showDialog<void>(
    context: context,
    barrierDismissible: true,
    useRootNavigator: true,
    builder: (_) => _QuotationItemsPopup(
      items: items,
      gstApplied: gstApplied,
      gstFraction: gstFraction,
    ),
  );
}

class _QuotationItemsPopup extends StatefulWidget {
  const _QuotationItemsPopup({
    required this.items,
    required this.gstApplied,
    required this.gstFraction,
  });

  final List<StockItem> items;
  final bool gstApplied;
  final double gstFraction;

  @override
  State<_QuotationItemsPopup> createState() => _QuotationItemsPopupState();
}

class _QuotationItemsPopupState extends State<_QuotationItemsPopup> {
  int? _detailIndex;
  PageController? _pages;

  bool get _showingDetail => _detailIndex != null || widget.items.length == 1;

  int get _activeIndex {
    if (widget.items.length == 1) return 0;
    return _detailIndex ?? 0;
  }

  void _open(int index) {
    _pages?.dispose();
    _pages = PageController(initialPage: index);
    setState(() => _detailIndex = index);
  }

  void _back() {
    _pages?.dispose();
    _pages = null;
    setState(() => _detailIndex = null);
  }

  @override
  void dispose() {
    _pages?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final landscape = size.width > size.height;
    final height = _showingDetail ? size.height * 0.86 : size.height * (landscape ? 0.72 : 0.58);
    return Dialog(
      backgroundColor: const Color(0xFFF7F5F6),
      insetPadding: EdgeInsets.symmetric(horizontal: landscape ? 12 : 14, vertical: landscape ? 12 : 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: SizedBox(
          width: size.width,
          height: height,
          child: Column(
            children: [
              _header(),
              Expanded(child: _showingDetail ? _detail() : _list()),
              _footer(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _header() {
    final canGoBack = _detailIndex != null && widget.items.length > 1;
    final item = widget.items[_activeIndex];
    final title = canGoBack
        ? 'Item Details'
        : (_showingDetail ? 'Scanned Item' : 'Scanned Items');
    final subtitle = _showingDetail
        ? (canGoBack
              ? '${_activeIndex + 1} / ${widget.items.length}  ·  ${_code(item)}'
              : _code(item))
        : '${widget.items.length} item${widget.items.length == 1 ? '' : 's'} found';
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(8, 10, 8, 10),
      child: Row(
        children: [
          if (canGoBack)
            IconButton(
              tooltip: 'Back',
              onPressed: _back,
              icon: Icon(Icons.arrow_back_rounded, color: Colors.grey.shade800),
            )
          else
            Container(
              margin: const EdgeInsets.only(left: 8),
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppColors.goldText.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.qr_code_scanner, color: AppColors.goldText, size: 20),
            ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: AppColors.goldText)),
                Text(subtitle, style: TextStyle(fontSize: 12, color: Colors.grey.shade600, fontWeight: FontWeight.w500)),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Close',
            onPressed: () => Navigator.of(context).pop(),
            icon: Icon(Icons.close_rounded, color: Colors.grey.shade700),
          ),
        ],
      ),
    );
  }

  Widget _footer() {
    return Container(
      width: double.infinity,
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
      child: ElevatedButton(
        onPressed: () => Navigator.of(context).pop(),
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.charcoal,
          foregroundColor: Colors.white,
          elevation: 0,
          minimumSize: const Size.fromHeight(44),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
        child: const Text('Done', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
      ),
    );
  }

  Widget _list() {
    final width = MediaQuery.sizeOf(context).width * 0.58;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: widget.items.length,
        separatorBuilder: (_, _) => const SizedBox(width: 12),
        itemBuilder: (context, index) {
          return SizedBox(
            width: width,
            child: _ItemCard(
              item: widget.items[index],
              gstApplied: widget.gstApplied,
              gstFraction: widget.gstFraction,
              onTap: () => _open(index),
            ),
          );
        },
      ),
    );
  }

  Widget _detail() {
    if (widget.items.length == 1) {
      return _detailPage(widget.items.first);
    }
    final controller = _pages;
    if (controller == null) return _detailPage(widget.items[_activeIndex]);
    return PageView.builder(
      controller: controller,
      itemCount: widget.items.length,
      onPageChanged: (index) => setState(() => _detailIndex = index),
      itemBuilder: (context, index) => _detailPage(widget.items[index]),
    );
  }

  Widget _detailPage(StockItem item) {
    final view = _ItemView(item, gstApplied: widget.gstApplied, gstFraction: widget.gstFraction);
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      child: Column(
        children: [
          SizedBox(height: 180, child: _ItemImage(url: view.imageUrl, expand: true)),
          const SizedBox(height: 8),
          Text(_code(item), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: AppColors.goldText)),
          if (view.product.isNotEmpty)
            Text(view.product, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.grey.shade800)),
          const SizedBox(height: 8),
          Expanded(
            child: GridView.builder(
              padding: EdgeInsets.zero,
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                mainAxisExtent: 46,
                crossAxisSpacing: 8,
                mainAxisSpacing: 6,
              ),
              itemCount: view.details.length,
              itemBuilder: (context, index) {
                final row = view.details[index];
                return Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8F5F6),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(row.$1, style: TextStyle(fontSize: 10, color: Colors.grey.shade600, height: 1)),
                      Text(
                        row.$2,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, height: 1.15),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 8),
          _totalBar(view.totalLabel),
        ],
      ),
    );
  }

  Widget _totalBar(String amount) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.goldText.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.goldText.withValues(alpha: 0.25)),
      ),
      child: Row(
        children: [
          const Text('TOTAL AMT', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: AppColors.goldText)),
          const Spacer(),
          Text(amount, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: AppColors.goldText)),
        ],
      ),
    );
  }

  String _code(StockItem item) {
    final code = item.itemCode.trim();
    if (code.isEmpty) return item.rfid.trim();
    return code.split('/').first.trim();
  }
}

class _ItemCard extends StatelessWidget {
  const _ItemCard({
    required this.item,
    required this.gstApplied,
    required this.gstFraction,
    required this.onTap,
  });

  final StockItem item;
  final bool gstApplied;
  final double gstFraction;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final view = _ItemView(item, gstApplied: gstApplied, gstFraction: gstFraction);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.grey.shade200),
            boxShadow: [
              BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 10, offset: const Offset(0, 3)),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  flex: 3,
                  child: ColoredBox(color: const Color(0xFFEDE8EA), child: _ItemImage(url: view.imageUrl)),
                ),
                Expanded(
                  flex: 4,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          view.code,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: AppColors.goldText),
                        ),
                        if (view.product.isNotEmpty)
                          Text(
                            view.product,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.grey.shade800),
                          ),
                        const SizedBox(height: 4),
                        Expanded(
                          child: ListView(
                            physics: const BouncingScrollPhysics(),
                            padding: EdgeInsets.zero,
                            children: [
                              for (final row in view.cardRows) _pair(row.$1, row.$2),
                            ],
                          ),
                        ),
                        Row(
                          children: [
                            const Text('Total', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: AppColors.goldText)),
                            const Spacer(),
                            Text(view.totalLabel, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: AppColors.goldText)),
                          ],
                        ),
                        const Text('Tap · swipe for next', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: AppColors.goldText)),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _pair(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Row(
        children: [
          Expanded(child: Text(label, style: TextStyle(fontSize: 10, color: Colors.grey.shade600))),
          Text(value, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}

class _ItemImage extends StatelessWidget {
  const _ItemImage({required this.url, this.expand = false});

  final String? url;
  final bool expand;

  @override
  Widget build(BuildContext context) {
    if (url == null) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.image_outlined, size: 48, color: AppColors.muted),
            SizedBox(height: 6),
            Text('No image', style: TextStyle(fontSize: 12, color: AppColors.muted, fontWeight: FontWeight.w500)),
          ],
        ),
      );
    }
    final image = Image.network(
      url!,
      fit: expand ? BoxFit.contain : BoxFit.cover,
      width: double.infinity,
      height: double.infinity,
      errorBuilder: (_, _, _) => const Center(
        child: Icon(Icons.image_outlined, size: 48, color: AppColors.muted),
      ),
    );
    return expand ? SizedBox.expand(child: image) : image;
  }
}

class _ItemView {
  _ItemView(this.item, {required this.gstApplied, required this.gstFraction})
    : line = priceLine(item, applyGst: gstApplied, gstFraction: gstFraction);

  final StockItem item;
  final bool gstApplied;
  final double gstFraction;
  final LinePrice line;

  String get code {
    final value = item.itemCode.trim();
    if (value.isEmpty) return item.rfid.trim();
    return value.split('/').first.trim();
  }

  String get product {
    final named = _text(const ['productname', 'name']);
    if (named.isNotEmpty) return named;
    return item.name.trim();
  }

  String? get imageUrl {
    for (final key in const ['images', 'image', 'imageurl', 'productimage', 'itemimage', 'photo', 'imagepath']) {
      final raw = item.extras[key];
      if (raw == null || raw.trim().isEmpty || raw.trim().toLowerCase() == 'null') continue;
      final match = RegExp(r'https?://[^\s"<>\],]+').firstMatch(raw);
      if (match != null) return match.group(0);
    }
    return null;
  }

  String get totalLabel {
    final hallmark = _num(const ['hallmarkamt', 'hallmarkamount']);
    final total = line.mrp ? line.total : line.total + hallmark;
    return '₹ ${total.toStringAsFixed(2)}';
  }

  List<(String, String)> get details {
    final rows = <(String, String)>[
      ('RFID Code', item.rfid.trim()),
      ('Category', _text(const ['categoryname', 'category'])),
      ('Design', item.design.trim().isNotEmpty ? item.design.trim() : _text(const ['designname', 'design'])),
      ('Purity', _text(const ['purity'])),
      ('Gr. Wt', _weight(_text(const ['grosswt', 'grossweight']), item.gross, 'g')),
      ('Net Wt', '${line.weight(line.net)} g'),
      ('Stone Wt', _weight(_text(const ['stonewt', 'stoneweight']), '', 'cts')),
      ('Diamond Wt', _weight(_text(const ['diamondwt', 'diamondweight']), '', 'cts')),
      ('Metal Amt', _money(line.metal)),
      ('Stone Amt', _money(line.stone)),
      ('Diamond Amt', _money(line.diamond)),
      ('Rate', _money(_num(const ['rate', 'metalrate', 'goldrate']))),
      ('Making Amt', _money(line.making)),
      ('Hallmark Amt', _money(_num(const ['hallmarkamt', 'hallmarkamount']))),
      ('GST Amt', _money(line.gst)),
    ];
    return [for (final row in rows) if (row.$2.isNotEmpty && row.$2 != '₹ 0.00') row];
  }

  List<(String, String)> get cardRows {
    final wanted = {'Design', 'Purity', 'Gr. Wt', 'Net Wt', 'Metal Amt', 'Making Amt', 'GST Amt'};
    return [for (final row in details) if (wanted.contains(row.$1)) row];
  }

  String _text(List<String> keys) {
    for (final key in keys) {
      final value = item.extras[key];
      if (value != null && value.trim().isNotEmpty && value.trim().toLowerCase() != 'null') {
        return value.trim();
      }
    }
    return '';
  }

  double _num(List<String> keys) => double.tryParse(_text(keys).replaceAll(',', '')) ?? 0;

  String _money(double value) => '₹ ${value.toStringAsFixed(2)}';

  String _weight(String raw, String fallback, String unit) {
    final value = raw.isNotEmpty ? raw : fallback.trim();
    if (value.isEmpty) return '';
    return value.toLowerCase().contains(unit) ? value : '$value $unit';
  }
}
