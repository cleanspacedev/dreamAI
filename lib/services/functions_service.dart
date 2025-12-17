import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

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

  /// Ensure today's public prompt exists (server-authoritative) and return it.
  /// Cloud Function name: ensureTodayPrompt
  ///
  /// The backend should create/update the doc in the top-level `prompts/{yyyyMMdd}`
  /// collection with necessary fields. This avoids client write permission issues.
  Future<Map<String, dynamic>> ensureTodayPrompt({String? language, String? topic}) async {
    try {
      final callable = _functions.httpsCallable('ensureTodayPrompt');
      final result = await callable.call<Map<String, dynamic>>({
        if (language != null) 'language': language,
        if (topic != null) 'topic': topic,
      });
      return result.data;
    } catch (e) {
      debugPrint('Cloud Functions ensureTodayPrompt error: $e');
      // Web often hits CORS issues if the callable endpoint is restricted.
      // Provide a CORS-safe HTTP fallback that calls our onRequest wrapper.
      if (kIsWeb) {
        try {
          final proj = Firebase.app().options.projectId;
          final regionHost = region; // e.g. us-central1
          if (proj != null && proj.isNotEmpty) {
            final uri = Uri.parse('https://$regionHost-$proj.cloudfunctions.net/ensureTodayPromptHttp');
            final resp = await http.post(
              uri,
              headers: const {
                'Content-Type': 'application/json',
                'Accept': 'application/json',
              },
              body: jsonEncode({
                if (language != null) 'language': language,
                if (topic != null) 'topic': topic,
              }),
            );
            if (resp.statusCode == 200) {
              final data = json.decode(utf8.decode(resp.bodyBytes)) as Map<String, dynamic>;
              return data;
            }
            debugPrint('ensureTodayPromptHttp ${resp.statusCode}: ${utf8.decode(resp.bodyBytes, allowMalformed: true)}');
          }
        } catch (we) {
          debugPrint('ensureTodayPrompt web fallback failed: $we');
        }
      }
      rethrow;
    }
  }
}
