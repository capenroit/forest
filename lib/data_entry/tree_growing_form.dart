import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';
import 'package:latlong2/latlong.dart' as ll;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../service/api_service.dart';
import '../service/auth_session.dart';
import '../service/location_capture_service.dart';
import '../service/lookup_service.dart';
import '../service/offline_sync_service.dart';
import '../service/seedling_list_service.dart';
import '../widget/add_seed_dialog.dart';
import '../widget/edit_coordinate_dialog.dart';
import '../../service/activity_model.dart';
import '../../widget/polygon_calculator.dart';

class SeedlingEntry {
  String seedlingType;
  int quantity;

  SeedlingEntry({required this.seedlingType, required this.quantity});
}

class TreeGrowingForm extends StatefulWidget {
  final List<String> municipalities;
  final List<String> barangays;
  final ValueChanged<TreePlanting> onSave;
  final VoidCallback onCancel;
  final TreePlanting? initialData;

  /// When set (together with [pendingPayload]), this form edits a still-
  /// queued offline draft (the legacy 'planting' queue shape: keys
  /// `planting`, `seedRows`, `coordinates`, `divisionTypeId`) instead of a
  /// server record or a brand-new entry.
  final String? pendingLocalId;
  final Map<String, dynamic>? pendingPayload;

  const TreeGrowingForm({
    Key? key,
    required this.municipalities,
    required this.barangays,
    required this.onSave,
    required this.onCancel,
    this.initialData,
    this.pendingLocalId,
    this.pendingPayload,
  }) : super(key: key);

  @override
  State<TreeGrowingForm> createState() => _TreeGrowingFormState();
}

class _TreeGrowingFormState extends State<TreeGrowingForm> {
  static const int _treeGrowingActivityTypeId = 1;
  // Supabase bucket id used by this app project.
  static const String _storageBucketName = 'Forest Management';
  final SeedlingListService seedlingListService = SeedlingListService();
  late TextEditingController _activityNameController;
  late TextEditingController _barangayController;
  late TextEditingController _detailsController;
  late TextEditingController _treeSpeciesController;
  late TextEditingController _numberOfTreesController;
  late TextEditingController _areaCoverController;
  late TextEditingController _dateController;

  LookupOption? _selectedMunicipality;
  String? _selectedBarangay;
  List<LookupOption> _municipalityOptions = [];
  List<String> _filteredBarangays = [];
  List<SeedlingEntry> _seedlings = [];
  List<String> seedlingNames = [];
  bool _isLoading = false;
  bool _isSaving = false;
  bool _isLoadingBarangays = false;
  bool _isLoadingSeedlings = false;
  String? selectedType;
  bool _isLoadingCoordinates = false;
  DateTime _selectedDate = DateTime.now();

  late TextEditingController _editLatController;
  late TextEditingController _editLngController;
  bool _locationPermissionGranted = false;
  bool _isCapturingLocation = false;
  final ImagePicker _imagePicker = ImagePicker();
  List<Map<String, dynamic>> capturedCoordinates = [];
  bool _didApplyInitialMunicipality = false;

  /// Same shape as [widget.initialData], but also covers the pending-draft
  /// case: a [TreePlanting] reconstructed from [widget.pendingPayload] for
  /// pre-filling display fields (activity name, municipality, date, etc).
  /// Unlike [widget.initialData], this must never be used to decide the
  /// save path (that still needs a real null for a pending draft, so
  /// `_handleSave` doesn't mistake it for an online edit).
  TreePlanting? _prefillSource;

  bool get _isEditingPending => widget.pendingLocalId != null;

  @override
  void initState() {
    super.initState();
    _dateController = TextEditingController();
    _areaCoverController = TextEditingController();
    _activityNameController = TextEditingController();
    _barangayController = TextEditingController();
    _detailsController = TextEditingController();
    _treeSpeciesController = TextEditingController();
    _numberOfTreesController = TextEditingController();
    _editLatController = TextEditingController();
    _editLngController = TextEditingController();
    _dateController.text = DateTime.now().toIso8601String().split('T').first;

    final pendingPayload = widget.pendingPayload;
    _prefillSource = widget.initialData ??
        (pendingPayload != null
            ? TreePlanting.fromJson(
                Map<String, dynamic>.from(pendingPayload['planting'] as Map))
            : null);

    final initial = _prefillSource;
    if (initial != null) {
      _activityNameController.text = initial.activityName?.trim() ?? '';
      _detailsController.text = initial.details?.trim() ?? '';
      _areaCoverController.text = initial.areaCover?.toString() ?? '';
      _selectedDate = initial.date;
      _dateController.text = _formatDateOnly(initial.date);
      _selectedBarangay =
          initial.barangay.trim().isEmpty ? null : initial.barangay.trim();
    }

    if (pendingPayload != null) {
      final seedRows = ((pendingPayload['seedRows'] as List?) ?? const [])
          .map((r) => Map<String, dynamic>.from(r as Map))
          .toList();
      _seedlings = seedRows
          .map((r) => SeedlingEntry(
                seedlingType: (r['seed_name'] ?? '').toString(),
                quantity: (r['seedling_count'] as num?)?.toInt() ?? 0,
              ))
          .where((s) => s.seedlingType.isNotEmpty)
          .toList();

      final coords = ((pendingPayload['coordinates'] as List?) ?? const [])
          .map((c) => Map<String, dynamic>.from(c as Map))
          .toList();
      capturedCoordinates = coords
          .map((c) {
            final stablePhotoPath = c['stablePhotoPath'] as String?;
            return <String, dynamic>{
              'lat': (c['lat'] as num?)?.toDouble(),
              'lng': (c['lng'] as num?)?.toDouble(),
              if (stablePhotoPath != null && stablePhotoPath.isNotEmpty)
                'photoPath': stablePhotoPath,
            };
          })
          .where((c) => c['lat'] != null && c['lng'] != null)
          .toList();
      // Only recompute when there are enough points to form a polygon —
      // otherwise this would wipe out the area we just loaded from the
      // saved draft (see the "else" branch of _updateAreaFromCoordinates,
      // which clears the field when there are fewer than 3 points).
      if (capturedCoordinates.length >= 3) {
        _updateAreaFromCoordinates();
      }
    }

    _requestLocationPermission();
    _loadMunicipalityOptions();
    _loadInitialSeedlings();
    _loadInitialCoordinates();
  }

  String _formatDateOnly(DateTime value) {
    final year = value.year.toString().padLeft(4, '0');
    final month = value.month.toString().padLeft(2, '0');
    final day = value.day.toString().padLeft(2, '0');
    return '$year-$month-$day';
  }

  @override
  void dispose() {
    _activityNameController.dispose();
    _barangayController.dispose();
    _detailsController.dispose();
    _treeSpeciesController.dispose();
    _numberOfTreesController.dispose();
    _areaCoverController.dispose();
    _dateController.dispose();
    _editLatController.dispose();
    _editLngController.dispose();
    super.dispose();
  }

