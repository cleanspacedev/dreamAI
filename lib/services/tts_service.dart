import 'dart:typed_data';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_sound/flutter_sound.dart';
import 'package:dreamweaver/openai/openai_config.dart' as openai;
import 'package:web/web.dart' as web;

/// TTS service powered by OpenAI Audio API (speech synthesis) with local playback.
class TTSService {
  TTSService._();
  static final TTSService instance = TTSService._();

  final FlutterSoundPlayer _player = FlutterSoundPlayer();
  web.HTMLAudioElement? _htmlAudio; // Web-only playback
  bool _initialized = false;
  String _style = 'default';
  String? _language; // kept for future prompt conditioning, currently not sent
  bool _isPlaying = false;

  Future<void> _ensureInit() async {
    if (_initialized) return;
    try {
      if (kIsWeb) {
        _htmlAudio = web.HTMLAudioElement();
        _htmlAudio!.controls = false;
        _htmlAudio!.volume = 1.0;
        _htmlAudio!.onEnded.listen((_) {
          _isPlaying = false;
        });
      } else {
        await _player.openPlayer();
      }
      _initialized = true;
    } catch (e) {
      debugPrint('TTS init error: $e');
    }
  }

  Future<void> setLanguage(String langCode) async {
    await _ensureInit();
    _language = langCode;
    // OpenAI voices are multi-lingual; we keep the hint for future use.
  }

  /// Speak arbitrary text using OpenAI TTS and play as MP3.
  Future<void> speak(String text) async {
    await _ensureInit();
    try {
      final voice = _voiceForStyle(_style);
      final Uint8List? bytes = await openai.openAiTtsSynthesize(
        text: text,
        model: 'gpt-4o-mini-tts',
        voice: voice,
        format: 'mp3',
      );
      if (bytes == null) {
        debugPrint('OpenAI TTS returned no audio.');
        return;
      }
      if (kIsWeb) {
        // Stop current playback
        if (_htmlAudio != null) {
          try { _htmlAudio!.pause(); } catch (_) {}
        }
        final b64 = base64Encode(bytes);
        _htmlAudio!.src = 'data:audio/mpeg;base64,' + b64;
        // Fire and forget; web.play() returns a Promise
        _htmlAudio!.play();
        _isPlaying = true;
      } else {
        await _player.stopPlayer();
        await _player.startPlayer(
          fromDataBuffer: bytes,
          codec: Codec.mp3,
          whenFinished: () => _isPlaying = false,
        );
        _isPlaying = true;
      }
    } catch (e) {
      debugPrint('TTS speak error: $e');
    }
  }

  /// Apply a voice style and speak a short sample so user can preview.
  Future<void> speakSampleForStyle(String style) async {
    await _ensureInit();
    try {
      _style = style;
      final sample = switch (style) {
        'warm' => 'Hi! This is the warm voice, gentle and friendly.',
        'bright' => 'Hello! This is the bright voice, energetic and clear.',
        'calm' => 'Hello. This is the calm voice, relaxed and steady.',
        _ => 'Hi there! This is the default voice.',
      };
      await speak(sample);
    } catch (e) {
      debugPrint('TTS speakSampleForStyle error: $e');
    }
  }

  Future<void> setStyle(String style) async {
    await _ensureInit();
    _style = style;
  }

  /// Map style to an OpenAI voice id.
  String _voiceForStyle(String style) {
    switch (style) {
      case 'warm':
        return 'alloy';
      case 'bright':
        return 'verse';
      case 'calm':
        return 'aria';
      default:
        return 'alloy';
    }
  }

  Future<void> stop() async {
    try {
      if (kIsWeb) {
        if (_htmlAudio != null) {
          try { _htmlAudio!.pause(); } catch (_) {}
          _htmlAudio!.currentTime = 0;
        }
        _isPlaying = false;
      } else {
        await _player.stopPlayer();
        _isPlaying = false;
      }
    } catch (e) {
      debugPrint('TTS stop error: $e');
    }
  }

  bool get isPlaying => _isPlaying;
}
