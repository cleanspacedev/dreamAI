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

// Default proxy domain (requested)
const _defaultProxyEndpoint = 'https://proxy.cleanspace.com/';

/// Returns true when API key and endpoint look usable.
bool get hasOpenAiConfig {
  // Allow either explicit endpoint or default proxy. API key may be optional if proxy injects it.
  final endpoint = (openAiEndpoint.isNotEmpty ? openAiEndpoint : _defaultProxyEndpoint).trim();
  return endpoint.isNotEmpty; // api key can be empty if proxy handles auth
}

/// Resolve the base endpoint. If the endpoint is a Cloud Functions root
/// (e.g. https://us-central1-<project>.cloudfunctions.net/), automatically
/// route requests through the `openaiProxy` function so that calls like
/// `.resolve('chat/completions')` work on Web without CORS failures.
Uri _resolvedBaseEndpoint() {
  try {
    // Prefer explicit endpoint; otherwise fall back to default proxy
    final raw = (openAiEndpoint.isNotEmpty ? openAiEndpoint : _defaultProxyEndpoint).trim();
    if (raw.isEmpty) return Uri();
    final base = Uri.parse(raw.endsWith('/') ? raw : '$raw/');
    if (base.host.contains('cloudfunctions.net')) {
      final segs = base.pathSegments.where((s) => s.isNotEmpty).toList();
      if (segs.isEmpty) {
        // No function name provided; default to openaiProxy/
        return base.resolve('openaiProxy/');
      }
    }
    return base;
  } catch (_) {
    return Uri();
  }
}

/// Public accessor for other services that need to build raw URLs
/// (e.g., multipart requests for audio/transcriptions).
Uri openAiBase() => _resolvedBaseEndpoint();

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
    final body = jsonEncode({
      'model': model,
      'voice': voice,
      'input': text,
      'format': format, // mp3, wav, etc.
    });

    // Try multiple URL shapes for Cloud Functions compatibility and proxy fallback.
    final base = _resolvedBaseEndpoint();
    // Helper to compute CF root, e.g. https://us-central1-<proj>.cloudfunctions.net/
    Uri _cfRoot(Uri u) => Uri.parse('${u.scheme}://${u.host}/');
    final candidates = <Uri>[
      // 1) {endpoint}/audio/speech
      if (base.toString().isNotEmpty) base.resolve('audio/speech'),
      // 2) {endpoint}?path=audio/speech (for functions that don’t expose subpaths)
      if (base.toString().isNotEmpty)
        base.replace(
          queryParameters: {
            ...base.queryParameters,
            'path': 'audio/speech',
          },
        ),
      // 3) If endpoint is Cloud Functions, also try the canonical function name openaiProxy at the root
      if (base.host.contains('cloudfunctions.net')) _cfRoot(base).resolve('openaiProxy/audio/speech'),
      // 4) As a final safety, try the requested default proxy domain
      Uri.parse(_defaultProxyEndpoint).resolve('audio/speech'),
    ];

    http.Response? good;
    for (final uri in candidates) {
      try {
        final resp = await http.post(
          uri,
          headers: {
            if (openAiApiKey.isNotEmpty) 'Authorization': 'Bearer $openAiApiKey',
            'Content-Type': 'application/json',
            // Hint desired binary type to proxies/edges
            'Accept': 'audio/mpeg',
            // Provide an alternate hint in case the proxy expects this header
            'X-OpenAI-Path': 'audio/speech',
          },
          body: body,
        );
        final ct = (resp.headers['content-type'] ?? resp.headers['Content-Type'] ?? '').toLowerCase();
        if (resp.statusCode == 200 && ct.startsWith('audio/')) {
          good = resp;
          break;
        }
        debugPrint('TTS attempt ${uri.toString()} -> ${resp.statusCode}: ${utf8.decode(resp.bodyBytes, allowMalformed: true)}');
      } catch (e) {
        debugPrint('TTS attempt failed for ${uri.toString()}: $e');
      }
    }

    if (good != null) {
      return good!.bodyBytes; // binary audio
    }

    // Fallback to legacy 'tts-1' if model unsupported
    // We cannot rely on a specific status code here due to multiple attempts.
    if (!model.contains('tts-1')) {
      debugPrint('Primary TTS model failed. Retrying with tts-1.');
      return await openAiTtsSynthesize(text: text, model: 'tts-1', voice: voice, format: format);
    }
    debugPrint('OpenAI TTS failed for all URL shapes.');
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
    final base = _resolvedBaseEndpoint();
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
    // Helper to compute CF root
    Uri _cfRoot(Uri u) => Uri.parse('${u.scheme}://${u.host}/');
    final candidates = <Uri>[
      base.resolve('chat/completions'),
      base.replace(queryParameters: {...base.queryParameters, 'path': 'chat/completions'}),
      if (base.host.contains('cloudfunctions.net')) _cfRoot(base).resolve('openaiProxy/chat/completions'),
      Uri.parse(_defaultProxyEndpoint).resolve('chat/completions'),
    ];

    http.Response? good;
    for (final uri in candidates) {
      try {
        final resp = await http.post(
          uri,
          headers: {
            if (openAiApiKey.isNotEmpty) 'Authorization': 'Bearer $openAiApiKey',
            'Content-Type': 'application/json',
            'Accept': 'application/json',
            'X-OpenAI-Path': 'chat/completions',
          },
          body: body,
        );
        if (resp.statusCode == 200) {
          good = resp;
          break;
        }
        debugPrint('Prompt attempt ${uri.toString()} -> ${resp.statusCode}: ${utf8.decode(resp.bodyBytes, allowMalformed: true)}');
      } catch (e) {
        debugPrint('Prompt attempt failed for ${uri.toString()}: $e');
      }
    }

    if (good != null) {
      final decoded = json.decode(utf8.decode(good!.bodyBytes)) as Map<String, dynamic>;
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

    debugPrint('OpenAI generate prompt failed for all URL shapes.');
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
    final base = _resolvedBaseEndpoint();
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
    Uri _cfRoot(Uri u) => Uri.parse('${u.scheme}://${u.host}/');
    final candidates = <Uri>[
      base.resolve('chat/completions'),
      base.replace(queryParameters: {...base.queryParameters, 'path': 'chat/completions'}),
      if (base.host.contains('cloudfunctions.net')) _cfRoot(base).resolve('openaiProxy/chat/completions'),
      Uri.parse(_defaultProxyEndpoint).resolve('chat/completions'),
    ];

    http.Response? good;
    for (final uri in candidates) {
      try {
        final resp = await http.post(
          uri,
          headers: {
            if (openAiApiKey.isNotEmpty) 'Authorization': 'Bearer $openAiApiKey',
            'Content-Type': 'application/json',
            'Accept': 'application/json',
            'X-OpenAI-Path': 'chat/completions',
          },
          body: body,
        );
        if (resp.statusCode == 200) {
          good = resp;
          break;
        }
        debugPrint('Translate attempt ${uri.toString()} -> ${resp.statusCode}: ${utf8.decode(resp.bodyBytes, allowMalformed: true)}');
      } catch (e) {
        debugPrint('Translate attempt failed for ${uri.toString()}: $e');
      }
    }

    if (good != null) {
      final decoded = json.decode(utf8.decode(good!.bodyBytes)) as Map<String, dynamic>;
      final content = ((decoded['choices'] as List).first as Map)['message']['content'] as String?;
      return content?.trim();
    }
    debugPrint('OpenAI translate failed for all URL shapes.');
    return null;
  } catch (e) {
    debugPrint('OpenAI translate error: $e');
    return null;
  }
}
