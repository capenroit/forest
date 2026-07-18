import 'dart:math';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'activity_model.dart';

class ApiService {
  // Supabase Configuration
  static const String supabaseUrl = 'https://izemjvfzbfdlayewhxfy.supabase.co';
  static const String supabaseAnonKey =
      'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Iml6ZW1qdmZ6YmZkbGF5ZXdoeGZ5Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzI2MzU5NTEsImV4cCI6MjA4ODIxMTk1MX0.VMiQELwUVkGM_3jAsT_DFL2p_mddXnWbLTOY5h2DHhQ';

  // Get Supabase client instance
  static SupabaseClient get _client => Supabase.instance.client;
  static const String _treeSurvivalTable = 'tree_survival_monitoring';

  // Initialize Supabase
  static Future<void> initialize() async {
    try {
      await Supabase.initialize(
        url: supabaseUrl,
        anonKey: supabaseAnonKey,
      );

    } catch (e) {

    }
  }

  // ===== DEBUG/HEALTH CHECK =====

  /// Test Supabase connectivity
  static Future<bool> testConnection() async {
    try {

      await _client.from('tree_growing').select('COUNT(*)').limit(1);

      return true;
    } catch (e) {

      return false;
    }
  }

  // ===== ACTIVITY ENDPOINTS =====

  /// Fetch all activities from database
  static Future<List<Activity>> getAllActivities() async {
    try {
      final data = await _client
          .from('activities')
          .select()
          .order('created_at', ascending: false);

      return (data as List<dynamic>)
          .map((json) => Activity.fromJson(json as Map<String, dynamic>))
          .toList();
    } catch (e) {
      throw Exception('Error fetching activities: $e');
    }
  }

  /// Get single activity by ID
  static Future<Activity> getActivity(int id) async {
    try {
      final data =
          await _client.from('activities').select().eq('id', id).single();

      return Activity.fromJson(data);
    } catch (e) {
      throw Exception('Error fetching activity: $e');
    }
  }

  /// Create new activity
  static Future<Map<String, dynamic>> createActivity(
      String activityName) async {
    try {
      final response = await _client
          .from('activities')
          .insert({'title': activityName})
          .select()
          .single();

      return response;
    } catch (e) {
      throw Exception('Error creating activity: $e');
    }
  }

  /// Update activity
  static Future<Map<String, dynamic>> updateActivity(
    int id,
    String activityName,
  ) async {
    try {
      final response = await _client
          .from('activities')
          .update({'title': activityName})
          .eq('id', id)
          .select()
          .single();

      return response;
    } catch (e) {
      throw Exception('Error updating activity: $e');
    }
  }

  // ===== FLORA/FAUNA SURVEY ENDPOINTS =====

  /// Create a Flora/Fauna survey header row.
  static Future<Map<String, dynamic>> createFloraFaunaSurvey({
    required String userId,
    required String municipality,
    required String barangay,
    String? activityName,
    DateTime? surveyDate,
    double? area,
    String? details,
    String? observer,
    int projectTypeId = 3,
  }) async {
    try {
      final payload = <String, dynamic>{
        'user_id': userId,
        'municipality': municipality,
        'barangay': barangay,
        'project_type_id': projectTypeId,
        if (activityName != null && activityName.trim().isNotEmpty)
          'activity_name': activityName.trim(),
        if (surveyDate != null) 'survey_date': _formatDateOnly(surveyDate),
        if (area != null) 'area': area,
        if (details != null && details.trim().isNotEmpty)
          'details': details.trim(),
        if (observer != null && observer.trim().isNotEmpty)
          'observer': observer.trim(),
      };

      final response = await _client
          .from('flora_fauna_survey')
          .insert(payload)
          .select()
          .single();

      return response;
    } catch (e) {
      throw Exception('Error creating flora_fauna_survey: $e');
    }
  }

  /// Get recent flora/fauna survey rows.
  static Future<List<Map<String, dynamic>>> getRecentFloraFaunaSurveys({
    int limit = 100,
  }) async {
    try {
      final data = await _client
          .from('flora_fauna_survey')
          .select(
            'id, project_type_id, activity_name, municipality, barangay, details, observer, survey_date, created_at, updated_at, area',
          )
          .eq('project_type_id', 3)
          .eq('is_deleted', 0)
          .order('survey_date', ascending: false)
          .order('created_at', ascending: false)
          .limit(limit);

      return (data as List<dynamic>)
          .map((json) => Map<String, dynamic>.from(json as Map))
          .toList();
    } catch (e) {
      throw Exception('Error fetching flora_fauna_survey rows: $e');
    }
  }

