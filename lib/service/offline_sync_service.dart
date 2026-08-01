import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'activity_model.dart';
import 'api_service.dart';

class OfflineSyncService {
  static const String _queueFileName = 'offline_queue.json';
  static const String _activitiesCacheFileName = 'activities_cache.json';
  static const String _photosDirName = 'offline_photos';
  static const String _storageBucketName = 'Forest Management';
  static const int _treeGrowingActivityTypeId = 1;
  static const Map<int, String> _storageFolderByProjectType = {
    1: 'tree_growing',
    6: 'mangrove_planting',
  };

  // ─── Platform gate ──────────────────────────────────────────────────────
  //
  // Offline mode (queueing + local caches) only engages on Android. Every
  // other platform (iOS, Windows, macOS, Linux, web) behaves exactly as it
  // did before this feature existed: hasInternetConnection() always reports
  // "online", so every save/sync call site below simply takes its normal
  // online path and no queueing ever happens there.

  static bool get isOfflineCapable => !kIsWeb && Platform.isAndroid;

  static Future<bool> hasInternetConnection() async {
    if (!isOfflineCapable) {
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

  // ─── Paths ───────────────────────────────────────────────────────────────

  static Future<File> _queueFile() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/$_queueFileName');
  }

  static Future<File> _activitiesCacheFile() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/$_activitiesCacheFileName');
  }

  static Future<Directory> _photosDir() async {
    final dir = await getApplicationDocumentsDirectory();
    final photosDir = Directory('${dir.path}/$_photosDirName');
    if (!await photosDir.exists()) {
      await photosDir.create(recursive: true);
    }
    return photosDir;
  }

  // ─── Queue persistence ────────────────────────────────────────────────────

