import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/constants/app_strings.dart';
import '../../../../core/constants/asset_paths.dart';
import '../../../../core/di/injection.dart';
import '../../../../core/session/app_session.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/utils/result.dart';
import '../../../home/presentation/pages/home_page.dart';
import '../../domain/usecases/login.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final TextEditingController _usernameController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  bool _rememberUsername = false;
  bool _passwordVisible = false;
  bool _signingIn = false;
  String? _usernameError;
  String? _passwordError;

  @override
  void initState() {
    super.initState();
    _restoreUsername();
  }

  Future<void> _restoreUsername() async {
    if (!Injection.ready) return;
    final saved = await Injection.rememberedUsername();
    final password = await Injection.rememberedUsername.password();
    if (!mounted) return;
    if ((saved == null || saved.isEmpty) && (password == null || password.isEmpty)) {
      return;
    }
    setState(() {
      if (saved != null && saved.isNotEmpty) _usernameController.text = saved;
      if (password != null && password.isNotEmpty) {
        _passwordController.text = password;
      }
      _rememberUsername = true;
    });
  }

  bool _validate() {
    final usernameError = _usernameController.text.isEmpty
        ? AppStrings.usernameRequired
        : null;
    final passwordError = _passwordController.text.isEmpty
        ? AppStrings.passwordRequired
        : null;
    setState(() {
      _usernameError = usernameError;
      _passwordError = passwordError;
    });
    return usernameError == null && passwordError == null;
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  void _showResetPassword() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFFFAF9F7),
      barrierColor: const Color(0x70151410),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(23)),
      ),
      builder: (_) => const _ResetPasswordSheet(),
    );
  }

  Future<void> _submit() async {
    if (_signingIn) return;
    FocusManager.instance.primaryFocus?.unfocus();
    if (!_validate()) return;
    setState(() => _signingIn = true);
    final result = await Injection.login(
      LoginParams(
        username: _usernameController.text,
        password: _passwordController.text,
        rememberMe: _rememberUsername,
      ),
    );
    if (!mounted) return;
    switch (result) {
      case Success(:final data):
        AppSession.apply(
          clientCode: data.clientCode,
          userId: data.id,
          token: data.token,
          branchId: data.branchId,
          branchName: data.branchName,
        );
        final notice = data.notice;
        if (notice != null && notice.isNotEmpty) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text(notice)));
        }
        if (Injection.ready) {
          unawaited(Injection.productSync.start(data));
        }
        Navigator.of(context).pushReplacement(
          MaterialPageRoute<void>(builder: (_) => const HomePage()),
        );
      case Error(:final failure):
        setState(() => _signingIn = false);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(failure.message)));
    }
  }

  TextStyle _text({
    double? fontSize,
    FontWeight? fontWeight,
    Color? color,
    double? height,
    double? letterSpacing,
  }) {
    return GoogleFonts.inter(
      fontSize: fontSize,
      fontWeight: fontWeight,
      color: color,
      height: height,
      letterSpacing: letterSpacing,
    );
  }

  InputDecoration _fieldDecoration({
    required String hint,
    Widget? suffix,
    String? errorText,
  }) {
    final border = OutlineInputBorder(
      borderRadius: const BorderRadius.all(Radius.circular(12)),
      borderSide: const BorderSide(color: AppColors.fieldBorder),
    );
    final errorBorder = border.copyWith(
      borderSide: const BorderSide(color: AppColors.error),
    );
    return InputDecoration(
      filled: true,
      fillColor: AppColors.white,
      hintText: hint,
      hintStyle: _text(fontSize: AppTypography.body, color: AppColors.muted),
      errorText: errorText,
      errorStyle: _text(
        fontSize: AppTypography.brandSubtitle,
        color: AppColors.error,
      ),
      errorMaxLines: 2,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      suffixIcon: suffix,
      border: border,
      enabledBorder: border,
      focusedBorder: border.copyWith(
        borderSide: const BorderSide(color: AppColors.goldText, width: 1.4),
      ),
      errorBorder: errorBorder,
      focusedErrorBorder: errorBorder,
    );
  }

  @override
  Widget build(BuildContext context) {
    final label = _text(
      fontSize: AppTypography.label,
      fontWeight: FontWeight.w600,
      color: AppColors.charcoal,
    );

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Color(0x00000000),
        statusBarIconBrightness: Brightness.dark,
        statusBarBrightness: Brightness.light,
        systemNavigationBarColor: AppColors.white,
        systemNavigationBarIconBrightness: Brightness.dark,
      ),
      child: Scaffold(
        backgroundColor: AppColors.white,
        body: SafeArea(
          child: Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 24, 24, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(14),
                          child: Image.asset(
                            AssetPaths.loginLogo,
                            width: AppTypography.logoMark,
                            height: AppTypography.logoMark,
                            fit: BoxFit.cover,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.centerLeft,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  AppStrings.brandName,
                                  style: _text(
                                    fontSize: AppTypography.brandTitle,
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: 0.3,
                                    height: 1.1,
                                    color: AppColors.charcoal,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  AppStrings.brandTagline,
                                  style: _text(
                                    fontSize: AppTypography.brandSubtitle,
                                    height: 1.2,
                                    color: AppColors.muted,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        IconButton(
                          onPressed: () {},
                          icon: const Icon(
                            Icons.face_retouching_natural,
                            size: 22,
                          ),
                          color: AppColors.charcoal,
                          tooltip: AppStrings.loginWithFace,
                          constraints: const BoxConstraints(
                            minWidth: AppTypography.minTouch,
                            minHeight: AppTypography.minTouch,
                          ),
                        ),
                        IconButton(
                          onPressed: () {},
                          icon: const Icon(Icons.help_outline, size: 22),
                          color: AppColors.charcoal,
                          tooltip: AppStrings.help,
                          constraints: const BoxConstraints(
                            minWidth: AppTypography.minTouch,
                            minHeight: AppTypography.minTouch,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 40),
                    Text(
                      AppStrings.welcomeBack,
                      style: _text(
                        fontSize: AppTypography.screenTitle,
                        fontWeight: FontWeight.w700,
                        height: 1.15,
                        letterSpacing: -0.4,
                        color: AppColors.charcoal,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      AppStrings.signInSubtitle,
                      style: _text(
                        fontSize: AppTypography.body,
                        height: 1.4,
                        color: AppColors.muted,
                      ),
                    ),
                    const SizedBox(height: 32),
                    Text(AppStrings.username, style: label),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _usernameController,
                      autocorrect: false,
                      enableSuggestions: false,
                      textInputAction: TextInputAction.next,
                      onChanged: (_) {
                        if (_usernameError == null) return;
                        setState(() => _usernameError = null);
                      },
                      style: _text(
                        fontSize: AppTypography.body,
                        color: AppColors.charcoal,
                      ),
                      decoration: _fieldDecoration(
                        hint: AppStrings.usernameHint,
                        errorText: _usernameError,
                      ),
                    ),
                    const SizedBox(height: 20),
                    Text(AppStrings.password, style: label),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _passwordController,
                      obscureText: !_passwordVisible,
                      autocorrect: false,
                      enableSuggestions: false,
                      textInputAction: TextInputAction.done,
                      onChanged: (_) {
                        if (_passwordError == null) return;
                        setState(() => _passwordError = null);
                      },
                      onSubmitted: (_) => _submit(),
                      style: _text(
                        fontSize: AppTypography.body,
                        color: AppColors.charcoal,
                      ),
                      decoration: _fieldDecoration(
                        hint: AppStrings.passwordHint,
                        errorText: _passwordError,
                        suffix: IconButton(
                          tooltip: _passwordVisible
                              ? AppStrings.hidePassword
                              : AppStrings.showPassword,
                          onPressed: () {
                            setState(
                              () => _passwordVisible = !_passwordVisible,
                            );
                          },
                          icon: Icon(
                            _passwordVisible
                                ? Icons.visibility_off_outlined
                                : Icons.visibility_outlined,
                            color: AppColors.muted,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        SizedBox(
                          width: AppTypography.minTouch,
                          height: AppTypography.minTouch,
                          child: Checkbox(
                            value: _rememberUsername,
                            activeColor: AppColors.charcoal,
                            side: const BorderSide(
                              color: AppColors.fieldBorder,
                              width: 1.4,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(4),
                            ),
                            onChanged: (value) {
                              if (value != null) {
                                setState(() => _rememberUsername = value);
                              }
                            },
                          ),
                        ),
                        Expanded(
                          child: Text(
                            AppStrings.rememberUsername,
                            maxLines: 2,
                            style: _text(
                              fontSize: AppTypography.label,
                              color: AppColors.charcoal,
                            ),
                          ),
                        ),
                        TextButton(
                          onPressed: _showResetPassword,
                          style: TextButton.styleFrom(
                            foregroundColor: AppColors.goldText,
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                            minimumSize: const Size(
                              AppTypography.minTouch,
                              AppTypography.minTouch,
                            ),
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                          child: Text(
                            AppStrings.forgotPassword,
                            style: _text(
                              fontSize: AppTypography.label,
                              fontWeight: FontWeight.w600,
                              color: AppColors.goldText,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    LayoutBuilder(
                      builder: (context, constraints) {
                        return Center(
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 400),
                            curve: Curves.easeIn,
                            clipBehavior: Clip.antiAlias,
                            width: _signingIn
                                ? AppTypography.mainActionHeight
                                : constraints.maxWidth,
                            height: AppTypography.mainActionHeight,
                            decoration: BoxDecoration(
                              color: AppColors.charcoal,
                              borderRadius: BorderRadius.circular(
                                _signingIn
                                    ? AppTypography.mainActionHeight / 2
                                    : 16,
                              ),
                            ),
                            child: Material(
                              color: Colors.transparent,
                              child: InkWell(
                                onTap: _signingIn ? null : _submit,
                                borderRadius: BorderRadius.circular(
                                  _signingIn
                                      ? AppTypography.mainActionHeight / 2
                                      : 16,
                                ),
                                child: Stack(
                                  alignment: Alignment.center,
                                  children: [
                                    AnimatedOpacity(
                                      duration: const Duration(
                                        milliseconds: 200,
                                      ),
                                      opacity: _signingIn ? 0 : 1,
                                      child: OverflowBox(
                                        maxWidth: constraints.maxWidth,
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Text(
                                              AppStrings.signIn,
                                              style: _text(
                                                color: AppColors.white,
                                                fontSize: AppTypography.body,
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                            const SizedBox(width: 8),
                                            const Icon(
                                              Icons.arrow_forward,
                                              size: 18,
                                              color: AppColors.white,
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                    if (_signingIn)
                                      const SizedBox(
                                        width: 22,
                                        height: 22,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2.4,
                                          color: AppColors.white,
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                    const SizedBox(height: 20),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          AppStrings.needAHand,
                          style: _text(
                            fontSize: AppTypography.label,
                            color: AppColors.muted,
                          ),
                        ),
                        TextButton(
                          onPressed: () {},
                          style: TextButton.styleFrom(
                            foregroundColor: AppColors.goldText,
                            padding: const EdgeInsets.symmetric(horizontal: 4),
                            minimumSize: const Size(
                              AppTypography.minTouch,
                              AppTypography.minTouch,
                            ),
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                          child: Text(
                            AppStrings.contactSupport,
                            style: _text(
                              fontSize: AppTypography.label,
                              fontWeight: FontWeight.w700,
                              color: AppColors.goldText,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    const Divider(
                      height: 1,
                      thickness: 1,
                      color: AppColors.fieldBorder,
                    ),
                    InkWell(
                      onTap: () {},
                      child: SizedBox(
                        height: AppTypography.minTouch,
                        child: Row(
                          children: [
                            const Icon(
                              Icons.tune,
                              size: 18,
                              color: AppColors.muted,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                AppStrings.connectionSettings,
                                style: _text(
                                  fontSize: AppTypography.label,
                                  fontWeight: FontWeight.w500,
                                  color: AppColors.charcoal,
                                ),
                              ),
                            ),
                            const Icon(
                              Icons.chevron_right,
                              size: 20,
                              color: AppColors.muted,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ResetPasswordSheet extends StatefulWidget {
  const _ResetPasswordSheet();

  @override
  State<_ResetPasswordSheet> createState() => _ResetPasswordSheetState();
}

class _ResetPasswordSheetState extends State<_ResetPasswordSheet> {
  final _username = TextEditingController();
  final _focus = FocusNode();
  var _error = '';
  var _preview = false;

  @override
  void dispose() {
    _username.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _continue() {
    if (_username.text.trim().isEmpty) {
      setState(() => _error = AppStrings.enterUsernameToReset);
      _focus.requestFocus();
      return;
    }
    setState(() => _preview = true);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(22, 0, 22, 24 + MediaQuery.viewInsetsOf(context).bottom),
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
                  _preview ? AppStrings.recoveryPreview : AppStrings.resetYourPassword,
                  style: _sheetText(size: 20, weight: FontWeight.w600, letterSpacing: -0.6),
                ),
              ),
              IconButton(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.close, size: 21, color: Color(0xFF20201E)),
              ),
            ],
          ),
          if (_preview) ...[
            Container(
              width: 62,
              height: 62,
              margin: const EdgeInsets.only(bottom: 17),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: const Color(0xFFEDE6D6),
                borderRadius: BorderRadius.circular(18),
              ),
              child: const Icon(Icons.check_circle_outline, color: Color(0xFF87652A), size: 29),
            ),
            Text(
              AppStrings.noRecoverySent,
              style: _sheetText(size: 13, color: AppColors.muted, height: 1.65),
            ),
            const SizedBox(height: 20),
            _continueButton(AppStrings.backToSignIn, () => Navigator.pop(context)),
          ] else ...[
            Text(
              AppStrings.resetPasswordNote,
              style: _sheetText(size: 13, color: AppColors.muted, height: 1.65),
            ),
            const SizedBox(height: 16),
            Text(
              AppStrings.username,
              style: _sheetText(size: 12, weight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _username,
              focusNode: _focus,
              autocorrect: false,
              enableSuggestions: false,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _continue(),
              style: _sheetText(size: 16),
              decoration: InputDecoration(
                hintText: AppStrings.usernameHint,
                hintStyle: _sheetText(size: 16, color: const Color(0xFF77736C)),
                filled: true,
                fillColor: AppColors.white,
                contentPadding: const EdgeInsets.symmetric(horizontal: 15, vertical: 16),
                border: _inputBorder(AppColors.fieldBorder),
                enabledBorder: _inputBorder(AppColors.fieldBorder),
                focusedBorder: _inputBorder(const Color(0xFF94702E)),
              ),
            ),
            if (_error.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                _error,
                style: _sheetText(size: 12, color: const Color(0xFFA22D32), height: 1.5),
              ),
            ],
            const SizedBox(height: 16),
            _continueButton(AppStrings.continueRecovery, _continue),
          ],
        ],
      ),
    );
  }

  Widget _continueButton(String label, VoidCallback onPressed) {
    return FilledButton(
      onPressed: onPressed,
      style: FilledButton.styleFrom(
        backgroundColor: const Color(0xFF20201E),
        foregroundColor: AppColors.white,
        minimumSize: const Size.fromHeight(56),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(13)),
        textStyle: _sheetText(size: 15, weight: FontWeight.w600, color: AppColors.white),
      ),
      child: Text(label),
    );
  }
}

OutlineInputBorder _inputBorder(Color color) {
  return OutlineInputBorder(
    borderRadius: const BorderRadius.all(Radius.circular(12)),
    borderSide: BorderSide(color: color),
  );
}

TextStyle _sheetText({
  required double size,
  FontWeight weight = FontWeight.w400,
  Color color = const Color(0xFF20201F),
  double? height,
  double? letterSpacing,
}) {
  return GoogleFonts.inter(
    fontSize: size,
    fontWeight: weight,
    color: color,
    height: height,
    letterSpacing: letterSpacing,
  );
}
