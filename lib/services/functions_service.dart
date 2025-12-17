import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';

/// Service for calling Firebase Cloud Functions
class FunctionsService {
  FunctionsService({this.region = 'us-central1'})
      : _functions = FirebaseFunctions.instanceFor(region: region);

  final String region;
  final FirebaseFunctions _functions;

  /// Example callable to analyze a dream via Cloud Functions
  Future<Map<String, dynamic>> analyzeDream(Map<String, dynamic> payload) async {
    try {
      final callable = _functions.httpsCallable('analyzeDream');
      final result = await callable.call<Map<String, dynamic>>(payload);
      return result.data;
    } catch (e) {
      debugPrint('Cloud Functions analyzeDream error: $e');
      rethrow;
    }
  }

  /// Trigger end-to-end dream processing on the backend.
  /// Cloud Function name: processDream
  Future<Map<String, dynamic>> processDream(Map<String, dynamic> payload) async {
    try {
      final callable = _functions.httpsCallable('processDream');
      final result = await callable.call<Map<String, dynamic>>(payload);
      return result.data;
    } catch (e) {
      debugPrint('Cloud Functions processDream error: $e');
      rethrow;
    }
  }

  /// Request generation of visual assets for a dream (image/video).
  /// Cloud Function name: generateDreamVisual
  Future<Map<String, dynamic>> generateDreamVisual(Map<String, dynamic> payload) async {
    try {
      final callable = _functions.httpsCallable('generateDreamVisual');
      final result = await callable.call<Map<String, dynamic>>(payload);
      return result.data;
    } catch (e) {
      debugPrint('Cloud Functions generateDreamVisual error: $e');
      rethrow;
    }
  }

  /// Create Stripe Checkout Session via Cloud Function (if implemented on backend)
  /// Returns a map with { url: string }
  Future<Map<String, dynamic>> createStripeCheckoutSession(Map<String, dynamic> payload) async {
    try {
      final callable = _functions.httpsCallable('createStripeCheckoutSession');
      final result = await callable.call<Map<String, dynamic>>(payload);
      return result.data;
    } catch (e) {
      debugPrint('Cloud Functions createStripeCheckoutSession error: $e');
      rethrow;
    }
  }

  /// Admin-only trends pulled from BigQuery via Cloud Function.
  /// Backend function name: adminGetTrends
  /// Returns a map like:
  /// {
  ///   dailyDreams: [{ day: '2025-01-10', count: 12 }, ...],
  ///   topTags: [{ tag: 'flying', count: 8 }, ...],
  ///   activeUsersDaily: [{ day: '2025-01-10', users: 24 }, ...],
  ///   avgProcessingSeconds: 12.4
  /// }
  Future<Map<String, dynamic>> adminGetTrends({String range = '30d'}) async {
    try {
      final callable = _functions.httpsCallable('adminGetTrends');
      final result = await callable.call<Map<String, dynamic>>({
        'range': range,
      });
      return result.data;
    } catch (e) {
      debugPrint('Cloud Functions adminGetTrends error: $e');
      rethrow;
    }
  }
}
