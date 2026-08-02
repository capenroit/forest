import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../home_screen.dart';
import '../service/auth_session.dart';
import '../service/offline_sync_service.dart';
import 'signup_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  static const _cachedEmailKey = 'cached_login_email';
  static const _cachedPasswordKey = 'cached_login_password';

  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isLoading = false;
  bool _obscurePassword = true;
  bool _rememberMe = true;

  /// Short, human-readable summary of a network failure for display in a
  /// SnackBar — e.g. "timed out" or "Failed host lookup" rather than a full
  /// stack-trace-style exception dump.
  String _describeNetworkError(Object error) {
    if (error is TimeoutException) return 'timed out';
    if (error is SocketException) {
      return error.osError?.message ?? error.message;
    }
    final text = error.toString().replaceFirst('Exception: ', '');
    return text.length > 80 ? '${text.substring(0, 80)}…' : text;
  }

  /// Attempts sign-in up to 3 times, retrying only on network-classified
  /// failures (DNS/socket/timeout) with a short delay between attempts.
  /// Covers transient hiccups seen right at cold app launch on some Android
  /// devices, where the first request can fail with "Failed host lookup"
  /// even though the network is genuinely fine a second later — without
  /// this, that single flaky first attempt would wrongly drop the user into
  /// offline-login mode.
  Future<AuthResponse> _signInWithRetry(String email, String password) async {
    const maxAttempts = 3;
    for (var attempt = 1; attempt <= maxAttempts; attempt++) {
      try {
        return await Supabase.instance.client.auth
            .signInWithPassword(email: email, password: password)
            .timeout(const Duration(seconds: 20));
      } catch (error) {
        final isLastAttempt = attempt == maxAttempts;
        if (isLastAttempt || !OfflineSyncService.isNetworkError(error)) {
          rethrow;
        }
        await Future.delayed(const Duration(seconds: 2));
      }
    }
    throw StateError('unreachable');
  }

  Future<void> _saveCredentials(String email, String password) async {
    final prefs = await SharedPreferences.getInstance();
    if (_rememberMe) {
      await prefs.setString(_cachedEmailKey, email);
      await prefs.setString(_cachedPasswordKey, password);
      return;
    }

    await prefs.remove(_cachedEmailKey);
    await prefs.remove(_cachedPasswordKey);
    await AuthSession.clearCachedUser();
  }

  Future<bool> _tryOfflineLogin(String email, String password) async {
    final prefs = await SharedPreferences.getInstance();
    final cachedEmail = prefs.getString(_cachedEmailKey);
    final cachedPassword = prefs.getString(_cachedPasswordKey);

    if (cachedEmail != email || cachedPassword != password) {
      return false;
    }

    await AuthSession.loadCachedUser();
    return AuthSession.currentUser?.status == 'Active' &&
        AuthSession.currentUser?.divisionTypeId != 3;
  }

  Future<AppUser> _loadUserProfile(String userId, String email) async {
    final profileData = await Supabase.instance.client
        .from('users')
        .select('seq_id, email, name, access_level, status, division_type_id')
        .eq('id', userId)
        .maybeSingle();

    if (profileData == null) {
      throw Exception('User profile not found. Please contact support.');
    }

    final profile = AppUser.fromJson(profileData, id: userId);
    AuthSession.currentUser = profile;
    return profile;
  }

  Future<void> _handleSignIn() async {
    final email = _emailController.text.trim();
    final password = _passwordController.text.trim();

    if (email.isEmpty || password.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please fill in all fields')),
      );
      return;
    }

    setState(() => _isLoading = true);

    final canUseOfflineLogin = !kIsWeb;

    try {
      AuthResponse response;
      try {
        response = await _signInWithRetry(email, password);
      } catch (error) {
        // Fall back to cached-credential offline login only for a genuine
        // connectivity failure on the actual sign-in call — not based on a
        // separate probe URL beforehand, which can report "offline" on
        // networks that block that one probe while Supabase itself is
        // perfectly reachable (the previous approach, and the cause of
        // false "no internet" reports on some carriers/devices).
        if (canUseOfflineLogin && OfflineSyncService.isNetworkError(error)) {
          final offlineSuccess = await _tryOfflineLogin(email, password);

          if (!mounted) {
            return;
          }

          if (offlineSuccess) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text(
                  'Offline login successful. Using cached credentials.',
                ),
                backgroundColor: Colors.orange,
                duration: Duration(seconds: 2),
              ),
            );

            Navigator.of(context).pushReplacement(
              MaterialPageRoute(builder: (context) => const HomeScreen()),
            );
          } else {
            // Surfaces the actual connectivity failure (timeout, DNS,
            // connection refused, etc.) instead of a generic message, so a
            // "connected to WiFi but this still happens" report is
            // diagnosable from the screen alone.
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  'Unable to reach the server (${_describeNetworkError(error)}). '
                  'No cached credentials for offline login either.',
                ),
                backgroundColor: Colors.orange,
                duration: const Duration(seconds: 6),
              ),
            );
          }
          return;
        }
        rethrow;
      }

      if (response.session == null) {
        if (!mounted) {
          return;
        }

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Login failed')),
        );
        return;
      }

      final userId = response.user?.id ?? response.session!.user.id;
      final profile = await _loadUserProfile(userId, email);

      if (profile.status != 'Active') {
        await Supabase.instance.client.auth.signOut();

        if (!mounted) {
          return;
        }

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Your account is ${profile.status}. Please contact support.',
            ),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 4),
          ),
        );
        return;
      }

      if (profile.divisionTypeId == 3) {
        await Supabase.instance.client.auth.signOut();

        if (!mounted) {
          return;
        }

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'This account is not permitted to sign in. Please contact support.',
            ),
            backgroundColor: Colors.red,
            duration: Duration(seconds: 4),
          ),
        );
        return;
      }

      await _saveCredentials(email, password);
      await AuthSession.cacheUser(profile);
      // A successful sign-in proves we're online — warm the offline caches
      // in the background so the app has something to work with if
      // connectivity drops later. Never blocks navigation to the dashboard.
      OfflineSyncService.warmCache().ignore();

      if (!mounted) {
        return;
      }

      final displayName = profile.name.isNotEmpty
          ? profile.name
          : (response.user?.userMetadata?['full_name'] as String? ?? 'User');

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Welcome back, $displayName!'),
          backgroundColor: Colors.green,
          duration: const Duration(seconds: 2),
        ),
      );

      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (context) => const HomeScreen()),
      );
    } on AuthException catch (error) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(error.message),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 4),
        ),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }

      final message = error.toString().replaceFirst('Exception: ', '');

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message.isEmpty ? 'Sign in failed' : message),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 4),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
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
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.10),
                        blurRadius: 10,
                        offset: const Offset(0, 6),
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Center(
                        child: Container(
                          width: 72,
                          height: 62,
                          decoration: BoxDecoration(
                            color: const Color.fromARGB(255, 0, 176, 80),
                            borderRadius: BorderRadius.circular(18),
                          ),
                          clipBehavior: Clip.antiAlias,
                          padding: const EdgeInsets.all(6),
                          child: Image.asset('assets/logo.png', fit: BoxFit.contain),
                        ),
                      ),
                      const SizedBox(height: 22),
                      const Center(
                        child: Text(
                          'Welcome Back',
                          style: TextStyle(
                            fontSize: 42,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF1F272A),
                          ),
                        ),
                      ),
                      const SizedBox(height: 6),
                      const Center(
                        child: Text(
                          'Sign in to your Eco Account',
                          style: TextStyle(
                            fontSize: 14,
                            color: Color(0xFF49595D),
                          ),
                        ),
                      ),
                      const SizedBox(height: 26),
                      const Text(
                        'Email Address',
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF253033),
                        ),
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: _emailController,
                        keyboardType: TextInputType.emailAddress,
                        decoration: InputDecoration(
                          hintText: 'your.email@example.com',
                          hintStyle: const TextStyle(color: Color(0xFF5A5D60)),
                          filled: true,
                          fillColor: const Color(0xFFE4E8E7),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 16,
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide.none,
                          ),
                          prefixIcon: const Icon(
                            Icons.email,
                            color: Color.fromARGB(255, 0, 176, 80),
                          ),
                        ),
                      ),
                      const SizedBox(height: 18),
                      const Text(
                        'Password',
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF253033),
                        ),
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: _passwordController,
                        obscureText: _obscurePassword,
                        decoration: InputDecoration(
                          hintText: 'Enter your password',
                          hintStyle: const TextStyle(color: Color(0xFF5A5D60)),
                          filled: true,
                          fillColor: const Color(0xFFE4E8E7),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 16,
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide.none,
                          ),
                          prefixIcon: const Icon(
                            Icons.lock,
                            color: Color.fromARGB(255, 0, 176, 80),
                          ),
                          suffixIcon: IconButton(
                            onPressed: () => setState(
                              () => _obscurePassword = !_obscurePassword,
                            ),
                            icon: Icon(
                              _obscurePassword
                                  ? Icons.visibility_off
                                  : Icons.visibility,
                              color: const Color.fromARGB(255, 0, 176, 80),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 22),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: _isLoading ? null : _handleSignIn,
                          style: ElevatedButton.styleFrom(
                            backgroundColor:
                                const Color.fromARGB(255, 0, 176, 80),
                            disabledBackgroundColor:
                                const Color.fromARGB(255, 0, 176, 80)
                                    .withValues(alpha: 0.55),
                            elevation: 0,
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: _isLoading
                              ? const SizedBox(
                                  height: 22,
                                  width: 22,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2.4,
                                    color: Colors.white,
                                  ),
                                )
                              : const Text(
                                  'Sign In',
                                  style: TextStyle(
                                    fontSize: 25,
                                    fontWeight: FontWeight.w500,
                                    color: Colors.white,
                                  ),
                                ),
                        ),
                      ),
                      const SizedBox(height: 20),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Text(
                            "Don't have an account? ",
                            style: TextStyle(
                              color: Color(0xFF475356),
                              fontSize: 15,
                            ),
                          ),
                          GestureDetector(
                            onTap: () {
                              Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (context) => const SignupScreen(),
                                ),
                              );
                            },
                            child: const Text(
                              'Sign up for free',
                              style: TextStyle(
                                color: Color.fromARGB(255, 0, 176, 80),
                                fontWeight: FontWeight.w700,
                                fontSize: 15,
                              ),
                            ),
                          ),
                        ],
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
}

