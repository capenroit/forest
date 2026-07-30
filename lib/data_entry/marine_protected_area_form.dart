import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';
import 'package:latlong2/latlong.dart' as ll;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../service/api_service.dart';
import '../service/auth_session.dart';
import '../service/lookup_service.dart';
import '../widget/edit_coordinate_dialog.dart';
import '../widget/polygon_calculator.dart';

class MarineProtectedAreaForm extends StatefulWidget {
  final VoidCallback onSave;
  final VoidCallback onCancel;

  const MarineProtectedAreaForm({
    super.key,
    required this.onSave,
    required this.onCancel,
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

  LookupOption? _selectedMunicipality;
  String? _selectedBarangay;
  List<LookupOption> _municipalityOptions = [];
  List<String> _filteredBarangays = [];

  bool _isLoading = false;
  bool _isSaving = false;
  bool _isLoadingBarangays = false;

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
    _requestLocationPermission();
    _loadMunicipalityOptions();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _areaController.dispose();
    _ordinanceController.dispose();
    super.dispose();
  }

  Future<void> _loadMunicipalityOptions() async {
    setState(() => _isLoading = true);
    try {
      final options = await LookupService.getMunicipalityOptions();
      if (!mounted) return;
      setState(() => _municipalityOptions = options);
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
      final position = await Geolocator.getCurrentPosition(
        timeLimit: const Duration(seconds: 10),
      );

      if (!mounted) return;

      setState(() {
        _capturedCoordinates.add({
          'lat': position.latitude,
          'lng': position.longitude,
        });
        _updateAreaFromCoordinates();
      });
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Unable to update data.'),
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

      final position = await Geolocator.getCurrentPosition(
        timeLimit: const Duration(seconds: 10),
      );

      if (!mounted) return;

      setState(() {
        _capturedCoordinates.add({
          'lat': position.latitude,
          'lng': position.longitude,
          'photoPath': photo.path,
        });
        _updateAreaFromCoordinates();
        _isCapturingLocation = false;
      });
    } catch (e) {
      await SystemChrome.setPreferredOrientations([
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);

      if (!mounted) return;
      setState(() => _isCapturingLocation = false);

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Unable to update data.'),
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

  void _removeCoordinate(int index) {
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

    final userSeqId = AuthSession.currentUser?.seqId;
    if (userSeqId == null) {
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
      final savedArea = await ApiService.saveMarineProtectedArea(
        userId: userSeqId,
        name: name,
        municipality: municipality,
        barangay: barangay,
        area: parsedArea,
        ordinance: ordinance.isEmpty ? null : ordinance,
      );

      final areaId = (savedArea['id'] as num?)?.toInt();

      if (areaId != null && _capturedCoordinates.isNotEmpty) {
        await ApiService.saveLocationRowsForActivity(
          activityId: areaId,
          coordinates: _capturedCoordinates,
          activityTypeId: ApiService.marineProtectedAreaActivityTypeId,
        );

        for (final coord in _capturedCoordinates) {
          final photoPath = coord['photoPath'] as String?;
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
          );
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
                                                if (_capturedCoordinates[i]['photoPath'] != null)
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
