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
import '../service/lookup_service.dart';
import '../widget/edit_coordinate_dialog.dart';
import '../widget/polygon_calculator.dart';

class HabitatSpeciesEntry {
  String speciesName;
  int count;

  HabitatSpeciesEntry({required this.speciesName, required this.count});
}

class HabitatAssessmentForm extends StatefulWidget {
  final VoidCallback onSave;
  final VoidCallback onCancel;
  final HabitatAssessment? initialData;

  const HabitatAssessmentForm({
    super.key,
    required this.onSave,
    required this.onCancel,
    this.initialData,
  });

  @override
  State<HabitatAssessmentForm> createState() => _HabitatAssessmentFormState();
}

class _HabitatAssessmentFormState extends State<HabitatAssessmentForm> {
  // Supabase bucket id used by this app project.
  static const String _storageBucketName = 'Forest Management';

  late TextEditingController _typeAssessmentController;
  late TextEditingController _areaController;
  late TextEditingController _dateController;

  LookupOption? _selectedMunicipality;
  String? _selectedBarangay;
  List<LookupOption> _municipalityOptions = [];
  List<String> _filteredBarangays = [];
  List<HabitatSpeciesEntry> _species = [];
  DateTime _selectedDate = DateTime.now();

  bool _isLoading = false;
  bool _isSaving = false;
  bool _isLoadingBarangays = false;
  bool _isLoadingSpecies = false;
  bool _didApplyInitialMunicipality = false;

  bool _locationPermissionGranted = false;
  bool _isCapturingLocation = false;
  final ImagePicker _imagePicker = ImagePicker();
  final List<Map<String, dynamic>> _capturedCoordinates = [];

  @override
  void initState() {
    super.initState();
    _typeAssessmentController = TextEditingController();
    _areaController = TextEditingController();
    _dateController = TextEditingController();

    final initial = widget.initialData;
    if (initial != null) {
      _typeAssessmentController.text = initial.typeAssessment.trim();
      _areaController.text = initial.area?.toString() ?? '';
      _selectedBarangay =
          initial.barangay.trim().isEmpty ? null : initial.barangay.trim();
      _selectedDate = initial.date;
      _loadInitialSpecies();
    }
    _dateController.text = _formatDateOnly(_selectedDate);

    _requestLocationPermission();
    _loadMunicipalityOptions();
  }

  @override
  void dispose() {
    _typeAssessmentController.dispose();
    _areaController.dispose();
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

  Future<void> _loadInitialSpecies() async {
    final assessmentId = widget.initialData?.id;
    if (assessmentId == null) return;

    setState(() => _isLoadingSpecies = true);

    try {
      final grouped =
          await ApiService.getHabitatAssessmentDataByAssessmentIds([assessmentId]);
      final rows = grouped[assessmentId] ?? const <Map<String, dynamic>>[];

      final loadedSpecies = rows
          .map((row) => HabitatSpeciesEntry(
                speciesName: (row['species_name'] ?? '').toString().trim(),
                count: (row['count'] as num?)?.toInt() ?? 0,
              ))
          .where((entry) => entry.speciesName.isNotEmpty)
          .toList();

      if (!mounted) return;
      setState(() => _species = loadedSpecies);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Unable to load species details: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) setState(() => _isLoadingSpecies = false);
    }
  }

  Future<void> _loadMunicipalityOptions() async {
    setState(() => _isLoading = true);
    try {
      final options = await LookupService.getMunicipalityOptions();
      if (!mounted) return;
      setState(() => _municipalityOptions = options);

      final initial = widget.initialData;
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

  Future<void> _addSpecies() async {
    final speciesController = TextEditingController();
    final countController = TextEditingController();

    final shouldAdd = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          title: const Text('Add Species'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: speciesController,
                decoration: const InputDecoration(labelText: 'Species Name'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: countController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Count'),
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
              child: const Text('Add'),
            ),
          ],
        );
      },
    );

    if (shouldAdd != true) return;

    final name = speciesController.text.trim();
    final count = int.tryParse(countController.text.trim()) ?? 0;

