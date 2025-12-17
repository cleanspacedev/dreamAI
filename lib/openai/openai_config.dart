import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// OpenAI configuration for DreamWeaver
///
/// Do NOT hardcode API keys. Values are provided at runtime via
/// --dart-define=OPENAI_PROXY_API_KEY=... and --dart-define=OPENAI_PROXY_ENDPOINT=...
///
/// IMPORTANT: Do not append path segments like 'v1/chat/completions' to the
/// endpoint here. Use Uri.parse(endpoint).resolve('...') per request.

const openAiApiKey = String.fromEnvironment('OPENAI_PROXY_API_KEY');
const openAiEndpoint = String.fromEnvironment('OPENAI_PROXY_ENDPOINT');

/// Returns true when API key and endpoint look usable.
bool get hasOpenAiConfig => openAiApiKey.isNotEmpty && openAiEndpoint.isNotEmpty;

/// Generate speech audio from text using OpenAI's TTS API.
///
/// - Defaults to model 'gpt-4o-mini-tts' with voice 'alloy'.
/// - Returns raw bytes for the chosen format (mp3 by default).
/// - Caller is responsible for audio playback.
Future<Uint8List?> openAiTtsSynthesize({
  required String text,
  String model = 'gpt-4o-mini-tts',
  String voice = 'alloy',
  String format = 'mp3',
}) async {
  if (!hasOpenAiConfig) {
    debugPrint('OpenAI config missing. Set OPENAI_PROXY_API_KEY and OPENAI_PROXY_ENDPOINT.');
    return null;
  }

  try {
    final uri = Uri.parse(openAiEndpoint).resolve('audio/speech');
    final body = jsonEncode({
      'model': model,
      'voice': voice,
      'input': text,
      'format': format, // mp3, wav, etc.
    });
    final resp = await http.post(
      uri,
      headers: {
        'Authorization': 'Bearer $openAiApiKey',
        'Content-Type': 'application/json',
      },
      body: body,
    );
    if (resp.statusCode == 200) {
      return resp.bodyBytes; // binary audio
    }

    // Fallback to legacy 'tts-1' if model unsupported
    if (resp.statusCode == 400 && !model.contains('tts-1')) {
      debugPrint('Primary TTS model failed (${resp.statusCode}). Retrying with tts-1. Body: ${resp.body}');
      return await openAiTtsSynthesize(text: text, model: 'tts-1', voice: voice, format: format);
    }
    debugPrint('OpenAI TTS failed: ${resp.statusCode} ${utf8.decode(resp.bodyBytes)}');
    return null;
  } catch (e) {
    debugPrint('OpenAI TTS error: $e');
    return null;
  }
}

/// Simple structured result for generated daily prompts via Chat Completions
class OpenAiGeneratedPrompt {
  final String? text;
  final String? theme;
  final List<String>? tags;
  const OpenAiGeneratedPrompt({this.text, this.theme, this.tags});
}

/// Generate a daily prompt suggestion via Chat Completions API.
/// Returns a small JSON-structured result with text, theme, and tags.
Future<OpenAiGeneratedPrompt> openAiGenerateDailyPrompt({
  String language = 'en',
  String? topic,
}) async {
  if (!hasOpenAiConfig) {
    debugPrint('OpenAI config missing. Set OPENAI_PROXY_API_KEY and OPENAI_PROXY_ENDPOINT.');
    return const OpenAiGeneratedPrompt();
  }
  try {
    final uri = Uri.parse(openAiEndpoint).resolve('chat/completions');
    final sys = 'You generate succinct daily journaling prompts about dreams. '
        'Return ONLY a JSON object with keys: text, theme, tags (array). '
        'Keep text under 140 characters. Use the requested language: $language.';
    final user = {
      'role': 'user',
      'content': [
        {
          'type': 'text',
          'text': topic == null
              ? 'Create today\'s dream journaling prompt.'
              : 'Create today\'s dream journaling prompt on the topic: "$topic".',
        }
      ],
    };
    final body = jsonEncode({
      'model': 'gpt-4o-mini',
      'messages': [
        {'role': 'system', 'content': sys},
        user,
      ],
      'temperature': 0.8,
      'response_format': {'type': 'json_object'},
    });
    final resp = await http.post(
      uri,
      headers: {
        'Authorization': 'Bearer $openAiApiKey',
        'Content-Type': 'application/json',
      },
      body: body,
    );
    if (resp.statusCode == 200) {
      final decoded = json.decode(utf8.decode(resp.bodyBytes)) as Map<String, dynamic>;
      final content = ((decoded['choices'] as List).first as Map)['message']['content'] as String?;
      if (content != null && content.trim().isNotEmpty) {
        try {
          final parsed = json.decode(content) as Map<String, dynamic>;
          final text = parsed['text']?.toString();
          final theme = parsed['theme']?.toString();
          final tags = (parsed['tags'] as List?)?.map((e) => e.toString()).toList();
          return OpenAiGeneratedPrompt(text: text, theme: theme, tags: tags);
        } catch (e) {
          debugPrint('Failed to parse JSON content from OpenAI: $e');
        }
      }
      return const OpenAiGeneratedPrompt();
    }
    debugPrint('OpenAI generate prompt failed: ${resp.statusCode} ${utf8.decode(resp.bodyBytes)}');
    return const OpenAiGeneratedPrompt();
  } catch (e) {
    debugPrint('OpenAI generate prompt error: $e');
    return const OpenAiGeneratedPrompt();
  }
}

/// Translate arbitrary text to a target language using Chat Completions.
/// Returns plain translated text (no JSON). Keeps emojis and tone natural.
Future<String?> openAiTranslate({
  required String text,
  required String targetLanguage,
  String? sourceLanguage,
  String? context,
}) async {
  if (!hasOpenAiConfig) {
    debugPrint('OpenAI config missing. Set OPENAI_PROXY_API_KEY and OPENAI_PROXY_ENDPOINT.');
    return null;
  }
  try {
    final uri = Uri.parse(openAiEndpoint).resolve('chat/completions');
    final sys = StringBuffer()
      ..writeln('You are a precise translator. Translate user-provided text into "$targetLanguage".')
      ..writeln('Rules:')
      ..writeln('- Output ONLY the translated text, no quotes, no explanations.')
      ..writeln('- Preserve emojis and punctuation.')
      ..writeln('- For short UI strings, keep it concise and idiomatic.')
      ..writeln('- Detect source language automatically.');
    if (context != null && context.trim().isNotEmpty) {
      sys.writeln('Context: $context');
    }
    if (sourceLanguage != null && sourceLanguage.trim().isNotEmpty) {
      sys.writeln('Source language hint: $sourceLanguage');
    }
    final body = jsonEncode({
      'model': 'gpt-4o-mini',
      'messages': [
        {'role': 'system', 'content': sys.toString()},
        {
          'role': 'user',
          'content': [
            {'type': 'text', 'text': text}
          ],
        },
      ],
      'temperature': 0.2,
    });
    final resp = await http.post(
      uri,
      headers: {
        'Authorization': 'Bearer $openAiApiKey',
        'Content-Type': 'application/json',
      },
      body: body,
    );
    if (resp.statusCode == 200) {
      final decoded = json.decode(utf8.decode(resp.bodyBytes)) as Map<String, dynamic>;
      final content = ((decoded['choices'] as List).first as Map)['message']['content'] as String?;
      return content?.trim();
    }
    debugPrint('OpenAI translate failed: ${resp.statusCode} ${utf8.decode(resp.bodyBytes)}');
    return null;
  } catch (e) {
    debugPrint('OpenAI translate error: $e');
    return null;
  }
}