  /// Soft delete a flora/fauna survey row.
  static Future<void> softDeleteFloraFaunaSurvey(int id) async {
    try {
      final response = await _client.from('flora_fauna_survey').update({
        'is_deleted': 1,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      }).eq('id', id).select('id');

      if (response is List && response.isEmpty) {
        throw Exception(
          'No record was deleted. Check row permissions or record id.',
        );
      }
    } catch (e) {
      throw Exception('Error deleting flora_fauna_survey row: $e');
    }
  }

  /// Save species detail rows linked to flora_fauna_survey.id.
  static Future<void> saveFloraFaunaSurveyDataRows({
    required int floraFaunaSurveyId,
    required List<Map<String, dynamic>> rows,
  }) async {
    if (rows.isEmpty) return;

    try {
      final payload = rows.map((row) {
        return {
          'flora_fauna_id': floraFaunaSurveyId,
          'name': (row['name'] ?? '').toString().trim(),
          'scientific_name': (row['scientific_name'] ?? '').toString().trim(),
          'species_type': (row['species_type'] ?? '').toString().trim(),
        };
      }).where((row) {
        final name = (row['name'] ?? '').toString();
        final scientificName = (row['scientific_name'] ?? '').toString();
        return name.isNotEmpty || scientificName.isNotEmpty;
      }).toList();

      if (payload.isEmpty) return;

      await _client.from('flora_fauna_survey_data').insert(payload);
    } catch (e) {
      throw Exception('Error saving flora_fauna_survey_data rows: $e');
    }
  }

  /// Save a photo row for the flora/fauna flow.
  static Future<Map<String, dynamic>> createPhotoRow({
    required int projectTypeId,
    required int activityId,
    required String photoUrl,
    String? name,
  }) async {
    try {
      final payload = <String, dynamic>{
        'project_type_id': projectTypeId,
        'activity_id': activityId,
        'photo_url': photoUrl,
        if (name != null && name.trim().isNotEmpty) 'name': name.trim(),
      };

      final response = await _client.from('photo').insert(payload).select().single();
      return response;
    } catch (e) {
      throw Exception('Error creating photo row: $e');
    }
  }

  /// Save captured coordinates to location table.
  ///
  /// location.activity_id references flora_fauna_survey.id for this flow.
  static Future<void> saveLocationRowsForActivity({
    required int activityId,
    required List<Map<String, dynamic>> coordinates,
    int activityTypeId = 3,
  }) async {
    if (coordinates.isEmpty) return;

    try {
      final payload = <Map<String, dynamic>>[];

      for (final coordinate in coordinates) {
        final latitude = (coordinate['lat'] as num?)?.toDouble();
        final longitude = (coordinate['lng'] as num?)?.toDouble();
        if (latitude == null || longitude == null) continue;

        payload.add({
          'activity_id': activityId,
          'activity_type_id': activityTypeId,
          'latitude': latitude,
          'longitude': longitude,
          'isDeleted': 0,
        });
      }

      if (payload.isEmpty) return;

      await _client.from('location').insert(payload);
    } catch (e) {
      throw Exception('Error saving location rows: $e');
    }
  }

  /// Delete activity
  static Future<void> deleteActivity(int id) async {
    try {
      await _client.from('activities').delete().eq('id', id);
    } catch (e) {
      throw Exception('Error deleting activity: $e');
    }
  }

  // ===== TREE PLANTING ENDPOINTS =====

  /// Save tree planting record with full details (creates new or updates existing)
  static Future<Map<String, dynamic>> saveTreePlanting(
      TreePlanting planting) async {
    try {


      // Check if this is an update (ID exists) or create (no ID)
      if (planting.id != null && planting.id!.isNotEmpty) {
        // UPDATE existing record
        final response = await _client
            .from('tree_growing')
            .update(planting.toJson())
            .eq('id', planting.id!)
            .select()
            .single();


        return response;
      } else {
        // CREATE new record

        final response = await _client
            .from('tree_growing')
            .insert(planting.toJson())
            .select()
            .single();


        return response;
      }
    } catch (e) {

      throw Exception('Error saving tree planting: $e');
    }
  }

