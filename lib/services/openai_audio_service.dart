import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';

import 'package:dreamweaver/openai/openai_config.dart';

/// Service for sending audio to OpenAI's transcription API.
class OpenAIAudioService {
  OpenAIAudioService._();
  static final OpenAIAudioService instance = OpenAIAudioService._();

  /// Transcribe raw audio bytes using OpenAI's Audio Transcriptions API.
  ///
  /// [bytes]: Raw audio data
  /// [fileName]: Suggested filename with appropriate extension (e.g. record.m4a)
  /// [mimeType]: Content type, e.g. audio/m4a, audio/mp3, audio/wav
  /// [language]: Optional language hint (e.g. 'en')
  /// [model]: Transcription model. Defaults to 'gpt-4o-mini-transcribe' with fallback to 'whisper-1'.
  Future<String?> transcribeBytes({
    required Uint8List bytes,
    String fileName = 'audio.m4a',
    String mimeType = 'audio/m4a',
    String? language,
    String? model,
  }) async {
    if (!hasOpenAiConfig) {
      debugPrint('OpenAI config missing. Set OPENAI_PROXY_API_KEY and OPENAI_PROXY_ENDPOINT.');
      return null;
    }

    final usedModel = model?.trim().isNotEmpty == true
        ? model!.trim()
        : 'gpt-4o-mini-transcribe'; // As of 2025-12 preferred; falls back below

    final uri = openAiBase().resolve('audio/transcriptions');

    final request = http.MultipartRequest('POST', uri)
      ..headers.addAll({
        if (openAiApiKey.isNotEmpty) 'Authorization': 'Bearer $openAiApiKey',
      })
      ..fields['model'] = usedModel
      ..files.add(
        http.MultipartFile.fromBytes(
          'file',
          bytes,
          filename: fileName,
          contentType: MediaType.parse(mimeType),
        ),
      );

    if (language != null && language.isNotEmpty) {
      request.fields['language'] = language;
    }

    try {
      final streamed = await request.send();
      final response = await http.Response.fromStream(streamed);
      if (response.statusCode == 200) {
        final data = jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
        // API returns {'text': '...'} for plain JSON responses
        return data['text'] as String?;
      }

      // Fallback: try legacy endpoint/model if server returns 400 about model
      if (response.statusCode == 400 && !usedModel.contains('whisper-1')) {
        debugPrint('Primary model failed (${response.statusCode}). Retrying with whisper-1. Body: ${response.body}');
        return await transcribeBytes(
          bytes: bytes,
          fileName: fileName,
          mimeType: mimeType,
          language: language,
          model: 'whisper-1',
        );
      }

      debugPrint('Transcription failed: ${response.statusCode} ${response.body}');
      return null;
    } catch (e) {
      debugPrint('Transcription error: $e');
      return null;
    }
  }
}
