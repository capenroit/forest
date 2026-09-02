import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:async';

import 'screens/login_screen.dart';
import 'screens/reset_password_screen.dart';
import 'home_screen.dart';
import 'service/api_service.dart';
import 'service/auth_session.dart';
import 'service/map_tile_cache_service.dart';
import 'service/offline_sync_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await ApiService.initialize();

  // Must happen before the first map tile is requested — it fixes the
  // configuration of flutter_map's cache singleton.
  await MapTileCacheService.configure();

  runApp(const MyApp());

  // First launch only: pull down the Panay Island basemap so the dashboard
  // map is already cached by the time anyone opens it, and stays cached
  // across restarts. Never blocks startup.
  MapTileCacheService.seedPanayIslandOnFirstRun().ignore();
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> with WidgetsBindingObserver {
  /// Needed so the password-recovery listener below can navigate without a
  /// BuildContext of its own — the event arrives from supabase_flutter's
  /// deep-link handler, outside the widget tree.
  static final navigatorKey = GlobalKey<NavigatorState>();

  late Future<Widget> _initialScreen;
  StreamSubscription<AuthState>? _authSubscription;
  bool _handlingRecovery = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _updateOrientation());
    _initialScreen = _loadInitialScreen();
    _listenForPasswordRecovery();
  }

  /// Opening the reset link from the recovery email hands supabase_flutter a
  /// short-lived session and fires [AuthChangeEvent.passwordRecovery]. That
  /// session would otherwise drop the user straight onto the dashboard, so
  /// intercept it and send them to ResetPasswordScreen instead.
  void _listenForPasswordRecovery() {
    _authSubscription =
        Supabase.instance.client.auth.onAuthStateChange.listen((data) {
      if (data.event != AuthChangeEvent.passwordRecovery) return;
      // The event can be replayed (e.g. the same link re-opened while the
      // reset screen is already up) — only act on the first one.
      if (_handlingRecovery) return;
      _handlingRecovery = true;

      WidgetsBinding.instance.addPostFrameCallback((_) {
        navigatorKey.currentState?.pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const ResetPasswordScreen()),
          (route) => false,
        );
        _handlingRecovery = false;
      });
    });
  }

  Future<Widget> _loadInitialScreen() async {
    try {
      final session = Supabase.instance.client.auth.currentSession;

      if (session != null) {
        // Session exists, load user profile
        await _loadUserProfile(session.user.id);
        return const HomeScreen();
      }
    } catch (e) {
      // Error loading profile, show login
    }

    return const LoginScreen();
  }

  Future<void> _loadUserProfile(String userId) async {
    try {
      final profileData = await Supabase.instance.client
          .from('users')
          .select('seq_id, email, name, access_level, status, division_type_id')
          .eq('id', userId)
          .maybeSingle();

      if (profileData != null) {
        final profile = AppUser.fromJson(profileData, id: userId);
        AuthSession.currentUser = profile;
        await AuthSession.cacheUser(profile);
        // Reaching here proves we're online — warm the offline caches in
        // the background so the app has something to work with if
        // connectivity drops later. Never blocks the dashboard.
        OfflineSyncService.warmCache().ignore();
        return;
      }
    } catch (_) {
      // Offline or the request otherwise failed — fall through to the
      // last cached profile below instead of leaving currentUser null.
    }

    final cached = await AuthSession.loadCachedUser();
    if (cached != null && cached.id != userId) {
      // Cached profile belongs to a different account than the restored
      // session — don't show the wrong person's name.
      AuthSession.currentUser = null;
    }
  }

  @override
  void dispose() {
    _authSubscription?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeMetrics() {
    super.didChangeMetrics();
    // React if the window metrics/sizes change dynamically
    _updateOrientation();
  }

  void _updateOrientation() {
    final view = View.of(context);
    final shortestSide = view.physicalSize.shortestSide / view.devicePixelRatio;

    if (shortestSide >= 600) {
      // Tablet → Landscape
      SystemChrome.setPreferredOrientations([
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
    } else {
      // Phone → Portrait
      SystemChrome.setPreferredOrientations([
        DeviceOrientation.portraitUp,
        DeviceOrientation.portraitDown,
      ]);
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      // Required on web: MaterialApp's `title` defaults to '' (not null), so
      // WidgetsApp wraps the tree in Title('') and blanks document.title —
      // wiping the <title> from web/index.html. Chrome then falls back to
      // showing the raw URL in the tab. Setting it here restores the name.
      title: 'iForest',
      debugShowCheckedModeBanner: false,
      navigatorKey: navigatorKey,
      home: FutureBuilder<Widget>(
        future: _initialScreen,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Scaffold(
              body: Center(child: CircularProgressIndicator()),
            );
          }

          if (snapshot.hasError) {
            return const LoginScreen();
          }

          return snapshot.data ?? const LoginScreen();
        },
      ),
    );
  }

  Widget _buildHome() {
    // Check if there's an active Supabase session
    final session = Supabase.instance.client.auth.currentSession;

    if (session != null) {
      // User is logged in, show HomeScreen
      return const HomeScreen();
    }

    // No session, show login
    return const LoginScreen();
  }
}
