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
///
/// That recovery session is also what lets this screen check whether the
/// account is allowed to use the app at all before showing the form — see
/// [_ResetPasswordScreenState._checkEligibility].
class ResetPasswordScreen extends StatefulWidget {
  const ResetPasswordScreen({super.key});

  @override
  State<ResetPasswordScreen> createState() => _ResetPasswordScreenState();
}

class _ResetPasswordScreenState extends State<ResetPasswordScreen> {
  static const _accent = Color.fromARGB(255, 0, 176, 80);

  /// Belongs to a separate app that this one doesn't handle sign-in for.
  static const int _swmDivisionTypeId = 3;

  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();

  bool _isLoading = false;
  bool _obscurePassword = true;
  bool _obscureConfirm = true;
  String? _error;

  /// Account gating, resolved once on load before the form is offered.
  bool _isCheckingEligibility = true;

  /// Set when the account exists but isn't allowed to use this app. Terminal
  /// — there is nothing the user can do here but go back.
  String? _blockedMessage;

  /// Set when the check itself failed (offline, server error). Retryable, and
  /// deliberately distinct from [_blockedMessage] so a flaky connection never
  /// reads as a rejection.
  String? _checkError;

  @override
  void initState() {
    super.initState();
    _passwordController.addListener(_validate);
    _confirmController.addListener(_validate);
    _checkEligibility();
  }

  @override
  void dispose() {
    _passwordController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  /// Applies the same two gates the login screen enforces after a successful
  /// sign-in (see `_handleSignIn` in login_screen.dart): division 3 (SWM)
  /// belongs to a separate app, and a non-Active account can't be used here.
  ///
  /// Without this the reset flow would happily let such a user set a new
  /// password and only turn them away afterwards, at sign-in.
  ///
  /// This can only be done here, not at the point the reset email is
  /// requested: there the user isn't authenticated, so RLS won't return their
  /// row — and checking would leak whether an account exists, which the
  /// deliberately generic "if an account exists…" message avoids.
  Future<void> _checkEligibility() async {
    setState(() {
      _isCheckingEligibility = true;
      _blockedMessage = null;
      _checkError = null;
    });

    final client = Supabase.instance.client;
    final userId = client.auth.currentUser?.id;

    if (userId == null) {
      if (!mounted) return;
      setState(() {
        _isCheckingEligibility = false;
        _blockedMessage = 'This reset link is no longer valid. '
            'Request a new one from the sign-in screen.';
      });
      return;
    }

    try {
      final row = await client
          .from('users')
          .select('status, division_type_id')
          .eq('id', userId)
          .maybeSingle()
          .timeout(const Duration(seconds: 20));

      if (!mounted) return;

      if (row == null) {
        await _blockAndSignOut(
          'We could not find a profile for this account. '
          'Please contact support.',
        );
        return;
      }

      final status = row['status']?.toString() ?? '';
      final divisionTypeId = (row['division_type_id'] as num?)?.toInt();

      if (divisionTypeId == _swmDivisionTypeId) {
        await _blockAndSignOut(
          'This account is not permitted to use this app. '
          'Please contact support.',
        );
        return;
      }

      if (status != 'Active') {
        await _blockAndSignOut(
          'Your account is ${status.isEmpty ? 'inactive' : status}. '
          'Please contact support.',
        );
        return;
      }

      setState(() => _isCheckingEligibility = false);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _isCheckingEligibility = false;
        _checkError = 'Could not verify your account. '
            'Check your connection and try again.';
      });
      debugPrint('[reset password] eligibility check failed: $error');
    }
  }

  /// Rejects the account and drops the recovery session, so a blocked user
  /// isn't left holding a valid session they could reuse elsewhere.
  Future<void> _blockAndSignOut(String message) async {
    try {
      await Supabase.instance.client.auth.signOut();
    } catch (_) {
      // Already signed out, or offline — the refusal below still stands.
    }
    if (!mounted) return;
    setState(() {
      _isCheckingEligibility = false;
      _blockedMessage = message;
    });
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
      _blockedMessage == null &&
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

      _goToSignIn();
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

  void _goToSignIn() {
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (route) => false,
    );
  }

  Future<void> _signOutAndGoToSignIn() async {
    try {
      await Supabase.instance.client.auth.signOut();
    } catch (_) {
      // Nothing to tear down — fall through and leave anyway.
    }
    if (!mounted) return;
    _goToSignIn();
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
                  child: _buildCardContent(),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCardContent() {
    if (_isCheckingEligibility) return _buildCheckingBody();

    if (_blockedMessage != null) {
      return _buildNoticeBody(
        icon: Icons.block,
        iconColor: const Color(0xFFB3261E),
        title: 'Password reset unavailable',
        message: _blockedMessage!,
      );
    }

    if (_checkError != null) {
      return _buildNoticeBody(
        icon: Icons.wifi_off,
        iconColor: const Color(0xFF8A6D1F),
        title: 'Could not verify your account',
        message: _checkError!,
        onRetry: _checkEligibility,
      );
    }

    return _buildFormBody();
  }

  Widget _buildCheckingBody() {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircularProgressIndicator(color: _accent),
          SizedBox(height: 16),
          Text(
            'Checking your account…',
            style: TextStyle(fontSize: 15, color: Color(0xFF475356)),
          ),
        ],
      ),
    );
  }

  Widget _buildNoticeBody({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String message,
    VoidCallback? onRetry,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, color: iconColor, size: 26),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                title,
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF253033),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Text(
          message,
          style: const TextStyle(fontSize: 15, color: Color(0xFF475356)),
        ),
        const SizedBox(height: 22),
        if (onRetry != null) ...[
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: onRetry,
              style: ElevatedButton.styleFrom(
                backgroundColor: _accent,
                elevation: 0,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: const Text(
                'Try again',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w500,
                  color: Colors.white,
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
        ],
        Center(child: _buildBackToSignIn()),
      ],
    );
  }

  Widget _buildFormBody() {
    return Column(
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
          style: TextStyle(fontSize: 15, color: Color(0xFF475356)),
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
              disabledBackgroundColor: _accent.withValues(alpha: 0.55),
              elevation: 0,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            // Same trick as the Sign In button: keep the label laid out so
            // the button doesn't change height when the spinner appears.
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
        Center(child: _buildBackToSignIn()),
      ],
    );
  }

  Widget _buildBackToSignIn() {
    return TextButton(
      onPressed: _isLoading ? null : _signOutAndGoToSignIn,
      child: const Text(
        'Back to sign in',
        style: TextStyle(
          color: Color(0xFF1F674E),
          fontWeight: FontWeight.w600,
          fontSize: 15,
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
