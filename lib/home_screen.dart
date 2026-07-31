import 'package:flutter/material.dart';
import 'screens/dashboard_page.dart';
import 'screens/coastal_dashboard_page.dart';
import 'service/auth_session.dart';
import 'widget/side_panel.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final isCoastal = AuthSession.currentUser?.divisionTypeId == 2;

    if (isCoastal) {
      // CoastalDashboardPage owns its own Scaffold/AppBar (its title differs
      // from the Forest one below), so it takes the drawer directly instead
      // of being nested inside another Scaffold.
      return const CoastalDashboardPage(drawer: SidePanel());
    }

    return Scaffold(
      appBar: AppBar(title: const Text("Dashboard")),
      drawer: const SidePanel(),
      body: const DashboardPage(),
    );
  }
}
