import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';
import 'package:latlong2/latlong.dart' as ll;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../service/activity_model.dart';
import '../service/api_service.dart';
import '../service/auth_session.dart';
import '../service/location_capture_service.dart';
import '../service/lookup_service.dart';
import '../service/offline_sync_service.dart';
import '../widget/edit_coordinate_dialog.dart';
import '../widget/polygon_calculator.dart';

class MarineProtectedAreaForm extends StatefulWidget {
  final VoidCallback onSave;
  final VoidCallback onCancel;
  final MarineProtectedArea? initialData;

  /// When set, this form is editing a record that was saved offline and is
  /// still sitting in the local sync queue (not yet on the server). In this
  /// mode fields are seeded from [pendingPayload] instead of [initialData],
  /// and saving rewrites the queued item instead of calling the network.
  final String? pendingLocalId;
  final Map<String, dynamic>? pendingPayload;

  const MarineProtectedAreaForm({
    super.key,
    required this.onSave,
    required this.onCancel,
    this.initialData,
    this.pendingLocalId,
    this.pendingPayload,
  });

  @override
  State<MarineProtectedAreaForm> createState() => _MarineProtectedAreaFormState();
}

class _MarineProtectedAreaFormState extends State<MarineProtectedAreaForm> {
  // Supabase bucket id used by this app project.
  static const String _storageBucketName = 'Forest Management';

  late TextEditingController _nameController;
  late TextEditingController _areaController;
  late TextEditingController _ordinanceController;
  late TextEditingController _dateController;

  LookupOption? _selectedMunicipality;
  String? _selectedBarangay;
  List<LookupOption> _municipalityOptions = [];
  List<String> _filteredBarangays = [];
  DateTime _selectedDate = DateTime.now();

  bool _isLoading = false;
  bool _isSaving = false;
  bool _isLoadingBarangays = false;
  bool _didApplyInitialMunicipality = false;

  bool _locationPermissionGranted = false;
  bool _isCapturingLocation = false;
  final ImagePicker _imagePicker = ImagePicker();
  final List<Map<String, dynamic>> _capturedCoordinates = [];

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController();
    _areaController = TextEditingController();
    _ordinanceController = TextEditingController();
    _dateController = TextEditingController();

    final pending = widget.pendingPayload;
    final initial = widget.initialData;
    if (pending != null) {
      _nameController.text = (pending['name'] as String? ?? '').trim();
      _ordinanceController.text = (pending['ordinance'] as String?)?.trim() ?? '';
      final pendingArea = pending['area'];
      _areaController.text = pendingArea != null ? pendingArea.toString() : '';
      final pendingBarangay = (pending['barangay'] as String? ?? '').trim();
      _selectedBarangay = pendingBarangay.isEmpty ? null : pendingBarangay;
      _selectedDate =
          DateTime.tryParse(pending['date'] as String? ?? '') ?? DateTime.now();

      final pendingCoordinates = (pending['coordinates'] as List?) ?? const [];
      for (final raw in pendingCoordinates) {
        final coord = Map<String, dynamic>.from(raw as Map);
        final lat = (coord['lat'] as num?)?.toDouble();
        final lng = (coord['lng'] as num?)?.toDouble();
        if (lat == null || lng == null) continue;
        final stablePhotoPath = coord['stablePhotoPath'] as String?;
        _capturedCoordinates.add({
          'lat': lat,
          'lng': lng,
          if (stablePhotoPath != null && stablePhotoPath.isNotEmpty)
            'photoPath': stablePhotoPath,
        });
      }
    } else if (initial != null) {
      _nameController.text = initial.name.trim();
      _ordinanceController.text = initial.ordinance?.trim() ?? '';
      _areaController.text = initial.area?.toString() ?? '';
      _selectedBarangay =
          initial.barangay.trim().isEmpty ? null : initial.barangay.trim();
      _selectedDate = initial.date;
      _loadInitialCoordinates();
    }
    _dateController.text = _formatDateOnly(_selectedDate);

