import 'dart:typed_data';

import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';

/// Service for uploading and retrieving media from Firebase Storage
class StorageService {
  final FirebaseStorage _storage = FirebaseStorage.instance;

  /// Uploads raw bytes to the given [path] and returns the download URL.
  Future<String> uploadBytes(
    Uint8List data,
    String path, {
    String? contentType,
    Map<String, String>? metadata,
  }) async {
    try {
      final ref = _storage.ref(path);
      final meta = SettableMetadata(
        contentType: contentType,
        customMetadata: metadata,
      );
      await ref.putData(data, meta);
      return await ref.getDownloadURL();
    } catch (e) {
      debugPrint('Storage upload error ($path): $e');
      rethrow;
    }
  }

  /// Deletes a file at [path]
  Future<void> delete(String path) async {
    try {
      await _storage.ref(path).delete();
    } catch (e) {
      debugPrint('Storage delete error ($path): $e');
      rethrow;
    }
  }
}
