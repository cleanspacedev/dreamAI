import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:dreamweaver/models/user_model.dart';

/// Service class for managing user data in Firestore
class UserService extends ChangeNotifier {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  /// Get user by ID
  Future<UserModel?> getUserById(String userId) async {
    try {
      final doc = await _firestore.collection('users').doc(userId).get();
      if (doc.exists) {
        return UserModel.fromJson(doc.data()!);
      }
      return null;
    } catch (e) {
      debugPrint('Error getting user: $e');
      return null;
    }
  }

  /// Update user profile
  Future<void> updateUser(UserModel user) async {
    try {
      await _firestore.collection('users').doc(user.userId).update(
            user.toJson(),
          );
      notifyListeners();
    } catch (e) {
      debugPrint('Error updating user: $e');
      rethrow;
    }
  }

  /// Stream user data
  Stream<UserModel?> streamUser(String userId) {
    return _firestore.collection('users').doc(userId).snapshots().map((doc) {
      if (doc.exists) {
        return UserModel.fromJson(doc.data()!);
      }
      return null;
    });
  }

  /// Create or merge user profile (useful for first-time setup)
  Future<void> createOrMergeUser(UserModel user) async {
    try {
      await _firestore.collection('users').doc(user.userId).set(
            user.toJson(),
            SetOptions(merge: true),
          );
      notifyListeners();
    } catch (e) {
      debugPrint('Error creating/merging user: $e');
      rethrow;
    }
  }

  /// Atomically increment dailyUsage.dreams and keep lastReset sane (day boundary)
  Future<void> incrementDailyDreams(String userId) async {
    final ref = _firestore.collection('users').doc(userId);
    await _firestore.runTransaction((tx) async {
      final snap = await tx.get(ref);
      if (!snap.exists) return;
      final data = snap.data() as Map<String, dynamic>;
      final usage = (data['dailyUsage'] as Map?)?.cast<String, dynamic>() ?? {};
      int dreams = (usage['dreams'] as num?)?.toInt() ?? 0;
      Timestamp lastResetTs = usage['lastReset'] is Timestamp ? usage['lastReset'] as Timestamp : Timestamp.now();
      final now = DateTime.now().toUtc();
      final last = lastResetTs.toDate().toUtc();
      final dayChanged = now.year != last.year || now.month != last.month || now.day != last.day;
      if (dayChanged) {
        dreams = 0;
        lastResetTs = Timestamp.fromDate(now);
      }
      tx.set(ref, {
        'dailyUsage': {
          'dreams': dreams + 1,
          'videos': (usage['videos'] as num?)?.toInt() ?? 0,
          'lastReset': lastResetTs,
        },
        'analyticsSummary': {
          'totalDreams': ((data['analyticsSummary']?['totalDreams']) as num?)?.toInt() == null
              ? 1
              : ((data['analyticsSummary']['totalDreams'] as num).toInt() + 1),
          'lastActive': FieldValue.serverTimestamp(),
        }
      }, SetOptions(merge: true));
    });
    notifyListeners();
  }
}