    _requestLocationPermission();
    _loadMunicipalityOptions();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _areaController.dispose();
    _ordinanceController.dispose();
    _dateController.dispose();
    super.dispose();
  }

  String _formatDateOnly(DateTime value) {
    final year = value.year.toString().padLeft(4, '0');
    final month = value.month.toString().padLeft(2, '0');
    final day = value.day.toString().padLeft(2, '0');
    return '$year-$month-$day';
  }

  Future<void> _selectDate(BuildContext context) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2000),
      lastDate: DateTime(2101),
    );
    if (picked != null) {
      setState(() {
        _selectedDate = picked;
        _dateController.text = _formatDateOnly(picked);
      });
    }
  }

  Future<void> _loadInitialCoordinates() async {
    final areaId = widget.initialData?.id;
    if (areaId == null) return;

    List<Map<String, dynamic>> rows;
    try {
      rows = await ApiService.getLocationRowsByActivity(
        activityTypeId: ApiService.marineProtectedAreaActivityTypeId,
        activityId: areaId,
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Unable to load location details: $e'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    // Photo lookup is best-effort: if it fails (e.g. no connection), the
    // captured points below should still populate instead of being lost.
    final photoUrlByLocationId = <int, String>{};
    try {
      final photoRows = await ApiService.getPhotosForActivity(
        projectTypeId: ApiService.marineProtectedAreaActivityTypeId,
        activityId: areaId,
      );
      for (final photo in photoRows) {
        final locationId = (photo['location_id'] as num?)?.toInt();
        final photoUrl = photo['photo_url'] as String?;
        if (locationId != null && photoUrl != null && photoUrl.isNotEmpty) {
          photoUrlByLocationId[locationId] = photoUrl;
        }
      }
    } catch (_) {
      // Ignore — locations still populate below without photo indicators.
    }

    final loadedCoordinates = rows
        .map((row) {
          final lat = (row['latitude'] as num?)?.toDouble();
          final lng = (row['longitude'] as num?)?.toDouble();
          final locationId = (row['id'] as num?)?.toInt();

          return <String, dynamic>{
            'lat': lat,
            'lng': lng,
            if (locationId != null) 'locationRowId': locationId,
            if (locationId != null && photoUrlByLocationId[locationId] != null)
              'photoUrl': photoUrlByLocationId[locationId],
          };
        })
        .where((row) => row['lat'] != null && row['lng'] != null)
        .toList();

    if (!mounted) return;
    setState(() {
      _capturedCoordinates
        ..clear()
        ..addAll(loadedCoordinates);
      _updateAreaFromCoordinates();
    });
  }

  Future<void> _loadMunicipalityOptions() async {
    setState(() => _isLoading = true);
    try {
      final options = await LookupService.getMunicipalityOptions();
      if (!mounted) return;
      setState(() => _municipalityOptions = options);

      final pending = widget.pendingPayload;
      final initial = widget.initialData;
      final seedMunicipalityName = pending != null
          ? pending['municipality'] as String?
          : initial?.municipality;

      if (!_didApplyInitialMunicipality &&
          seedMunicipalityName != null &&
          seedMunicipalityName.trim().isNotEmpty) {
        _didApplyInitialMunicipality = true;
        final initialMunicipality = seedMunicipalityName.trim().toLowerCase();

        LookupOption? match;
        for (final option in options) {
          if (option.name.trim().toLowerCase() == initialMunicipality) {
            match = option;
            break;
          }
        }

        if (match != null) {
          if (!mounted) return;
          setState(() => _selectedMunicipality = match);
          await _loadBarangaysForMunicipality(match.id);

          if (!mounted || _selectedBarangay == null) return;
          final selectedLower = _selectedBarangay!.trim().toLowerCase();
          String? matchedBarangay;
          for (final name in _filteredBarangays) {
            if (name.trim().toLowerCase() == selectedLower) {
              matchedBarangay = name;
              break;
            }
          }
          setState(() => _selectedBarangay = matchedBarangay);
        }
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _loadBarangaysForMunicipality(int municipalityId) async {
    setState(() {
      _isLoadingBarangays = true;
      _filteredBarangays = [];
    });

    try {
      final options =
          await LookupService.getBarangayOptionsByMunicipalityId(municipalityId);
      if (!mounted) return;

      final seen = <String>{};
      final uniqueBarangays = <String>[];
      for (final option in options) {
        final name = option.name.trim();
        if (name.isEmpty) continue;
        if (seen.add(name.toLowerCase())) {
          uniqueBarangays.add(name);
        }
      }

      setState(() => _filteredBarangays = uniqueBarangays);
    } finally {
      if (mounted) setState(() => _isLoadingBarangays = false);
    }
  }

  Future<void> _requestLocationPermission() async {
    try {
      final permission = await Geolocator.checkPermission();

      if (permission == LocationPermission.denied) {
        final result = await Geolocator.requestPermission();
        setState(() => _locationPermissionGranted =
            result == LocationPermission.whileInUse ||
                result == LocationPermission.always);
      } else if (permission == LocationPermission.whileInUse ||
          permission == LocationPermission.always) {
        setState(() => _locationPermissionGranted = true);
      } else if (permission == LocationPermission.deniedForever) {
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
    } catch (_) {
      setState(() => _locationPermissionGranted = false);
    }
  }

  void _updateAreaFromCoordinates() {
    if (_capturedCoordinates.length >= 3) {
      try {
        final coordinates = _capturedCoordinates
            .map((coord) =>
                ll.LatLng(coord['lat'] as double, coord['lng'] as double))
            .toList();
        final areaInHectares =
            PolygonCalculator.calculatePolygonAreaInHectares(coordinates);
        _areaController.text = areaInHectares.toStringAsFixed(2);
      } catch (_) {
        // Ignore errors computing area; leave the field as-is.
      }
    } else if (_capturedCoordinates.isEmpty && _areaController.text.isNotEmpty) {
      _areaController.clear();
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

      setState(() {
        _capturedCoordinates.add({
          'lat': result.position.latitude,
          'lng': result.position.longitude,
        });
        _updateAreaFromCoordinates();
      });

      if (result.isFallback) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'GPS fix timed out — used your last known location. Verify it or retake.',
            ),
            backgroundColor: Colors.orange,
          ),
        );
      }
    } catch (_) {
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
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Action timed out.'),
                    backgroundColor: Colors.red,
                  ),
                );
              }
              return null;
            },
          );

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

      final locationResult = await LocationCaptureService.capture();

      if (!mounted) return;

      setState(() {
        _capturedCoordinates.add({
          'lat': locationResult.position.latitude,
          'lng': locationResult.position.longitude,
          'photoPath': photo.path,
        });
        _updateAreaFromCoordinates();
        _isCapturingLocation = false;
      });

      if (locationResult.isFallback) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'GPS fix timed out — used your last known location. Verify it or retake.',
            ),
            backgroundColor: Colors.orange,
          ),
        );
      }
    } catch (e) {
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

  Future<void> _editCoordinate(int index) async {
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => EditCoordinateDialog(
        coordinate: _capturedCoordinates[index],
        onLocationPermissionDenied: _requestLocationPermission,
      ),
    );

    if (result != null && mounted) {
      setState(() {
        _capturedCoordinates[index] = result;
        _updateAreaFromCoordinates();
      });
    }
  }

  Future<void> _removeCoordinate(int index) async {
    final locationRowId = (_capturedCoordinates[index]['locationRowId'] as num?)?.toInt();

    if (locationRowId != null) {
      final confirmed = await showDialog<bool>(
            context: context,
            builder: (dialogContext) => AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              title: const Text('Remove Point?'),
              content: const Text(
                  'This point was already saved. Removing it will delete it from this record.'),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(false),
                  child: const Text('Cancel'),
                ),
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(true),
                  child: const Text('Remove', style: TextStyle(color: Colors.red)),
                ),
              ],
            ),
          ) ??
          false;

      if (!confirmed) return;

      try {
        await ApiService.deleteLocationRow(locationRowId);
        await ApiService.deletePhotoRowsForLocation(locationRowId);
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Unable to remove point: $e'),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }
    }

    if (!mounted) return;
    setState(() {
      _capturedCoordinates.removeAt(index);
      _updateAreaFromCoordinates();
    });
  }

  String _contentTypeFromPath(String path) {
    final lower = path.toLowerCase();
    if (lower.endsWith('.png')) return 'image/png';
    if (lower.endsWith('.webp')) return 'image/webp';
    return 'image/jpeg';
  }

  String _extractFileExtension(String path) {
    final lastSeparator = path.lastIndexOf(Platform.pathSeparator);
    final fileName = lastSeparator >= 0 ? path.substring(lastSeparator + 1) : path;
    final dotIndex = fileName.lastIndexOf('.');
    if (dotIndex <= 0 || dotIndex == fileName.length - 1) return '';
    return fileName.substring(dotIndex);
  }

  Future<String> _uploadMarineProtectedAreaPhotoToSupabase({
    required String localPath,
    required String photoName,
  }) async {
    final file = File(localPath);
    if (!await file.exists()) {
      throw Exception('Photo file does not exist: $localPath');
    }

    final objectPath = 'public/marine_protected_area/$photoName';
    final contentType = _contentTypeFromPath(photoName);

    await Supabase.instance.client.storage.from(_storageBucketName).upload(
          objectPath,
          file,
          fileOptions: FileOptions(upsert: false, contentType: contentType),
        );

    try {
      await file.delete();
    } catch (_) {
      // Best effort only. File is temporary camera output.
    }

    final encodedBucket = Uri.encodeComponent(_storageBucketName);
    return 'public/$encodedBucket/$objectPath';
  }

  /// Stages every captured coordinate's photo (if any) into stable offline
  /// storage and returns the offline-queue coordinate shape expected by
  /// `OfflineSyncService`'s `marine_protected_area` payload.
  Future<List<Map<String, dynamic>>> _stageCoordinatesForOfflineQueue() async {
    final staged = <Map<String, dynamic>>[];
    for (final coord in _capturedCoordinates) {
      final photoPath = coord['photoPath'] as String?;
      final stablePhotoPath = await OfflineSyncService.stagePhoto(photoPath);
      staged.add({
        'lat': coord['lat'],
        'lng': coord['lng'],
        if (stablePhotoPath != null) 'stablePhotoPath': stablePhotoPath,
      });
    }
    return staged;
  }

  void _showQueuedSnackBar() {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Data was saved.'),
        backgroundColor: Colors.orange,
        duration: Duration(seconds: 3),
      ),
    );
  }

  Future<void> _handleSave() async {
    if (_isSaving) return;

    final name = _nameController.text.trim();
    final municipality = _selectedMunicipality?.name.trim() ?? '';
    final barangay = _selectedBarangay?.trim() ?? '';
    final ordinance = _ordinanceController.text.trim();

    if (name.isEmpty || municipality.isEmpty || barangay.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Data is incomplete.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    final isPendingDraft = widget.pendingLocalId != null;
    final isEditing = widget.initialData?.id != null;

    final userSeqId = AuthSession.currentUser?.seqId;
    if (!isEditing && !isPendingDraft && userSeqId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Unable to save data: missing user id. Try signing out and back in.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    final parsedArea = double.tryParse(_areaController.text.trim());

    setState(() => _isSaving = true);

    try {
      // ── Editing a draft that is still sitting in the offline queue ──────
      if (isPendingDraft) {
        final stagedCoordinates = await _stageCoordinatesForOfflineQueue();
        final pendingUserId =
            (widget.pendingPayload?['userId'] as num?)?.toInt() ?? userSeqId;

        final payload = {
          'userId': pendingUserId,
          'name': name,
          'municipality': municipality,
          'barangay': barangay,
          'date': _selectedDate.toIso8601String(),
          'area': parsedArea,
          'ordinance': ordinance.isEmpty ? null : ordinance,
          'coordinates': stagedCoordinates,
        };

        await OfflineSyncService.updatePendingItem(
          widget.pendingLocalId!,
          payload,
        );

        _showQueuedSnackBar();
        widget.onSave();
        return;
      }
      // ── End pending-draft path ───────────────────────────────────────────

      // ── Offline path (create-only; editing an already-synced record
      // requires an internet connection) ──────────────────────────────────
      final isOnline = await OfflineSyncService.hasInternetConnection();
      if (!mounted) return;
      if (!isOnline) {
        if (isEditing) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Editing requires an internet connection.'),
              backgroundColor: Colors.red,
            ),
          );
          return;
        }

        final stagedCoordinates = await _stageCoordinatesForOfflineQueue();

        final payload = {
          'userId': userSeqId,
          'name': name,
          'municipality': municipality,
          'barangay': barangay,
          'date': _selectedDate.toIso8601String(),
          'area': parsedArea,
          'ordinance': ordinance.isEmpty ? null : ordinance,
          'coordinates': stagedCoordinates,
        };

        await OfflineSyncService.queueGenericRecord(
          type: 'marine_protected_area',
          payload: payload,
        );

        _showQueuedSnackBar();
        widget.onSave();
        return;
      }
      // ── End offline path ─────────────────────────────────────────────────

      final savedArea = isEditing
          ? await ApiService.updateMarineProtectedArea(
              id: widget.initialData!.id!,
              name: name,
              municipality: municipality,
              barangay: barangay,
              date: _selectedDate,
              area: parsedArea,
              ordinance: ordinance.isEmpty ? null : ordinance,
            )
          : await ApiService.saveMarineProtectedArea(
              userId: userSeqId!,
              name: name,
              municipality: municipality,
              barangay: barangay,
              date: _selectedDate,
              area: parsedArea,
              ordinance: ordinance.isEmpty ? null : ordinance,
            );

      final areaId = (savedArea['id'] as num?)?.toInt();

      if (areaId != null && _capturedCoordinates.isNotEmpty) {
        for (final coord in _capturedCoordinates) {
          final latitude = (coord['lat'] as num?)?.toDouble();
          final longitude = (coord['lng'] as num?)?.toDouble();
          if (latitude == null || longitude == null) continue;

          final photoPath = coord['photoPath'] as String?;
          int? locationId = (coord['locationRowId'] as num?)?.toInt();

          if (locationId != null) {
            await ApiService.updateLocationRowCoordinates(
              locationId: locationId,
              latitude: latitude,
              longitude: longitude,
            );
          } else {
            final createdRow = await ApiService.createLocationRow(
              activityId: areaId,
              activityTypeId: ApiService.marineProtectedAreaActivityTypeId,
              latitude: latitude,
              longitude: longitude,
            );
            locationId = (createdRow['id'] as num?)?.toInt();
            coord['locationRowId'] = locationId;
          }

          if (photoPath == null || photoPath.isEmpty) continue;

          final extension = _extractFileExtension(photoPath);
          final photoName =
              'photo_marine_${ApiService.marineProtectedAreaActivityTypeId}_${areaId}_${DateTime.now().millisecondsSinceEpoch}${extension.isEmpty ? '.jpg' : extension}';

          final supabasePhotoUrl = await _uploadMarineProtectedAreaPhotoToSupabase(
            localPath: photoPath,
            photoName: photoName,
          );

          await ApiService.createPhotoRow(
            projectTypeId: ApiService.marineProtectedAreaActivityTypeId,
            activityId: areaId,
            photoUrl: supabasePhotoUrl,
            locationId: locationId,
          );

          coord['photoPath'] = null;
          coord['photoUrl'] = supabasePhotoUrl;
        }
      }

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Data was saved.'),
          backgroundColor: Colors.green,
        ),
      );

      widget.onSave();
      OfflineSyncService.syncAll().ignore();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Unable to save data: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
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

  @override
  Widget build(BuildContext context) {
    final hasMunicipalityItems = !_isLoading && _municipalityOptions.isNotEmpty;
    LookupOption? selectedMunicipalityValue;
    if (hasMunicipalityItems && _selectedMunicipality != null) {
      final matches = _municipalityOptions
          .where((option) => option.id == _selectedMunicipality!.id)
          .toList();
      if (matches.length == 1) selectedMunicipalityValue = matches.first;
    }

    final hasBarangayItems = !_isLoading &&
        !_isLoadingBarangays &&
        _selectedMunicipality != null &&
        _filteredBarangays.isNotEmpty;
    String? selectedBarangayValue;
    if (hasBarangayItems && _selectedBarangay != null) {
      final selectedLower = _selectedBarangay!.trim().toLowerCase();
      final matches = _filteredBarangays
          .where((name) => name.trim().toLowerCase() == selectedLower)
          .toList();
      if (matches.length == 1) selectedBarangayValue = matches.first;
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
          // Header
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
                Icon(Icons.sailing, color: Colors.white, size: 24),
                SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Marine Protected Area Data Entry',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                    Text(
                      'Record new marine protected area',
                      style: TextStyle(fontSize: 11, color: Colors.white70),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // Content
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Name *',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: Colors.grey.shade700,
                    ),
                  ),
                  const SizedBox(height: 6),
                  TextField(
                    enabled: !_isLoading,
                    controller: _nameController,
                    decoration: _modernInputDecoration(
                      label: '',
                      hint: 'Enter marine protected area name',
                      icon: Icons.edit_rounded,
                    ),
                  ),
                  const SizedBox(height: 14),

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

                  Text(
                    'Ordinance',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: Colors.grey.shade700,
                    ),
                  ),
                  const SizedBox(height: 6),
                  TextField(
                    enabled: !_isLoading,
                    controller: _ordinanceController,
                    decoration: _modernInputDecoration(
                      label: '',
                      hint: 'e.g. Municipal Ordinance No. 2024-01',
                      icon: Icons.gavel_rounded,
                    ),
                    maxLines: 2,
                  ),
                  const SizedBox(height: 14),

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
                    controller: _areaController,
                    enabled: !_isLoading,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: _modernInputDecoration(
                      label: '',
                      hint: 'Hectares',
                      icon: Icons.square_foot_rounded,
                    ),
                  ),
                  const SizedBox(height: 16),

                  // GPS / Photo capture (feeds photourl_area, activity_type_id = 9)
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
                                  onPressed: (_isLoading || _isCapturingLocation)
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
                                  onPressed: (_isLoading || _isCapturingLocation)
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
                        if (_isCapturingLocation) ...[
                          const SizedBox(height: 16),
                          const Center(
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                ),
                                SizedBox(width: 12),
                                Text('Capturing...', style: TextStyle(fontSize: 13)),
                              ],
                            ),
                          ),
                        ],
                        const SizedBox(height: 16),
                        if (_capturedCoordinates.isNotEmpty)
                          for (int i = 0; i < _capturedCoordinates.length; i++)
                            Column(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(color: Colors.teal.shade100),
                                  ),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Container(
                                            width: 40,
                                            height: 40,
                                            decoration: BoxDecoration(
                                              color: Colors.grey.shade200,
                                              borderRadius: BorderRadius.circular(10),
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
                                              crossAxisAlignment: CrossAxisAlignment.start,
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
                                                  'Lat: ${_capturedCoordinates[i]['lat']?.toStringAsFixed(6) ?? 'N/A'}, Lng: ${_capturedCoordinates[i]['lng']?.toStringAsFixed(6) ?? 'N/A'}',
                                                  style: TextStyle(
                                                    color: Colors.grey.shade600,
                                                    fontSize: 11,
                                                  ),
                                                ),
                                                if (_capturedCoordinates[i]['photoPath'] != null ||
                                                    _capturedCoordinates[i]['photoUrl'] != null)
                                                  Padding(
                                                    padding: const EdgeInsets.only(top: 4),
                                                    child: Text(
                                                      '📷 Photo captured',
                                                      style: TextStyle(
                                                        color: Colors.green.shade600,
                                                        fontSize: 11,
                                                        fontWeight: FontWeight.w500,
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
                                              onPressed: () => _editCoordinate(i),
                                              color: Colors.amber.shade400,
                                            ),
                                          ),
                                          const SizedBox(width: 6),
                                          Expanded(
                                            child: _buildCaptureButton(
                                              label: 'Remove',
                                              icon: Icons.delete_rounded,
                                              onPressed: () => _removeCoordinate(i),
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
                              style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
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

          // Footer
          Container(
            decoration: BoxDecoration(
              border: Border(top: BorderSide(color: Colors.grey.shade200)),
            ),
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: widget.onCancel,
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
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
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
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
                                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
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
}
