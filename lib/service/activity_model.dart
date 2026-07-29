class Activity {
  final String id;
  final String activityname;
  final DateTime logdate;

  Activity({
    required this.id,
    required this.activityname,
    required this.logdate,
  });

  factory Activity.fromJson(Map<String, dynamic> json) {
    return Activity(
      id: json['id'].toString(),
      activityname: json['activityname'] as String? ?? json['name'] as String? ?? '',
      logdate: json['logdate'] != null 
        ? DateTime.parse(json['logdate'] as String)
        : (json['created_at'] != null ? DateTime.parse(json['created_at'] as String) : DateTime.now()),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'activityname': activityname,
    };
  }
}

class TreePlanting {
  final String? id;
  final int? seqId;  // Sequence ID for photourl_area lookup
  final int? projectTypeId;
  final String userid;  // UUID from Supabase Auth
  final String? activityName;
  final String barangay;
  final String municipality;
  final String? details;
  final String treeSpecies;
  final int numberOfTrees;
  final double? areaCover;
  final double? perimeter;  // Perimeter in kilometers, calculated from polygon coordinates
  final DateTime date;
  final DateTime? updatedAt;  // Track when record was last modified
  final int isSync;
  final DateTime? logdate;

  TreePlanting({
    this.id,
    this.seqId,
    this.projectTypeId,
    required this.userid,
    this.activityName,
    required this.barangay,
    required this.municipality,
    this.details,
    required this.treeSpecies,
    required this.numberOfTrees,
    this.areaCover,
    this.perimeter,
    required this.date,
    this.updatedAt,
    this.isSync = 0,
    this.logdate,
  });

  factory TreePlanting.fromJson(Map<String, dynamic> json) {
    try {
      return TreePlanting(
        id: json['id']?.toString(),
        seqId: json['seq_id'] as int?,
        projectTypeId: json['project_type_id'] as int? ?? json['projectTypeId'] as int?,
        userid: (json['user_id'] ?? json['userid'] ?? '').toString(),
        activityName: json['activity_name'] as String? ?? json['activityName'] as String?,
        barangay: json['barangay'] as String? ?? '',
        municipality: json['municipality'] as String? ?? '',
        details: json['details'] as String?,
        treeSpecies: json['tree_species'] as String? ?? json['treeSpecies'] as String? ?? json['treeSpicies'] as String? ?? 'Unknown',
        numberOfTrees: json['number_of_trees'] as int? ?? json['numberOfTrees'] as int? ?? 0,
        areaCover: (json['area_cover'] as num? ?? json['areaCover'] as num?)?.toDouble(),
        perimeter: (json['perimeter'] as num?)?.toDouble(),
        // Use planting_date if available (the actual planting date), otherwise fallback
        date: json['planting_date'] != null && json['planting_date'].toString().isNotEmpty
          ? DateTime.parse(json['planting_date'] as String)
          : (json['created_at'] != null 
            ? DateTime.parse(json['created_at'] as String)
            : (json['date'] != null ? DateTime.parse(json['date'] as String) : DateTime.now())),
        // Track last modification time separately
        updatedAt: json['updated_at'] != null 
          ? DateTime.parse(json['updated_at'] as String)
          : null,
        isSync: json['is_synced'] as int? ?? json['isSync'] as int? ?? 0,
        logdate: json['created_at'] != null ? DateTime.parse(json['created_at'] as String) : null,
      );
    } catch (e) {
      rethrow;
    }
  }

  Map<String, dynamic> toJson() {
    final json = {
      'user_id': userid,
      'project_type_id': projectTypeId,
      'activity_name': activityName,
      'barangay': barangay,
      'municipality': municipality,
      'details': details,
      'tree_species': treeSpecies,
      'number_of_trees': numberOfTrees,
      'area_cover': areaCover,
      'perimeter': perimeter,
      // Save as date-only to avoid timezone day shifts.
      'planting_date': _formatDateOnly(date),
      'updated_at': DateTime.now().toUtc().toIso8601String(),  // Last modified timestamp in UTC
    };
    
    // Include ID field if present (for updates)
    if (id != null && id!.isNotEmpty) {
      json['id'] = id;
    }
    
    return json;
  }

