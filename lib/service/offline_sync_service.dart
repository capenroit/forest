import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:path_provider/path_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'activity_model.dart';
import 'api_service.dart';

class OfflineSyncService {
  static const String _queueFileName = 'offline_queue.json';
  static const String _photosDirName = 'offline_photos';
  static const String _storageBucketName = 'Forest Management';
  static const int _treeGrowingActivityTypeId = 1;
  static const Map<int, String> _storageFolderByProjectType = {
    1: 'tree_growing',
    6: 'mangrove_planting',
  };

  // ─── Paths ───────────────────────────────────────────────────────────────

  static Future<File> _queueFile() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/$_queueFileName');
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

  // ─── Public API ───────────────────────────────────────────────────────────

  /// Returns the number of records waiting to be synced.
  static Future<int> getPendingCount() async {
    final queue = await _loadQueue();
    return queue.length;
  }

  /// Queue a tree-growing record for later upload.
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
            final ext = tempPath.contains('.')
                ? tempPath.split('.').last.toLowerCase()
                : 'jpg';
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
      'queuedAt': DateTime.now().toUtc().toIso8601String(),
      'planting': planting.toJson(),
      'seedRows': seedRows,
      'coordinates': stableCoords,
      'divisionTypeId': divisionTypeId,
    });

    await _saveQueue(queue);
  }

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
      try {
        await _syncItem(item);
        synced++;
      } catch (_) {
        // Keep the item for the next sync attempt.
        remaining.add(item);
      }
    }

    await _saveQueue(remaining);
    return synced;
  }

  // ─── Internal sync ────────────────────────────────────────────────────────

  static Future<void> _syncItem(Map<String, dynamic> item) async {
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
          final photoFile = File(stablePath);
          if (await photoFile.exists()) {
            final ext = stablePath.contains('.')
                ? stablePath.split('.').last.toLowerCase()
                : 'jpg';
            final photoName =
                'photo_000_${divisionTypeId}_${projectTypeId}_${activityId}_$locationId.$ext';

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
        }
      }
    }
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

