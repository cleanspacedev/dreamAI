import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:firebase_auth/firebase_auth.dart' as fb;
import 'package:flutter/foundation.dart';

/// Centralized analytics logger
/// - Writes per-user event documents under: /users/{uid}/analytics
/// - Updates /users/{uid}.analyticsSummary with eventCounts and lastActive
/// - Mirrors events to Firebase Analytics for dashboards
class AnalyticsService {
  AnalyticsService._();
  static final AnalyticsService instance = AnalyticsService._();

  final _firestore = FirebaseFirestore.instance;
  final _fa = FirebaseAnalytics.instance;

  /// Log a custom analytics event.
  ///
  /// Writes a document to /users/{uid}/analytics and updates analyticsSummary.eventCounts.
  /// Also logs to Firebase Analytics.
  Future<void> logEvent({
    required String eventType,
    Map<String, Object?> details = const {},
  }) async {
    try {
      final user = fb.FirebaseAuth.instance.currentUser;
      if (user == null) {
        debugPrint('AnalyticsService.logEvent skipped: no user');
        return;
      }

      final uid = user.uid;
      final now = FieldValue.serverTimestamp();

      // Sanitize details for Firestore and Firebase Analytics
      final sanitized = <String, Object?>{};
      details.forEach((key, value) {
        if (value == null) return;
        if (value is num || value is String || value is bool) {
          sanitized[key] = value;
        } else if (value is DateTime) {
          sanitized[key] = Timestamp.fromDate(value);
        } else if (value is Duration) {
          sanitized[key] = value.inMilliseconds;
        } else if (value is List) {
          // Keep list of simple types only
          sanitized[key] = value.where((e) => e is num || e is String || e is bool).toList();
        } else {
          // Fallback to string representation
          sanitized[key] = value.toString();
        }
      });

      // Firestore: write event doc
      final eventsCol = _firestore.collection('users').doc(uid).collection('analytics');
      await eventsCol.add({
        'eventType': eventType,
        'timestamp': now,
        if (sanitized.isNotEmpty) 'details': sanitized,
      });

      // Firestore: update summary (lastActive + per-event counter)
      final userRef = _firestore.collection('users').doc(uid);
      await userRef.set({
        'analyticsSummary': {
          'lastActive': now,
          'eventCounts': {
            eventType: FieldValue.increment(1),
          },
        },
      }, SetOptions(merge: true));

      // Firebase Analytics: mirror event
      try {
        await _fa.logEvent(name: _normalizeEventName(eventType), parameters: _limitAnalyticsParams(sanitized));
      } catch (e) {
        debugPrint('Firebase Analytics logEvent error: $e');
      }
    } catch (e) {
      debugPrint('AnalyticsService.logEvent error: $e');
    }
  }

  /// Convenience: dream logged
  Future<void> logDreamLogged({
    required String dreamId,
    String method = 'text', // text | voice | voice_stt
    int lengthChars = 0,
    bool fromPrompt = false,
  }) async {
    await logEvent(
      eventType: 'dream_logged',
      details: {
        'dreamId': dreamId,
        'method': method,
        'lengthChars': lengthChars,
        'fromPrompt': fromPrompt,
      },
    );
  }

  /// Convenience: video generated
  Future<void> logVideoGenerated({
    required String dreamId,
    int durationSeconds = 0,
    String quality = 'standard',
  }) async {
    await logEvent(
      eventType: 'video_generated',
      details: {
        'dreamId': dreamId,
        'durationSeconds': durationSeconds,
        'quality': quality,
      },
    );
  }

  // Firebase Analytics helpers
  String _normalizeEventName(String name) {
    // Firebase Analytics: [a-zA-Z0-9_], <= 40 chars
    final norm = name.replaceAll(RegExp(r'[^a-zA-Z0-9_]'), '_');
    return norm.length <= 40 ? norm : norm.substring(0, 40);
  }

  Map<String, Object> _limitAnalyticsParams(Map<String, Object?> params) {
    // Limit to <= 25 params, sanitize keys similarly
    final out = <String, Object>{};
    int count = 0;
    for (final entry in params.entries) {
      if (count >= 25) break;
      final key = entry.key.replaceAll(RegExp(r'[^a-zA-Z0-9_]'), '_');
      final value = entry.value;
      if (value is num || value is String || value is bool) {
        out[key] = value as Object;
        count++;
      } else if (value is Timestamp) {
        out[key] = value.millisecondsSinceEpoch;
        count++;
      }
    }
    return out;
  }
}
