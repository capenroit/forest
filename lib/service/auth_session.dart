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
}

