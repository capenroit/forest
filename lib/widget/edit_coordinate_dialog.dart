import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:async';
import 'dart:io';

class EditCoordinateDialog extends StatefulWidget {
  final Map<String, dynamic> coordinate;
  final VoidCallback? onLocationPermissionDenied;

  const EditCoordinateDialog({
    Key? key,
    required this.coordinate,
    this.onLocationPermissionDenied,
  }) : super(key: key);

  @override
  State<EditCoordinateDialog> createState() => _EditCoordinateDialogState();
}

class _EditCoordinateDialogState extends State<EditCoordinateDialog> {
  late TextEditingController _latController;
  late TextEditingController _lngController;
  late Map<String, dynamic> _currentCoordinate;
  bool _isCapturing = false;
  final ImagePicker _imagePicker = ImagePicker();

  @override
  void initState() {
    super.initState();
    _currentCoordinate = Map.from(widget.coordinate);
    _latController = TextEditingController(
      text: _currentCoordinate['lat']?.toString() ?? '',
    );
    _lngController = TextEditingController(
      text: _currentCoordinate['lng']?.toString() ?? '',
    );
  }

  @override
  void dispose() {
    _latController.dispose();
    _lngController.dispose();
    super.dispose();
  }

  Future<void> _captureGPS() async {
    // Check permission
    final permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      if (mounted) {
        widget.onLocationPermissionDenied?.call();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Location permission not granted'),
            backgroundColor: Colors.red,
          ),
        );
      }
      return;
    }

    setState(() => _isCapturing = true);

    try {
      final position = await Geolocator.getCurrentPosition(
        timeLimit: const Duration(seconds: 10),
      );

      if (!mounted) return;

      setState(() {
        _currentCoordinate['lat'] = position.latitude;
        _currentCoordinate['lng'] = position.longitude;
        _latController.text = position.latitude.toString();
        _lngController.text = position.longitude.toString();
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('GPS captured successfully'),
          backgroundColor: Colors.blue,
          duration: Duration(seconds: 2),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error capturing GPS: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) setState(() => _isCapturing = false);
    }
  }

  Future<void> _capturePhoto() async {
    try {
      setState(() => _isCapturing = true);

      // Capture photo
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
                content: Text('Camera operation timed out'),
                backgroundColor: Colors.red,
              ),
            );
          }
          return null;
        },
      );

      if (photo == null) {
        setState(() => _isCapturing = false);
        return;
      }

      if (!mounted) return;

      // Save photo to persistent storage
      String? persistentPhotoPath;
      try {
        final appDocDir = await getApplicationDocumentsDirectory();
        final offlinePhotosDir = Directory('${appDocDir.path}/offline_photos');

        if (!await offlinePhotosDir.exists()) {
          await offlinePhotosDir.create(recursive: true);
        }

        final fileName = 'photo_${DateTime.now().millisecondsSinceEpoch}.jpg';
        final persistentPath = '${offlinePhotosDir.path}/$fileName';

        await File(photo.path).copy(persistentPath);
        persistentPhotoPath = persistentPath;
      } catch (e) {
        persistentPhotoPath = photo.path;
      }

      if (!mounted) return;

      // Update coordinate with photo
      setState(() {
        _currentCoordinate['photoPath'] = persistentPhotoPath;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Photo captured successfully'),
          backgroundColor: Colors.green,
          duration: Duration(seconds: 2),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error capturing photo: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) setState(() => _isCapturing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      insetPadding: const EdgeInsets.all(16),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          color: Colors.white,
        ),
        constraints: const BoxConstraints(
          maxWidth: 450,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header - Green
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
                  Icon(Icons.edit_location_rounded, color: Colors.white, size: 24),
                  SizedBox(width: 12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Edit Point',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
                      Text(
                        'Update coordinates or capture new data',
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
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Capture buttons
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.teal.shade50,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.teal.shade200),
                      ),
                      child: Column(
                        children: [
                          ElevatedButton.icon(
                            onPressed: _isCapturing ? null : _captureGPS,
                            icon: const Icon(Icons.gps_fixed_rounded, size: 18),
                            label: const Text('Capture GPS'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.blue.shade500,
                              foregroundColor: Colors.white,
                              minimumSize: const Size(double.infinity, 40),
                              disabledBackgroundColor: Colors.grey.shade300,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                          ),
                          const SizedBox(height: 8),
                          ElevatedButton.icon(
                            onPressed: _isCapturing ? null : _capturePhoto,
                            icon: const Icon(Icons.camera_alt_rounded, size: 18),
                            label: const Text('Take Photo'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.green.shade500,
                              foregroundColor: Colors.white,
                              minimumSize: const Size(double.infinity, 40),
                              disabledBackgroundColor: Colors.grey.shade300,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                          ),
                          if (_isCapturing) ...[
                            const SizedBox(height: 8),
                            const Center(
                              child: SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),

                    const SizedBox(height: 16),

                    // Manual edit label
                    Text(
                      'Or edit manually:',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: Colors.grey.shade700,
                      ),
                    ),

                    const SizedBox(height: 8),

                    // Latitude field
                    TextField(
                      controller: _latController,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      enabled: !_isCapturing,
                      decoration: InputDecoration(
                        labelText: 'Latitude',
                        prefixIcon: const Icon(Icons.location_on_rounded, size: 18),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                      ),
                    ),

                    const SizedBox(height: 12),

                    // Longitude field
                    TextField(
                      controller: _lngController,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      enabled: !_isCapturing,
                      decoration: InputDecoration(
                        labelText: 'Longitude',
                        prefixIcon: const Icon(Icons.location_on_rounded, size: 18),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                      ),
                    ),

                    // Photo status
                    if (_currentCoordinate['photoPath'] != null) ...[
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Colors.green.shade50,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.green.shade200),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.check_circle, color: Colors.green.shade700, size: 18),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                '📷 Photo attached',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.green.shade700,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],

                    const SizedBox(height: 24),

                    // Action buttons (now inside the Padding / SingleChildScrollView to match AddSeedlingDialog styling)
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: _isCapturing ? null : () => Navigator.pop(context, null),
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                            child: const Text('Cancel'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: ElevatedButton(
                            onPressed: _isCapturing
                                ? null
                                : () => Navigator.pop(context, _currentCoordinate),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF1B8B5E),
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                            child: const Text('Save'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

