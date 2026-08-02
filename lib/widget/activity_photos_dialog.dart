import 'dart:typed_data';

import 'package:file_saver/file_saver.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import '../service/api_service.dart';
import 'web_helper.dart' as web_helper;

class ActivityPhoto {
  final String url;
  final String name;

  const ActivityPhoto({required this.url, required this.name});
}

/// Shows a dialog listing every photo attached to an activity, with
/// per-photo and "download all" actions backed by Supabase Storage.
Future<void> showActivityPhotosDialog({
  required BuildContext context,
  required String title,
  required Future<List<ActivityPhoto>> Function() loadPhotos,
}) {
  return showDialog<void>(
    context: context,
    builder: (_) => _ActivityPhotosDialog(title: title, loadPhotos: loadPhotos),
  );
}

class _ActivityPhotosDialog extends StatefulWidget {
  const _ActivityPhotosDialog({required this.title, required this.loadPhotos});

  final String title;
  final Future<List<ActivityPhoto>> Function() loadPhotos;

  @override
  State<_ActivityPhotosDialog> createState() => _ActivityPhotosDialogState();
}

class _ActivityPhotosDialogState extends State<_ActivityPhotosDialog> {
  late final Future<List<ActivityPhoto>> _future;
  final Map<String, Future<Uint8List>> _bytesCache = {};
  bool _isDownloadingAll = false;

  @override
  void initState() {
    super.initState();
    _future = widget.loadPhotos();
  }

  Future<Uint8List> _bytesFor(ActivityPhoto photo) {
    return _bytesCache.putIfAbsent(
      photo.url,
      () => ApiService.downloadActivityPhoto(photo.url),
    );
  }

  String _extensionFor(String name) {
    final lower = name.toLowerCase();
    if (lower.endsWith('.png')) return 'png';
    if (lower.endsWith('.webp')) return 'webp';
    return 'jpg';
  }

  MimeType _mimeTypeFor(String ext) {
    switch (ext) {
      case 'png':
        return MimeType.png;
      case 'jpg':
      case 'jpeg':
        return MimeType.jpeg;
      default:
        return MimeType.other;
    }
  }

  Future<void> _downloadOne(ActivityPhoto photo, {bool silent = false}) async {
    try {
      final bytes = await _bytesFor(photo);
      final ext = _extensionFor(photo.name);
      final baseName = photo.name.contains('.')
          ? photo.name.substring(0, photo.name.lastIndexOf('.'))
          : photo.name;

      if (kIsWeb) {
        web_helper.downloadBytes(bytes, '$baseName.$ext', 'image/$ext');
        if (!silent && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Downloaded ${photo.name}')),
          );
        }
        return;
      }

      if (silent) {
        // Bulk "Download All" — save straight to the default location so
        // the user isn't hit with a save-location picker per photo.
        await FileSaver.instance.saveFile(
          name: baseName,
          bytes: bytes,
          ext: ext,
          mimeType: _mimeTypeFor(ext),
        );
        return;
      }

      // A single photo download: same "Save As" picker + confirmed path as
      // the Excel/map export flows, so the user knows exactly where it went.
      final savedPath = await FileSaver.instance.saveAs(
        name: baseName,
        bytes: bytes,
        ext: ext,
        mimeType: _mimeTypeFor(ext),
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              savedPath != null
                  ? 'Saved to $savedPath'
                  : 'Downloaded ${photo.name}',
            ),
            duration: const Duration(seconds: 6),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to download ${photo.name}: $e')),
        );
      }
    }
  }

  Future<void> _downloadAll(List<ActivityPhoto> photos) async {
    if (photos.isEmpty || _isDownloadingAll) return;
    setState(() => _isDownloadingAll = true);

    for (final photo in photos) {
      await _downloadOne(photo, silent: true);
    }

    if (!mounted) return;
    setState(() => _isDownloadingAll = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Downloaded ${photos.length} photo(s)')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      insetPadding: const EdgeInsets.all(20),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560, maxHeight: 620),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 14, 10, 14),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      widget.title,
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              const Divider(height: 12),
              Flexible(
                child: FutureBuilder<List<ActivityPhoto>>(
                  future: _future,
                  builder: (context, snapshot) {
                    if (snapshot.connectionState != ConnectionState.done) {
                      return const Padding(
                        padding: EdgeInsets.symmetric(vertical: 60),
                        child: Center(child: CircularProgressIndicator()),
                      );
                    }
                    if (snapshot.hasError) {
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 8),
                        child: Center(
                          child: Text('Failed to load photos: ${snapshot.error}'),
                        ),
                      );
                    }
                    final photos = snapshot.data ?? const [];
                    if (photos.isEmpty) {
                      return const Padding(
                        padding: EdgeInsets.symmetric(vertical: 60),
                        child: Center(child: Text('No photos for this activity.')),
                      );
                    }
                    return Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Align(
                          alignment: Alignment.centerRight,
                          child: TextButton.icon(
                            onPressed: _isDownloadingAll ? null : () => _downloadAll(photos),
                            icon: _isDownloadingAll
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(strokeWidth: 2),
                                  )
                                : const Icon(Icons.download_rounded),
                            label: Text(
                              _isDownloadingAll
                                  ? 'Downloading…'
                                  : 'Download All (${photos.length})',
                            ),
                          ),
                        ),
                        Flexible(
                          child: GridView.builder(
                            shrinkWrap: true,
                            itemCount: photos.length,
                            gridDelegate:
                                const SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: 3,
                              crossAxisSpacing: 10,
                              mainAxisSpacing: 10,
                            ),
                            itemBuilder: (context, index) {
                              final photo = photos[index];
                              return _PhotoTile(
                                photo: photo,
                                bytesLoader: () => _bytesFor(photo),
                                onDownload: () => _downloadOne(photo),
                              );
                            },
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PhotoTile extends StatelessWidget {
  const _PhotoTile({
    required this.photo,
    required this.bytesLoader,
    required this.onDownload,
  });

  final ActivityPhoto photo;
  final Future<Uint8List> Function() bytesLoader;
  final VoidCallback onDownload;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: Stack(
        fit: StackFit.expand,
        children: [
          Container(color: const Color(0xFFEFEFF2)),
          FutureBuilder<Uint8List>(
            future: bytesLoader(),
            builder: (context, snapshot) {
              if (snapshot.connectionState != ConnectionState.done) {
                return const Center(
                  child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                );
              }
              if (snapshot.hasError || !snapshot.hasData) {
                return const Center(
                  child: Icon(Icons.broken_image_outlined, color: Colors.grey),
                );
              }
              final bytes = snapshot.data!;
              return GestureDetector(
                onTap: () => _openPreview(context, bytes),
                child: Image.memory(bytes, fit: BoxFit.cover),
              );
            },
          ),
          Positioned(
            right: 4,
            bottom: 4,
            child: Material(
              color: Colors.black54,
              shape: const CircleBorder(),
              child: IconButton(
                icon: const Icon(Icons.download_rounded, color: Colors.white, size: 18),
                tooltip: 'Download',
                onPressed: onDownload,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _openPreview(BuildContext context, Uint8List bytes) {
    showDialog<void>(
      context: context,
      builder: (_) => Dialog(
        insetPadding: const EdgeInsets.all(16),
        child: InteractiveViewer(child: Image.memory(bytes)),
      ),
    );
  }
}