  /// Save per-seed rows for a tree growing record
  static Future<void> saveTreeGrowingDataRows({
    required int treeGrowingId,
    required List<Map<String, dynamic>> seedRows,
  }) async {
    if (seedRows.isEmpty) return;

    try {
      final payload = seedRows.map((row) {
        return {
          'tree_growing_id': treeGrowingId,
          'seed_name': row['seed_name'],
          'seedling_count': row['seedling_count'],
        };
      }).toList();

      await _client.from('tree_growing_data').insert(payload);
    } catch (e) {

      throw Exception('Error saving tree_growing_data rows: $e');
    }
  }

  /// Replace per-seed rows for a tree growing record.
  ///
  /// Used by edit flow to prevent duplicate seedling rows.
  static Future<void> replaceTreeGrowingDataRows({
    required int treeGrowingId,
    required List<Map<String, dynamic>> seedRows,
  }) async {
    try {
      await _client
          .from('tree_growing_data')
          .delete()
          .eq('tree_growing_id', treeGrowingId);

      if (seedRows.isEmpty) return;

      final payload = seedRows.map((row) {
        return {
          'tree_growing_id': treeGrowingId,
          'seed_name': row['seed_name'],
          'seedling_count': row['seedling_count'],
        };
      }).toList();

      await _client.from('tree_growing_data').insert(payload);
    } catch (e) {

      throw Exception('Error replacing tree_growing_data rows: $e');
    }
  }

  /// Fetch seed rows grouped by tree_growing_id.
  ///
  /// Relationship used by UI:
  /// tree_growing.seq_id == tree_growing_data.tree_growing_id
  static Future<Map<int, List<Map<String, dynamic>>>>
      getTreeGrowingDataByTreeGrowingIds(List<int> treeGrowingIds) async {
    if (treeGrowingIds.isEmpty) return <int, List<Map<String, dynamic>>>{};

    final uniqueIds = treeGrowingIds.toSet().toList()..sort();

    try {
      final groupedRows = await Future.wait(
        uniqueIds.map((treeGrowingId) async {
          final data = await _client
              .from('tree_growing_data')
              .select('tree_growing_id, seed_name, seedling_count')
              .eq('tree_growing_id', treeGrowingId);

          return List<Map<String, dynamic>>.from(data as List<dynamic>);
        }),
      );

      final result = <int, List<Map<String, dynamic>>>{};

      for (final rows in groupedRows) {
        for (final row in rows) {
          final treeGrowingId = (row['tree_growing_id'] as num?)?.toInt();
          if (treeGrowingId == null) continue;

          result.putIfAbsent(treeGrowingId, () => <Map<String, dynamic>>[]);
          result[treeGrowingId]!.add(row);
        }
      }

      return result;
    } catch (e) {
      throw Exception('Error fetching tree_growing_data rows: $e');
    }
  }

  /// Get all tree planting records
  static Future<List<TreePlanting>> getAllTreePlantings(
      {int limit = 500, int offset = 0}) async {
    try {
      final data = await _client
          .from('tree_growing')
          .select()
          .eq('is_deleted', 0)
          .order('created_at', ascending: false)
          .range(offset, offset + limit - 1);



      final result = (data as List<dynamic>)
          .map((json) => TreePlanting.fromJson(json as Map<String, dynamic>))
          .toList();


      return result;
    } catch (e) {


      // Check if it's a table not found error
      if (e.toString().contains('PGRST203') ||
          e.toString().contains('Could not find')) {


        throw Exception(
            'Database table not found: tree_growing. Please contact administrator to create the table.');
      }

      throw Exception('Error fetching tree plantings: $e');
    }
  }

