import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'screens/login_screen.dart';
import 'home_screen.dart';
import 'service/api_service.dart';
import 'service/auth_session.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await ApiService.initialize();

  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> with WidgetsBindingObserver {
  late Future<Widget> _initialScreen;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _updateOrientation());
    _initialScreen = _loadInitialScreen();
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
      }
    } catch (e) {
      // Failed to load profile
    }
  }

  @override
  void dispose() {
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
      debugShowCheckedModeBanner: false,
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
