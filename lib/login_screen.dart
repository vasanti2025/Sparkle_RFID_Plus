import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final TextEditingController _usernameController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  bool _rememberMe = false;
  bool _passwordVisible = false;

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  TextStyle _text({
    double? fontSize,
    FontWeight? fontWeight,
    Color? color,
    double? height,
    double? letterSpacing,
  }) {
    return GoogleFonts.bodoniModa(
      fontSize: fontSize,
      fontWeight: fontWeight,
      color: color,
      height: height,
      letterSpacing: letterSpacing,
    );
  }

  InputDecoration _fieldDecoration({Widget? suffix}) {
    const border = OutlineInputBorder(
      borderRadius: BorderRadius.all(Radius.circular(12)),
      borderSide: BorderSide(color: Color(0xFFDCD8D0)),
    );
    return InputDecoration(
      filled: true,
      fillColor: Colors.white,
      contentPadding: const EdgeInsets.symmetric(horizontal: 15, vertical: 16),
      suffixIcon: suffix,
      border: border,
      enabledBorder: border,
      focusedBorder: const OutlineInputBorder(
        borderRadius: BorderRadius.all(Radius.circular(12)),
        borderSide: BorderSide(color: Color(0xFF94702E), width: 1.4),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final label = _text(
      fontSize: 12,
      fontWeight: FontWeight.w600,
      color: const Color(0xFF20201F),
    );

    return Scaffold(
      backgroundColor: const Color(0xFFF6F5F2),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(11),
                        child: const ColoredBox(
                          color: Color(0xFF111111),
                          child: Padding(
                            padding: EdgeInsets.all(6),
                            child: Image(
                              image: AssetImage(
                                'assets/branding/splash_logo_white.png',
                              ),
                              width: 46,
                              height: 48,
                              fit: BoxFit.contain,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 11),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'SPARKLE RFID',
                              style: _text(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 1.1,
                                color: const Color(0xFF20201F),
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Intelligent jewellery operations',
                              style: _text(
                                fontSize: 10,
                                color: const Color(0xFF6D6B66),
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        onPressed: () {},
                        icon: const Icon(
                          Icons.face_retouching_natural,
                          size: 22,
                        ),
                        color: const Color(0xFF20201F),
                        tooltip: 'Login with Face',
                      ),
                      IconButton(
                        onPressed: () {},
                        icon: const Icon(Icons.help_outline, size: 22),
                        color: const Color(0xFF20201F),
                        tooltip: 'Help',
                      ),
                    ],
                  ),
                  const SizedBox(height: 28),
                  Text(
                    'Welcome back.',
                    style: _text(
                      fontSize: 29,
                      fontWeight: FontWeight.w600,
                      height: 1.12,
                      color: const Color(0xFF20201F),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Sign in to your jewellery workspace.',
                    style: _text(
                      fontSize: 14,
                      height: 1.6,
                      color: const Color(0xFF6D6B66),
                    ),
                  ),
                  const SizedBox(height: 27),
                  Text('Username', style: label),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _usernameController,
                    autocorrect: false,
                    enableSuggestions: false,
                    style: _text(fontSize: 16),
                    decoration: _fieldDecoration(),
                  ),
                  const SizedBox(height: 19),
                  Text('Password', style: label),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _passwordController,
                    obscureText: !_passwordVisible,
                    autocorrect: false,
                    enableSuggestions: false,
                    style: _text(fontSize: 16),
                    decoration: _fieldDecoration(
                      suffix: IconButton(
                        icon: Icon(
                          _passwordVisible
                              ? Icons.visibility_outlined
                              : Icons.visibility_off_outlined,
                          color: const Color(0xFF6D6B66),
                        ),
                        onPressed: () {
                          setState(() => _passwordVisible = !_passwordVisible);
                        },
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      SizedBox(
                        width: 24,
                        height: 24,
                        child: Checkbox(
                          value: _rememberMe,
                          activeColor: const Color(0xFF282825),
                          onChanged: (val) {
                            if (val != null) setState(() => _rememberMe = val);
                          },
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text('Remember Me', style: _text(fontSize: 12)),
                      const Spacer(),
                      Text(
                        'Forgot Password?',
                        style: _text(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: const Color(0xFF866526),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    height: 56,
                    child: FilledButton(
                      onPressed: () {
                        FocusManager.instance.primaryFocus?.unfocus();
                      },
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFF20201E),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(13),
                        ),
                      ),
                      child: Text(
                        'Login',
                        style: _text(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 22),
                  Material(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    child: InkWell(
                      onTap: () {},
                      borderRadius: BorderRadius.circular(12),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 12,
                        ),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: const Color(0xFFDCD8D0)),
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 36,
                              height: 36,
                              decoration: BoxDecoration(
                                color: const Color(0xFFF6F5F2),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: const Icon(
                                Icons.tune,
                                size: 18,
                                color: Color(0xFF866526),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Connection settings',
                                    style: _text(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                      color: const Color(0xFF20201F),
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    'Configure Custom API',
                                    style: _text(
                                      fontSize: 11,
                                      color: const Color(0xFF6D6B66),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const Icon(
                              Icons.chevron_right,
                              size: 20,
                              color: Color(0xFF6D6B66),
                            ),
                          ],
                        ),
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
