import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:image_picker/image_picker.dart' show XFile;
import 'package:supabase_flutter/supabase_flutter.dart';

/// Uploads a locally captured photo to Supabase Storage, on every platform.
///
/// The data-entry forms originally did this with `File(localPath)` passed to
/// `Storage.upload`. That can never work on web: image_picker hands back a
/// `blob:` URL rather than a filesystem path, and `dart:io`'s [File] throws
/// `UnsupportedError` there. The result was a photo that saved fine on
/// Android but silently failed in the browser.
///
/// Reading the bytes through [XFile] works everywhere — on web it re-hydrates
/// the blob from the URL via an XHR, on native it reads the file — and
/// `uploadBinary` takes those bytes directly.
class PhotoUploadService {
  const PhotoUploadService._();

  /// Uploads the photo at [localPath] to [bucket]/[objectPath] and returns
  /// the storage reference the `photo` rows expect
  /// (`public/<bucket>/<objectPath>`).
  ///
  /// On native platforms the local temp file is deleted afterwards; on web
  /// there is nothing on disk to clean up.
  static Future<String> upload({
    required String bucket,
    required String objectPath,
    required String localPath,
    required String contentType,
  }) async {
    final bytes = await readBytes(localPath);

    await Supabase.instance.client.storage.from(bucket).uploadBinary(
          objectPath,
          bytes,
          fileOptions: FileOptions(upsert: false, contentType: contentType),
        );

    await _deleteTempFile(localPath);

    final encodedBucket = Uri.encodeComponent(bucket);
    return 'public/$encodedBucket/$objectPath';
  }

  /// Reads a captured photo's bytes from [localPath], which is a filesystem
  /// path on native and a `blob:` URL on web.
  static Future<Uint8List> readBytes(String localPath) async {
    if (kIsWeb) return XFile(localPath).readAsBytes();

    final file = File(localPath);
    if (!await file.exists()) {
      throw Exception('Photo file does not exist: $localPath');
    }
    return file.readAsBytes();
  }

  static Future<void> _deleteTempFile(String localPath) async {
    if (kIsWeb) return;
    try {
      await File(localPath).delete();
    } catch (_) {
      // Best effort only — this is temporary camera output.
    }
  }
}
