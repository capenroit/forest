import 'package:flutter/material.dart';
import '../widget/side_panel.dart';
import 'setting_mangrove_page.dart';
import 'setting_nursery_page.dart';
import 'setting_seedling_page.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      drawer: const SidePanel(),
      appBar: AppBar(
        title: const Text('Settings'),
        backgroundColor: const Color.fromARGB(255, 31, 103, 78),
        foregroundColor: Colors.white,
        leading: Builder(
          builder: (context) => IconButton(
            icon: const Icon(Icons.menu),
            onPressed: () => Scaffold.of(context).openDrawer(),
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // These shared lookup lists are visible to everyone since data
          // entry forms need them, but only admins/managers can edit or
          // remove entries (enforced inside each page).
          Card(
            child: ListTile(
              leading: const Icon(Icons.eco),
              title: const Text('Seedling List'),
              subtitle: const Text('Manage seedling names and details'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const SettingSeedlingPage()),
                );
              },
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: ListTile(
              leading: const Icon(Icons.forest),
              title: const Text('Mangrove List'),
              subtitle:
                  const Text('Manage mangrove species names and details'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const SettingMangrovePage()),
                );
              },
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: ListTile(
              leading: const Icon(Icons.park),
              title: const Text('Nursery List'),
              subtitle: const Text('Manage nurseries and their division'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const SettingNurseryPage()),
                );
              },
            ),
          ),
          const SizedBox(height: 12),
          const Card(
            child: ListTile(
              leading: Icon(Icons.settings_suggest),
              title: Text('More settings coming soon'),
            ),
          ),
        ],
      ),
    );
  }
}

