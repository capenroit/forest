import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../service/auth_session.dart';
import '../widget/side_panel.dart';

class ManageMembersPage extends StatefulWidget {
  const ManageMembersPage({super.key});

  @override
  State<ManageMembersPage> createState() => _ManageMembersPageState();
}

class _ManageMembersPageState extends State<ManageMembersPage> {
  // Mirrors the division picker in signup_screen.dart.
  static const Map<int, String> _divisionNames = {
    1: 'FMS',
    2: 'CRM',
    3: 'SWM',
  };

  List<Map<String, dynamic>> _members = [];
  bool _isLoading = true;
  String? _errorMessage;
  final Set<String> _updatingIds = {};

  bool get _canManage {
    final level = AuthSession.currentUser?.accessLevel;
    return level == 1 || level == 2;
  }

  @override
  void initState() {
    super.initState();
    if (_canManage) {
      _loadMembers();
    } else {
      _isLoading = false;
    }
  }

  Future<void> _loadMembers({bool showLoader = true}) async {
    if (showLoader && mounted) {
      setState(() {
        _isLoading = true;
        _errorMessage = null;
      });
    }

    try {
      final rows = await Supabase.instance.client
          .from('users')
          .select(
              'id, seq_id, name, email, status, access_level, division_type_id, created_at, email_confirmed')
          .order('created_at', ascending: false);

      // access_level 1 (top-level admin) accounts aren't manageable from
      // here, division_type_id 3 (SWM) belongs to a separate app this one
      // doesn't handle sign-in for, and accounts that haven't confirmed
      // their email yet aren't real members yet — none of these should
      // show up in this list.
      final filtered = List<Map<String, dynamic>>.from(rows as List)
          .where((row) => (row['access_level'] as num?)?.toInt() != 1)
          .where((row) => (row['division_type_id'] as num?)?.toInt() != 3)
          .where((row) => row['email_confirmed'] == true)
          .toList();

      if (!mounted) return;
      setState(() {
        _members = filtered;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorMessage = 'Failed to load members: $e';
      });
    }
  }

  Future<void> _setStatus(Map<String, dynamic> member, String newStatus) async {
    final id = member['id']?.toString();
    if (id == null || id.isEmpty) return;

    setState(() => _updatingIds.add(id));

    try {
      // .select() + emptiness check matters here: Postgrest doesn't throw
      // when an UPDATE's RLS policy silently matches 0 rows (e.g. missing
      // admin-update permission on someone else's row) — without this, a
      // blocked update would still show a false "success" message.
      final response = await Supabase.instance.client
          .from('users')
          .update({'status': newStatus})
          .eq('id', id)
          .select('id');

      if (response.isEmpty) {
        throw Exception(
          'No row was updated. You may not have permission to change this member.',
        );
      }

      if (!mounted) return;
      setState(() {
        member['status'] = newStatus;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${member['name'] ?? 'Member'} is now $newStatus.',
          ),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Unable to update status: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _updatingIds.remove(id));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F5F7),
      drawer: const SidePanel(),
      appBar: AppBar(
        backgroundColor: const Color.fromARGB(255, 31, 103, 78),
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        leading: Builder(
          builder: (context) => IconButton(
            icon: const Icon(Icons.menu),
            onPressed: () => Scaffold.of(context).openDrawer(),
          ),
        ),
        title: const Row(
          children: [
            Icon(Icons.manage_accounts_rounded, color: Colors.white, size: 26),
            SizedBox(width: 10),
            Text(
              'Members',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
          ],
        ),
      ),
      body: !_canManage
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'You do not have permission to manage members.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Color(0xFF636780), fontSize: 15),
                ),
              ),
            )
          : RefreshIndicator(
              onRefresh: () => _loadMembers(showLoader: false),
              child: _buildBody(),
            ),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_errorMessage != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _errorMessage!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.redAccent),
              ),
              const SizedBox(height: 10),
              ElevatedButton(
                onPressed: _loadMembers,
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    if (_members.isEmpty) {
      return const Center(
        child: Text(
          'No members found.',
          style: TextStyle(fontSize: 16, color: Color(0xFF636780)),
        ),
      );
    }

    return ListView.separated(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      itemCount: _members.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (context, index) => _buildMemberCard(_members[index]),
    );
  }

  Widget _buildMemberCard(Map<String, dynamic> member) {
    final id = member['id']?.toString() ?? '';
    final name = (member['name'] ?? '').toString().trim();
    final email = (member['email'] ?? '').toString().trim();
    final status = (member['status'] ?? 'Inactive').toString();
    final isActive = status == 'Active';
    final accessLevel = (member['access_level'] as num?)?.toInt();
    final divisionTypeId = (member['division_type_id'] as num?)?.toInt();
    final divisionLabel = _divisionNames[divisionTypeId] ?? 'N/A';
    final isUpdating = _updatingIds.contains(id);
    final isSelf = id == AuthSession.currentUser?.id;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: const [
          BoxShadow(
            color: Color(0x11000000),
            blurRadius: 8,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        name.isEmpty ? 'Unnamed' : name,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF25273B),
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (isSelf) ...[
                      const SizedBox(width: 6),
                      const Text(
                        '(you)',
                        style: TextStyle(
                          fontSize: 11,
                          color: Color(0xFF9B9DAE),
                        ),
                      ),
                    ],
                    const SizedBox(width: 8),
                    Container(
                      padding:
                          const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: isActive
                            ? const Color(0xFFE3F6E9)
                            : const Color(0xFFFDECEA),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        status,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: isActive
                              ? const Color(0xFF1B8B5E)
                              : const Color(0xFFC62828),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  email,
                  style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFF666A80),
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: [
                    _buildChip('Division: $divisionLabel'),
                    _buildChip('Access: ${accessLevel ?? 'N/A'}'),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              SizedBox(
                height: 30,
                child: isUpdating
                    ? const SizedBox(
                        width: 30,
                        child: Center(
                          child: SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        ),
                      )
                    : isSelf
                        ? const SizedBox.shrink()
                        : TextButton(
                            onPressed: () => _setStatus(
                              member,
                              isActive ? 'Inactive' : 'Active',
                            ),
                            style: TextButton.styleFrom(
                              padding: const EdgeInsets.symmetric(horizontal: 10),
                              minimumSize: Size.zero,
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                            child: Text(
                              isActive ? 'Deactivate' : 'Activate',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: isActive
                                    ? const Color(0xFFC62828)
                                    : const Color(0xFF1B8B5E),
                              ),
                            ),
                          ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildChip(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: const Color(0xFFF1F2F6),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        text,
        style: const TextStyle(fontSize: 11, color: Color(0xFF636780)),
      ),
    );
  }
}
