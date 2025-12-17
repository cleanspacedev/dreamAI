import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

/// FreemiumService encapsulates quota checks and counters for video generation.
///
/// Rules:
/// - Free: 1 lifetime video (analyticsSummary.totalVideos >= 1 blocks), unlimited text
/// - Premium: 3 videos/day, max 20s
/// - Premium+: 8 videos/day, max 30s
///
/// We use a Firestore transaction to:
/// - Reset dailyUsage when day changed
/// - Enforce limits
/// - Increment dailyUsage.videos and analyticsSummary.totalVideos atomically
class FreemiumService extends ChangeNotifier {
  FreemiumService();

  /// Ensure the user can start a video generation and atomically consume a slot.
  /// Returns allowed and the tier-derived maxSeconds when allowed.
  Future<({bool allowed, String reason, int maxSeconds, String tier, int remainingToday})> checkAndConsume({
    required String uid,
    required String tier,
  }) async {
    final ref = FirebaseFirestore.instance.collection('users').doc(uid);
    return FirebaseFirestore.instance.runTransaction((tx) async {
      final snap = await tx.get(ref);
      if (!snap.exists) {
        return (allowed: false, reason: 'profile_missing', maxSeconds: 0, tier: 'free', remainingToday: 0);
      }
      final data = snap.data() as Map<String, dynamic>;
      final sub = (data['subscriptionStatus'] as String?) ?? tier;
      final analytics = (data['analyticsSummary'] as Map?)?.cast<String, dynamic>() ?? {};
      final totalVideos = (analytics['totalVideos'] as num?)?.toInt() ?? 0;
      final usage = (data['dailyUsage'] as Map?)?.cast<String, dynamic>() ?? {};
      int videos = (usage['videos'] as num?)?.toInt() ?? 0;
      Timestamp lastResetTs = usage['lastReset'] is Timestamp ? usage['lastReset'] as Timestamp : Timestamp.now();

      // Reset if day changed (UTC day boundary)
      final now = DateTime.now().toUtc();
      final last = lastResetTs.toDate().toUtc();
      final dayChanged = now.year != last.year || now.month != last.month || now.day != last.day;
      if (dayChanged) {
        videos = 0;
        lastResetTs = Timestamp.fromDate(now);
      }

      int dailyLimit = 0;
      int maxSeconds = 0;
      switch (sub) {
        case 'premium_plus':
          dailyLimit = 8;
          maxSeconds = 30;
          break;
        case 'premium':
          dailyLimit = 3;
          maxSeconds = 20;
          break;
        default:
          dailyLimit = 0; // free has lifetime limit handled below
          maxSeconds = 0;
      }

      // Enforce free lifetime limit
      if (sub == 'free') {
        if (totalVideos >= 1) {
          return (allowed: false, reason: 'free_lifetime_limit', maxSeconds: 0, tier: sub, remainingToday: 0);
        }
        // Consume: increment totalVideos (lifetime) and mark lastActive
        tx.set(ref, {
          'analyticsSummary': {
            'totalVideos': totalVideos + 1,
            'lastActive': FieldValue.serverTimestamp(),
          }
        }, SetOptions(merge: true));
        return (allowed: true, reason: 'ok', maxSeconds: 15, tier: sub, remainingToday: 0);
      }

      // Paid tiers: enforce daily limit
      if (videos >= dailyLimit) {
        return (allowed: false, reason: 'daily_limit', maxSeconds: maxSeconds, tier: sub, remainingToday: 0);
      }

      // Consume one slot and update counters
      tx.set(ref, {
        'dailyUsage': {
          'videos': videos + 1,
          'dreams': (usage['dreams'] as num?)?.toInt() ?? 0,
          'lastReset': lastResetTs,
        },
        'analyticsSummary': {
          'totalVideos': totalVideos + 1,
          'lastActive': FieldValue.serverTimestamp(),
        }
      }, SetOptions(merge: true));

      return (
        allowed: true,
        reason: 'ok',
        maxSeconds: maxSeconds,
        tier: sub,
        remainingToday: (dailyLimit - (videos + 1)).clamp(0, dailyLimit),
      );
    });
  }
}
