import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'screens/dashboard_page.dart';
import 'screens/capiz_flora_fauna_recent_activity_page.dart';
import 'screens/coastal_dashboard_page.dart';
import 'screens/habitat_assessment_page.dart';
import 'screens/login_screen.dart';
import 'screens/marine_protected_area_page.dart';
import 'screens/report_page.dart';
import 'screens/seed_for_forest_recent_activity_page.dart';
import 'screens/seedling_inventory_page.dart';
import 'screens/seedling_request_page.dart';
import 'screens/settings_page.dart';
import 'screens/tree_growing_page.dart';
import 'screens/tree_survival_monitoring_page.dart';
import 'service/auth_session.dart';
import 'service/offline_sync_service.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Dashboard")),
      drawer: const SidePanel(),
      body: const DashboardPage(),
    );
  }
}

class SidePanel extends StatefulWidget {
  const SidePanel({super.key});

  @override
  State<SidePanel> createState() => _SidePanelState();
}

class _SidePanelState extends State<SidePanel> {
  bool _isOnline = true;

  @override
  void initState() {
    super.initState();
    _checkConnectivity();
  }

  Future<void> _checkConnectivity() async {
    if (kIsWeb) {
      if (mounted) {
        setState(() => _isOnline = true);
      }
      return;
    }

    try {
      final response = await http
          .get(Uri.parse('https://clients3.google.com/generate_204'))
          .timeout(const Duration(seconds: 5));
      if (mounted) {
        final online = response.statusCode == 204 || response.statusCode == 200;
        setState(() => _isOnline = online);
        if (online) {
          // Silently flush any records that were saved while offline.
          OfflineSyncService.syncAll().ignore();
        }
      }
    } catch (_) {
      if (mounted) setState(() => _isOnline = false);
    }
  }

  Future<void> _signOut() async {
    final online = await _checkConnectivityNow();

    if (!online) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content:
              Text('No internet connection. Please go online to sign out.'),
          backgroundColor: Colors.orange,
          duration: Duration(seconds: 3),
        ),
      );
      return;
    }

    await Supabase.instance.client.auth.signOut();
    AuthSession.currentUser = null;
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (_) => false,
    );
  }

  Future<bool> _checkConnectivityNow() async {
    if (kIsWeb) {
      return true;
    }

    try {
      final response = await http
          .get(Uri.parse('https://clients3.google.com/generate_204'))
          .timeout(const Duration(seconds: 5));
      return response.statusCode == 204 || response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = AuthSession.currentUser;
    final displayName = user?.name ?? 'User';
    final initial = displayName.isNotEmpty ? displayName[0].toUpperCase() : 'U';

    return Drawer(
      child: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [
              Color.fromARGB(255, 31, 103, 78),
              Color.fromARGB(255, 67, 160, 71),
            ],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: Column(
          children: [
            // Logo + App name header
            SafeArea(
              bottom: false,
              child: Container(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child:
                          const Icon(Icons.eco, color: Colors.green, size: 32),
                    ),
                    const SizedBox(width: 12),
                    const Text(
                      "EnviApp",
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
            // Menu items
            Expanded(
              child: ListView(
                padding: EdgeInsets.zero,
                children: [
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    child: Text(
                      "FOREST MANAGEMENT",
                      style: TextStyle(
                        color: Colors.white70,
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1.2,
                      ),
                    ),
                  ),
                  _buildNavItem(Icons.dashboard, "Dashboard", () {
                    Navigator.pop(context);
                  }),
                  _buildNavItem(Icons.nature, "Tree Growing Activity", () {
                    Navigator.pop(context);
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => const TreeGrowingPage()),
                    );
                  }),
                  _buildNavItem(Icons.monitor, "Monitoring of Tree Survival",
                      () {
                    Navigator.pop(context);
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const TreeSurvivalMonitoringPage(),
                      ),
                    );
                  }),
                  _buildNavItem(Icons.eco, "Capiz Flora and Fauna Survey", () {
                    Navigator.pop(context);
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) =>
                            const CapizFloraFaunaRecentActivityPage(),
                      ),
                    );
                  }),
                  _buildNavItem(Icons.inventory, "Available Seedling Inventory",
                      () {
                    Navigator.pop(context);
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const SeedlingInventoryPage(),
                      ),
                    );
                  }),
                  _buildNavItem(Icons.assignment_outlined, "Seedling Request",
                      () {
                    Navigator.pop(context);
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const SeedlingRequestPage(),
                      ),
                    );
                  }),
                  _buildNavItem(Icons.park, "Seed for a Forest", () {
                    Navigator.pop(context);
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const SeedForForestRecentActivityPage(),
                      ),
                    );
                  }),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    child: Divider(color: Colors.white30),
                  ),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    child: Text(
                      "COASTAL MANAGEMENT",
                      style: TextStyle(
                        color: Colors.white70,
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1.2,
                      ),
                    ),
                  ),
                  _buildNavItem(Icons.dashboard, "Dashboard", () {
                    Navigator.pop(context);
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const CoastalDashboardPage(),
                      ),
                    );
                  }),
                  _buildNavItem(Icons.waves, "Habitat Assessment", () {
                    Navigator.pop(context);
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const HabitatAssessmentPage(),
                      ),
                    );
                  }),
                  _buildNavItem(Icons.sailing, "Marine Protected Area", () {
                    Navigator.pop(context);
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const MarineProtectedAreaPage(),
                      ),
                    );
                  }),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    child: Divider(color: Colors.white30),
                  ),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    child: Text(
                      "REPORTS & ANALYTICS",
                      style: TextStyle(
                        color: Colors.white70,
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1.2,
                      ),
                    ),
                  ),
                  _buildNavItem(Icons.bar_chart, "Reports", () {
                    Navigator.pop(context);
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const ReportPage(),
                      ),
                    );
                  }),
                ],
              ),
            ),
            _buildNavItem(Icons.settings, "Settings", () {
              Navigator.pop(context);
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const SettingsPage()),
              );
            }),

            // User footer
            Container(
              margin: const EdgeInsets.all(12),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  // Avatar
                  CircleAvatar(
                    radius: 20,
                    backgroundColor: const Color.fromARGB(255, 0, 176, 80),
                    child: Text(
                      initial,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  // Name + status
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          displayName,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Row(
                          children: [
                            Container(
                              width: 7,
                              height: 7,
                              decoration: BoxDecoration(
                                color: _isOnline
                                    ? const Color(0xFF4ADE80)
                                    : Colors.red.shade300,
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 5),
                            Text(
                              _isOnline ? 'Online' : 'Offline',
                              style: TextStyle(
                                color: _isOnline
                                    ? const Color(0xFF4ADE80)
                                    : Colors.red.shade300,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  // Sign out button
                  IconButton(
                    onPressed: _signOut,
                    icon: const Icon(Icons.logout,
                        color: Colors.white70, size: 20),
                    tooltip: 'Sign out',
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Widget _buildNavItem(IconData icon, String label, VoidCallback onTap) {
    return ListTile(
      leading: Icon(icon, color: const Color.fromARGB(255, 153, 226, 177)),
      title: Text(
        label,
        style: const TextStyle(
          color: Color.fromARGB(255, 188, 235, 204),
          fontSize: 14,
        ),
      ),
      onTap: onTap,
    );
  }
}
