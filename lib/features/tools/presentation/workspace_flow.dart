import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/constants/app_strings.dart';
import '../../../core/di/injection.dart';
import '../../../core/theme/app_colors.dart';
import '../../auth/presentation/pages/login_page.dart';
import '../../find/presentation/pages/find_jewellery_page.dart';
import '../../inventory/presentation/pages/inventory_page.dart';
import '../../orders/presentation/pages/orders_page.dart';
import '../../products/presentation/pages/products_page.dart';
import '../../transfers/presentation/pages/transfer_page.dart';

class WorkspaceModule {
  const WorkspaceModule(this.name, this.icon, this.group);

  final String name;
  final IconData icon;
  final String group;
}

const workspaceModules = <WorkspaceModule>[
  WorkspaceModule(AppStrings.products, Icons.diamond_outlined, AppStrings.groupStock),
  WorkspaceModule(AppStrings.inventory, Icons.layers_outlined, AppStrings.groupStock),
  WorkspaceModule(AppStrings.search, Icons.search, AppStrings.groupStock),
  WorkspaceModule(AppStrings.orders, Icons.receipt_long_outlined, AppStrings.groupBusiness),
  WorkspaceModule(AppStrings.quotations, Icons.description_outlined, AppStrings.groupBusiness),
  WorkspaceModule(AppStrings.estimations, Icons.calculate_outlined, AppStrings.groupBusiness),
  WorkspaceModule(AppStrings.grn, Icons.inventory_2_outlined, AppStrings.groupOperations),
  WorkspaceModule(AppStrings.transfers, Icons.swap_horiz, AppStrings.groupOperations),
  WorkspaceModule(AppStrings.sampleIn, Icons.move_to_inbox_outlined, AppStrings.groupOperations),
  WorkspaceModule(AppStrings.sampleOut, Icons.outbox_outlined, AppStrings.groupOperations),
  WorkspaceModule(AppStrings.deliveryChallan, Icons.local_shipping_outlined, AppStrings.groupOperations),
  WorkspaceModule(AppStrings.reports, Icons.show_chart, AppStrings.groupBusiness),
  WorkspaceModule(AppStrings.labelTodayRate, Icons.trending_up, AppStrings.groupBusiness),
  WorkspaceModule(AppStrings.settings, Icons.settings_outlined, AppStrings.groupWorkspace),
];

void openSparkleModule(BuildContext context, String module, {bool replaceSheet = false}) {
  final navigator = Navigator.of(context);
  void openPage(Widget page) {
    if (replaceSheet) navigator.pop();
    navigator.push(MaterialPageRoute<void>(builder: (_) => page));
  }

  void openSheet(void Function(BuildContext host) show) {
    if (!replaceSheet) {
      show(context);
      return;
    }
    navigator.pop();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!navigator.mounted) return;
      show(navigator.context);
    });
  }

  switch (module) {
    case AppStrings.products:
      openPage(const ProductsPage());
    case AppStrings.inventory:
      openPage(const InventoryPage());
    case AppStrings.search:
      openSheet(showFindJewellery);
    case AppStrings.orders:
      openPage(const OrdersPage());
    case AppStrings.transfers:
    case AppStrings.stockTransfer:
      openPage(const TransferPage());
    case AppStrings.settings:
      openSheet(showSettingsSheet);
    default:
      openSheet((host) => showModulePreview(host, module));
  }
}

void showAllTools(BuildContext context) {
  var group = '';
  final children = <Widget>[];
  for (final module in workspaceModules) {
    if (group != module.group) {
      group = module.group;
      children.add(
        Padding(
          padding: const EdgeInsets.only(top: 16, bottom: 4),
          child: Text(
            module.group,
            style: _text(size: 10, color: const Color(0xFF746F62), letterSpacing: 1),
          ),
        ),
      );
    }
    children.add(
      InkWell(
        onTap: () => openSparkleModule(context, module.name, replaceSheet: true),
        child: Container(
          constraints: const BoxConstraints(minHeight: 54),
          decoration: const BoxDecoration(
            border: Border(bottom: BorderSide(color: Color(0xFFE8E3D9))),
          ),
          child: Row(
            children: [
              Icon(module.icon, size: 20, color: const Color(0xFF7B622F)),
              const SizedBox(width: 14),
              Expanded(child: Text(module.name, style: _text(size: 13, weight: FontWeight.w600))),
              const Icon(Icons.chevron_right, size: 16, color: Color(0xFF8F897B)),
            ],
          ),
        ),
      ),
    );
  }
  _sheet(context, AppStrings.allToolsTitle, Column(children: children));
}