    if (name.isEmpty || count <= 0) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter a valid species and count.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() {
      _species.add(HabitatSpeciesEntry(speciesName: name, count: count));
    });
  }

  Future<void> _editSpecies(int index) async {
    final item = _species[index];
    final speciesController = TextEditingController(text: item.speciesName);
    final countController = TextEditingController(text: item.count.toString());

    final shouldSave = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          title: const Text('Edit Species'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: speciesController,
                decoration: const InputDecoration(labelText: 'Species Name'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: countController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Count'),
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

    final name = speciesController.text.trim();
    final count = int.tryParse(countController.text.trim()) ?? 0;

    if (name.isEmpty || count <= 0) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter a valid species and count.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() {
      _species[index] = HabitatSpeciesEntry(speciesName: name, count: count);
    });
  }

  void _removeSpecies(int index) {
    setState(() => _species.removeAt(index));
  }

  int get _totalSpeciesCount =>
      _species.fold(0, (sum, entry) => sum + entry.count);

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

  Future<String> _uploadHabitatPhotoToSupabase({
    required String localPath,
    required String photoName,
  }) async {
    final file = File(localPath);
    if (!await file.exists()) {
      throw Exception('Photo file does not exist: $localPath');
    }

    final objectPath = 'public/habitat_assessment/$photoName';
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

    final municipality = _selectedMunicipality?.name.trim() ?? '';
    final barangay = _selectedBarangay?.trim() ?? '';
    final typeAssessment = _typeAssessmentController.text.trim();

    if (municipality.isEmpty || barangay.isEmpty || typeAssessment.isEmpty) {
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
    final isEditing = widget.initialData?.id != null;

    setState(() => _isSaving = true);

    try {
      final savedAssessment = isEditing
          ? await ApiService.updateHabitatAssessment(
              id: widget.initialData!.id!,
              municipality: municipality,
              barangay: barangay,
              typeAssessment: typeAssessment,
              date: _selectedDate,
              area: parsedArea,
            )
          : await ApiService.saveHabitatAssessment(
              userId: userSeqId,
              municipality: municipality,
              barangay: barangay,
              typeAssessment: typeAssessment,
              date: _selectedDate,
              area: parsedArea,
            );

      final assessmentId = (savedAssessment['id'] as num?)?.toInt();

      if (assessmentId != null) {
        final speciesRows = _species
            .map((entry) => {
                  'species_name': entry.speciesName,
                  'count': entry.count,
                })
            .toList();

        if (isEditing) {
          await ApiService.replaceHabitatAssessmentDataRows(
            assessmentId: assessmentId,
            speciesRows: speciesRows,
          );
        } else if (speciesRows.isNotEmpty) {
          await ApiService.saveHabitatAssessmentDataRows(
            assessmentId: assessmentId,
            speciesRows: speciesRows,
          );
        }
      }

      if (assessmentId != null && _capturedCoordinates.isNotEmpty) {
        await ApiService.saveLocationRowsForActivity(
          activityId: assessmentId,
          coordinates: _capturedCoordinates,
          activityTypeId: ApiService.habitatAssessmentActivityTypeId,
        );

        for (final coord in _capturedCoordinates) {
          final photoPath = coord['photoPath'] as String?;
          if (photoPath == null || photoPath.isEmpty) continue;

          final extension = _extractFileExtension(photoPath);
          final photoName =
              'photo_habitat_${ApiService.habitatAssessmentActivityTypeId}_${assessmentId}_${DateTime.now().millisecondsSinceEpoch}${extension.isEmpty ? '.jpg' : extension}';

          final supabasePhotoUrl = await _uploadHabitatPhotoToSupabase(
            localPath: photoPath,
            photoName: photoName,
          );

          await ApiService.createPhotoRow(
            projectTypeId: ApiService.habitatAssessmentActivityTypeId,
            activityId: assessmentId,
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
                Icon(Icons.waves, color: Colors.white, size: 24),
                SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Habitat Assessment Data Entry',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                    Text(
                      'Record new habitat assessment',
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
                    'Type of Assessment *',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: Colors.grey.shade700,
                    ),
                  ),
                  const SizedBox(height: 6),
                  TextField(
                    enabled: !_isLoading,
                    controller: _typeAssessmentController,
                    decoration: _modernInputDecoration(
                      label: '',
                      hint: 'e.g. Coral Reef, Mangrove, Seagrass',
                      icon: Icons.edit_rounded,
                    ),
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

                  // Species Details Section
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      _buildSectionHeader('Species Details', Icons.eco),
                      ElevatedButton.icon(
                        onPressed: _isLoadingSpecies ? null : _addSpecies,
                        icon: const Icon(Icons.add, size: 16),
                        label: const Text('Add', style: TextStyle(fontSize: 12)),
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

                  if (_isLoadingSpecies)
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.grey.shade200, width: 1),
                        borderRadius: BorderRadius.circular(6),
                        color: Colors.grey.shade50,
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        'Loading species details...',
                        style: TextStyle(color: Colors.grey.shade600, fontSize: 11),
                      ),
                    )
                  else if (_species.isEmpty)
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.grey.shade200, width: 1),
                        borderRadius: BorderRadius.circular(6),
                        color: Colors.grey.shade50,
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        'No species added yet.',
                        style: TextStyle(color: Colors.grey.shade600, fontSize: 11),
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
                              constraints:
                                  BoxConstraints(minWidth: constraints.maxWidth),
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
                                        'Count',
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
                                rows: _species.asMap().entries.map((entry) {
                                  final index = entry.key;
                                  final species = entry.value;

                                  return DataRow(
                                    cells: [
                                      DataCell(
                                        SizedBox(
                                          width: speciesWidth,
                                          child: Text(species.speciesName),
                                        ),
                                      ),
                                      DataCell(
                                        SizedBox(
                                          width: countWidth,
                                          child: Text('${species.count}'),
                                        ),
                                      ),
                                      DataCell(
                                        SizedBox(
                                          width: actionsWidth,
                                          child: Row(
                                            children: [
                                              IconButton(
                                                onPressed: () => _editSpecies(index),
                                                icon: const Icon(
                                                  Icons.edit_rounded,
                                                  size: 18,
                                                  color: Color(0xFF1B8B5E),
                                                ),
                                                tooltip: 'Edit',
                                              ),
                                              IconButton(
                                                onPressed: () => _removeSpecies(index),
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
                        border: Border.all(color: Colors.green.shade300, width: 1),
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
                            '${_species.length} species | $_totalSpeciesCount count',
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF1B8B5E),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
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

                  // GPS / Photo capture (feeds photourl_area, activity_type_id = 8)
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