  String _formatDateOnly(DateTime value) {
    final year = value.year.toString().padLeft(4, '0');
    final month = value.month.toString().padLeft(2, '0');
    final day = value.day.toString().padLeft(2, '0');
    return '$year-$month-$day';
  }
}

class TreePlantingArea {
  final String? id;
  final String treePlantingId;
  final double latitude;
  final double longitude;
  final String? photoUrl;

  TreePlantingArea({
    this.id,
    required this.treePlantingId,
    required this.latitude,
    required this.longitude,
    this.photoUrl,
  });

  factory TreePlantingArea.fromJson(Map<String, dynamic> json) {
    return TreePlantingArea(
      id: json['id']?.toString(),
      treePlantingId: (json['tree_planting_id'] ?? json['treePlantingId'] ?? '').toString(),
      latitude: (json['latitude'] as num?)?.toDouble() ?? 0.0,
      longitude: (json['longitude'] as num?)?.toDouble() ?? 0.0,
      photoUrl: json['photo_url'] as String? ?? json['photourl'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'tree_planting_id': treePlantingId,
      'latitude': latitude,
      'longitude': longitude,
      'photo_url': photoUrl,
    };
  }
}

class HabitatAssessment {
  final int? id;
  final int userid;
  final String municipality;
  final String barangay;
  final String typeAssessment;
  final double? area;
  final DateTime date;

  HabitatAssessment({
    this.id,
    required this.userid,
    required this.municipality,
    required this.barangay,
    required this.typeAssessment,
    this.area,
    required this.date,
  });

  factory HabitatAssessment.fromJson(Map<String, dynamic> json) {
    return HabitatAssessment(
      id: (json['id'] as num?)?.toInt(),
      userid: (json['userid'] as num?)?.toInt() ?? 0,
      municipality: json['municipality'] as String? ?? '',
      barangay: json['barangay'] as String? ?? '',
      typeAssessment: json['type_assessment'] as String? ?? '',
      area: (json['area'] as num?)?.toDouble(),
      date: json['created_at'] != null
          ? DateTime.parse(json['created_at'] as String)
          : DateTime.now(),
    );
  }
}

class MarineProtectedArea {
  final int? id;
  final String name;
  final String municipality;
  final String barangay;
  final double? area;
  final String? ordinance;
  final DateTime date;

  MarineProtectedArea({
    this.id,
    required this.name,
    required this.municipality,
    required this.barangay,
    this.area,
    this.ordinance,
    required this.date,
  });

  factory MarineProtectedArea.fromJson(Map<String, dynamic> json) {
    return MarineProtectedArea(
      id: (json['id'] as num?)?.toInt(),
      name: json['name'] as String? ?? '',
      municipality: json['municipality'] as String? ?? '',
      barangay: json['barangay'] as String? ?? '',
      area: (json['area'] as num?)?.toDouble(),
      ordinance: json['ordinance'] as String?,
      date: json['created_at'] != null
          ? DateTime.parse(json['created_at'] as String)
          : DateTime.now(),
    );
  }
}

/// Legacy PlantingArea model (for backwards compatibility)
class PlantingArea {
  final String? id;
  final String activityid;
  final String coordinate;
  final String? photourl;

  PlantingArea({
    this.id,
    required this.activityid,
    required this.coordinate,
    this.photourl,
  });

  factory PlantingArea.fromJson(Map<String, dynamic> json) {
    return PlantingArea(
      id: json['id']?.toString(),
      activityid: json['activityid'].toString(),
      coordinate: json['coordinate'] as String,
      photourl: json['photourl'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'activityid': activityid,
      'coordinate': coordinate,
      'photourl': photourl,
    };
  }
}


