import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

class AppUser {
  final String id;
  final int? seqId;
  final String email;
  final String name;
  final int? accessLevel;
  final String status;
  final int? divisionTypeId;

  AppUser({
    required this.id,
    this.seqId,
    required this.email,
    required this.name,
    required this.accessLevel,
    required this.status,
    this.divisionTypeId,
  });

  factory AppUser.fromJson(Map<String, dynamic> json, {required String id}) {
    return AppUser(
      id: id,
      seqId: _readInt(json['seq_id']),
      email: json['email'] as String? ?? '',
      name: json['name'] as String? ?? '',
      accessLevel: _readInt(json['access_level']),
      status: json['status']?.toString() ?? '',
      divisionTypeId: _readInt(json['division_type_id']),
    );
  }

  static int? _readInt(dynamic value) {
    if (value is int) {
      return value;
    }

    if (value is String) {
      return int.tryParse(value);
    }

    return null;
  }

  Map<String, dynamic> toJson() {
    return {
      'seq_id': seqId,
      'email': email,
      'name': name,
      'access_level': accessLevel,
      'status': status,
      'division_type_id': divisionTypeId,
    };
  }
}

class AuthSession {
  static AppUser? currentUser;

  // Key shared with the login screen's own (pre-existing) cache write, so
  // a user who last signed in from there is still recognized here.
  static const String _cachedUserKey = 'cached_login_user';

  /// Persists [user] to disk so their name/role are still available after
  /// an app restart with no connectivity (see [loadCachedUser]).
  static Future<void> cacheUser(AppUser user) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _cachedUserKey,
        jsonEncode({'id': user.id, ...user.toJson()}),
      );
    } catch (_) {
      // Best effort — caching failure just means no offline fallback later.
    }
  }

  /// Loads the last cached user from disk into [currentUser], if any.
  /// Returns the loaded user, or null when nothing usable was cached.
  static Future<AppUser?> loadCachedUser() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cachedUserJson = prefs.getString(_cachedUserKey);
      if (cachedUserJson == null || cachedUserJson.isEmpty) return null;

      final cached = jsonDecode(cachedUserJson) as Map<String, dynamic>;
      final cachedUserId = cached['id'] as String?;
      if (cachedUserId == null || cachedUserId.isEmpty) return null;

      final user = AppUser.fromJson(cached, id: cachedUserId);
      currentUser = user;
      return user;
    } catch (_) {
      return null;
    }
  }

  static Future<void> clearCachedUser() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_cachedUserKey);
    } catch (_) {
      // Best effort.
    }
  }

  static bool get isAdmin {
    final level = currentUser?.accessLevel;
    return level == 1 || level == 2;
  }

  /// Whether the current user may delete a record created by [creatorId]
  /// (a uuid matching AppUser.id) — the record's owner, or an admin.
  /// Records with no known creator (legacy rows, or a null/empty id) are
  /// admin-only, since ownership can't be established for them.
  static bool canDelete(String? creatorId) {
    if (isAdmin) return true;
    if (creatorId == null || creatorId.isEmpty) return false;
    return currentUser?.id == creatorId;
  }

  /// Same as [canDelete], for tables that track the creator via
  /// users.seq_id (an int) instead of the uuid id.
  static bool canDeleteBySeqId(int? creatorSeqId) {
    if (isAdmin) return true;
    if (creatorSeqId == null) return false;
    return currentUser?.seqId == creatorSeqId;
  }
}