void showModulePreview(BuildContext context, String module) {
  final icon = workspaceModules
      .where((item) => item.name == module)
      .map((item) => item.icon)
      .firstOrNull ??
      Icons.inventory_2_outlined;
  final steps = _steps[module] ?? const <String>[];
  final note = module == AppStrings.labelTodayRate
      ? AppStrings.labelTodayNote
      : '${AppStrings.connectsExisting} ${module.toLowerCase()} ${AppStrings.existingWorkflow}';
  _sheet(
    context,
    module,
    Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
          decoration: BoxDecoration(
            color: const Color(0xFFEFEBE2),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(AppStrings.moduleEntryPreview, style: _text(size: 10, color: const Color(0xFF706247))),
        ),
        const SizedBox(height: 15),
        Container(
          width: 62,
          height: 62,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: const Color(0xFFEDE6D6),
            borderRadius: BorderRadius.circular(18),
          ),
          child: Icon(icon, color: const Color(0xFF87652A), size: 29),
        ),
        if (steps.isNotEmpty) ...[
          const SizedBox(height: 17),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final step in steps)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                  decoration: BoxDecoration(
                    color: const Color(0xFFEEEADF),
                    borderRadius: BorderRadius.circular(7),
                  ),
                  child: Text(step, style: _text(size: 10, color: const Color(0xFF6C5C39))),
                ),
            ],
          ),
        ],
        const SizedBox(height: 17),
        Text(note, style: _text(size: 13, color: const Color(0xFF6D6B66), height: 1.5)),
        const SizedBox(height: 16),
        FilledButton(
          onPressed: () => Navigator.pop(context),
          style: FilledButton.styleFrom(
            backgroundColor: const Color(0xFF20201E),
            foregroundColor: AppColors.white,
            minimumSize: const Size.fromHeight(52),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
          child: const Text(AppStrings.backToWorkspace),
        ),
      ],
    ),
  );
}

void showAccountSheet(BuildContext context) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: const Color(0xFFFAF9F7),
    barrierColor: const Color(0x70151410),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(23)),
    ),
    builder: (sheetContext) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(22, 0, 22, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 11),
            Center(
              child: Container(
                width: 33,
                height: 4,
                decoration: BoxDecoration(
                  color: const Color(0xFFD3CFC6),
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
            ),
            Row(
              children: [
                Expanded(
                  child: Text(
                    AppStrings.yourAccount,
                    style: _text(size: 20, weight: FontWeight.w600, letterSpacing: -0.6),
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.pop(sheetContext),
                  icon: const Icon(Icons.close, size: 20, color: Color(0xFF20201E)),
                  style: IconButton.styleFrom(
                    fixedSize: const Size(48, 48),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    side: const BorderSide(color: Color(0xFFB18332), width: 1.5),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            _symbol(Icons.person_outline),
            Text(
              '${AppStrings.demoWorkspace}\n${AppStrings.brandName}',
              style: _text(size: 13, color: const Color(0xFF6D6B66), height: 1.65),
            ),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: () => _signOut(sheetContext),
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF20201E),
                foregroundColor: AppColors.white,
                minimumSize: const Size.fromHeight(56),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(13)),
                textStyle: _text(size: 15, weight: FontWeight.w600, color: AppColors.white),
              ),
              child: const Text(AppStrings.signOut),
            ),
          ],
        ),
      );
    },
  );
}

void showSettingsSheet(BuildContext context) {
  _sheet(
    context,
    AppStrings.settings,
    Column(
      children: [
        _settingsRow(context, AppStrings.readerConnection, Icons.wifi_tethering, _reader),
        _settingsRow(context, AppStrings.serverConnection, Icons.settings_outlined, _connection),
        _settingsRow(context, AppStrings.helpSupport, Icons.help_outline, _support),
        _settingsRow(context, AppStrings.signOut, Icons.logout, _signOut),
      ],
    ),
  );
}

