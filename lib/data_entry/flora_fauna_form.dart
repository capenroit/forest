import 'dart:io';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart' as ll;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../service/lookup_service.dart';
import '../service/api_service.dart';
import '../service/auth_session.dart';
import '../service/location_capture_service.dart';
import '../service/offline_sync_service.dart';
import '../widget/add_flora_fauna_dialog.dart';
import '../widget/edit_coordinate_dialog.dart';
import '../widget/polygon_calculator.dart';

class FloraFaunaSpeciesDetail {
  final String speciesType;
  final String name;
  final String scientificName;
  final String? classification;

  /// A local temp file path for a photo captured this session, not yet
  /// uploaded. Distinct from [existingPhotoUrl] — only this one is ever
  /// treated as "needs uploading" on save.
  final String? photoPath;

  /// The URL of a photo already uploaded for this species on a previous
  /// save, looked up by matching `photo.name` back to this species (see
  /// `_matchExistingSpeciesPhotos` in capiz_flora_fauna_recent_activity_page
  /// .dart). Shown read-only; never re-uploaded.
  final String? existingPhotoUrl;

  const FloraFaunaSpeciesDetail({
    required this.speciesType,
    required this.name,
    required this.scientificName,
    this.classification,
    this.photoPath,
    this.existingPhotoUrl,
  });
}

typedef _SpeciesDetail = FloraFaunaSpeciesDetail;

class FloraFaunaEntry {
  final int? id;
  final String? userId;
  final String? activityName;
  final String entryType;
  final String speciesName;
  final String scientificName;
  final double? areaHectares;
  final String municipality;
  final String barangay;
  final DateTime surveyDate;
  final String observer;
  final List<FloraFaunaSpeciesDetail> speciesDetails;

  const FloraFaunaEntry({
    this.id,
    this.userId,
    this.activityName,
    required this.entryType,
    required this.speciesName,
    required this.scientificName,
    this.areaHectares,
    required this.municipality,
    required this.barangay,
    required this.surveyDate,
    required this.observer,
    this.speciesDetails = const [],
  });
}

class FloraFaunaForm extends StatefulWidget {
  final ValueChanged<FloraFaunaEntry> onSave;
  final VoidCallback onCancel;
  final FloraFaunaEntry? initialData;

  /// When non-null, this form is editing a record still sitting in the
  /// offline queue (not yet synced to the server). Saving in this mode
  /// rewrites the queued item in place instead of talking to Supabase.
  final String? pendingLocalId;

  /// The queued payload (`{'survey': ..., 'species': ..., 'coordinates':
  /// ...}`) to seed the form fields from when [pendingLocalId] is set.
  final Map<String, dynamic>? pendingPayload;

  const FloraFaunaForm({
    super.key,
    required this.onSave,
    required this.onCancel,
    this.initialData,
    this.pendingLocalId,
    this.pendingPayload,
  });

  @override
  State<FloraFaunaForm> createState() => _FloraFaunaFormState();
}

class _FloraFaunaFormState extends State<FloraFaunaForm> {
  static const String _storageBucketName = 'Forest Management';
  static const String _floraFaunaStorageFolder = 'public/flora_fauna';
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  late TextEditingController _activityNameController;
  late TextEditingController _observerController;
  late TextEditingController _areaController;
  late List<_SpeciesDetail> _speciesDetails;
  LookupOption? _selectedMunicipality;
  String? _selectedBarangay;
  List<LookupOption> _municipalityOptions = [];
  List<String> _filteredBarangays = [];
  bool _isLoadingMunicipalities = false;
  bool _isLoadingBarangays = false;
  bool _didApplyInitialMunicipality = false;
  String? _initialMunicipalityName;
  bool _locationPermissionGranted = false;
  bool _isCapturingLocation = false;
  bool _isSaving = false;
  final List<Map<String, dynamic>> _capturedCoordinates = [];

  DateTime _surveyDate = DateTime.now();

