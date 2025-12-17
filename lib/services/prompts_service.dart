import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:dreamweaver/services/functions_service.dart';

import 'package:dreamweaver/openai/openai_config.dart' as openai;

/// Model representing a daily prompt
class PromptModel {
  final String id; // typically yyyyMMdd
  final String text;
  final String? theme;
  final List<String> tags;
  final String? language;
  final DateTime date; // start of day (UTC)
  final DateTime createdAt;

  const PromptModel({
    required this.id,
    required this.text,
    required this.date,
    required this.createdAt,
    this.theme,
    this.tags = const [],
    this.language,
  });

  factory PromptModel.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? {};
    final tsDate = data['date'];
    final tsCreated = data['createdAt'];
    return PromptModel(
      id: doc.id,
      text: (data['text'] as String?) ?? (data['prompt'] as String?) ?? 'Reflect on your most vivid moment.',
      theme: data['theme'] as String?,
      tags: (data['tags'] as List?)?.map((e) => e.toString()).toList() ?? const [],
      language: data['language'] as String?,
      date: tsDate is Timestamp ? tsDate.toDate() : DateTime.fromMillisecondsSinceEpoch(0),
      createdAt: tsCreated is Timestamp ? tsCreated.toDate() : DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() => {
        'text': text,
        'theme': theme,
        'tags': tags,
        'language': language,
        'date': Timestamp.fromDate(date),
        'createdAt': Timestamp.fromDate(createdAt),
        'dynamic': true,
      };
}

/// Service for handling daily prompts and streaks
class PromptsService extends ChangeNotifier {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  /// Stream latest prompt (sorted by date/createdAt desc)
  Stream<PromptModel?> streamLatestPrompt() {
    return _firestore
        .collection('prompts')
        .orderBy('date', descending: true)
        .orderBy('createdAt', descending: true)
        .limit(1)
        .snapshots()
        .map((snap) {
      if (snap.docs.isEmpty) return null;
      return PromptModel.fromDoc(snap.docs.first);
    });
  }

  /// Ensure today's prompt exists (idempotent via yyyyMMdd docId). Returns the prompt.
  Future<PromptModel> ensureTodayPrompt({String? language, String? topic}) async {
    final nowUtc = DateTime.now().toUtc();
    final todayUtc = DateTime.utc(nowUtc.year, nowUtc.month, nowUtc.day);
    final id = _yyyymmdd(todayUtc);
    final ref = _firestore.collection('prompts').doc(id);

    // Try read first
    final existing = await ref.get();
    if (existing.exists) {
      return PromptModel.fromDoc(existing);
    }

    String text = 'Describe a dream that felt unusually real.';
    String? theme;
    List<String> tags = const [];

    // Generate via OpenAI if configured
    if (openai.hasOpenAiConfig) {
      try {
        final result = await openai.openAiGenerateDailyPrompt(
          language: language ?? 'en',
          topic: topic,
        );
        text = result.text ?? text;
        theme = result.theme;
        tags = result.tags ?? [];
      } catch (e) {
        debugPrint('OpenAI prompt generation failed, using fallback: $e');
      }
    }

    final model = PromptModel(
      id: id,
      text: text,
      theme: theme,
      tags: tags,
      language: language,
      date: todayUtc,
      createdAt: DateTime.now().toUtc(),
    );

    try {
      await ref.set(model.toJson());
    } catch (e) {
      // If rules reject client writes, fall back to Cloud Function to create it server-side.
      final msg = e.toString();
      if (msg.contains('permission-denied') || msg.contains('PERMISSION_DENIED')) {
        debugPrint('Client write denied for prompts. Falling back to Cloud Function. Error: $e');
        try {
          // Lazy import to avoid tight coupling
          // ignore: prefer_interpolation_to_compose_strings
          debugPrint('Invoking ensureTodayPrompt Cloud Function...');
          // Use a local import to avoid circular deps at file top
          // ignore: avoid_dynamic_calls
        } catch (_) {}
        try {
          // Call via FunctionsService
          // We import here to keep top-level clean
          // ignore: unnecessary_import
          // ignore: depend_on_referenced_packages
        } catch (_) {}
        try {
          // We can't import inside a method in Dart, so actually add a direct dependency at file top
          // Instead, call through a helper below.
          await _ensurePromptViaFunction(language: language, topic: topic);
        } catch (fe) {
          debugPrint('Cloud Function ensureTodayPrompt failed: $fe');
        }
      } else {
        // Another client may have created it concurrently; read back
        debugPrint('Failed to create today prompt (likely exists): $e');
      }
    }
    final doc = await ref.get();
    return PromptModel.fromDoc(doc);
  }

  Future<void> _ensurePromptViaFunction({String? language, String? topic}) async {
    try {
      // Import locally
      // ignore: unnecessary_import
      // ignore: implementation_imports
      // Use the global FunctionsService
      final functions = FunctionsService();
      await functions.ensureTodayPrompt(language: language, topic: topic);
    } catch (e) {
      debugPrint('ensureTodayPrompt via function error: $e');
    }
  }

  /// Compute current streak (consecutive days up to today) of prompt-based entries
  Stream<int> streamPromptStreak(String userId) {
    return _firestore
        .collection('dreams')
        .where('ownerId', isEqualTo: userId)
        .where('metadata.source', isEqualTo: 'prompt')
        .orderBy('dreamDate', descending: true)
        .limit(60)
        .snapshots()
        .map((snap) {
      final dates = snap.docs
          .map((d) => (d.data()['dreamDate'] as Timestamp).toDate().toUtc())
          .map((dt) => DateTime.utc(dt.year, dt.month, dt.day))
          .toSet()
          .toList()
        ..sort((a, b) => b.compareTo(a));

      int streak = 0;
      final nowUtc = DateTime.now().toUtc();
      DateTime day = DateTime.utc(nowUtc.year, nowUtc.month, nowUtc.day);

      while (true) {
        if (dates.contains(day)) {
          streak += 1;
          day = day.subtract(const Duration(days: 1));
        } else {
          break;
        }
      }
      return streak;
    });
  }

  String _yyyymmdd(DateTime d) {
    final mm = d.month.toString().padLeft(2, '0');
    final dd = d.day.toString().padLeft(2, '0');
    return '${d.year}$mm$dd';
  }
}

/// Result for generated prompt from OpenAI
class GeneratedPromptResult {
  final String? text;
  final String? theme;
  final List<String>? tags;
  const GeneratedPromptResult({this.text, this.theme, this.tags});
}
