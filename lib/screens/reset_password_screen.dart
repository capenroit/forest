import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'login_screen.dart';

/// Where the user lands after opening the recovery link from their email.
///
/// Supabase has already exchanged the link for a short-lived session by the
/// time this screen is shown, so [GoTrueClient.updateUser] is all that's
/// needed to set the new password. The session is deliberately torn down
/// afterwards so the user signs in again with the new credentials — that also
/// refreshes the cached offline password on the login screen.
class ResetPasswordScreen extends StatefulWidget {
  const ResetPasswordScreen({super.key});

  @override
  State<ResetPasswordScreen> createState() => _ResetPasswordScreenState();
}

class _ResetPasswordScreenState extends State<ResetPasswordScreen> {
  static const _accent = Color.fromARGB(255, 0, 176, 80);

  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();

  bool _isLoading = false;
  bool _obscurePassword = true;
  bool _obscureConfirm = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _passwordController.addListener(_validate);
    _confirmController.addListener(_validate);
  }

  @override
  void dispose() {
    _passwordController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  /// Mirrors the rules the signup screen enforces, so a password accepted
  /// here would also have been accepted at registration.
  void _validate() {
    final password = _passwordController.text;
    final confirm = _confirmController.text;

    setState(() {
      if (password.isNotEmpty && password.length < 8) {
        _error = 'Password must be at least 8 characters';
      } else if (confirm.isNotEmpty && password != confirm) {
        _error = 'Passwords do not match';
      } else {
        _error = null;
      }
    });
  }

  bool get _canSubmit =>
      !_isLoading &&
      _error == null &&
      _passwordController.text.length >= 8 &&
      _passwordController.text == _confirmController.text;

  Future<void> _handleSubmit() async {
    if (!_canSubmit) return;

    setState(() => _isLoading = true);

    try {
      await Supabase.instance.client.auth.updateUser(
        UserAttributes(password: _passwordController.text),
      );

      // Force a fresh sign-in rather than riding the recovery session, so
      // the login screen re-caches the new password for offline use.
      await Supabase.instance.client.auth.signOut();

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Password updated. Please sign in.'),
          backgroundColor: Colors.green,
          duration: Duration(seconds: 3),
        ),
      );

      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const LoginScreen()),
        (route) => false,
      );
    } on AuthException catch (error) {
      if (!mounted) return;
      // The recovery link is single-use and short-lived, so an expired one is
      // the most likely failure here — say so rather than showing the raw
      // "invalid claim" style message.
      setState(() => _error = error.message);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(error.message),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 4),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not update password: $error'),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 4),
        ),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final screenWidth = media.size.width;
    final keyboardBottom = media.viewInsets.bottom;
    final cardWidth = screenWidth < 560 ? screenWidth - 28 : 430.0;

    return Scaffold(
      backgroundColor: const Color.fromARGB(255, 20, 99, 78),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) => SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(14, 12, 14, 16 + keyboardBottom),
            child: ConstrainedBox(
              constraints:
                  BoxConstraints(minHeight: constraints.maxHeight - 20),
              child: Center(
                child: Container(
                  width: cardWidth,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 22, vertical: 24),
                  decoration: BoxDecoration(
                    color: const Color(0xFFB7D2C8),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text(
                        'Set a new password',
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF253033),
                        ),
                      ),
                      const SizedBox(height: 6),
                      const Text(
                        'Choose a password of at least 8 characters.',
                        style: TextStyle(
                          fontSize: 15,
                          color: Color(0xFF475356),
                        ),
                      ),
                      const SizedBox(height: 22),
                      _buildLabel('New Password'),
                      const SizedBox(height: 10),
                      _buildPasswordField(
                        controller: _passwordController,
                        hintText: 'Enter your new password',
                        obscure: _obscurePassword,
                        onToggle: () => setState(
                          () => _obscurePassword = !_obscurePassword,
                        ),
                      ),
                      const SizedBox(height: 18),
                      _buildLabel('Confirm Password'),
                      const SizedBox(height: 10),
                      _buildPasswordField(
                        controller: _confirmController,
                        hintText: 'Re-enter your new password',
                        obscure: _obscureConfirm,
                        onToggle: () => setState(
                          () => _obscureConfirm = !_obscureConfirm,
                        ),
                        onSubmitted: (_) => _handleSubmit(),
                      ),
                      if (_error != null) ...[
                        const SizedBox(height: 10),
                        Text(
                          _error!,
                          style: const TextStyle(
                            color: Color(0xFFB3261E),
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                      const SizedBox(height: 22),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: _canSubmit ? _handleSubmit : null,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _accent,
                            disabledBackgroundColor:
                                _accent.withValues(alpha: 0.55),
                            elevation: 0,
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          // Same trick as the Sign In button: keep the label
                          // laid out so the button doesn't change height when
                          // the spinner appears.
                          child: Stack(
                            alignment: Alignment.center,
                            children: [
                              Opacity(
                                opacity: _isLoading ? 0 : 1,
                                child: const Text(
                                  'Update Password',
                                  style: TextStyle(
                                    fontSize: 22,
                                    fontWeight: FontWeight.w500,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                              if (_isLoading)
                                const SizedBox(
                                  height: 22,
                                  width: 22,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2.4,
                                    color: Colors.white,
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Center(
                        child: TextButton(
                          onPressed: _isLoading
                              ? null
                              : () async {
                                  await Supabase.instance.client.auth
                                      .signOut();
                                  if (!context.mounted) return;
                                  Navigator.of(context).pushAndRemoveUntil(
                                    MaterialPageRoute(
                                      builder: (_) => const LoginScreen(),
                                    ),
                                    (route) => false,
                                  );
                                },
                          child: const Text(
                            'Back to sign in',
                            style: TextStyle(
                              color: Color(0xFF1F674E),
                              fontWeight: FontWeight.w600,
                              fontSize: 15,
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
        ),
      ),
    );
  }

  Widget _buildLabel(String text) => Text(
        text,
        style: const TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.w600,
          color: Color(0xFF253033),
        ),
      );

  Widget _buildPasswordField({
    required TextEditingController controller,
    required String hintText,
    required bool obscure,
    required VoidCallback onToggle,
    ValueChanged<String>? onSubmitted,
  }) {
    return TextField(
      controller: controller,
      obscureText: obscure,
      enabled: !_isLoading,
      onSubmitted: onSubmitted,
      decoration: InputDecoration(
        hintText: hintText,
        hintStyle: const TextStyle(color: Color(0xFF5A5D60)),
        filled: true,
        fillColor: const Color(0xFFE4E8E7),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        prefixIcon: const Icon(Icons.lock, color: _accent),
        suffixIcon: IconButton(
          onPressed: onToggle,
          icon: Icon(
            obscure ? Icons.visibility_off : Icons.visibility,
            color: _accent,
          ),
        ),
      ),
    );
  }
}
