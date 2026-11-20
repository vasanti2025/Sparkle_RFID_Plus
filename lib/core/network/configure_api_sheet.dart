import 'package:flutter/material.dart';

import '../constants/app_constants.dart';
import '../constants/app_strings.dart';
import '../locale/feature_strings.dart';
import '../theme/app_colors.dart';
import 'api_host.dart';

Future<void> showConfigureApiSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.homeSurface,
    barrierColor: const Color(0x70151410),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(23)),
    ),
    builder: (context) => const _ConfigureApiDialog(),
  );
}

class _ConfigureApiDialog extends StatefulWidget {
  const _ConfigureApiDialog();

  @override
  State<_ConfigureApiDialog> createState() => _ConfigureApiDialogState();
}

class _ConfigureApiDialogState extends State<_ConfigureApiDialog> {
  late final TextEditingController _url = TextEditingController(text: ApiHost.saved);
  String? _error;
  var _saving = false;

  @override
  void dispose() {
    _url.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (ApiHost.normalize(_url.text) == null) {
      setState(() => _error = tx('invalidApiUrl', AppStrings.invalidApiUrl));
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    final previous = ApiHost.base;
    final ok = await ApiHost.save(_url.text);
    if (!mounted) return;
    if (!ok) {
      setState(() {
        _saving = false;
        _error = tx('invalidApiUrl', AppStrings.invalidApiUrl);
      });
      return;
    }
    final messenger = ScaffoldMessenger.of(context);
    Navigator.pop(context);
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            ApiHost.base == AppConstants.qaBaseUrl && previous != AppConstants.qaBaseUrl
                ? tx('defaultServerRestored', AppStrings.defaultServerRestored)
                : tx('customApiSaved', AppStrings.customApiSaved),
          ),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    final keyboard = MediaQuery.viewInsetsOf(context).bottom;
    return Directionality(
      textDirection: featureDirection,
      child: Padding(
        padding: EdgeInsets.only(bottom: keyboard),
        child: SingleChildScrollView(
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
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 8, 0),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        tx('configureCustomApi', AppStrings.configureCustomApi),
                        style: _style(size: 18, weight: FontWeight.w600),
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close, color: AppColors.charcoal),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      tx('apiUrlAuthorizedMessage', AppStrings.apiUrlAuthorizedMessage),
                      style: _style(size: 13, color: AppColors.muted, height: 1.45),
                    ),
                    const SizedBox(height: 14),
                    Text(
                      tx('enterApiUrl', AppStrings.enterApiUrl),
                      style: _style(size: 13, weight: FontWeight.w600),
                    ),
                    const SizedBox(height: 8),
                    Directionality(
                      textDirection: TextDirection.ltr,
                      child: TextField(
                        controller: _url,
                        keyboardType: TextInputType.url,
                        textDirection: TextDirection.ltr,
                        autocorrect: false,
                        enableSuggestions: false,
                        style: _style(size: 15),
                        decoration: InputDecoration(
                          hintText: AppStrings.customApiUrlHint,
                          errorText: _error,
                          isDense: true,
                          filled: true,
                          fillColor: AppColors.white,
                          enabledBorder: _border(AppColors.fieldBorder),
                          focusedBorder: _border(AppColors.goldText),
                          errorBorder: _border(AppColors.error),
                          focusedErrorBorder: _border(AppColors.error),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: _saving ? null : () => Navigator.pop(context),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.charcoal,
                          minimumSize: const Size.fromHeight(46),
                          side: const BorderSide(color: AppColors.fieldBorder),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                        child: Text(tx('cancel', AppStrings.cancel), style: _style(size: 14, weight: FontWeight.w600)),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton(
                        onPressed: _saving ? null : _save,
                        style: FilledButton.styleFrom(
                          backgroundColor: AppColors.charcoal,
                          foregroundColor: AppColors.white,
                          minimumSize: const Size.fromHeight(46),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                        child: _saving
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.white),
                              )
                            : Text(
                                tx('save', AppStrings.save),
                                style: _style(size: 14, weight: FontWeight.w600, color: AppColors.white),
                              ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  OutlineInputBorder _border(Color color) {
    return OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: BorderSide(color: color),
    );
  }
}

TextStyle _style({
  required double size,
  FontWeight weight = FontWeight.w400,
  Color color = AppColors.charcoal,
  double? height,
}) {
  return TextStyle(
    fontFamily: 'Inter',
    fontFamilyFallback: const <String>[],
    fontSize: size,
    fontWeight: weight,
    color: color,
    height: height,
  );
}