  @override
  void initState() {
    super.initState();

    final initial = widget.initialData;
    final pendingPayload = widget.pendingPayload;
    final pendingSurvey = pendingPayload != null
        ? Map<String, dynamic>.from(
            (pendingPayload['survey'] as Map?) ?? const {})
        : null;

    if (pendingSurvey != null) {
      // ── Seed from a queued (not-yet-synced) draft ─────────────────────
      _surveyDate =
          DateTime.tryParse(pendingSurvey['surveyDate'] as String? ?? '') ??
              DateTime.now();

      final pendingSpeciesRows = ((pendingPayload!['species'] as List?) ?? [])
          .map((r) => Map<String, dynamic>.from(r as Map))
          .toList();
      _speciesDetails = pendingSpeciesRows.map((row) {
        final classification = (row['classification'] as String?)?.trim();
        return _SpeciesDetail(
          speciesType: (row['species_type'] ?? '').toString(),
          name: (row['name'] ?? '').toString(),
          scientificName: (row['scientific_name'] ?? '').toString(),
          classification:
              classification != null && classification.isNotEmpty
                  ? classification
                  : null,
          photoPath: row['stablePhotoPath'] as String?,
        );
      }).toList();

      final pendingCoordinateRows =
          ((pendingPayload['coordinates'] as List?) ?? [])
              .map((r) => Map<String, dynamic>.from(r as Map))
              .toList();
      _capturedCoordinates.addAll(pendingCoordinateRows);

      final pendingMunicipality =
          (pendingSurvey['municipality'] as String?)?.trim();
      _initialMunicipalityName =
          (pendingMunicipality != null && pendingMunicipality.isNotEmpty)
              ? pendingMunicipality
              : null;

      final pendingBarangay = (pendingSurvey['barangay'] as String?)?.trim();
      _selectedBarangay =
          (pendingBarangay != null && pendingBarangay.isNotEmpty)
              ? pendingBarangay
              : null;

      _activityNameController = TextEditingController(
        text: (pendingSurvey['activityName'] as String?) ?? '',
      );
      _observerController = TextEditingController(
        text: (pendingSurvey['observer'] as String?) ?? '',
      );
      _areaController = TextEditingController(
        text: (pendingSurvey['area'] as num?)?.toStringAsFixed(2) ?? '',
      );
    } else {
      _surveyDate = initial?.surveyDate ?? DateTime.now();

      _speciesDetails = initial == null
          ? <_SpeciesDetail>[]
          : initial.speciesDetails.isNotEmpty
              ? List<_SpeciesDetail>.from(initial.speciesDetails)
              : <_SpeciesDetail>[
                  _SpeciesDetail(
                    speciesType: initial.entryType,
                    name: initial.speciesName,
                    scientificName: initial.scientificName,
                    photoPath: null,
                  ),
                ];
      _initialMunicipalityName = initial?.municipality.trim().isNotEmpty == true
          ? initial!.municipality.trim()
          : null;
      _selectedBarangay = initial?.barangay.trim().isNotEmpty == true
          ? initial!.barangay.trim()
          : null;
      _activityNameController = TextEditingController(
        text: initial?.activityName ?? '',
      );
      _observerController = TextEditingController(
        text: initial?.observer ?? '',
      );
      _areaController = TextEditingController(
        text: initial?.areaHectares?.toStringAsFixed(2) ?? '',
      );
    }

    _loadMunicipalityOptions();
    _requestLocationPermission();
  }

  @override
  void dispose() {
    _activityNameController.dispose();
    _observerController.dispose();
    _areaController.dispose();
    super.dispose();
  }

