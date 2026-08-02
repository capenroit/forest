import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../screens/capiz_flora_fauna_recent_activity_page.dart';
import '../screens/habitat_assessment_page.dart';
import '../screens/login_screen.dart';
import '../screens/manage_members_page.dart';
import '../screens/mangrove_planting_activity_page.dart';
import '../screens/mangrove_survival_monitoring_page.dart';
import '../screens/marine_protected_area_page.dart';
import '../screens/report_page.dart';
import '../screens/seed_for_forest_recent_activity_page.dart';
import '../screens/seedling_inventory_page.dart';
import '../screens/seedling_request_page.dart';
import '../screens/settings_page.dart';
import '../screens/tree_growing_page.dart';
import '../screens/tree_survival_monitoring_page.dart';
import '../service/auth_session.dart';
import '../service/offline_sync_service.dart';

class SidePanel extends StatefulWidget {
  const SidePanel({super.key});

  @override
  State<SidePanel> createState() => _SidePanelState();
}

class _SidePanelState extends State<SidePanel> {
  bool _isOnline = true;

  // Mirrors the division picker in signup_screen.dart / manage_members_page
  // .dart. SWM (3) belongs to a separate app this one doesn't sign in for,
  // but a user's own division_type_id could still be 3 (e.g. an admin
  // account), so it's kept here for a correct label.
  static const Map<int, String> _divisionNames = {
    1: 'FMS',
    2: 'CRM',
    3: 'SWM',
  };

  // Mirrors the access_level lookup table in Supabase (id, name,
  // description): 1=Admin, 2=Data Manager, 3=Data Collector, 4=Recipient.
  static const Map<int, String> _accessLevelNames = {
    1: 'Admin',
    2: 'Data Manager',
    3: 'Data Collector',
    4: 'Recipient',
  };

  @override
  void initState() {
    super.initState();
    _checkConnectivity();
  }

  Future<void> _checkConnectivity() async {
    final online = await OfflineSyncService.hasInternetConnection();
    if (!mounted) return;

    setState(() => _isOnline = online);
    if (online) {
      // Silently flush any records that were saved while offline.
      OfflineSyncService.syncAll().ignore();
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

  Future<bool> _checkConnectivityNow() => OfflineSyncService.hasInternetConnection();

  @override
  Widget build(BuildContext context) {
    final user = AuthSession.currentUser;
    final displayName = user?.name ?? 'User';
    final initial = displayName.isNotEmpty ? displayName[0].toUpperCase() : 'U';
    final divisionLabel = _divisionNames[user?.divisionTypeId];
    final accessLevelLabel = _accessLevelNames[user?.accessLevel];
    final roleSubtitle = [
      if (divisionLabel != null) divisionLabel,
      if (accessLevelLabel != null) accessLevelLabel,
    ].join(' • ');

    // division_type_id gates which activity group shows: 1 = Forest
    // Management, 2 = Coastal Management. Anything else (null/unrecognized)
    // shows both rather than locking the user out of everything.
    final divisionTypeId = user?.divisionTypeId;
    final showForestManagement = divisionTypeId != 2;
    final showCoastalManagement = divisionTypeId != 1;

    final sections = <List<Widget>>[
      if (showForestManagement) _buildForestManagementSection(context),
      if (showCoastalManagement) _buildCoastalManagementSection(context),
      _buildSeedlingManagementSection(context),
      _buildReportsSection(context),
    ];

    final menuChildren = <Widget>[];
    for (var i = 0; i < sections.length; i++) {
      if (i > 0) menuChildren.add(_buildSectionDivider());
      menuChildren.addAll(sections[i]);
    }

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
                      clipBehavior: Clip.antiAlias,
                      child: Image.asset('assets/logo.png', fit: BoxFit.cover),
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
                children: menuChildren,
              ),
            ),
            if (user?.accessLevel == 1 || user?.accessLevel == 2)
              _buildNavItem(Icons.manage_accounts_rounded, "Members", () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const ManageMembersPage()),
                );
              }),
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
                        if (roleSubtitle.isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Text(
                            roleSubtitle,
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 11,
                              fontWeight: FontWeight.w500,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
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

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Text(
        title,
        style: const TextStyle(
          color: Colors.white70,
          fontSize: 14,
          fontWeight: FontWeight.bold,
          letterSpacing: 1.2,
        ),
      ),
    );
  }

  Widget _buildSectionDivider() {
    return const Padding(
      padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Divider(color: Colors.white30),
    );
  }

  List<Widget> _buildForestManagementSection(BuildContext context) {
    return [
      _buildSectionHeader("FOREST MANAGEMENT"),
      _buildNavItem(Icons.dashboard, "Dashboard", () {
        Navigator.pop(context);
        Navigator.of(context).popUntil((route) => route.isFirst);
      }),
      _buildNavItem(Icons.nature, "Tree Growing Activity", () {
        Navigator.pop(context);
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const TreeGrowingPage()),
        );
      }),
      _buildNavItem(Icons.monitor, "Monitoring of Tree Survival", () {
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
            builder: (_) => const CapizFloraFaunaRecentActivityPage(),
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
    ];
  }

  List<Widget> _buildCoastalManagementSection(BuildContext context) {
    return [
      _buildSectionHeader("COASTAL MANAGEMENT"),
      _buildNavItem(Icons.dashboard, "Dashboard", () {
        Navigator.pop(context);
        Navigator.of(context).popUntil((route) => route.isFirst);
      }),
      _buildNavItem(Icons.forest, "Mangrove Planting Activity", () {
        Navigator.pop(context);
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => const MangrovePlantingActivityPage(),
          ),
        );
      }),
      _buildNavItem(Icons.monitor_heart_rounded,
          "Monitoring of Mangrove Survival", () {
        Navigator.pop(context);
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => const MangroveSurvivalMonitoringPage(),
          ),
        );
      }),
      _buildNavItem(Icons.waves, "Habitat Assessment", () {
        Navigator.pop(context);
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const HabitatAssessmentPage()),
        );
      }),
      _buildNavItem(Icons.sailing, "Marine Protected Area", () {
        Navigator.pop(context);
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const MarineProtectedAreaPage()),
        );
      }),
    ];
  }

  List<Widget> _buildSeedlingManagementSection(BuildContext context) {
    return [
      _buildSectionHeader("SEEDLING MANAGEMENT"),
      _buildNavItem(Icons.inventory, "Available Seedling Inventory", () {
        Navigator.pop(context);
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const SeedlingInventoryPage()),
        );
      }),
      _buildNavItem(Icons.assignment_outlined, "Seedling Request", () {
        Navigator.pop(context);
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const SeedlingRequestPage()),
        );
      }),
    ];
  }

  List<Widget> _buildReportsSection(BuildContext context) {
    return [
      _buildSectionHeader("REPORTS & ANALYTICS"),
      _buildNavItem(Icons.bar_chart, "Reports", () {
        Navigator.pop(context);
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const ReportPage()),
        );
      }),
    ];
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