  /// Get tree planting records by project type ID.
  static Future<List<TreePlanting>> getTreePlantingsByProjectTypeId(
    int projectTypeId, {
    int limit = 500,
    int offset = 0,
  }) async {
    try {
      final data = await _client
          .from('tree_growing')
          .select()
          .eq('project_type_id', projectTypeId)
          .eq('is_deleted', 0)
          .order('created_at', ascending: false)
          .range(offset, offset + limit - 1);

      return (data as List<dynamic>)
          .map((json) => TreePlanting.fromJson(json as Map<String, dynamic>))
          .toList();
    } catch (e) {
      throw Exception('Error fetching tree plantings by project type: $e');
    }
  }

  static String _formatDateOnly(DateTime value) {
    final year = value.year.toString().padLeft(4, '0');
    final month = value.month.toString().padLeft(2, '0');
    final day = value.day.toString().padLeft(2, '0');
    return '$year-$month-$day';
  }

  /// Save Monitoring of Tree Survival record.
  ///
  /// seq_id is not sent; it should be auto-generated by the database identity.
  static Future<Map<String, dynamic>> saveTreeSurvivalMonitoring({
    required String userId,
    required int activityId,
    required int numberTreeSurvived,
    int? quarter,
    String? details,
    required DateTime date,
  }) async {
    final basePayload = <String, dynamic>{
      'user_id': userId,
      'activity_id': activityId,
      'details': details,
      if (quarter != null) 'quarter': quarter,
      'date': _formatDateOnly(date),
    };

    try {
      final payload = {
        ...basePayload,
        'number_tree_survived': numberTreeSurvived,
      };

      return await _client
          .from(_treeSurvivalTable)
          .insert(payload)
          .select()
          .single();
    } catch (e) {
      // Compatibility fallback for schemas that use a shorter column name.
      if (e is PostgrestException) {
        final messageText = e.message.toString();
        final detailsText = e.details?.toString() ?? '';
        if (messageText.contains('number_tree_survived') ||
            detailsText.contains('number_tree_survived')) {
        final fallbackPayload = {
          ...basePayload,
          'number_tree_sur': numberTreeSurvived,
        };

        return await _client
            .from(_treeSurvivalTable)
            .insert(fallbackPayload)
            .select()
            .single();
        }

        if (messageText.contains('quarter') || detailsText.contains('quarter')) {
          final payloadWithoutQuarter = {
            'user_id': userId,
            'activity_id': activityId,
            'details': details,
            'date': _formatDateOnly(date),
            'number_tree_survived': numberTreeSurvived,
          };

          return await _client
              .from(_treeSurvivalTable)
              .insert(payloadWithoutQuarter)
              .select()
              .single();
        }
      }
      throw Exception('Error saving tree survival monitoring: $e');
    }
  }

  /// Load Monitoring of Tree Survival records directly from Supabase table.
  static Future<List<Map<String, dynamic>>> getTreeSurvivalMonitoringRecords({
    int limit = 200,
    int offset = 0,
  }) async {
    try {
      final monitoringRows = await _client
          .from(_treeSurvivalTable)
          .select()
          .order('created_at', ascending: false)
          .range(offset, offset + limit - 1);
      return List<Map<String, dynamic>>.from(monitoringRows as List<dynamic>);
    } catch (e) {
      throw Exception('Error fetching tree survival monitoring records: $e');
    }
  }

  /// Resolve tree_growing seq_id values to activity info.
  static Future<Map<int, Map<String, String>>> getTreeGrowingActivityInfoBySeqIds(
    List<int> seqIds,
  ) async {
    if (seqIds.isEmpty) return <int, Map<String, String>>{};

    final uniqueSeqIds = seqIds.toSet().toList()..sort();

    try {
      final rows = await _client
          .from('tree_growing')
          .select('seq_id, activity_name, municipality, barangay')
          .inFilter('seq_id', uniqueSeqIds);

      final result = <int, Map<String, String>>{};
      for (final row in List<Map<String, dynamic>>.from(rows as List<dynamic>)) {
        final seqId = (row['seq_id'] as num?)?.toInt();
        if (seqId == null) continue;

        result[seqId] = {
          'activity_name': (row['activity_name'] ?? '').toString().trim(),
          'municipality': (row['municipality'] ?? '').toString().trim(),
          'barangay': (row['barangay'] ?? '').toString().trim(),
        };
      }

      return result;
    } catch (e) {
      throw Exception('Error fetching tree growing activity info: $e');
    }
  }