  Future<void> _loadMunicipalityOptions() async {
    setState(() => _isLoadingMunicipalities = true);

    try {
      final options = await LookupService.getMunicipalityOptions();
      if (!mounted) return;
      setState(() {
        _municipalityOptions = options;
      });

      final initialMunicipalityName = _initialMunicipalityName;
      if (!_didApplyInitialMunicipality && initialMunicipalityName != null) {
        _didApplyInitialMunicipality = true;
        final initialMunicipality = initialMunicipalityName.toLowerCase();

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
        setState(() => _isLoadingMunicipalities = false);
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

  Future<void> _requestLocationPermission() async {
    try {
      final permission = await Geolocator.checkPermission();

      if (permission == LocationPermission.denied) {
        final result = await Geolocator.requestPermission();
        if (!mounted) return;
        setState(() {
          _locationPermissionGranted =
              result == LocationPermission.whileInUse ||
                  result == LocationPermission.always;
        });
      } else if (permission == LocationPermission.whileInUse ||
          permission == LocationPermission.always) {
        if (!mounted) return;
        setState(() => _locationPermissionGranted = true);
      } else if (permission == LocationPermission.deniedForever) {
        if (!mounted) return;
        setState(() => _locationPermissionGranted = false);
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
    } catch (_) {
      if (!mounted) return;
      setState(() => _locationPermissionGranted = false);
    }
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

  String _buildFloraFaunaPhotoName({
    required int surveyId,
    required String activityName,
    required String speciesName,
    required int photoIndex,
    required String sourcePath,
  }) {
    final extension = _extractFileExtension(sourcePath);
    final fallbackExtension = extension.isEmpty ? '.jpg' : extension;
    final safeActivityName = _sanitizeForFileName(activityName);
    final safeSpeciesName = _sanitizeForFileName(speciesName);
    // The activity/species name make the file recognizable at a glance; the
    // timestamp + index keep it unique so re-uploads never collide (photo
    // rows are inserted with upsert disabled).
    return 'flora_fauna_${safeActivityName}_${safeSpeciesName}_'
        '${DateTime.now().millisecondsSinceEpoch}_${photoIndex + 1}$fallbackExtension';
  }

  /// The `photo.name` shown to users (photo list, downloaded file name) —
  /// unlike [_buildFloraFaunaPhotoName] (the storage object path, which
  /// must stay unique), this can be the plain `flora_fauna_{activityName}_
  /// {speciesName}` the user actually wants to see, since multiple photo
  /// rows sharing a display name is harmless.
  String _buildFloraFaunaDisplayName({
    required String activityName,
    required String speciesName,
    required String sourcePath,
  }) {
    final extension = _extractFileExtension(sourcePath);
    final fallbackExtension = extension.isEmpty ? '.jpg' : extension;
    final safeActivityName = _sanitizeForFileName(activityName);
    final safeSpeciesName = _sanitizeForFileName(speciesName);
    return 'flora_fauna_${safeActivityName}_$safeSpeciesName$fallbackExtension';
  }

  Future<String> _uploadFloraFaunaPhotoToSupabase({
    required String localPath,
    required String photoName,
  }) async {
    final file = File(localPath);
    if (!await file.exists()) {
      throw Exception('Photo file does not exist: $localPath');
    }

    final objectPath = '$_floraFaunaStorageFolder/$photoName';
    final contentType = _contentTypeFromPath(photoName);

    await Supabase.instance.client.storage.from(_storageBucketName).upload(
          objectPath,
          file,
          fileOptions: FileOptions(
            upsert: false,
            contentType: contentType,
          ),
        );

    try {
      await file.delete();
    } catch (_) {
      // Best effort only. File is temporary camera output.
    }

    final encodedBucket = Uri.encodeComponent(_storageBucketName);
    return 'public/$encodedBucket/$objectPath';
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
      if (mounted) {
        setState(() => _isCapturingLocation = false);
      }
    }
  }

  Future<void> _editCoordinate(int index) async {
    if (!mounted) return;

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
    final confirmed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Remove Point?'),
            content: const Text('Are you sure you want to remove this point?'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, true),
                child:
                    const Text('Remove', style: TextStyle(color: Colors.red)),
              ),
            ],
          ),
        ) ??
        false;

    if (!confirmed || !mounted) return;
    setState(() {
      _capturedCoordinates.removeAt(index);
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

  Widget _buildGpsCaptureSection() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF7FAF8),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFD7E6DE)),
      ),
      child: Column(
        children: [
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _isCapturingLocation ? null : _captureCurrentLocation,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF1976D2),
                foregroundColor: Colors.white,
                minimumSize: const Size(double.infinity, 44),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              icon: _isCapturingLocation
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.my_location, size: 18),
              label:
                  Text(_isCapturingLocation ? 'Capturing...' : 'Capture GPS'),
            ),
          ),
          const SizedBox(height: 10),
          if (_capturedCoordinates.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Text(
                'No GPS points captured yet.',
                style: TextStyle(color: Color(0xFF6B7280), fontSize: 12),
              ),
            )
          else
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _capturedCoordinates.length,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (context, index) {
                final point = _capturedCoordinates[index];
                final lat = (point['lat'] as num?)?.toDouble();
                final lng = (point['lng'] as num?)?.toDouble();

                return Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFFD7E6DE)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(
                            Icons.location_on,
                            size: 18,
                            color: Color(0xFF6B7280),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            'Point ${index + 1}',
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF374151),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        lat != null && lng != null
                            ? 'Lat: ${lat.toStringAsFixed(6)}, Lng: ${lng.toStringAsFixed(6)}'
                            : 'Invalid coordinate',
                        style: const TextStyle(
                          color: Color(0xFF6B7280),
                          fontSize: 12,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: ElevatedButton.icon(
                              onPressed: () => _editCoordinate(index),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFFF2B300),
                                foregroundColor: Colors.white,
                                minimumSize: const Size(double.infinity, 38),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8),
                                ),
                              ),
                              icon: const Icon(Icons.edit, size: 16),
                              label: const Text('Edit'),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: ElevatedButton.icon(
                              onPressed: () => _deleteCoordinate(index),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFFD32F2F),
                                foregroundColor: Colors.white,
                                minimumSize: const Size(double.infinity, 38),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8),
                                ),
                              ),
                              icon: const Icon(Icons.delete, size: 16),
                              label: const Text('Remove'),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                );
              },
            ),
        ],
      ),
    );
  }

  void _updateAreaFromCoordinates() {
    if (_capturedCoordinates.length >= 3) {
      try {
        final coordinates = _capturedCoordinates.map((coord) {
          return ll.LatLng(
            (coord['lat'] as num).toDouble(),
            (coord['lng'] as num).toDouble(),
          );
        }).toList();

        final areaInHectares =
            PolygonCalculator.calculatePolygonAreaInHectares(coordinates);
        _areaController.text = areaInHectares.toStringAsFixed(2);
      } catch (_) {
        _areaController.clear();
      }
      return;
    }

    _areaController.clear();
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
    final hasMunicipalityItems =
        !_isLoadingMunicipalities && _municipalityOptions.isNotEmpty;
    LookupOption? selectedMunicipalityValue;
    if (hasMunicipalityItems && _selectedMunicipality != null) {
      final municipalityMatches = _municipalityOptions
          .where((option) => option.id == _selectedMunicipality!.id)
          .toList();
      if (municipalityMatches.length == 1) {
        selectedMunicipalityValue = municipalityMatches.first;
      }
    }

    final hasBarangayItems = !_isLoadingMunicipalities &&
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
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
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
                children: [
                  const Icon(Icons.eco_rounded, color: Colors.white, size: 24),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Flora and Fauna Data Entry',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                          ),
                        ),
                        Text(
                          'Record species survey activity',
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.white70,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: widget.onCancel,
                    icon: const Icon(Icons.close, color: Colors.white),
                    tooltip: 'Close',
                  ),
                ],
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildSectionHeader(
                        'Survey Details', Icons.assignment_rounded),
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF7FAF8),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: const Color(0xFFD7E6DE)),
                      ),
                      child: Column(
                        children: [
                          TextFormField(
                            controller: _activityNameController,
                            decoration: _modernInputDecoration(
                              label: 'Activity Name',
                              hint: 'Enter activity name',
                              icon: Icons.assignment_outlined,
                            ),
                            validator: (value) {
                              if (value == null || value.trim().isEmpty) {
                                return 'Activity name is required';
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: 10),
                          DropdownButtonFormField<LookupOption>(
                            value: selectedMunicipalityValue,
                            onChanged: _isLoadingMunicipalities
                                ? null
                                : (LookupOption? newValue) {
                                    final municipalityId = newValue?.id;
                                    setState(() {
                                      _selectedMunicipality = newValue;
                                      _selectedBarangay = null;
                                      _filteredBarangays = [];
                                    });

                                    if (municipalityId != null) {
                                      _loadBarangaysForMunicipality(
                                          municipalityId);
                                    }
                                  },
                            decoration: _modernInputDecoration(
                              label: 'Municipality',
                              hint: '',
                              icon: Icons.location_city_outlined,
                            ),
                            dropdownColor: Colors.white,
                            borderRadius: BorderRadius.circular(8),
                            items: _isLoadingMunicipalities ||
                                    _municipalityOptions.isEmpty
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
                            validator: (value) {
                              if (value == null) {
                                return 'Municipality is required';
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: 10),
                          DropdownButtonFormField<String>(
                            value: selectedBarangayValue,
                            onChanged: (_isLoadingMunicipalities ||
                                    _isLoadingBarangays ||
                                    _selectedMunicipality == null ||
                                    _filteredBarangays.isEmpty)
                                ? null
                                : (String? newValue) {
                                    setState(
                                        () => _selectedBarangay = newValue);
                                  },
                            decoration: _modernInputDecoration(
                              label: 'Barangay',
                              hint: '',
                              icon: Icons.map_outlined,
                            ),
                            dropdownColor: Colors.white,
                            borderRadius: BorderRadius.circular(8),
                            items: _isLoadingMunicipalities
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
                                              child: Text(
                                                'Select municipality first',
                                              ),
                                            )
                                          ]
                                        : _filteredBarangays.isEmpty
                                            ? [
                                                const DropdownMenuItem<String>(
                                                  value: null,
                                                  child: Text(
                                                    'No barangays found',
                                                  ),
                                                )
                                              ]
                                            : _filteredBarangays
                                                .map((String value) {
                                                return DropdownMenuItem<String>(
                                                  value: value,
                                                  child: Text(value),
                                                );
                                              }).toList(),
                            validator: (value) {
                              if (value == null || value.trim().isEmpty) {
                                return 'Barangay is required';
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: 10),
                          TextFormField(
                            controller: _observerController,
                            decoration: _modernInputDecoration(
                              label: 'Observer',
                              hint: 'Enter observer name',
                              icon: Icons.person_outline_rounded,
                            ),
                            validator: (value) {
                              if (value == null || value.trim().isEmpty) {
                                return 'Observer is required';
                              }
                              return null;
                            },
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),
                    _buildSectionHeader('Species Details', Icons.eco_rounded),
                    const SizedBox(height: 10),
                    _buildSpeciesDetailsTable(),
                    const SizedBox(height: 14),
                    _buildSectionHeader(
                        'GPS Coordinates', Icons.my_location_rounded),
                    const SizedBox(height: 10),
                    _buildGpsCaptureSection(),
                    const SizedBox(height: 14),
                    _buildSectionHeader(
                        'Area and Date', Icons.event_note_rounded),
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF7FAF8),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: const Color(0xFFD7E6DE)),
                      ),
                      child: Column(
                        children: [
                          TextFormField(
                            controller: _areaController,
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            decoration: _modernInputDecoration(
                              label: 'Area (ha)',
                              hint: 'Computed from captured GPS points',
                              icon: Icons.square_foot_outlined,
                            ),
                          ),
                          const SizedBox(height: 10),
                          InkWell(
                            onTap: _pickSurveyDate,
                            borderRadius: BorderRadius.circular(8),
                            child: InputDecorator(
                              decoration: _modernInputDecoration(
                                label: 'Survey Date',
                                icon: Icons.calendar_month_outlined,
                              ),
                              child: Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    _formatDate(_surveyDate),
                                    style: const TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w500,
                                      color: Color(0xFF111827),
                                    ),
                                  ),
                                  const Icon(Icons.calendar_today, size: 18),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Container(
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAF8),
                border: Border(
                  top: BorderSide(color: Colors.grey.shade200),
                ),
              ),
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _isSaving ? null : widget.onCancel,
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size(double.infinity, 44),
                        side: const BorderSide(
                            color: Color(0xFF1B8B5E), width: 1.5),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      child: const Text(
                        'Cancel',
                        style: TextStyle(
                          color: Color(0xFF1B5E20),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: _isSaving ? null : _handleSave,
                      style: ElevatedButton.styleFrom(
                        minimumSize: const Size(double.infinity, 44),
                        backgroundColor: const Color(0xFF1B8B5E),
                        foregroundColor: Colors.white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      child: Text(
                        _isSaving ? 'Saving...' : 'Save',
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSpeciesDetailsTable() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        ElevatedButton.icon(
          onPressed: _openAddSpeciesDialog,
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF1B8B5E),
            foregroundColor: Colors.white,
            minimumSize: const Size(90, 34),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
          icon: const Icon(Icons.add, size: 16),
          label: const Text('Add'),
        ),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            color: const Color(0xFFF7FAF8),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: const Color(0xFFD7E6DE)),
          ),
          child: Column(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: const BoxDecoration(
                  border: Border(
                    bottom: BorderSide(color: Color(0xFFD7E6DE)),
                  ),
                ),
                child: const Row(
                  children: [
                    Expanded(
                      flex: 5,
                      child: Text(
                        'Species',
                        style: TextStyle(
                            fontWeight: FontWeight.w700, fontSize: 13),
                      ),
                    ),
                    Expanded(
                      flex: 2,
                      child: Text(
                        'Species Type',
                        style: TextStyle(
                            fontWeight: FontWeight.w700, fontSize: 13),
                      ),
                    ),
                    Expanded(
                      flex: 3,
                      child: Text(
                        'Actions',
                        style: TextStyle(
                            fontWeight: FontWeight.w700, fontSize: 13),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ],
                ),
              ),
              if (_speciesDetails.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 20),
                  child: Text(
                    'No species details yet.',
                    style: TextStyle(color: Color(0xFF6B7280), fontSize: 13),
                  ),
                )
              else
                ListView.separated(
                  itemCount: _speciesDetails.length,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  separatorBuilder: (_, __) => const Divider(
                    height: 1,
                    color: Color(0xFFD7E6DE),
                  ),
                  itemBuilder: (context, index) {
                    final item = _speciesDetails[index];
                    return Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 8),
                      child: Row(
                        children: [
                          Expanded(
                            flex: 5,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  item.name,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                    fontSize: 13,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  item.scientificName,
                                  style: const TextStyle(
                                    color: Color(0xFF6B7280),
                                    fontSize: 12,
                                    fontStyle: FontStyle.italic,
                                  ),
                                ),
                                if (item.classification != null &&
                                    item.classification!.trim().isNotEmpty) ...[
                                  const SizedBox(height: 2),
                                  Text(
                                    item.classification!,
                                    style: const TextStyle(
                                      color: Color(0xFF1976D2),
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                                if (item.photoPath != null) ...[
                                  const SizedBox(height: 2),
                                  const Text(
                                    'Photo captured',
                                    style: TextStyle(
                                      color: Color(0xFF1B8B5E),
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                          Expanded(
                            flex: 2,
                            child: Text(
                              item.speciesType,
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 12,
                                color: Color(0xFF1F2937),
                              ),
                            ),
                          ),
                          Expanded(
                            flex: 3,
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                IconButton(
                                  tooltip: 'Edit',
                                  icon: const Icon(Icons.edit,
                                      color: Color(0xFF1B8B5E)),
                                  onPressed: () =>
                                      _openAddSpeciesDialog(index: index),
                                ),
                                IconButton(
                                  tooltip: 'Delete',
                                  icon: const Icon(Icons.delete_outline,
                                      color: Colors.red),
                                  onPressed: () => _deleteSpeciesDetail(index),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: const BoxDecoration(
                  border: Border(
                    top: BorderSide(color: Color(0xFFD7E6DE)),
                  ),
                ),
                child: Row(
                  children: [
                    const Text(
                      'Total:',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                    const Spacer(),
                    Text(
                      '${_speciesDetails.length} type',
                      style: const TextStyle(
                        color: Color(0xFF1B8B5E),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _pickSurveyDate() async {
    final selectedDate = await showDatePicker(
      context: context,
      initialDate: _surveyDate,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (selectedDate != null) {
      setState(() => _surveyDate = selectedDate);
    }
  }

  Future<void> _openAddSpeciesDialog({int? index}) async {
    final currentItem = index == null ? null : _speciesDetails[index];
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AddFloraFaunaDialog(
        initialSpeciesType: currentItem?.speciesType,
        initialName: currentItem?.name,
        initialScientificName: currentItem?.scientificName,
        initialClassification: currentItem?.classification,
        initialPhotoPath: currentItem?.photoPath,
        initialExistingPhotoUrl: currentItem?.existingPhotoUrl,
        submitLabel: index == null ? 'Add Species' : 'Update Species',
        onAdd: ({
          required String speciesType,
          required String name,
          required String scientificName,
          String? classification,
          String? photoPath,
          String? existingPhotoUrl,
        }) {
          setState(() {
            final item = _SpeciesDetail(
              speciesType: speciesType,
              name: name,
              scientificName: scientificName,
              classification: classification,
              photoPath: photoPath,
              existingPhotoUrl: existingPhotoUrl,
            );
            if (index == null) {
              _speciesDetails.add(item);
            } else {
              _speciesDetails[index] = item;
            }
          });
        },
      ),
    );
  }

  Future<void> _deleteSpeciesDetail(int index) async {
    final shouldDelete = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Delete Species'),
            content: const Text('Remove this species detail from the list?'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, true),
                child:
                    const Text('Delete', style: TextStyle(color: Colors.red)),
              ),
            ],
          ),
        ) ??
        false;
    if (!shouldDelete) return;
    setState(() {
      _speciesDetails.removeAt(index);
    });
  }

  // ── Offline payload helpers ────────────────────────────────────────────

  Map<String, dynamic> _buildOfflineSurveyPayload({
    required String authUserId,
    required String activityName,
    required String municipality,
    required String barangay,
    required String? details,
    required double? parsedArea,
  }) {
    return {
      'userId': authUserId,
      'userSeqId': AuthSession.currentUser?.seqId,
      'municipality': municipality,
      'barangay': barangay,
      'activityName': activityName,
      'surveyDate': _surveyDate.toIso8601String(),
      'area': parsedArea,
      'details': details,
      'observer': _observerController.text.trim(),
      'projectTypeId': 3,
    };
  }

  /// Stages any not-yet-staged species photos (temp camera files) into
  /// stable local storage and returns the `species` payload list. Photos
  /// that were already staged in a previous offline save (their path
  /// already lives under the offline photos directory) are left alone.
  Future<List<Map<String, dynamic>>> _buildOfflineSpeciesPayload() async {
    final species = <Map<String, dynamic>>[];
    for (final item in _speciesDetails) {
      final photoPath = item.photoPath;
      String? stablePhotoPath;
      if (photoPath != null && photoPath.isNotEmpty) {
        stablePhotoPath = photoPath.contains('offline_photos')
            ? photoPath
            : await OfflineSyncService.stagePhoto(photoPath);
      }

      species.add({
        'species_type': item.speciesType,
        'name': item.name,
        'scientific_name': item.scientificName,
        'classification': item.classification,
        'stablePhotoPath': stablePhotoPath,
      });
    }
    return species;
  }

  List<Map<String, dynamic>> _buildOfflineCoordinatesPayload() {
    return _capturedCoordinates
        .map((coord) => {
              'lat': coord['lat'],
              'lng': coord['lng'],
            })
        .toList();
  }

  Future<void> _handleSave() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }
    if (_speciesDetails.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Please add at least one species detail.')),
      );
      return;
    }

    final first = _speciesDetails.first;
    final entryType =
        _speciesDetails.map((item) => item.speciesType).toSet().length == 1
            ? first.speciesType
            : 'Mixed';
    final speciesName = _speciesDetails.length == 1
        ? first.name
        : '${first.name} +${_speciesDetails.length - 1} more';
    final scientificName = _speciesDetails.length == 1
        ? first.scientificName
        : '${first.scientificName} +${_speciesDetails.length - 1} more';
    final activityName = _activityNameController.text.trim();
    final municipality = _selectedMunicipality?.name.trim() ?? '';
    final barangay = _selectedBarangay?.trim() ?? '';

    if (activityName.isEmpty || municipality.isEmpty || barangay.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Data is incomplete.')),
      );
      return;
    }

    final authUserId = AuthSession.currentUser?.id ??
        Supabase.instance.client.auth.currentUser?.id;

    if (authUserId == null || authUserId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Unable to save data.')),
      );
      return;
    }

    final speciesDetailsText = _speciesDetails
        .map((item) {
          final species = item.name.trim();
          final scientific = item.scientificName.trim();
          if (scientific.isEmpty) {
            return species;
          }
          return '$species ($scientific)';
        })
        .where((value) => value.isNotEmpty)
        .join('; ');

    final details = speciesDetailsText;

    final parsedArea = double.tryParse(_areaController.text.trim());

    // ── Editing a pending (not-yet-synced) draft ──────────────────────────
    // Skip connectivity checks and every Supabase/ApiService call — just
    // rewrite the queued item in place.
    if (widget.pendingLocalId != null) {
      setState(() => _isSaving = true);
      try {
        final speciesPayload = await _buildOfflineSpeciesPayload();
        final payload = {
          'survey': _buildOfflineSurveyPayload(
            authUserId: authUserId,
            activityName: activityName,
            municipality: municipality,
            barangay: barangay,
            details: details.isEmpty ? null : details,
            parsedArea: parsedArea,
          ),
          'species': speciesPayload,
          'coordinates': _buildOfflineCoordinatesPayload(),
        };

        await OfflineSyncService.updatePendingItem(
          widget.pendingLocalId!,
          payload,
        );

        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Data was saved.'),
            backgroundColor: Colors.orange,
            duration: Duration(seconds: 3),
          ),
        );

        widget.onSave(
          FloraFaunaEntry(
            id: widget.initialData?.id,
            activityName: activityName,
            entryType: entryType,
            speciesName: speciesName,
            scientificName: scientificName,
            areaHectares: parsedArea,
            municipality: municipality,
            barangay: barangay,
            surveyDate: _surveyDate,
            observer: _observerController.text.trim(),
            speciesDetails:
                List<FloraFaunaSpeciesDetail>.unmodifiable(_speciesDetails),
          ),
        );
      } catch (_) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Unable to save data.')),
        );
      } finally {
        if (mounted) {
          setState(() => _isSaving = false);
        }
      }
      return;
    }
    // ── End pending-draft edit path ────────────────────────────────────────

    final isOnline = await OfflineSyncService.hasInternetConnection();
    if (!mounted) return;

    final isEditingSyncedRecord = widget.initialData?.id != null;

    if (!isOnline && isEditingSyncedRecord) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Editing requires an internet connection.'),
        ),
      );
      return;
    }

    setState(() => _isSaving = true);

    if (!isOnline) {
      // ── Offline path: brand-new record, queue it for later sync ────────
      try {
        final speciesPayload = await _buildOfflineSpeciesPayload();
        final payload = {
          'survey': _buildOfflineSurveyPayload(
            authUserId: authUserId,
            activityName: activityName,
            municipality: municipality,
            barangay: barangay,
            details: details.isEmpty ? null : details,
            parsedArea: parsedArea,
          ),
          'species': speciesPayload,
          'coordinates': _buildOfflineCoordinatesPayload(),
        };

        await OfflineSyncService.queueGenericRecord(
          type: 'flora_fauna',
          payload: payload,
        );

        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Data was saved.'),
            backgroundColor: Colors.orange,
            duration: Duration(seconds: 3),
          ),
        );

        widget.onSave(
          FloraFaunaEntry(
            activityName: activityName,
            entryType: entryType,
            speciesName: speciesName,
            scientificName: scientificName,
            areaHectares: parsedArea,
            municipality: municipality,
            barangay: barangay,
            surveyDate: _surveyDate,
            observer: _observerController.text.trim(),
            speciesDetails:
                List<FloraFaunaSpeciesDetail>.unmodifiable(_speciesDetails),
          ),
        );
      } catch (_) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Unable to save data.')),
        );
      } finally {
        if (mounted) {
          setState(() => _isSaving = false);
        }
      }
      return;
    }
    // ── End offline path ─────────────────────────────────────────────────

    try {
      final savedSurvey = await ApiService.createFloraFaunaSurvey(
        id: widget.initialData?.id,
        userId: authUserId,
        userSeqId: AuthSession.currentUser?.seqId,
        municipality: municipality,
        barangay: barangay,
        activityName: activityName,
        surveyDate: _surveyDate,
        area: parsedArea,
        details: details.isEmpty ? null : details,
        observer: _observerController.text.trim(),
        projectTypeId: 3,
      );

      final floraFaunaId = (savedSurvey['id'] as num?)?.toInt();
      if (floraFaunaId == null) {
        throw Exception('flora_fauna_survey id is missing');
      }

      final detailRows = _speciesDetails
          .map((item) => {
                'name': item.name,
                'scientific_name': item.scientificName,
                'species_type': item.speciesType,
                'classification': item.classification,
              })
          .toList();

      await ApiService.saveFloraFaunaSurveyDataRows(
        floraFaunaSurveyId: floraFaunaId,
        rows: detailRows,
      );

      for (var index = 0; index < _speciesDetails.length; index++) {
        final item = _speciesDetails[index];
        final photoPath = item.photoPath;
        if (photoPath == null || photoPath.isEmpty) continue;

        final photoName = _buildFloraFaunaPhotoName(
          surveyId: floraFaunaId,
          activityName: activityName,
          speciesName: item.name,
          photoIndex: index,
          sourcePath: photoPath,
        );

        final photoUrl = await _uploadFloraFaunaPhotoToSupabase(
          localPath: photoPath,
          photoName: photoName,
        );

        await ApiService.createPhotoRow(
          projectTypeId: 3,
          activityId: floraFaunaId,
          photoUrl: photoUrl,
          name: _buildFloraFaunaDisplayName(
            activityName: activityName,
            speciesName: item.name,
            sourcePath: photoPath,
          ),
        );
      }

      await ApiService.saveLocationRowsForActivity(
        activityId: floraFaunaId,
        coordinates: _capturedCoordinates,
        activityTypeId: 3,
      );

      if (!mounted) return;

      widget.onSave(
        FloraFaunaEntry(
          id: floraFaunaId,
          activityName: activityName,
          entryType: entryType,
          speciesName: speciesName,
          scientificName: scientificName,
          areaHectares: parsedArea,
          municipality: municipality,
          barangay: barangay,
          surveyDate: _surveyDate,
          observer: _observerController.text.trim(),
          speciesDetails:
              List<FloraFaunaSpeciesDetail>.unmodifiable(_speciesDetails),
        ),
      );

      OfflineSyncService.syncAll().ignore();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Unable to save data.')),
      );
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  String _formatDate(DateTime date) {
    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');
    return '${date.year}-$month-$day';
  }
}