const _steps = <String, List<String>>{
  AppStrings.sampleOut: [
    AppStrings.stepSelectRecipient,
    AppStrings.stepScanItems,
    AppStrings.stepReviewMovement,
  ],
  AppStrings.sampleIn: [
    AppStrings.stepSelectReturn,
    AppStrings.stepScanItems,
    AppStrings.stepReviewMovement,
  ],
  AppStrings.reports: [
    AppStrings.stepChooseReport,
    AppStrings.stepChooseScope,
    AppStrings.stepReview,
  ],
  AppStrings.quotations: [
    AppStrings.stepSelectCustomer,
    AppStrings.stepSelectItems,
    AppStrings.stepReviewQuotation,
  ],
  AppStrings.deliveryChallan: [
    AppStrings.stepSelectMovement,
    AppStrings.stepReviewItems,
    AppStrings.stepReviewChallan,
  ],
  AppStrings.labelTodayRate: [AppStrings.stepOpenExisting],
};

Widget _settingsRow(BuildContext context, String label, IconData icon, void Function(BuildContext context) onTap) {
  return InkWell(
    onTap: () => onTap(context),
    child: Container(
      constraints: const BoxConstraints(minHeight: 54),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Color(0xFFE8E3D9))),
      ),
      child: Row(
        children: [
          Icon(icon, size: 20, color: const Color(0xFF7B622F)),
          const SizedBox(width: 14),
          Expanded(child: Text(label, style: _text(size: 13, weight: FontWeight.w600))),
          const Icon(Icons.chevron_right, size: 16, color: Color(0xFF8F897B)),
        ],
      ),
    ),
  );
}

void _reader(BuildContext context) {
  final navigator = Navigator.of(context);
  navigator.pop();
  WidgetsBinding.instance.addPostFrameCallback((_) {
    if (!navigator.mounted) return;
    _sheet(
      navigator.context,
      AppStrings.readerConnection,
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _symbol(Icons.wifi_tethering),
          Text(AppStrings.readerReadyNote, style: _text(size: 13, color: const Color(0xFF6D6B66), height: 1.5)),
          const SizedBox(height: 16),
          _primary(AppStrings.checkReaderConnection, () {
            Navigator.pop(navigator.context);
            ScaffoldMessenger.of(navigator.context)
              ..hideCurrentSnackBar()
              ..showSnackBar(const SnackBar(content: Text(AppStrings.demoReaderReady)));
          }),
          const SizedBox(height: 8),
          Text(AppStrings.simulatedHardware, style: _text(size: 11, color: const Color(0xFF817866))),
        ],
      ),
    );
  });
}

void _support(BuildContext context) {
  final navigator = Navigator.of(context);
  navigator.pop();
  WidgetsBinding.instance.addPostFrameCallback((_) {
    if (!navigator.mounted) return;
    _sheet(
      navigator.context,
      AppStrings.hereToHelp,
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _symbol(Icons.help_outline),
          Text(AppStrings.supportNote, style: _text(size: 13, color: const Color(0xFF6D6B66), height: 1.5)),
          const SizedBox(height: 16),
          _primary(AppStrings.emailSupport, () async {
            await Clipboard.setData(const ClipboardData(text: AppStrings.supportEmail));
            if (!navigator.mounted) return;
            ScaffoldMessenger.of(navigator.context)
              ..hideCurrentSnackBar()
              ..showSnackBar(const SnackBar(content: Text(AppStrings.supportEmail)));
          }),
        ],
      ),
    );
  });
}

void _connection(BuildContext context) {
  final navigator = Navigator.of(context);
  navigator.pop();
  WidgetsBinding.instance.addPostFrameCallback((_) {
    if (!navigator.mounted) return;
    _sheet(
      navigator.context,
      AppStrings.connectionSettings,
      const _ConnectionForm(),
    );
  });
}