  String _buildTreeGrowingPhotoName({
    required int divisionTypeId,
    required int activityId,
    required int photoId,
    required String sourcePath,
  }) {
    final extension = _extractFileExtension(sourcePath);
    final fallbackExtension = extension.isEmpty ? '.jpg' : extension;
    return 'photo_000_${divisionTypeId}_${_treeGrowingActivityTypeId}_${activityId}_$photoId$fallbackExtension';
  }

  /// Storage object paths can't safely contain spaces, slashes, or other
  /// punctuation from free-text fields — keep only alphanumerics, folding
  /// everything else down to a single underscore.
  String _sanitizeForFileName(String value) {
    final sanitized = value
        .trim()
        .replaceAll(RegExp(r'[^A-Za-z0-9]+'), '_')
        .replaceAll(RegExp(r'^_+|_+$'), '');
    return sanitized.isEmpty ? 'unnamed' : sanitized;
  }

  /// The `photo.name` / `photourl_area.name` shown to users — unlike
  /// [_buildTreeGrowingPhotoName] (the storage object path, which must stay
  /// unique), this is the plain `tree_growing_{activityName}_Point{N}` the
  /// user actually wants to see. [photoIndex] is 1-based and counts only
  /// points that actually have a photo, so two photos on one save come out
  /// `..._Point1` and `..._Point2` — letting the point each photo belongs
  /// to be told apart at a glance in the photo gallery.
  String _buildTreeGrowingDisplayName({
    required String activityName,
    required int photoIndex,
    required String sourcePath,
  }) {
    final extension = _extractFileExtension(sourcePath);
    final fallbackExtension = extension.isEmpty ? '.jpg' : extension;
    final safeActivityName = _sanitizeForFileName(activityName);
    return 'tree_growing_${safeActivityName}_Point$photoIndex$fallbackExtension';
  }

  int _resolveDivisionTypeId() {
    return AuthSession.currentUser?.divisionTypeId ?? 0;
  }

  Future<String> _uploadTreeGrowingPhotoToSupabase({
    required String localPath,
    required String photoName,
  }) async {
    final file = File(localPath);
    if (!await file.exists()) {
      throw Exception('Photo file does not exist: $localPath');
    }

    final objectPath = 'public/tree_growing/$photoName';
    final contentType = _contentTypeFromPath(photoName);
    final fileLength = await file.length();

    try {
      await Supabase.instance.client.storage.from(_storageBucketName).upload(
            objectPath,
            file,
            fileOptions: FileOptions(
              upsert: false,
              contentType: contentType,
            ),
          );
    } catch (e) {
      rethrow;
    }

    try {
      await file.delete();
    } catch (_) {
      // Best effort only. File is temporary camera output.
    }

    final encodedBucket = Uri.encodeComponent(_storageBucketName);
    final storagePath = 'public/$encodedBucket/$objectPath';
    return storagePath;
  }

  String _contentTypeFromPath(String path) {
    final lower = path.toLowerCase();
    if (lower.endsWith('.png')) {
      return 'image/png';
    }
    if (lower.endsWith('.webp')) {
      return 'image/webp';
    }
    return 'image/jpeg';
  }

  String _extractFileExtension(String path) {
    final lastSeparator = path.lastIndexOf(Platform.pathSeparator);
    final fileName =
        lastSeparator >= 0 ? path.substring(lastSeparator + 1) : path;
    final dotIndex = fileName.lastIndexOf('.');

    if (dotIndex <= 0 || dotIndex == fileName.length - 1) {
      return '';
    }

    return fileName.substring(dotIndex);
  }

