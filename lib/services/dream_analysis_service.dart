import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:dreamweaver/models/dream_analysis_model.dart';

/// Service class for managing dream analysis data in Firestore
class DreamAnalysisService extends ChangeNotifier {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  /// Create a new dream analysis
  Future<String> createAnalysis(DreamAnalysisModel analysis) async {
    try {
      final docRef = _firestore.collection('dream_analyses').doc();
      final now = DateTime.now();
      final newAnalysis = analysis.copyWith(
        id: docRef.id,
        createdAt: now,
        updatedAt: now,
      );
      await docRef.set(newAnalysis.toJson());
      notifyListeners();
      return docRef.id;
    } catch (e) {
      debugPrint('Error creating analysis: $e');
      rethrow;
    }
  }

  /// Get analysis for a dream
  Future<DreamAnalysisModel?> getAnalysisForDream(String dreamId) async {
    try {
      final querySnapshot = await _firestore
          .collection('dream_analyses')
          .where('dreamId', isEqualTo: dreamId)
          .limit(1)
          .get();

      if (querySnapshot.docs.isNotEmpty) {
        return DreamAnalysisModel.fromJson(querySnapshot.docs.first.data());
      }
      return null;
    } catch (e) {
      debugPrint('Error getting analysis: $e');
      return null;
    }
  }

  /// Update analysis
  Future<void> updateAnalysis(DreamAnalysisModel analysis) async {
    try {
      await _firestore.collection('dream_analyses').doc(analysis.id).update(
            analysis.copyWith(updatedAt: DateTime.now()).toJson(),
          );
      notifyListeners();
    } catch (e) {
      debugPrint('Error updating analysis: $e');
      rethrow;
    }
  }

  /// Stream user's dream analyses
  Stream<List<DreamAnalysisModel>> streamUserAnalyses(String userId) {
    return _firestore
        .collection('dream_analyses')
        .where('ownerId', isEqualTo: userId)
        .orderBy('createdAt', descending: true)
        .limit(100)
        .snapshots()
        .map((snapshot) => snapshot.docs
            .map((doc) => DreamAnalysisModel.fromJson(doc.data()))
            .toList());
  }
}
