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