Future<void> _signOut(BuildContext context) async {
  final navigator = Navigator.of(context);
  navigator.pop();
  if (Injection.ready) {
    await Injection.signOut();
    Injection.productSync.abandon();
  }
  if (!navigator.mounted) return;
  navigator.pushAndRemoveUntil(
    MaterialPageRoute<void>(builder: (_) => const LoginPage()),
    (_) => false,
  );
}

class _ConnectionForm extends StatefulWidget {
  const _ConnectionForm();

  @override
  State<_ConnectionForm> createState() => _ConnectionFormState();
}

class _ConnectionFormState extends State<_ConnectionForm> {
  final _server = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _server.dispose();
    super.dispose();
  }

  void _save() {
    final uri = Uri.tryParse(_server.text.trim());
    final good = uri != null && uri.scheme == 'https' && uri.host.isNotEmpty;
    if (!good) {
      setState(() => _error = AppStrings.validHttps);
      return;
    }
    final messenger = ScaffoldMessenger.of(context);
    Navigator.pop(context);
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(const SnackBar(content: Text(AppStrings.connectionAccepted)));
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(AppStrings.serverAddressNote, style: _text(size: 13, color: const Color(0xFF6D6B66), height: 1.5)),
        const SizedBox(height: 12),
        TextField(
          controller: _server,
          keyboardType: TextInputType.url,
          decoration: InputDecoration(
            labelText: AppStrings.serverAddress,
            hintText: AppStrings.serverHint,
            filled: true,
            fillColor: AppColors.white,
            errorText: _error,
            border: _border(const Color(0xFFD5CBBC)),
            enabledBorder: _border(const Color(0xFFD5CBBC)),
            focusedBorder: _border(const Color(0xFF967431)),
          ),
        ),
        const SizedBox(height: 14),
        _primary(AppStrings.saveConnection, _save),
        const SizedBox(height: 8),
        Text(AppStrings.prototypeOnlyNetwork, style: _text(size: 11, color: const Color(0xFF817866))),
      ],
    );
  }
}

Widget _symbol(IconData icon) {
  return Container(
    width: 62,
    height: 62,
    margin: const EdgeInsets.only(bottom: 17),
    alignment: Alignment.center,
    decoration: BoxDecoration(
      color: const Color(0xFFEDE6D6),
      borderRadius: BorderRadius.circular(18),
    ),
    child: Icon(icon, color: const Color(0xFF87652A), size: 29),
  );
}

Widget _primary(String label, VoidCallback onPressed) {
  return FilledButton(
    onPressed: onPressed,
    style: FilledButton.styleFrom(
      backgroundColor: const Color(0xFF20201E),
      foregroundColor: AppColors.white,
      minimumSize: const Size.fromHeight(52),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
    child: Text(label),
  );
}

void _sheet(BuildContext context, String title, Widget body) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: const Color(0xFFFAF9F7),
    barrierColor: const Color(0x70151410),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(23)),
    ),
    builder: (context) {
      return Padding(
        padding: EdgeInsets.fromLTRB(22, 0, 22, 20 + MediaQuery.viewInsetsOf(context).bottom),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 11),
              Center(
                child: Container(
                  width: 33,
                  height: 4,
                  decoration: BoxDecoration(
                    color: const Color(0xFFD3CFC6),
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
              ),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      title,
                      style: _text(size: 20, weight: FontWeight.w600, letterSpacing: -0.6),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close, size: 20),
                  ),
                ],
              ),
              body,
            ],
          ),
        ),
      );
    },
  );
}

OutlineInputBorder _border(Color color) {
  return OutlineInputBorder(
    borderRadius: const BorderRadius.all(Radius.circular(10)),
    borderSide: BorderSide(color: color),
  );
}

TextStyle _text({
  required double size,
  FontWeight weight = FontWeight.w400,
  Color color = const Color(0xFF20201F),
  double? height,
  double? letterSpacing,
}) {
  return TextStyle(
    fontFamily: 'Inter',
    fontFamilyFallback: const <String>[],
    fontSize: size,
    fontWeight: weight,
    color: color,
    height: height,
    letterSpacing: letterSpacing,
    decoration: TextDecoration.none,
  );
}