  /// Get tree planting records by activity ID
  static Future<List<TreePlanting>> getTreePlantingsByActivity(
      int activityId) async {
    try {

      final data = await _client
          .from('tree_growing')
          .select()
          .eq('activity_id', activityId)
          .order('created_at', ascending: false);

      return (data as List<dynamic>)
          .map((json) => TreePlanting.fromJson(json as Map<String, dynamic>))
          .toList();
    } catch (e) {
      throw Exception('Error fetching tree plantings: $e');
    }
  }

  /// Get single tree planting by ID
  static Future<TreePlanting> getTreePlanting(int id) async {
    try {
      final data =
          await _client.from('tree_growing').select().eq('id', id).single();

      return TreePlanting.fromJson(data);
    } catch (e) {
      throw Exception('Error fetching tree planting: $e');
    }
  }

  /// Update tree planting record
  static Future<Map<String, dynamic>> updateTreePlanting(
    int id,
    TreePlanting planting,
  ) async {
    try {
      final response = await _client
          .from('tree_growing')
          .update(planting.toJson())
          .eq('id', id)
          .select()
          .single();

      return response;
    } catch (e) {
      throw Exception('Error updating tree planting: $e');
    }
  }

  /// Delete tree planting record
  static Future<void> deleteTreePlanting(Object id) async {
    try {
      await _client.from('tree_growing').update({
        'is_deleted': 1,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      }).eq('id', id);
    } catch (e) {
      throw Exception('Error deleting tree planting: $e');
    }
  }

  // ===== TREE PLANTING AREA ENDPOINTS =====

  /// Create new tree planting area with photo
  static Future<Map<String, dynamic>> createTreePlantingArea({
    required String treePlantingId,
    required double latitude,
    required double longitude,
    String? photoUrl,
    String? photourlAreaId,
  }) async {
    try {
      final data = {
        'tree_planting_id': treePlantingId,
        'latitude': latitude,
        'longitude': longitude,
        'photo_url': photoUrl,
      };


      final response =
          await _client.from('tree_planting_areas').insert(data).select();



      if (response.isEmpty) {

        return {
          'tree_planting_id': treePlantingId,
          'latitude': latitude,
          'longitude': longitude,
          'photo_url': photoUrl,
        };
      }



      return response[0];
    } catch (e) {



      if (e is PostgrestException) {

      }

      throw Exception('Error creating tree planting area: $e');
    }
  }

  /// Get areas by tree planting ID
  static Future<List<TreePlantingArea>> getTreePlantingAreasByTreePlanting(
      String treePlantingId) async {
    try {
      final data = await _client
          .from('tree_planting_areas')
          .select()
          .eq('tree_planting_id', treePlantingId)
          .order('created_at', ascending: false);

      return (data as List<dynamic>)
          .map(
              (json) => TreePlantingArea.fromJson(json as Map<String, dynamic>))
          .toList();
    } catch (e) {
      throw Exception('Error fetching tree planting areas: $e');
    }
  }

  // ===== PLANTING AREA ENDPOINTS (LEGACY) =====

  /// Fetch all planting areas
  static Future<List<PlantingArea>> getAllAreas() async {
    try {
      final data = await _client
          .from('areas')
          .select()
          .order('created_at', ascending: false);

      return (data as List<dynamic>)
          .map((json) => PlantingArea.fromJson(json as Map<String, dynamic>))
          .toList();
    } catch (e) {
      throw Exception('Error fetching areas: $e');
    }
  }

  /// Get areas by activity ID
  static Future<List<PlantingArea>> getAreasByActivity(int activityId) async {
    try {
      final data = await _client
          .from('areas')
          .select()
          .eq('activity_id', activityId)
          .order('created_at', ascending: false);

      return (data as List<dynamic>)
          .map((json) => PlantingArea.fromJson(json as Map<String, dynamic>))
          .toList();
    } catch (e) {
      throw Exception('Error fetching areas: $e');
    }
  }

  /// Get single area by ID
  static Future<PlantingArea> getArea(int id) async {
    try {
      final data = await _client.from('areas').select().eq('id', id).single();

      return PlantingArea.fromJson(data);
    } catch (e) {
      throw Exception('Error fetching area: $e');
    }
  }

