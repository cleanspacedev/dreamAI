import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:dreamweaver/models/dream_model.dart';

/// Service class for managing dream data in Firestore
class DreamService extends ChangeNotifier {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  /// Create a new dream
  Future<String> createDream(DreamModel dream) async {
    try {
      final docRef = _firestore.collection('dreams').doc();
      final now = DateTime.now();
      final newDream = dream.copyWith(
        id: docRef.id,
        createdAt: now,
        updatedAt: now,
      );
      await docRef.set(newDream.toJson());
      notifyListeners();
      return docRef.id;
    } catch (e) {
      debugPrint('Error creating dream: $e');
      rethrow;
    }
  }

  /// Get dream by ID
  Future<DreamModel?> getDreamById(String dreamId) async {
    try {
      final doc = await _firestore.collection('dreams').doc(dreamId).get();
      if (doc.exists) {
        return DreamModel.fromJson(doc.data()!);
      }
      return null;
    } catch (e) {
      debugPrint('Error getting dream: $e');
      return null;
    }
  }

  /// Update dream
  Future<void> updateDream(DreamModel dream) async {
    try {
      await _firestore.collection('dreams').doc(dream.id).update(
            dream.copyWith(updatedAt: DateTime.now()).toJson(),
          );
      notifyListeners();
    } catch (e) {
      debugPrint('Error updating dream: $e');
      rethrow;
    }
  }

  /// Delete dream
  Future<void> deleteDream(String dreamId) async {
    try {
      await _firestore.collection('dreams').doc(dreamId).delete();
      notifyListeners();
    } catch (e) {
      debugPrint('Error deleting dream: $e');
      rethrow;
    }
  }

  /// Archive or unarchive a dream
  Future<void> setArchived(String dreamId, bool archived) async {
    try {
      await _firestore.collection('dreams').doc(dreamId).update({
        'archived': archived,
        'updatedAt': Timestamp.now(),
      });
      notifyListeners();
    } catch (e) {
      debugPrint('Error updating archived flag: $e');
      rethrow;
    }
  }

  /// Get user's dreams ordered by date
  Stream<List<DreamModel>> streamUserDreams(String userId) {
    return _firestore
        .collection('dreams')
        .where('ownerId', isEqualTo: userId)
        .orderBy('dreamDate', descending: true)
        .limit(100)
        .snapshots()
        .map((snapshot) => snapshot.docs
            .map((doc) => DreamModel.fromJson(doc.data()))
            .toList());
  }

  /// Search dreams by tags
  Stream<List<DreamModel>> searchDreamsByTag(String userId, String tag) {
    return _firestore
        .collection('dreams')
        .where('ownerId', isEqualTo: userId)
        .where('tags', arrayContains: tag)
        .orderBy('dreamDate', descending: true)
        .limit(50)
        .snapshots()
        .map((snapshot) => snapshot.docs
            .map((doc) => DreamModel.fromJson(doc.data()))
            .toList());
  }
}