  static Future<List<Map<String, dynamic>>> _loadQueue() async {
    try {
      final file = await _queueFile();
      if (!await file.exists()) return [];
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is List) {
        return decoded.cast<Map<String, dynamic>>();
      }
    } catch (_) {
      // Corrupted queue — start fresh.
    }
    return [];
  }

  static Future<void> _saveQueue(List<Map<String, dynamic>> queue) async {
    try {
      final file = await _queueFile();
      await file.writeAsString(jsonEncode(queue));
    } catch (_) {
      // Best effort.
    }
  }

  // ─── Photo staging (temp camera file -> stable offline storage) ─────────

  /// Copies a temporary camera file into stable local storage so it survives
  /// until the queued record syncs. Returns the stable path, or null if
  /// there was nothing to copy.
  static Future<String?> stagePhoto(String? tempPath) async {
    if (tempPath == null || tempPath.isEmpty) return null;

    try {
      final src = File(tempPath);
      if (!await src.exists()) return null;

      final photosDir = await _photosDir();
      final ext = _extensionOf(tempPath);
      final fileName =
          'photo_${DateTime.now().millisecondsSinceEpoch}_${_rand()}.$ext';
      final dst = File('${photosDir.path}/$fileName');
      await src.copy(dst.path);
      return dst.path;
    } catch (_) {
      return null;
    }
  }

  // ─── Public API — tree growing / mangrove planting queue (legacy shape) ──

  /// Returns the number of records waiting to be synced (all types).
  static Future<int> getPendingCount() async {
    final queue = await _loadQueue();
    return queue.length;
  }

  /// Queue a tree-growing/mangrove-planting record for later upload.
  ///
  /// [coordinates] entries are expected to have keys: `lat`, `lng`, and
  /// optionally `photoPath` (the temporary camera file path).
  static Future<void> queueRecord({
    required TreePlanting planting,
    required List<Map<String, dynamic>> seedRows,
    required List<Map<String, dynamic>> coordinates,
    required int divisionTypeId,
  }) async {
    final queue = await _loadQueue();
    final photosDir = await _photosDir();

    // Copy any temporary photos to stable offline storage before queuing.
    final stableCoords = <Map<String, dynamic>>[];
    for (final coord in coordinates) {
      final tempPath = coord['photoPath'] as String?;
      String? stablePath;

      if (tempPath != null && tempPath.isNotEmpty) {
        try {
          final src = File(tempPath);
          if (await src.exists()) {
            final ext = _extensionOf(tempPath);
            final fileName =
                'photo_${DateTime.now().millisecondsSinceEpoch}_${_rand()}.$ext';
            final dst = File('${photosDir.path}/$fileName');
            await src.copy(dst.path);
            stablePath = dst.path;
          }
        } catch (_) {
          // If copy fails we skip the photo but keep the coordinate.
        }
      }

      stableCoords.add({
        'lat': coord['lat'],
        'lng': coord['lng'],
        if (stablePath != null) 'stablePhotoPath': stablePath,
      });
    }

    queue.add({
      'localId': '${DateTime.now().millisecondsSinceEpoch}_${_rand()}',
      'type': 'planting',
      'queuedAt': DateTime.now().toUtc().toIso8601String(),
      'planting': planting.toJson(),
      'seedRows': seedRows,
      'coordinates': stableCoords,
      'divisionTypeId': divisionTypeId,
    });

    await _saveQueue(queue);
  }

  // ─── Public API — generic typed queue (the 6 newer forms) ────────────────

  /// Queue a record of any of the newer types (see the `_sync*` dispatch in
  /// [syncAll]) for later upload. Returns the new item's localId.
  static Future<String> queueGenericRecord({
    required String type,
    required Map<String, dynamic> payload,
  }) async {
    final queue = await _loadQueue();
    final localId = '${DateTime.now().millisecondsSinceEpoch}_${_rand()}';

    queue.add({
      'localId': localId,
      'type': type,
      'queuedAt': DateTime.now().toUtc().toIso8601String(),
      'payload': payload,
    });

    await _saveQueue(queue);
    return localId;
  }

  /// Returns queued-not-yet-synced items, optionally filtered by [type].
  static Future<List<Map<String, dynamic>>> getPendingItems(
      {String? type}) async {
    final queue = await _loadQueue();
    if (type == null) return queue;

    return queue.where((item) {
      final itemType = (item['type'] as String?) ?? 'planting';
      return itemType == type;
    }).toList();
  }

  /// Rewrites a still-queued item's payload in place — used when the user
  /// edits a record they saved offline before it has synced.
  static Future<void> updatePendingItem(
      String localId, Map<String, dynamic> newPayload) async {
    final queue = await _loadQueue();
    final index = queue.indexWhere((item) => item['localId'] == localId);
    if (index == -1) return;

    queue[index] = {
      ...queue[index],
      'payload': newPayload,
      'queuedAt': DateTime.now().toUtc().toIso8601String(),
    };

    await _saveQueue(queue);
  }

  /// Removes a queued item without syncing it (e.g. the user deletes a
  /// pending draft before it ever reaches the server).
  static Future<void> deletePendingItem(String localId) async {
    final queue = await _loadQueue();
    queue.removeWhere((item) => item['localId'] == localId);
    await _saveQueue(queue);
  }

  // ─── Public API — cached activity list for the monitoring pickers ────────

  /// Write-through cache of synced tree_growing rows for a project type
  /// (1 = tree growing, 6 = mangrove planting), so the survival-monitoring
  /// pickers can still list activities to monitor while offline. Only ever
  /// holds activities that have actually synced to the server — nothing
  /// still sitting in the offline queue is included.
  static Future<void> cacheActivities(
      int projectTypeId, List<TreePlanting> activities) async {
    try {
      final file = await _activitiesCacheFile();
      Map<String, dynamic> cache = {};

      if (await file.exists()) {
        try {
          final decoded = jsonDecode(await file.readAsString());
          if (decoded is Map<String, dynamic>) cache = decoded;
        } catch (_) {
          // Corrupted cache — overwrite it below.
        }
      }

      cache[projectTypeId.toString()] = activities
          .map((activity) => {
                'seq_id': activity.seqId,
                'id': activity.id,
                'project_type_id': activity.projectTypeId,
                'activity_name': activity.activityName,
                'barangay': activity.barangay,
                'municipality': activity.municipality,
                'planting_date': activity.date.toIso8601String(),
              })
          .toList();

      await file.writeAsString(jsonEncode(cache));
    } catch (_) {
      // Best effort — the picker just falls back to an empty list.
    }
  }

  static Future<List<TreePlanting>> getCachedActivities(
      int projectTypeId) async {
    try {
      final file = await _activitiesCacheFile();
      if (!await file.exists()) return [];

      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map<String, dynamic>) return [];

      final rows = decoded[projectTypeId.toString()];
      if (rows is! List) return [];

      return rows
          .cast<Map<String, dynamic>>()
          .map((row) => TreePlanting.fromJson(row))
          .toList();
    } catch (_) {
      return [];
    }
  }

  // ─── Sync dispatch ────────────────────────────────────────────────────────

  /// Push all queued records to Supabase.
  ///
  /// Returns the number of records that were successfully uploaded.
  /// Failed records stay in the queue and will be retried on the next call.
  static Future<int> syncAll() async {
    final queue = await _loadQueue();
    if (queue.isEmpty) return 0;

    int synced = 0;
    final remaining = <Map<String, dynamic>>[];

    for (final item in queue) {
      final type = (item['type'] as String?) ?? 'planting';
      try {
        switch (type) {
          case 'seed_for_forest':
            await _syncSeedForForest(item);
            break;
          case 'flora_fauna':
            await _syncFloraFauna(item);
            break;
          case 'habitat_assessment':
            await _syncHabitatAssessment(item);
            break;
          case 'marine_protected_area':
            await _syncMarineProtectedArea(item);
            break;
          case 'tree_survival_monitoring':
            await _syncTreeSurvivalMonitoring(item);
            break;
          case 'planting':
          default:
            await _syncPlantingItem(item);
        }
        synced++;
      } catch (_) {
        // Keep the item for the next sync attempt.
        remaining.add(item);
      }
    }

    await _saveQueue(remaining);
    return synced;
  }

  // ─── Internal sync — tree growing / mangrove planting (legacy shape) ─────

  static Future<void> _syncPlantingItem(Map<String, dynamic> item) async {
    final plantingJson =
        Map<String, dynamic>.from(item['planting'] as Map<dynamic, dynamic>);
    final seedRows = (item['seedRows'] as List)
        .map((r) => Map<String, dynamic>.from(r as Map<dynamic, dynamic>))
        .toList();
    final coordinates = (item['coordinates'] as List)
        .map((c) => Map<String, dynamic>.from(c as Map<dynamic, dynamic>))
        .toList();
    final divisionTypeId = item['divisionTypeId'] as int? ?? 0;

    // Ensure user_id is populated from the active session when it was lost.
    final existingUserId = plantingJson['user_id'] as String?;
    if (existingUserId == null || existingUserId.isEmpty) {
      plantingJson['user_id'] =
          Supabase.instance.client.auth.currentUser?.id ?? '';
    }

    final planting = TreePlanting(
      projectTypeId: plantingJson['project_type_id'] as int? ??
          plantingJson['projectTypeId'] as int? ??
          1,
      userid: plantingJson['user_id'] as String,
      activityName: plantingJson['activity_name'] as String?,
      barangay: plantingJson['barangay'] as String? ?? '',
      municipality: plantingJson['municipality'] as String? ?? '',
      details: plantingJson['details'] as String?,
      treeSpecies: plantingJson['tree_species'] as String? ?? '',
      numberOfTrees: plantingJson['number_of_trees'] as int? ?? 0,
      areaCover: (plantingJson['area_cover'] as num?)?.toDouble(),
      perimeter: (plantingJson['perimeter'] as num?)?.toDouble(),
      date: DateTime.tryParse(plantingJson['planting_date'] as String? ?? '') ??
          DateTime.now(),
    );

    // 1. Insert the tree_growing record.
    final saved = await ApiService.saveTreePlanting(planting);
    final activityId = (saved['seq_id'] as num?)?.toInt();

    // 2. Insert per-seedling rows.
    if (activityId != null && seedRows.isNotEmpty) {
      await ApiService.saveTreeGrowingDataRows(
        treeGrowingId: activityId,
        seedRows: seedRows,
      );
    }

    // 3. Insert coordinate + photo rows — mirrors the online save path
    // (a `location` row per point, a `photo` row per captured image) rather
    // than the legacy `photourl_area` table, so offline-synced photos show
    // up alongside online ones for the same activity.
    if (activityId != null) {
      final projectTypeId = planting.projectTypeId ?? _treeGrowingActivityTypeId;
      final storageFolder =
          _storageFolderByProjectType[projectTypeId] ?? 'tree_growing';

      for (final coord in coordinates) {
        final lat = (coord['lat'] as num?)?.toDouble();
        final lng = (coord['lng'] as num?)?.toDouble();
        if (lat == null || lng == null) continue;

        final createdLocation = await ApiService.createLocationRow(
          activityId: activityId,
          activityTypeId: projectTypeId,
          latitude: lat,
          longitude: lng,
        );
        final locationId = (createdLocation['id'] as num?)?.toInt();

        final stablePath = coord['stablePhotoPath'] as String?;
        if (locationId != null &&
            stablePath != null &&
            stablePath.isNotEmpty) {
          final ext = _extensionOf(stablePath);
          final photoName =
              'photo_000_${divisionTypeId}_${projectTypeId}_${activityId}_$locationId.$ext';

          await _uploadQueuedPhoto(
            stablePath: stablePath,
            storageFolder: storageFolder,
            photoName: photoName,
            projectTypeId: projectTypeId,
            activityId: activityId,
          );
        }
      }
    }
  }

  // ─── Internal sync — seed for a forest / mangrove data entry ─────────────
  //
  // seed_for_forest_form.dart talks to Supabase directly rather than through
  // ApiService, so this mirrors that form's own online save code instead of
  // introducing ApiService methods that would only exist for this.

  static Future<void> _syncSeedForForest(Map<String, dynamic> item) async {
    final payload = Map<String, dynamic>.from(item['payload'] as Map);
    final headerPayload =
        Map<String, dynamic>.from(payload['headerPayload'] as Map);
    final seedDetails = (payload['seedDetails'] as List)
        .map((r) => Map<String, dynamic>.from(r as Map))
        .toList();

    final client = Supabase.instance.client;

    final headerRow = await client
        .from('seed_donation')
        .insert(headerPayload)
        .select('id')
        .single();
    final seedDonationId = (headerRow['id'] as num).toInt();

    final dataRows = seedDetails
        .map((row) => {
              ...row,
              'seed_donation_id': seedDonationId,
            })
        .toList();

    await client.from('seed_donation_data').insert(dataRows);
  }

  // ─── Internal sync — flora & fauna survey ─────────────────────────────────

  static Future<void> _syncFloraFauna(Map<String, dynamic> item) async {
    final payload = Map<String, dynamic>.from(item['payload'] as Map);
    final survey = Map<String, dynamic>.from(payload['survey'] as Map);
    final species = (payload['species'] as List)
        .map((r) => Map<String, dynamic>.from(r as Map))
        .toList();
    final coordinates = (payload['coordinates'] as List)
        .map((r) => Map<String, dynamic>.from(r as Map))
        .toList();
    final projectTypeId = (survey['projectTypeId'] as num?)?.toInt() ?? 3;

    final saved = await ApiService.createFloraFaunaSurvey(
      userId: survey['userId'] as String,
      userSeqId: (survey['userSeqId'] as num?)?.toInt(),
      municipality: survey['municipality'] as String,
      barangay: survey['barangay'] as String,
      activityName: survey['activityName'] as String?,
      surveyDate: survey['surveyDate'] != null
          ? DateTime.tryParse(survey['surveyDate'] as String)
          : null,
      area: (survey['area'] as num?)?.toDouble(),
      details: survey['details'] as String?,
      observer: survey['observer'] as String?,
      projectTypeId: projectTypeId,
    );
    final surveyId = (saved['id'] as num).toInt();

    await ApiService.saveFloraFaunaSurveyDataRows(
      floraFaunaSurveyId: surveyId,
      rows: species,
    );

    for (var i = 0; i < species.length; i++) {
      final stablePath = species[i]['stablePhotoPath'] as String?;
      if (stablePath == null || stablePath.isEmpty) continue;

      final ext = _extensionOf(stablePath);
      final photoName =
          'flora_fauna_${surveyId}_${DateTime.now().millisecondsSinceEpoch}_${i + 1}.$ext';

      await _uploadQueuedPhoto(
        stablePath: stablePath,
        storageFolder: 'flora_fauna',
        photoName: photoName,
        projectTypeId: projectTypeId,
        activityId: surveyId,
      );
    }

    await ApiService.saveLocationRowsForActivity(
      activityId: surveyId,
      coordinates: coordinates,
      activityTypeId: projectTypeId,
    );
  }

  // ─── Internal sync — habitat assessment ───────────────────────────────────

  static Future<void> _syncHabitatAssessment(Map<String, dynamic> item) async {
    final payload = Map<String, dynamic>.from(item['payload'] as Map);
    final speciesRows = (payload['speciesRows'] as List)
        .map((r) => Map<String, dynamic>.from(r as Map))
        .toList();
    final coordinates = (payload['coordinates'] as List)
        .map((r) => Map<String, dynamic>.from(r as Map))
        .toList();
    final date =
        DateTime.tryParse(payload['date'] as String? ?? '') ?? DateTime.now();

    final saved = await ApiService.saveHabitatAssessment(
      userId: (payload['userId'] as num).toInt(),
      municipality: payload['municipality'] as String,
      barangay: payload['barangay'] as String,
      typeAssessment: payload['typeAssessment'] as String,
      date: date,
      area: (payload['area'] as num?)?.toDouble(),
    );
    final assessmentId = (saved['id'] as num).toInt();

    await ApiService.saveHabitatAssessmentDataRows(
      assessmentId: assessmentId,
      speciesRows: speciesRows,
    );

    await ApiService.saveLocationRowsForActivity(
      activityId: assessmentId,
      coordinates: coordinates,
      activityTypeId: ApiService.habitatAssessmentActivityTypeId,
    );

    for (final coord in coordinates) {
      final stablePath = coord['stablePhotoPath'] as String?;
      if (stablePath == null || stablePath.isEmpty) continue;

      final ext = _extensionOf(stablePath);
      final photoName =
          'photo_habitat_${ApiService.habitatAssessmentActivityTypeId}_${assessmentId}_${DateTime.now().millisecondsSinceEpoch}.$ext';

      await _uploadQueuedPhoto(
        stablePath: stablePath,
        storageFolder: 'habitat_assessment',
        photoName: photoName,
        projectTypeId: ApiService.habitatAssessmentActivityTypeId,
        activityId: assessmentId,
      );
    }
  }

  // ─── Internal sync — marine protected area ────────────────────────────────

  static Future<void> _syncMarineProtectedArea(
      Map<String, dynamic> item) async {
    final payload = Map<String, dynamic>.from(item['payload'] as Map);
    final coordinates = (payload['coordinates'] as List)
        .map((r) => Map<String, dynamic>.from(r as Map))
        .toList();
    final date =
        DateTime.tryParse(payload['date'] as String? ?? '') ?? DateTime.now();

    final saved = await ApiService.saveMarineProtectedArea(
      userId: (payload['userId'] as num).toInt(),
      name: payload['name'] as String,
      municipality: payload['municipality'] as String,
      barangay: payload['barangay'] as String,
      date: date,
      area: (payload['area'] as num?)?.toDouble(),
      ordinance: payload['ordinance'] as String?,
    );
    final areaId = (saved['id'] as num).toInt();

    await ApiService.saveLocationRowsForActivity(
      activityId: areaId,
      coordinates: coordinates,
      activityTypeId: ApiService.marineProtectedAreaActivityTypeId,
    );

    for (final coord in coordinates) {
      final stablePath = coord['stablePhotoPath'] as String?;
      if (stablePath == null || stablePath.isEmpty) continue;

      final ext = _extensionOf(stablePath);
      final photoName =
          'photo_marine_${ApiService.marineProtectedAreaActivityTypeId}_${areaId}_${DateTime.now().millisecondsSinceEpoch}.$ext';

      await _uploadQueuedPhoto(
        stablePath: stablePath,
        storageFolder: 'marine_protected_area',
        photoName: photoName,
        projectTypeId: ApiService.marineProtectedAreaActivityTypeId,
        activityId: areaId,
      );
    }
  }

  // ─── Internal sync — tree/mangrove survival monitoring ────────────────────
  //
  // The picker only ever lets the user record a monitoring entry against an
  // already-synced activity (see OfflineSyncService.getCachedActivities), so
  // activityId here is always a real, existing tree_growing.seq_id — no
  // id-resolution against another queued item is needed.

  static Future<void> _syncTreeSurvivalMonitoring(
      Map<String, dynamic> item) async {
    final payload = Map<String, dynamic>.from(item['payload'] as Map);
    final speciesSurvival = (payload['speciesSurvival'] as List)
        .map((r) => Map<String, dynamic>.from(r as Map))
        .map((r) => (
              seedId: (r['seedId'] as num).toInt(),
              numberTreeSurvived: (r['numberTreeSurvived'] as num).toInt(),
              seedName: r['seedName'] as String,
              plantedCount: (r['plantedCount'] as num).toInt(),
            ))
        .toList();

    await ApiService.saveTreeSurvivalMonitoringRows(
      userId: payload['userId'] as String,
      userSeqId: (payload['userSeqId'] as num?)?.toInt(),
      activityId: (payload['activityId'] as num).toInt(),
      speciesSurvival: speciesSurvival,
      quarter: (payload['quarter'] as num?)?.toInt(),
      details: payload['details'] as String?,
      date: DateTime.tryParse(payload['date'] as String? ?? '') ??
          DateTime.now(),
    );
  }

  // ─── Shared photo upload ───────────────────────────────────────────────────

  static Future<void> _uploadQueuedPhoto({
    required String stablePath,
    required String storageFolder,
    required String photoName,
    required int projectTypeId,
    required int activityId,
  }) async {
    final photoFile = File(stablePath);
    if (!await photoFile.exists()) return;

    final ext = _extensionOf(stablePath);

    await Supabase.instance.client.storage
        .from(_storageBucketName)
        .upload(
          'public/$storageFolder/$photoName',
          photoFile,
          fileOptions: FileOptions(
            upsert: false,
            contentType: _contentType(ext),
          ),
        );

    final encodedBucket = Uri.encodeComponent(_storageBucketName);
    final photoUrl =
        'public/$encodedBucket/public/$storageFolder/$photoName';

    await ApiService.createPhotoRow(
      projectTypeId: projectTypeId,
      activityId: activityId,
      photoUrl: photoUrl,
    );

    // Clean up the stable local file after a successful upload.
    try {
      await photoFile.delete();
    } catch (_) {}
  }

  static String _extensionOf(String path) {
    return path.contains('.') ? path.split('.').last.toLowerCase() : 'jpg';
  }

  static String _contentType(String ext) {
    switch (ext) {
      case 'png':
        return 'image/png';
      case 'webp':
        return 'image/webp';
      default:
        return 'image/jpeg';
    }
  }

  static int _rand() => Random().nextInt(99999);
}