  /// Create new planting area (coordinate)
  static Future<Map<String, dynamic>> createArea(
    int activityId,
    double latitude,
    double longitude,
    String? photoUrl,
  ) async {
    try {
      final response = await _client
          .from('areas')
          .insert({
            'activity_id': activityId,
            'latitude': latitude,
            'longitude': longitude,
            'url': photoUrl,
          })
          .select()
          .single();

      return response;
    } catch (e) {
      throw Exception('Error creating area: $e');
    }
  }

  /// Add multiple coordinates for an activity
  static Future<List<Map<String, dynamic>>> createMultipleAreas(
    int activityId,
    List<Map<String, String?>> coordinates,
  ) async {
    try {
      final results = <Map<String, dynamic>>[];
      for (var coord in coordinates) {
        final parts = (coord['coordinate'] ?? '').split(',');
        if (parts.length == 2) {
          final response = await _client
              .from('areas')
              .insert({
                'activity_id': activityId,
                'latitude': double.tryParse(parts[0].trim()),
                'longitude': double.tryParse(parts[1].trim()),
                'url': coord['photourl'],
              })
              .select()
              .single();

          results.add(response);
        }
      }
      return results;
    } catch (e) {
      throw Exception('Error creating areas: $e');
    }
  }

  /// Update planting area
  static Future<Map<String, dynamic>> updateArea(
    int id,
    String coordinate,
    String? photoUrl,
  ) async {
    try {
      final parts = coordinate.split(',');
      final updateData = <String, dynamic>{
        'url': photoUrl,
      };

      if (parts.length == 2) {
        updateData['latitude'] = double.tryParse(parts[0].trim());
        updateData['longitude'] = double.tryParse(parts[1].trim());
      }

      final response = await _client
          .from('areas')
          .update(updateData)
          .eq('id', id)
          .select()
          .single();

      return response;
    } catch (e) {
      throw Exception('Error updating area: $e');
    }
  }

  /// Delete planting area
  static Future<void> deleteArea(int id) async {
    try {
      await _client.from('areas').delete().eq('id', id);
    } catch (e) {
      throw Exception('Error deleting area: $e');
    }
  }

  // ===== PHOTOURL AREA ENDPOINTS =====

  /// Create a new photourl area with coordinates and optional photo
  static Future<Map<String, dynamic>> createPhotourlArea({
    required double latitude,
    required double longitude,
    String? photoUrl,
    int? activityId,
    int? activityTypeId,
  }) async {
    try {







      final data = {
        'latitude': latitude,
        'longitude': longitude,
        'photo_url': photoUrl,
      };

      // Only add optional fields if they're not null
      if (activityId != null) {
        data['activity_id'] = activityId;
      }
      if (activityTypeId != null) {
        data['activity_type_id'] = activityTypeId;
      }

      final response =
          await _client.from('photourl_area').insert(data).select();

      if (response.isEmpty) {

        throw Exception('Failed to create photourl area - no response');
      }

      final createdArea = response[0];







      return createdArea;
    } catch (e) {

      throw Exception('Error creating photourl area: $e');
    }
  }

  /// Update photourl area with photo URL
  static Future<Map<String, dynamic>> updatePhotourlAreaPhotoUrl({
    required String photourlAreaId,
    required String photoUrl,
    String? photoName,
  }) async {
    try {
      final updateData = {'photo_url': photoUrl};
      if (photoName != null) {
        updateData['name'] = photoName;
      }

      final response = await _client
          .from('photourl_area')
          .update(updateData)
          .eq('id', photourlAreaId)
          .select();

      if (response.isEmpty) {

        throw Exception('Failed to update photourl area - no response');
      }

      final updatedArea = response[0];
      return updatedArea;
    } catch (e) {

      throw Exception('Error updating photourl area photo: $e');
    }
  }

  /// Update photourl area coordinates.
  static Future<void> updatePhotourlAreaCoordinates({
    required String photourlAreaId,
    required double latitude,
    required double longitude,
  }) async {
    try {
      await _client
          .from('photourl_area')
          .update({
            'latitude': latitude,
            'longitude': longitude,
          })
          .eq('id', photourlAreaId);
    } catch (e) {
      throw Exception('Error updating photourl area coordinates: $e');
    }
  }

