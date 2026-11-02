import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/constants/app_strings.dart';
import '../../../../core/constants/asset_paths.dart';
import '../../../../core/di/injection.dart';
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

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_signingIn) return;
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() => _signingIn = true);
    final result = await Injection.login(
      LoginParams(
        username: _usernameController.text,
        password: _passwordController.text,
        rememberMe: _rememberUsername,
      ),
    );
    await Future<void>.delayed(const Duration(milliseconds: 700));
    if (!mounted) return;
    switch (result) {
      case Success():
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

  InputDecoration _fieldDecoration({required String hint, Widget? suffix}) {
    final border = OutlineInputBorder(
      borderRadius: const BorderRadius.all(Radius.circular(12)),
      borderSide: const BorderSide(color: AppColors.fieldBorder),
    );
    return InputDecoration(
      filled: true,
      fillColor: AppColors.white,
      hintText: hint,
      hintStyle: _text(fontSize: AppTypography.body, color: AppColors.muted),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      suffixIcon: suffix,
      border: border,
      enabledBorder: border,
      focusedBorder: border.copyWith(
        borderSide: const BorderSide(color: AppColors.goldText, width: 1.4),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final label = _text(
      fontSize: AppTypography.label,
      fontWeight: FontWeight.w600,
      color: AppColors.charcoal,
    );

    return Scaffold(
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
                    style: _text(
                      fontSize: AppTypography.body,
                      color: AppColors.charcoal,
                    ),
                    decoration: _fieldDecoration(hint: AppStrings.usernameHint),
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
                    onSubmitted: (_) => _submit(),
                    style: _text(
                      fontSize: AppTypography.body,
                      color: AppColors.charcoal,
                    ),
                    decoration: _fieldDecoration(
                      hint: AppStrings.passwordHint,
                      suffix: IconButton(
                        tooltip: _passwordVisible
                            ? AppStrings.hidePassword
                            : AppStrings.showPassword,
                        onPressed: () {
                          setState(() => _passwordVisible = !_passwordVisible);
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
                        onPressed: () {},
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
                                    duration: const Duration(milliseconds: 200),
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
    );
  }
}