  Future<void> _handleSave() async {
    if (_isSaving) return;

    setState(() => _isSaving = true);

    try {
      final activityName = _activityNameController.text.trim();
      final details = _detailsController.text.trim();
      final municipality = _selectedMunicipality?.name.trim() ?? '';
      final barangay = _selectedBarangay?.trim() ?? '';

      if (activityName.isEmpty || municipality.isEmpty || barangay.isEmpty) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Data is incomplete.'),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }

      final authUserId = AuthSession.currentUser?.id ??
          Supabase.instance.client.auth.currentUser?.id;

      if (authUserId == null || authUserId.isEmpty) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Unable to save data.'),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }

      final parsedDate =
          DateTime.tryParse(_dateController.text.trim()) ?? DateTime.now();
      final parsedArea = double.tryParse(_areaCoverController.text.trim());

      const treeSpecies = '';
      final numberOfTrees = _totalSeedlings;

      // ── Pending-draft edit path ─────────────────────────────────────────
      // Rewriting a still-queued offline draft is a purely local operation
      // — no connectivity check needed.
      if (_isEditingPending) {
        final pendingPlanting = TreePlanting(
          projectTypeId: 1,
          userid: authUserId,
          userSeqId: AuthSession.currentUser?.seqId,
          activityName: activityName,
          barangay: barangay,
          municipality: municipality,
          details: details.isEmpty ? null : details,
          treeSpecies: treeSpecies,
          numberOfTrees: numberOfTrees,
          areaCover: parsedArea,
          date: parsedDate,
        );
        final seedRows = _seedlings
            .map((s) => {
                  'seed_name': s.seedlingType,
                  'seedling_count': s.quantity,
                })
            .toList();

        try {
          await OfflineSyncService.updatePendingPlantingItem(
            localId: widget.pendingLocalId!,
            planting: pendingPlanting,
            seedRows: seedRows,
            coordinates: List<Map<String, dynamic>>.from(capturedCoordinates),
            divisionTypeId: _resolveDivisionTypeId(),
          );
        } catch (e) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Unable to save data.'),
              backgroundColor: Colors.red,
            ),
          );
          return;
        }

        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Data was saved.'),
            backgroundColor: Colors.orange,
            duration: Duration(seconds: 3),
          ),
        );
        widget.onSave(pendingPlanting);
        return;
      }
      // ── End pending-draft edit path ─────────────────────────────────────

      // ── Offline path ────────────────────────────────────────────────────
      final isOnline = await OfflineSyncService.hasInternetConnection();
      if (!mounted) return;
      if (!isOnline) {
        final offlinePlanting = TreePlanting(
          id: widget.initialData?.id,
          seqId: widget.initialData?.seqId,
          projectTypeId: 1,
          userid: authUserId,
          userSeqId: AuthSession.currentUser?.seqId,
          activityName: activityName,
          barangay: barangay,
          municipality: municipality,
          details: details.isEmpty ? null : details,
          treeSpecies: treeSpecies,
          numberOfTrees: numberOfTrees,
          areaCover: parsedArea,
          date: parsedDate,
        );
        final seedRows = _seedlings
            .map((s) => {
                  'seed_name': s.seedlingType,
                  'seedling_count': s.quantity,
                })
            .toList();

        try {
          await OfflineSyncService.queueRecord(
            planting: offlinePlanting,
            seedRows: seedRows,
            coordinates: List<Map<String, dynamic>>.from(capturedCoordinates),
            divisionTypeId: _resolveDivisionTypeId(),
          ).timeout(
            const Duration(seconds: 15),
            onTimeout: () => throw TimeoutException(
              'Saving offline is taking too long. Please try again.',
            ),
          );
        } catch (e, st) {
          debugPrint('SAVE FAILED: $e\n$st');
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                e is TimeoutException
                    ? (e.message ?? 'Unable to save data.')
                    : 'Unable to save data.',
              ),
              backgroundColor: Colors.red,
            ),
          );
          return;
        }

        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Data was saved.'),
            backgroundColor: Colors.orange,
            duration: Duration(seconds: 3),
          ),
        );
        widget.onSave(offlinePlanting);
        return;
      }
      // ── End offline path ────────────────────────────────────────────────

      final isEditing =
          widget.initialData?.id != null && widget.initialData!.id!.isNotEmpty;

      final planting = TreePlanting(
        id: widget.initialData?.id,
        seqId: widget.initialData?.seqId,
        projectTypeId: 1,
        userid: authUserId,
        activityName: activityName,
        barangay: barangay,
        municipality: municipality,
        details: details.isEmpty ? null : details,
        treeSpecies: treeSpecies,
        numberOfTrees: numberOfTrees,
        areaCover: parsedArea,
        date: parsedDate,
      );

      Map<String, dynamic> savedTreeGrowing;
      try {
        // Every Supabase call below is a plain network request with no
        // built-in timeout. Without this guard, a dropped/slow connection
        // mid-save leaves the (non-dismissible) dialog spinning forever —
        // which is what looks like the app "freezing".
        savedTreeGrowing = await (() async {
          final saved = await ApiService.saveTreePlanting(planting);
          final int? activityId = (saved['seq_id'] as num?)?.toInt();
          final divisionTypeId = _resolveDivisionTypeId();

          if (activityId != null) {
            final seedRows = _seedlings
                .map((seedling) => {
                      'seed_name': seedling.seedlingType,
                      'seedling_count': seedling.quantity,
                    })
                .toList();

            if (isEditing) {
              await ApiService.replaceTreeGrowingDataRows(
                treeGrowingId: activityId,
                seedRows: seedRows,
              );
            } else if (seedRows.isNotEmpty) {
              await ApiService.saveTreeGrowingDataRows(
                treeGrowingId: activityId,
                seedRows: seedRows,
              );
            }
          }

          if (activityId != null && capturedCoordinates.isNotEmpty) {
            var photoCounter = 0;
            for (final coord in capturedCoordinates) {
              final latitude = (coord['lat'] as num?)?.toDouble();
              final longitude = (coord['lng'] as num?)?.toDouble();

              if (latitude == null || longitude == null) continue;

              final photoPath = coord['photoPath'] as String?;

              // Points loaded from the legacy photourl_area table
              // (pre-existing records) keep using photourl_area so
              // historical data isn't fragmented across two tables.
              // Everything else (new captures, and points already
              // migrated to `location` in a prior edit) uses the
              // location/photo tables, matching the Flora & Fauna /
              // Habitat Assessment / Marine Protected Area pattern.
              final existingPhotourlAreaId =
                  (coord['photourlAreaId'] ?? '').toString().trim();
              final existingSeqId = _toInt(coord['photourlAreaSeqId']);

              if (existingPhotourlAreaId.isNotEmpty) {
                await ApiService.updatePhotourlAreaCoordinates(
                  photourlAreaId: existingPhotourlAreaId,
                  latitude: latitude,
                  longitude: longitude,
                );

                if (photoPath != null &&
                    photoPath.isNotEmpty &&
                    existingSeqId != null) {
                  final photoName = _buildTreeGrowingPhotoName(
                    divisionTypeId: divisionTypeId,
                    activityId: activityId,
                    photoId: existingSeqId,
                    sourcePath: photoPath,
                  );
                  photoCounter++;
                  final displayName = _buildTreeGrowingDisplayName(
                    activityName: activityName,
                    photoIndex: photoCounter,
                    sourcePath: photoPath,
                  );

                  final supabasePhotoUrl =
                      await _uploadTreeGrowingPhotoToSupabase(
                    localPath: photoPath,
                    photoName: photoName,
                  );

                  await ApiService.updatePhotourlAreaPhotoUrl(
                    photourlAreaId: existingPhotourlAreaId,
                    photoUrl: supabasePhotoUrl,
                    photoName: displayName,
                  );

                  coord['photoPath'] = null;
                  coord['photoUrl'] = supabasePhotoUrl;
                }

                continue;
              }

              int? locationId = _toInt(coord['locationRowId']);
              if (locationId != null) {
                await ApiService.updateLocationRowCoordinates(
                  locationId: locationId,
                  latitude: latitude,
                  longitude: longitude,
                );
              } else {
                final createdRow = await ApiService.createLocationRow(
                  activityId: activityId,
                  activityTypeId: _treeGrowingActivityTypeId,
                  latitude: latitude,
                  longitude: longitude,
                );
                locationId = (createdRow['id'] as num?)?.toInt();
                coord['locationRowId'] = locationId;
              }

              if (photoPath != null && photoPath.isNotEmpty) {
                final photoName = _buildTreeGrowingPhotoName(
                  divisionTypeId: divisionTypeId,
                  activityId: activityId,
                  photoId: locationId ?? DateTime.now().millisecondsSinceEpoch,
                  sourcePath: photoPath,
                );
                photoCounter++;
                final displayName = _buildTreeGrowingDisplayName(
                  activityName: activityName,
                  photoIndex: photoCounter,
                  sourcePath: photoPath,
                );

                final supabasePhotoUrl =
                    await _uploadTreeGrowingPhotoToSupabase(
                  localPath: photoPath,
                  photoName: photoName,
                );

                await ApiService.createPhotoRow(
                  projectTypeId: _treeGrowingActivityTypeId,
                  activityId: activityId,
                  name: displayName,
                  photoUrl: supabasePhotoUrl,
                  locationId: locationId,
                );

                coord['photoPath'] = null;
                coord['photoUrl'] = supabasePhotoUrl;
              }
            }
          }

          return saved;
        })()
            .timeout(
          const Duration(seconds: 45),
          onTimeout: () => throw TimeoutException(
            'Saving is taking too long. Check your connection and try again.',
          ),
        );
      } catch (e, st) {
        debugPrint('SAVE FAILED: $e\n$st');
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              e is TimeoutException
                  ? (e.message ?? 'Unable to save data.')
                  : 'Unable to save data.',
            ),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }

      // The record is already saved on the server at this point — a
      // failure below is just a local response-parsing issue, not a save
      // failure, so it must not be reported as one (the dialog should
      // still close on a save that actually succeeded).
      TreePlanting savedPlanting;
      try {
        savedPlanting = TreePlanting.fromJson(savedTreeGrowing);
      } catch (e, st) {
        debugPrint(
          'SAVE FAILED (response parse only, save succeeded): $e\n$st',
        );
        savedPlanting = TreePlanting(
          id: (savedTreeGrowing['id'] ?? planting.id)?.toString(),
          seqId: _toInt(savedTreeGrowing['seq_id']) ?? planting.seqId,
          projectTypeId: planting.projectTypeId,
          userid: planting.userid,
          userSeqId: planting.userSeqId,
          activityName: planting.activityName,
          barangay: planting.barangay,
          municipality: planting.municipality,
          details: planting.details,
          treeSpecies: planting.treeSpecies,
          numberOfTrees: planting.numberOfTrees,
          areaCover: planting.areaCover,
          date: planting.date,
        );
      }

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Data was saved.'),
          backgroundColor: Colors.green,
        ),
      );

      widget.onSave(savedPlanting);

      // Flush any other pending offline records now that we know we're
      // online and this save has already completed. Running this earlier
      // (before the save above) raced it against this save over the same
      // local queue/connection.
      OfflineSyncService.syncAll().ignore();
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  int? _toInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value);
    return null;
  }

  void _removeSeedling(int index) {
    setState(() {
      _seedlings.removeAt(index);
    });
  }

  Future<void> _editSeedling(int index) async {
    final item = _seedlings[index];
    final speciesController = TextEditingController(text: item.seedlingType);
    final countController =
        TextEditingController(text: item.quantity.toString());

    final shouldSave = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          title: const Text('Edit Seedling'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: speciesController,
                decoration: const InputDecoration(
                  labelText: 'Species',
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: countController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Seedling Count',
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Save'),
            ),
          ],
        );
      },
    );

    if (shouldSave != true) return;

    final species = speciesController.text.trim();
    final quantity = int.tryParse(countController.text.trim()) ?? 0;

    if (species.isEmpty || quantity <= 0) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter valid species and count.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    if (!mounted) return;
    setState(() {
      _seedlings[index] = SeedlingEntry(seedlingType: species, quantity: quantity);
    });
  }

  Future<void> _loadMunicipalityOptions() async {
    setState(() => _isLoading = true);

    try {
      final options = await LookupService.getMunicipalityOptions();
      if (!mounted) return;
      setState(() {
        _municipalityOptions = options;
      });

      final initial = _prefillSource;
      if (!_didApplyInitialMunicipality && initial != null) {
        _didApplyInitialMunicipality = true;
        final initialMunicipality = initial.municipality.trim().toLowerCase();

        LookupOption? match;
        for (final option in options) {
          if (option.name.trim().toLowerCase() == initialMunicipality) {
            match = option;
            break;
          }
        }

        if (match != null) {
          if (!mounted) return;
          setState(() {
            _selectedMunicipality = match;
          });

          await _loadBarangaysForMunicipality(match.id);

          if (!mounted || _selectedBarangay == null) return;
          String? matchedBarangay;
          final selectedLower = _selectedBarangay!.trim().toLowerCase();
          for (final name in _filteredBarangays) {
            if (name.trim().toLowerCase() == selectedLower) {
              matchedBarangay = name;
              break;
            }
          }

          if (matchedBarangay == null) {
            setState(() {
              _selectedBarangay = null;
            });
          } else if (matchedBarangay != _selectedBarangay) {
            setState(() {
              _selectedBarangay = matchedBarangay;
            });
          }
        }
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _loadBarangaysForMunicipality(int municipalityId) async {
    setState(() {
      _isLoadingBarangays = true;
      _filteredBarangays = [];
    });

    try {
      final options = await LookupService.getBarangayOptionsByMunicipalityId(
        municipalityId,
      );
      if (!mounted) return;

      final seen = <String>{};
      final uniqueBarangays = <String>[];
      for (final option in options) {
        final name = option.name.trim();
        if (name.isEmpty) continue;

        final key = name.toLowerCase();
        if (seen.add(key)) {
          uniqueBarangays.add(name);
        }
      }

      setState(() {
        _filteredBarangays = uniqueBarangays;

        if (_selectedBarangay != null) {
          String? matchedBarangay;
          final selectedLower = _selectedBarangay!.trim().toLowerCase();
          for (final name in _filteredBarangays) {
            if (name.toLowerCase() == selectedLower) {
              matchedBarangay = name;
              break;
            }
          }
          _selectedBarangay = matchedBarangay;
        }
      });
    } finally {
      if (mounted) {
        setState(() => _isLoadingBarangays = false);
      }
    }
  }

  Future<void> _loadInitialSeedlings() async {
    final seqId = widget.initialData?.seqId;
    if (seqId == null || seqId <= 0) return;

    setState(() {
      _isLoadingSeedlings = true;
    });

    try {
      final grouped =
          await ApiService.getTreeGrowingDataByTreeGrowingIds([seqId]);
      final rows = grouped[seqId] ?? const <Map<String, dynamic>>[];

      final summedBySeed = <String, int>{};
      for (final row in rows) {
        final seedName = (row['seed_name'] ?? '').toString().trim();
        if (seedName.isEmpty) continue;

        final quantity = (row['seedling_count'] as num?)?.toInt() ?? 0;
        summedBySeed.update(seedName, (value) => value + quantity,
            ifAbsent: () => quantity);
      }

      final loadedSeedlings = summedBySeed.entries
          .map(
            (entry) => SeedlingEntry(
              seedlingType: entry.key,
              quantity: entry.value,
            ),
          )
          .toList()
        ..sort((a, b) => a.seedlingType.compareTo(b.seedlingType));

      if (!mounted) return;
      setState(() {
        _seedlings = loadedSeedlings;
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Unable to load seedling details: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingSeedlings = false;
        });
      }
    }
  }

  Future<void> _loadInitialCoordinates() async {
    final seqId = widget.initialData?.seqId;
    if (seqId == null || seqId <= 0) return;

    setState(() {
      _isLoadingCoordinates = true;
    });

    try {
      // Legacy points, still stored per-point in photourl_area (with an
      // inline photo_url) from before this activity's records were
      // migrated to the location/photo tables.
      final areas = await ApiService.getPhotourlAreasByActivityId(seqId);

      final legacyCoordinates = areas.map((row) {
        final lat = (row['latitude'] as num?)?.toDouble();
        final lng = (row['longitude'] as num?)?.toDouble();

        return <String, dynamic>{
          'lat': lat,
          'lng': lng,
          'photoUrl': row['photo_url'],
          'photourlAreaId': row['id']?.toString(),
          'photourlAreaSeqId': (row['seq_id'] as num?)?.toInt(),
        };
      }).where((row) => row['lat'] != null && row['lng'] != null);

      // Points captured after the migration to location/photo. Each photo
      // row carries the location.id it was taken at, so it can be matched
      // straight back to its point.
      final locationRows = await ApiService.getLocationRowsByActivity(
        activityTypeId: _treeGrowingActivityTypeId,
        activityId: seqId,
      );
      final photoRows = await ApiService.getPhotosForActivity(
        projectTypeId: _treeGrowingActivityTypeId,
        activityId: seqId,
      );
      final photoUrlByLocationId = <int, String>{};
      for (final photo in photoRows) {
        final locationId = (photo['location_id'] as num?)?.toInt();
        final photoUrl = photo['photo_url'] as String?;
        if (locationId != null && photoUrl != null && photoUrl.isNotEmpty) {
          photoUrlByLocationId[locationId] = photoUrl;
        }
      }

      final migratedCoordinates = locationRows.map((row) {
        final lat = (row['latitude'] as num?)?.toDouble();
        final lng = (row['longitude'] as num?)?.toDouble();
        final locationId = (row['id'] as num?)?.toInt();

        return <String, dynamic>{
          'lat': lat,
          'lng': lng,
          'locationRowId': locationId,
          if (locationId != null && photoUrlByLocationId[locationId] != null)
            'photoUrl': photoUrlByLocationId[locationId],
        };
      }).where((row) => row['lat'] != null && row['lng'] != null);

      final loadedCoordinates = [
        ...legacyCoordinates,
        ...migratedCoordinates,
      ];

      if (!mounted) return;
      setState(() {
        capturedCoordinates = loadedCoordinates;
      });

      // Only recompute when there are enough points to form a polygon —
      // otherwise this would wipe out the area already loaded from the
      // saved record (see the "else" branch of _updateAreaFromCoordinates,
      // which clears the field when there are fewer than 3 points).
      if (capturedCoordinates.length >= 3) {
        _updateAreaFromCoordinates();
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Unable to load coordinates: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingCoordinates = false;
        });
      }
    }
  }

  Future<void> _captureCurrentLocation() async {
    if (!_locationPermissionGranted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Permission required.')),
      );
      await _requestLocationPermission();
      return;
    }

    setState(() => _isCapturingLocation = true);

    try {
      final result = await LocationCaptureService.capture();

      if (!mounted) return;

      // Store GPS coordinates locally (will be saved to database when user presses save)
      setState(() {
        capturedCoordinates.add({
          'lat': result.position.latitude,
          'lng': result.position.longitude,
        });
        _updateAreaFromCoordinates(); // Compute area after adding coordinate
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            result.isFallback
                ? 'GPS fix timed out — used your last known location. Verify it or retake.'
                : 'Data updated.',
          ),
          backgroundColor: result.isFallback ? Colors.orange : Colors.blue,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Unable to get GPS location. Move to an open area and try again.',
          ),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) setState(() => _isCapturingLocation = false);
    }
  }

  Future<void> _capturePhotoAndCoordinate() async {
    try {
      setState(() => _isCapturingLocation = true);

      // Lock orientation to landscape before opening camera
      await SystemChrome.setPreferredOrientations([
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);

      final XFile? photo = await _imagePicker
          .pickImage(
        source: ImageSource.camera,
        preferredCameraDevice: CameraDevice.rear,
      )
          .timeout(
        const Duration(minutes: 5),
        onTimeout: () {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Action timed out.'),
              backgroundColor: Colors.red,
            ),
          );
          return null;
        },
      );

      // Ensure landscape orientation is maintained after camera closes
      await SystemChrome.setPreferredOrientations([
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);

      if (photo == null) {
        setState(() => _isCapturingLocation = false);
        return;
      }

      if (!_locationPermissionGranted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Permission required.')),
        );
        await _requestLocationPermission();
        setState(() => _isCapturingLocation = false);
        return;
      }

      final result = await LocationCaptureService.capture();

      if (!mounted) return;

      // Keep camera temp path only until Save uploads to Supabase.
      setState(() {
        capturedCoordinates.add({
          'lat': result.position.latitude,
          'lng': result.position.longitude,
          'photoPath': photo.path,
        });
        _updateAreaFromCoordinates(); // Compute area after adding coordinate
        _isCapturingLocation = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            result.isFallback
                ? 'GPS fix timed out — used your last known location. Verify it or retake.'
                : 'Data updated.',
          ),
          backgroundColor: result.isFallback ? Colors.orange : Colors.green,
        ),
      );
    } catch (e) {
      // Ensure landscape orientation is maintained even after error
      await SystemChrome.setPreferredOrientations([
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);

      if (!mounted) return;
      setState(() => _isCapturingLocation = false);

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Unable to get GPS location. Move to an open area and try again.',
          ),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _requestLocationPermission() async {
    try {
      final permission = await Geolocator.checkPermission();

      if (permission == LocationPermission.denied) {
        // Permission not granted yet, request it
        final result = await Geolocator.requestPermission();
        setState(() => _locationPermissionGranted =
            result == LocationPermission.whileInUse ||
                result == LocationPermission.always);
      } else if (permission == LocationPermission.whileInUse ||
          permission == LocationPermission.always) {
        // Permission already granted
        setState(() => _locationPermissionGranted = true);
      } else if (permission == LocationPermission.deniedForever) {
        // Permission permanently denied, show app settings option
        setState(() => _locationPermissionGranted = false);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('Permission required.'),
              action: SnackBarAction(
                label: 'Open Settings',
                onPressed: () => Geolocator.openLocationSettings(),
              ),
            ),
          );
        }
      }
    } catch (e) {
      setState(() => _locationPermissionGranted = false);
    }
  }

  void _updateAreaFromCoordinates() {
    if (capturedCoordinates.length >= 3) {
      try {
        // Convert captured coordinates to LatLng format
        List<ll.LatLng> coordinates = capturedCoordinates
            .map((coord) =>
                ll.LatLng(coord['lat'] as double, coord['lng'] as double))
            .toList();

        // Calculate area in hectares
        double areaInHectares =
            PolygonCalculator.calculatePolygonAreaInHectares(coordinates);

        // Update the area controller with the computed area
        _areaCoverController.text = areaInHectares.toStringAsFixed(2);

      } catch (e) {
        // Error computing area
      }
    } else {
      // Clear area if less than 4 coordinates
      if (capturedCoordinates.isNotEmpty &&
          _areaCoverController.text.isNotEmpty) {
        _areaCoverController.clear();
      }
    }
  }

  Future<void> _editCoordinate(int index) async {
    if (!mounted) return;

    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => EditCoordinateDialog(
        coordinate: capturedCoordinates[index],
        onLocationPermissionDenied: _requestLocationPermission,
      ),
    );

    if (result != null && mounted) {
      setState(() {
        capturedCoordinates[index] = result;
        _updateAreaFromCoordinates();
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Data updated.'),
          backgroundColor: Colors.green,
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  Future<void> _deleteCoordinate(int index) async {
    final coord = capturedCoordinates[index];
    final photourlAreaId = coord['photourlAreaId'] as String?;
    final photourlAreaSeqId = coord['photourlAreaSeqId']?.toString();
    // Show confirmation dialog
    if (!mounted) return;
    final confirmed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Delete Area?'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Are you sure you want to delete this planting area?',
                  style: TextStyle(color: Colors.grey.shade700),
                ),
                if (photourlAreaSeqId != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.blue.shade50,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        'Area #$photourlAreaSeqId will be marked as deleted',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.blue.shade700,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: Text('Cancel',
                    style: TextStyle(color: Colors.grey.shade600)),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text(
                  'Delete',
                  style: TextStyle(color: Colors.red),
                ),
              ),
            ],
          ),
        ) ??
        false;

    if (!confirmed) return;

    final locationRowId = _toInt(coord['locationRowId']);

    // If it's an existing coordinate from database, mark as deleted via API
    if (photourlAreaId != null && photourlAreaId.isNotEmpty) {
      try {
        await ApiService.deletePhotourlArea(photourlAreaId).timeout(
          const Duration(seconds: 10),
          onTimeout: () {
            throw TimeoutException('Delete area timed out after 10 seconds');
          },
        );

        if (!mounted) return;

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Data updated.'),
            backgroundColor: Colors.orange,
            duration: const Duration(seconds: 2),
          ),
        );
      } catch (e) {
        if (!mounted) return;

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Unable to update data.'),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }
    } else if (locationRowId != null) {
      try {
        await ApiService.deleteLocationRow(locationRowId).timeout(
          const Duration(seconds: 10),
          onTimeout: () {
            throw TimeoutException('Delete area timed out after 10 seconds');
          },
        );
        await ApiService.deletePhotoRowsForLocation(locationRowId);

        if (!mounted) return;

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Data updated.'),
            backgroundColor: Colors.orange,
            duration: const Duration(seconds: 2),
          ),
        );
      } catch (e) {
        if (!mounted) return;

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Unable to update data.'),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }
    }

    // Remove from local list
    if (!mounted) return;
    setState(() {
      capturedCoordinates.removeAt(index);
      _updateAreaFromCoordinates(); // Compute area after deleting coordinate
    });

    // Show success
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Data updated.'),
        backgroundColor: Colors.green,
        duration: Duration(seconds: 2),
      ),
    );
  }

  int get _totalSeedlings {
    return _seedlings.fold(0, (sum, entry) => sum + entry.quantity);
  }

  Future<void> _selectDate(BuildContext context) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2000),
      lastDate: DateTime(2101),
    );
    if (picked != null) {
      setState(() {
        _selectedDate = picked;
        _dateController.text = '${picked.toLocal()}'.split(' ')[0];
      });
    }
  }

  Future<void> loadSeedlingNames() async {
    final data = await seedlingListService.getSeedlingNames();
    setState(() {
      seedlingNames = data;
      _isLoading = false;
    });
  }

  InputDecoration _modernInputDecoration({
    required String label,
    String? hint,
    IconData? icon,
    Widget? suffixIcon,
  }) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      prefixIcon: icon != null ? Icon(icon, color: Colors.grey.shade600) : null,
      suffixIcon: suffixIcon,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: Colors.grey.shade300, width: 2),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: Colors.grey.shade300, width: 2),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: Color(0xFF1B8B5E), width: 2),
      ),
      filled: true,
      fillColor: Colors.white,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      labelStyle: TextStyle(color: Colors.grey.shade700, fontSize: 13),
      hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 12),
    );
  }

  Widget _buildSectionHeader(String title, IconData icon) {
    return Row(
      children: [
        Icon(icon, color: Colors.green.shade700, size: 18),
        const SizedBox(width: 8),
        Text(
          title,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: Colors.green.shade900,
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final hasMunicipalityItems = !_isLoading && _municipalityOptions.isNotEmpty;
    LookupOption? selectedMunicipalityValue;
    if (hasMunicipalityItems && _selectedMunicipality != null) {
      final municipalityMatches = _municipalityOptions
          .where((option) => option.id == _selectedMunicipality!.id)
          .toList();
      if (municipalityMatches.length == 1) {
        selectedMunicipalityValue = municipalityMatches.first;
      }
    }

    final hasBarangayItems =
        !_isLoading &&
        !_isLoadingBarangays &&
        _selectedMunicipality != null &&
        _filteredBarangays.isNotEmpty;
    String? selectedBarangayValue;
    if (hasBarangayItems && _selectedBarangay != null) {
      final selectedLower = _selectedBarangay!.trim().toLowerCase();
      final barangayMatches = _filteredBarangays
          .where((name) => name.trim().toLowerCase() == selectedLower)
          .toList();
      if (barangayMatches.length == 1) {
        selectedBarangayValue = barangayMatches.first;
      }
    }

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        color: Colors.white,
      ),
      constraints: const BoxConstraints(maxWidth: 600, maxHeight: 800),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Header - Similar to AddSeedlingDialog
          Container(
            decoration: const BoxDecoration(
              color: Color(0xFF1B8B5E),
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(12),
                topRight: Radius.circular(12),
              ),
            ),
            padding: const EdgeInsets.all(18),
            child: Row(
              children: const [
                Icon(Icons.forest, color: Colors.white, size: 24),
                SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Tree Growing Data Entry',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                    Text(
                      'Record new growing activity',
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.white70,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // Content - Scrollable
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Activity Name
                  Text(
                    'Activity Name *',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: Colors.grey.shade700,
                    ),
                  ),
                  const SizedBox(height: 6),
                  TextField(
                    enabled: !_isLoading,
                    controller: _activityNameController,
                    decoration: _modernInputDecoration(
                      label: '',
                      hint: 'Enter activity name',
                      icon: Icons.edit_rounded,
                    ),
                  ),
                  const SizedBox(height: 14),

                  // Municipality
                  Text(
                    'Municipality *',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: Colors.grey.shade700,
                    ),
                  ),
                  const SizedBox(height: 6),
                  DropdownButtonFormField<LookupOption>(
                    value: selectedMunicipalityValue,
                    onChanged: _isLoading
                        ? null
                        : (LookupOption? newValue) {
                            final municipalityId = newValue?.id;
                            setState(() {
                              _selectedMunicipality = newValue;
                              _selectedBarangay = null;
                              _filteredBarangays = [];
                            });

                            if (municipalityId != null) {
                              _loadBarangaysForMunicipality(municipalityId);
                            }
                          },
                    decoration: _modernInputDecoration(
                      label: '',
                      icon: Icons.location_city_rounded,
                    ),
                    dropdownColor: Colors.white,
                    borderRadius: BorderRadius.circular(8),
                    items: _isLoading || _municipalityOptions.isEmpty
                        ? [
                            const DropdownMenuItem<LookupOption>(
                              value: null,
                              child: Text('Loading...'),
                            )
                          ]
                        : _municipalityOptions.map((option) {
                            return DropdownMenuItem<LookupOption>(
                              value: option,
                              child: Text(option.name),
                            );
                          }).toList(),
                  ),
                  const SizedBox(height: 14),

                  // Barangay
                  Text(
                    'Barangay *',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: Colors.grey.shade700,
                    ),
                  ),
                  const SizedBox(height: 6),
                  DropdownButtonFormField<String>(
                    value: selectedBarangayValue,
                    onChanged: (_isLoading ||
                            _isLoadingBarangays ||
                            _selectedMunicipality == null ||
                            _filteredBarangays.isEmpty)
                        ? null
                        : (String? newValue) {
                            setState(() => _selectedBarangay = newValue);
                          },
                    decoration: _modernInputDecoration(
                      label: '',
                      icon: Icons.location_city_rounded,
                    ),
                    dropdownColor: Colors.white,
                    borderRadius: BorderRadius.circular(8),
                    items: _isLoading
                        ? [
                            const DropdownMenuItem<String>(
                              value: null,
                              child: Text('Loading...'),
                            )
                          ]
                        : _isLoadingBarangays
                            ? [
                                const DropdownMenuItem<String>(
                                  value: null,
                                  child: Text('Loading barangays...'),
                                )
                              ]
                            : _selectedMunicipality == null
                                ? [
                                    const DropdownMenuItem<String>(
                                      value: null,
                                      child: Text('Select municipality first'),
                                    )
                                  ]
                                : _filteredBarangays.isEmpty
                                    ? [
                                        const DropdownMenuItem<String>(
                                          value: null,
                                          child: Text('No barangays found'),
                                        )
                                      ]
                                    : _filteredBarangays.map((String value) {
                                        return DropdownMenuItem<String>(
                                          value: value,
                                          child: Text(value),
                                        );
                                      }).toList(),
                  ),
                  const SizedBox(height: 14),

                  // Date
                  Text(
                    'Date *',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: Colors.grey.shade700,
                    ),
                  ),
                  const SizedBox(height: 6),
                  TextField(
                    controller: _dateController,
                    enabled: !_isLoading,
                    readOnly: true,
                    onTap: _isLoading ? null : () => _selectDate(context),
                    decoration: _modernInputDecoration(
                      label: '',
                      icon: Icons.calendar_today_rounded,
                      suffixIcon: Icon(
                        Icons.arrow_drop_down_rounded,
                        color: Colors.grey.shade600,
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),

                  // Seedling Details Section
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      _buildSectionHeader('Seedling Details', Icons.eco),
                      ElevatedButton.icon(
                        onPressed: _isLoadingSeedlings
                            ? null
                            : () async {
                          // Open instantly with whatever's cached so the
                          // button doesn't sit there waiting on a network
                          // round-trip; refresh the cache in the background
                          // for next time.
                          final cached = SeedlingListService.getCachedNames();
                          List<String> seedlingNames;
                          if (cached.isNotEmpty) {
                            seedlingNames = cached;
                            seedlingListService.getSeedlingNames();
                          } else {
                            setState(() => _isLoadingSeedlings = true);
                            seedlingNames =
                                await seedlingListService.getSeedlingNames();
                            if (!mounted) return;
                            setState(() => _isLoadingSeedlings = false);
                          }

                          if (!mounted) return;
                          showDialog(
                            context: context,
                            builder: (context) => AddSeedlingDialog(
                              seedlingInventory: seedlingNames,
                              onAdd: (type, quantity) {
                                setState(() {
                                  _seedlings.add(
                                    SeedlingEntry(
                                        seedlingType: type, quantity: quantity),
                                  );
                                });
                              },
                            ),
                          );
                        },
                        icon: const Icon(Icons.add, size: 16),
                        label:
                            const Text("Add", style: TextStyle(fontSize: 12)),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF1B8B5E),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 30, vertical: 6),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),

                  // Seedlings Display
                  if (_isLoadingSeedlings)
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        border:
                            Border.all(color: Colors.grey.shade200, width: 1),
                        borderRadius: BorderRadius.circular(6),
                        color: Colors.grey.shade50,
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        'Loading seedling details...',
                        style: TextStyle(
                          color: Colors.grey.shade600,
                          fontSize: 11,
                        ),
                      ),
                    )
                  else if (_seedlings.isEmpty)
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        border:
                            Border.all(color: Colors.grey.shade200, width: 1),
                        borderRadius: BorderRadius.circular(6),
                        color: Colors.grey.shade50,
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        'No seedlings added yet.',
                        style: TextStyle(
                          color: Colors.grey.shade600,
                          fontSize: 11,
                        ),
                      ),
                    )
                  else ...[
                    Container(
                      width: double.infinity,
                      decoration: BoxDecoration(
                        color: Colors.green.shade50,
                        border: Border.all(color: Colors.green.shade200),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          final speciesWidth = constraints.maxWidth * 0.50;
                          final countWidth = constraints.maxWidth * 0.22;
                          final actionsWidth = constraints.maxWidth * 0.18;

                          return SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: ConstrainedBox(
                              constraints: BoxConstraints(minWidth: constraints.maxWidth),
                              child: DataTable(
                                headingRowHeight: 40,
                                dataRowMinHeight: 44,
                                dataRowMaxHeight: 52,
                                columnSpacing: 10,
                                columns: [
                                  DataColumn(
                                    label: SizedBox(
                                      width: speciesWidth,
                                      child: const Text(
                                        'Species',
                                        style: TextStyle(fontWeight: FontWeight.w700),
                                      ),
                                    ),
                                  ),
                                  DataColumn(
                                    numeric: true,
                                    label: SizedBox(
                                      width: countWidth,
                                      child: const Text(
                                        'Seedling Count',
                                        style: TextStyle(fontWeight: FontWeight.w700),
                                      ),
                                    ),
                                  ),
                                  DataColumn(
                                    label: SizedBox(
                                      width: actionsWidth,
                                      child: const Text(
                                        'Actions',
                                        style: TextStyle(fontWeight: FontWeight.w700),
                                      ),
                                    ),
                                  ),
                                ],
                                rows: _seedlings.asMap().entries.map((entry) {
                                  final index = entry.key;
                                  final seedling = entry.value;

                                  return DataRow(
                                    cells: [
                                      DataCell(
                                        SizedBox(
                                          width: speciesWidth,
                                          child: Text(seedling.seedlingType),
                                        ),
                                      ),
                                      DataCell(
                                        SizedBox(
                                          width: countWidth,
                                          child: Text('${seedling.quantity}'),
                                        ),
                                      ),
                                      DataCell(
                                        SizedBox(
                                          width: actionsWidth,
                                          child: Row(
                                            children: [
                                              IconButton(
                                                onPressed: () => _editSeedling(index),
                                                icon: const Icon(
                                                  Icons.edit_rounded,
                                                  size: 18,
                                                  color: Color(0xFF1B8B5E),
                                                ),
                                                tooltip: 'Edit',
                                              ),
                                              IconButton(
                                                onPressed: () => _removeSeedling(index),
                                                icon: const Icon(
                                                  Icons.delete_outline_rounded,
                                                  size: 18,
                                                  color: Colors.red,
                                                ),
                                                tooltip: 'Delete',
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ],
                                  );
                                }).toList(),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        border:
                            Border.all(color: Colors.green.shade300, width: 1),
                        borderRadius: BorderRadius.circular(6),
                        color: Colors.green.shade50,
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Total:',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: Colors.green.shade900,
                            ),
                          ),
                          Text(
                            '${_seedlings.length} type | ${_totalSeedlings} qty',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: const Color(0xFF1B8B5E),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 14),
                  // Notes
                  Text(
                    'Notes',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: Colors.grey.shade700,
                    ),
                  ),
                  const SizedBox(height: 6),
                  TextField(
                    enabled: !_isLoading,
                    controller: _detailsController,
                    decoration: _modernInputDecoration(
                      label: '',
                      hint: 'Optional details...',
                      icon: Icons.notes_rounded,
                    ),
                    maxLines: 2,
                  ),
                  const SizedBox(height: 14),

                  // Area
                  Text(
                    'Area (ha)',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: Colors.grey.shade700,
                    ),
                  ),
                  const SizedBox(height: 6),
                  TextField(
                    controller: _areaCoverController,
                    enabled: !_isLoading,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    decoration: _modernInputDecoration(
                      label: '',
                      hint: 'Hectares',
                      icon: Icons.square_foot_rounded,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [Colors.teal.shade50, Colors.green.shade50],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Colors.teal.shade100),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (_locationPermissionGranted)
                          Row(
                            children: [
                              Expanded(
                                child: _buildCaptureButton(
                                  icon: Icons.gps_fixed_rounded,
                                  label: 'Capture GPS',
                                  color: const Color(0xFF2196F3),
                                  onPressed: (_isLoading ||
                                          _isCapturingLocation ||
                                          _isLoadingCoordinates)
                                      ? null
                                      : _captureCurrentLocation,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: _buildCaptureButton(
                                  icon: Icons.camera_alt_rounded,
                                  label: 'Take Photo',
                                  color: const Color(0xFF4CAF50),
                                  onPressed: (_isLoading ||
                                          _isCapturingLocation ||
                                          _isLoadingCoordinates)
                                      ? null
                                      : _capturePhotoAndCoordinate,
                                ),
                              ),
                            ],
                          )
                        else
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.orange.shade50,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(
                              children: [
                                Icon(Icons.warning_amber_rounded,
                                    color: Colors.orange.shade700, size: 20),
                                const SizedBox(width: 8),
                                const Expanded(
                                  child: Text(
                                    'Location permission required',
                                    style: TextStyle(fontSize: 13),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        if (_isCapturingLocation || _isLoadingCoordinates) ...[
                          const SizedBox(height: 16),
                          Center(
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child:
                                      CircularProgressIndicator(strokeWidth: 2),
                                ),
                                const SizedBox(width: 12),
                                Text(
                                  _isLoadingCoordinates
                                      ? 'Loading areas...'
                                      : 'Capturing...',
                                  style: const TextStyle(fontSize: 13),
                                ),
                              ],
                            ),
                          ),
                        ],
                        const SizedBox(height: 16),
                        if (capturedCoordinates.isNotEmpty)
                          for (int i = 0; i < capturedCoordinates.length; i++)
                            Column(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    borderRadius: BorderRadius.circular(12),
                                    border:
                                        Border.all(color: Colors.teal.shade100),
                                  ),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Container(
                                            width: 40,
                                            height: 40,
                                            decoration: BoxDecoration(
                                              color: Colors.grey.shade200,
                                              borderRadius:
                                                  BorderRadius.circular(10),
                                            ),
                                            child: Icon(
                                              Icons.location_on_rounded,
                                              color: Colors.grey.shade500,
                                              size: 20,
                                            ),
                                          ),
                                          const SizedBox(width: 12),
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  'Point ${i + 1}',
                                                  style: TextStyle(
                                                    fontSize: 14,
                                                    fontWeight: FontWeight.w600,
                                                    color: Colors.grey.shade600,
                                                  ),
                                                ),
                                                const SizedBox(height: 4),
                                                Text(
                                                  'Lat: ${capturedCoordinates[i]['lat']?.toStringAsFixed(6) ?? 'N/A'}, Lng: ${capturedCoordinates[i]['lng']?.toStringAsFixed(6) ?? 'N/A'}',
                                                  style: TextStyle(
                                                    color: Colors.grey.shade600,
                                                    fontSize: 11,
                                                  ),
                                                ),
                                                if (capturedCoordinates[i]
                                                      ['photoPath'] !=
                                                    null ||
                                                  capturedCoordinates[i]
                                                      ['photoUrl'] !=
                                                    null)
                                                  Padding(
                                                    padding:
                                                        const EdgeInsets.only(
                                                            top: 4),
                                                    child: Text(
                                                      '📷 Photo captured',
                                                      style: TextStyle(
                                                        color: Colors
                                                            .green.shade600,
                                                        fontSize: 11,
                                                        fontWeight:
                                                            FontWeight.w500,
                                                      ),
                                                    ),
                                                  ),
                                              ],
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 12),
                                      Row(
                                        children: [
                                          Expanded(
                                            child: _buildCaptureButton(
                                              label: 'Edit',
                                              icon: Icons.edit_rounded,
                                              onPressed: () =>
                                                  _editCoordinate(i),
                                              color: Colors.amber.shade400,
                                            ),
                                          ),
                                          const SizedBox(width: 6),
                                          Expanded(
                                            child: _buildCaptureButton(
                                              label: 'Remove',
                                              icon: Icons.delete_rounded,
                                              onPressed: () =>
                                                  _deleteCoordinate(i),
                                              color: Colors.red.shade400,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(height: 12),
                              ],
                            )
                        else
                          Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: Colors.grey.shade50,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            alignment: Alignment.center,
                            child: Text(
                              'No points captured yet. Use the buttons above to capture GPS or take photos.',
                              style: TextStyle(
                                color: Colors.grey.shade600,
                                fontSize: 12,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Buttons Footer - Similar to AddSeedlingDialog
          Container(
            decoration: BoxDecoration(
              border: Border(
                top: BorderSide(color: Colors.grey.shade200),
              ),
            ),
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: widget.onCancel,
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    child: const Text('Cancel', style: TextStyle(fontSize: 13)),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  flex: 2,
                  child: ElevatedButton(
                    onPressed: (_isLoading || _isSaving) ? null : _handleSave,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF1B8B5E),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      elevation: 0,
                    ),
                    child: _isSaving
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.save_rounded, size: 20),
                              SizedBox(width: 8),
                              Text(
                                'Save Record',
                                style: TextStyle(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 15,
                                ),
                              ),
                            ],
                          ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCaptureButton({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback? onPressed,
  }) {
    return ElevatedButton(
      onPressed: onPressed,
      style: ElevatedButton.styleFrom(
        backgroundColor: color,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        elevation: 0,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 18),
          const SizedBox(width: 8),
          Text(label, style: const TextStyle(fontWeight: FontWeight.w400)),
        ],
      ),
    );
  }
}