  /// Mark photourl area as deleted (soft delete via isDeleted flag)
  static Future<void> deletePhotourlArea(String photourlAreaId) async {
    try {



      await _client
          .from('photourl_area')
          .update({'isDeleted': 1}).eq('id', photourlAreaId);



    } catch (e) {

      throw Exception('Error deleting photourl area: $e');
    }
  }

  /// Get all photourl areas
  static Future<List<Map<String, dynamic>>> getPhotourlAreas() async {
    try {
      final data = await _client
          .from('photourl_area')
          .select()
          .order('created_at', ascending: false);

      return List<Map<String, dynamic>>.from(data as List);
    } catch (e) {

      return [];
    }
  }

  /// Find photourl area by ID
  static Future<Map<String, dynamic>?> getPhotourlArea(String id) async {
    try {
      final data =
          await _client.from('photourl_area').select().eq('id', id).single();

      return data;
    } catch (e) {

      return null;
    }
  }

  /// Get photourl area by seq_id to fetch coordinates
  static Future<String?> getPhotourlAreaCoordinates(int seqId) async {
    try {

      final data = await _client
          .from('photourl_area')
          .select('latitude, longitude')
          .eq('seq_id', seqId)
          .single();

      final latitude = data['latitude'];
      final longitude = data['longitude'];
      final coordinates = '$latitude, $longitude';

      return coordinates;
    } catch (e) {

      return null;
    }
  }

  /// Get all photourl areas by seq_id to fetch all coordinates
  static Future<List<String>> getPhotourlAreaCoordinatesBySeqId(
      int seqId) async {
    try {

      final data = await _client
          .from('photourl_area')
          .select('latitude, longitude, activity_id')
          .eq('activity_id', seqId)
          .order('activity_id', ascending: true);

      if (data.isNotEmpty) {
        final coordinates = (data as List)
            .map((item) => '${item['latitude']}, ${item['longitude']}')
            .toList();

        return coordinates;
      }
      return [];
    } catch (e) {

      return [];
    }
  }

  /// Get tree planting by ID to extract seq_id
  static Future<Map<String, dynamic>?> getTreePlantingById(
      String treePlantingId) async {
    try {

      final data = await _client
          .from('tree_growing')
          .select(
              'id, seq_id, activity_name, municipality, barangay, tree_species, number_of_trees, area_cover, created_at')
          .eq('id', treePlantingId)
          .single();

      return data;
    } catch (e) {

      return null;
    }
  }

  /// Get photourl areas by activity_id (for edit mode)
  static Future<List<Map<String, dynamic>>> getPhotourlAreasByActivityId(
      int activityId) async {
    try {
      final data = await _client
          .from('photourl_area')
          .select()
          .eq('activity_id', activityId)
          .eq('isDeleted', 0)
          .order('seq_id', ascending: true);


      return List<Map<String, dynamic>>.from(data as List);
    } catch (e) {

      return [];
    }
  }

  /// Find closest photourl area to coordinates
  /// Uses simple distance calculation to find the nearest area
  static Future<String?> findClosestPhotourlAreaId(
    double latitude,
    double longitude,
  ) async {
    try {
      final areas = await getPhotourlAreas();

      if (areas.isEmpty) {

        return null;
      }

      // Calculate distance to each area and find closest
      double minDistance = double.infinity;
      String? closestAreaId;

      for (var area in areas) {
        final areaLat = (area['latitude'] as num?)?.toDouble() ?? 0.0;
        final areaLng = (area['longitude'] as num?)?.toDouble() ?? 0.0;

        // Simple Euclidean distance (good enough for nearby areas)
        final distance =
            _calculateDistance(latitude, longitude, areaLat, areaLng);

        if (distance < minDistance) {
          minDistance = distance;
          closestAreaId = area['id']?.toString();
        }
      }

      return closestAreaId;
    } catch (e) {

      return null;
    }
  }

  /// Calculate simple distance between two coordinates (in degrees, not km)
  static double _calculateDistance(
    double lat1,
    double lng1,
    double lat2,
    double lng2,
  ) {
    final dLat = lat2 - lat1;
    final dLng = lng2 - lng1;
    return sqrt(dLat * dLat + dLng * dLng);
  }
}

