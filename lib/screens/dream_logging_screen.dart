import 'dart:async';
import 'dart:io' show File;
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart' as firebase_auth;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_sound/flutter_sound.dart';
import 'package:go_router/go_router.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

import 'package:dreamweaver/models/dream_model.dart';
import 'package:dreamweaver/services/dream_service.dart';
import 'package:dreamweaver/services/functions_service.dart';
import 'package:dreamweaver/services/openai_audio_service.dart';
import 'package:dreamweaver/services/storage_service.dart';
import 'package:dreamweaver/services/language_service.dart';
import 'package:dreamweaver/services/analytics_service.dart';
import 'package:dreamweaver/services/user_service.dart';
import 'package:dreamweaver/widgets/translated_text.dart';

/// Optional prefill when starting from a Daily Prompt
class DreamLogPrefill {
  final String promptId;
  final String promptText;
  final String? theme;
  final List<String>? tags;
  const DreamLogPrefill({
    required this.promptId,
    required this.promptText,
    this.theme,
    this.tags,
  });
}

class DreamLoggingScreen extends StatefulWidget {
  final DreamLogPrefill? prefill;
  const DreamLoggingScreen({super.key, this.prefill});

  @override
  State<DreamLoggingScreen> createState() => _DreamLoggingScreenState();
}

class _DreamLoggingScreenState extends State<DreamLoggingScreen> {
  final _textController = TextEditingController();
  final _titleController = TextEditingController();
  final _focusNode = FocusNode();

  // STT (for live preview)
  final stt.SpeechToText _stt = stt.SpeechToText();
  bool _sttAvailable = false;
  String _partialTranscript = '';

  // Recording
  final FlutterSoundRecorder _recorder = FlutterSoundRecorder();
  bool _isRecording = false;
  String? _recordedFilePath; // local temp path

  // UI state
  bool _saving = false;
  double _estimatedSeconds = 30;

  // Emoji suggestions
  static const List<String> _emojis = [
    '😴', '😱', '😢', '😍', '😡', '🤯', '🌊', '🐍', '🕳️', '🌀', '🌙', '✨', '🔥', '🌧️', '🏃',
  ];

  @override
  void initState() {
    super.initState();
    _initStt();
    if (!kIsWeb) {
      _recorder.openRecorder();
    }
    // If prefill exists, show the keyboard to start typing and optionally seed title
    if (widget.prefill != null) {
      // Defer setting controller text to after first frame
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        // Keep main text empty to let user write, but we can hint via banner
        if (widget.prefill!.theme != null && _titleController.text.isEmpty) {
          final theme = widget.prefill!.theme!;
          _titleController.text = 'On: $theme';
        }
      });
    }
  }

  Future<void> _initStt() async {
    try {
      _sttAvailable = await _stt.initialize(
        onStatus: (s) => debugPrint('STT status: $s'),
        onError: (e) => debugPrint('STT error: $e'),
      );
      setState(() {});
    } catch (e) {
      debugPrint('STT init error: $e');
    }
  }

  @override
  void dispose() {
    _textController.dispose();
    _titleController.dispose();
    _focusNode.dispose();
    _stt.stop();
    if (!kIsWeb) {
      _recorder.closeRecorder();
    }
    super.dispose();
  }

  Future<void> _toggleRecord() async {
    if (_isRecording) {
      await _stopRecording();
      return;
    }
    await _startRecording();
  }

  Future<void> _startRecording() async {
    if (kIsWeb) {
      // On web, flutter_sound recording is unreliable; use STT only.
      if (_sttAvailable) {
        final lang = context.read<LanguageService>().languageCode;
        await _stt.listen(
          onResult: (r) => setState(() => _partialTranscript = r.recognizedWords),
          listenMode: stt.ListenMode.dictation,
          localeId: lang,
        );
      }
      setState(() => _isRecording = true);
      return;
    }

    // Request mic permission
    final status = await Permission.microphone.request();
    if (!status.isGranted) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Microphone permission denied')),
        );
      }
      return;
    }

    try {
      final dir = await getTemporaryDirectory();
      final path = '${dir.path}/dream_record.m4a';
      _recordedFilePath = path;
      await _recorder.startRecorder(toFile: path, codec: Codec.aacADTS, bitRate: 128000, sampleRate: 44100);
      if (_sttAvailable) {
        final lang = context.read<LanguageService>().languageCode;
        await _stt.listen(
          onResult: (r) => setState(() => _partialTranscript = r.recognizedWords),
          listenMode: stt.ListenMode.dictation,
          localeId: lang,
        );
      }
      setState(() => _isRecording = true);
    } catch (e) {
      debugPrint('Start recording error: $e');
    }
  }

  Future<void> _stopRecording() async {
    try {
      if (_stt.isListening) {
        await _stt.stop();
      }
      if (!_isRecording) return;
      final path = await _recorder.stopRecorder();
      setState(() => _isRecording = false);
      // Transcribe if file exists
      if (!kIsWeb) {
        final filePath = path ?? _recordedFilePath;
        if (filePath != null) {
          final file = File(filePath);
          final bytes = await file.readAsBytes();
          final text = await OpenAIAudioService.instance.transcribeBytes(
            bytes: bytes,
            fileName: 'record.m4a',
            mimeType: 'audio/m4a',
            language: context.read<LanguageService>().languageCode,
          );
          if (text != null && text.trim().isNotEmpty) {
            _mergeTranscript(text);
          } else if (_partialTranscript.isNotEmpty) {
            _mergeTranscript(_partialTranscript);
          }
        }
      } else {
        if (_partialTranscript.isNotEmpty) {
          _mergeTranscript(_partialTranscript);
        }
      }
    } catch (e) {
      debugPrint('Stop recording/transcribe error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Transcription failed')),
        );
      }
    }
  }

  void _mergeTranscript(String text) {
    final current = _textController.text.trim();
    final combined = current.isEmpty ? text.trim() : '$current ${text.trim()}';
    _textController.text = combined;
    _textController.selection = TextSelection.fromPosition(TextPosition(offset: _textController.text.length));
    setState(() => _partialTranscript = '');
    _recomputeEta();
  }

  void _insertEmoji(String e) {
    final text = _textController.text;
    final sel = _textController.selection;
    final start = sel.start >= 0 ? sel.start : text.length;
    final end = sel.end >= 0 ? sel.end : text.length;
    final newText = text.replaceRange(start, end, '$e ');
    _textController.text = newText;
    _textController.selection = TextSelection.fromPosition(TextPosition(offset: start + e.length + 1));
  }

  void _recomputeEta() {
    final len = _textController.text.length;
    // Heuristic: 15–60s based on text length
    final est = 15 + (len / 300 * 45);
    setState(() => _estimatedSeconds = est.clamp(15, 90));
  }

  Future<void> _save() async {
    if (_saving) return;
    final user = firebase_auth.FirebaseAuth.instance.currentUser;
    if (user == null) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please sign in first')));
      return;
    }
    final dreamService = context.read<DreamService>();
    final functions = FunctionsService();
    final storage = StorageService();

    final now = DateTime.now();
    final rawText = _textController.text.trim();
    if (rawText.isEmpty) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please add some text')));
      return;
    }

    final titleFromText = _titleController.text.trim().isEmpty
        ? _deriveTitle(rawText)
        : _titleController.text.trim();

    final draft = DreamModel(
      id: 'temp',
      ownerId: user.uid,
      title: titleFromText,
      description: rawText,
      tags: const [],
      audioUrl: null,
      imageUrl: null,
      dreamDate: now,
      createdAt: now,
      updatedAt: now,
      metadata: {
        'status': 'processing',
        'processing': true,
        'progress': 0.05,
        'rawText': rawText,
        'inputMethod': _recordedFilePath != null ? 'voice' : (_sttAvailable ? 'voice_stt' : 'text'),
        'timelineEstSec': _estimatedSeconds,
        if (widget.prefill != null) ...{
          'source': 'prompt',
          'promptId': widget.prefill!.promptId,
          'promptText': widget.prefill!.promptText,
          if (widget.prefill!.theme != null) 'promptTheme': widget.prefill!.theme,
          if (widget.prefill!.tags != null) 'promptTags': widget.prefill!.tags,
        },
      },
    );

    setState(() => _saving = true);
    try {
      final dreamId = await dreamService.createDream(draft);
      // Update daily usage and analytics summary counters for dreams
      try {
        await context.read<UserService>().incrementDailyDreams(user.uid);
      } catch (e) {
        debugPrint('incrementDailyDreams error: $e');
      }

      // Upload audio if present
      String? audioUrl;
      Uint8List? audioBytes;
      if (!kIsWeb && _recordedFilePath != null) {
        try {
          final bytes = await File(_recordedFilePath!).readAsBytes();
          audioBytes = bytes;
          audioUrl = await storage.uploadBytes(
            bytes,
            'users/${user.uid}/audio/$dreamId.m4a',
            contentType: 'audio/m4a',
            metadata: {
              'dreamId': dreamId,
              'createdAt': now.toIso8601String(),
            },
          );
        } catch (e) {
          debugPrint('Audio upload error: $e');
        }
      }

      // Update dream with audioUrl if uploaded
      if (audioUrl != null) {
        await FirebaseFirestore.instance.collection('dreams').doc(dreamId).update({
          'audioUrl': audioUrl,
          'metadata.audioBytesLength': audioBytes?.length ?? 0,
        });
      }

      // Trigger processing function (server will do GPT, probes, etc.)
      try {
        await functions.processDream({'dreamId': dreamId, 'ownerId': user.uid});
      } catch (e) {
        debugPrint('processDream callable failed: $e');
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Dream saved. Processing (~${_estimatedSeconds.toStringAsFixed(0)}s)...')),
        );
        // Log analytics event (fire-and-forget)
        final method = _recordedFilePath != null
            ? 'voice'
            : (_sttAvailable ? 'voice_stt' : 'text');
        final fromPrompt = widget.prefill != null;
        unawaited(AnalyticsService.instance.logDreamLogged(
          dreamId: dreamId,
          method: method,
          lengthChars: rawText.length,
          fromPrompt: fromPrompt,
        ));
        context.push('/insights/$dreamId');
      }
    } catch (e) {
      debugPrint('Save dream error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Failed to save dream')));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  String _deriveTitle(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return 'Untitled Dream';
    final first = trimmed.split(RegExp(r'[\.!?\n]')).first.trim();
    return first.length > 60 ? '${first.substring(0, 57)}…' : first;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const TranslatedText('Log Dream', contextKey: 'appbar.log_dream'),
        centerTitle: true,
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _saving ? null : _toggleRecord,
        icon: Icon(_isRecording ? Icons.stop : Icons.mic, color: Colors.white),
        label: TranslatedText(_isRecording ? 'Stop' : 'Speak', contextKey: 'fab.record'),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 120),
          children: [
            if (widget.prefill != null) ...[
              Card(
                clipBehavior: Clip.antiAlias,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.lightbulb, color: theme.colorScheme.primary),
                          const SizedBox(width: 8),
                          const TranslatedText('Prompt', contextKey: 'label.prompt'),
                          const Spacer(),
                          if (widget.prefill!.theme != null)
                            Chip(
                              label: Text(widget.prefill!.theme!),
                              avatar: const Icon(Icons.label_important, size: 16),
                            ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(widget.prefill!.promptText, style: theme.textTheme.bodyMedium),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
            ],
            // Title
            TextField(
              controller: _titleController,
              decoration: const InputDecoration(
                labelText: 'Title (optional)',
                prefixIcon: Icon(Icons.title),
              ),
              textInputAction: TextInputAction.next,
            ),
            const SizedBox(height: 12),
            // Live transcript / text input
            Card(
              clipBehavior: Clip.antiAlias,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.keyboard_alt_outlined, color: theme.colorScheme.primary),
                        const SizedBox(width: 8),
                        const TranslatedText('Describe your dream', contextKey: 'label.describe'),
                        const Spacer(),
                        if (_isRecording)
                          Row(children: [
                            const SizedBox(width: 8),
                            _PulseDot(color: theme.colorScheme.error),
                            const SizedBox(width: 6),
                            TranslatedText('Listening…', contextKey: 'label.listening', style: theme.textTheme.labelSmall),
                          ]),
                      ],
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _textController,
                      focusNode: _focusNode,
                      onChanged: (_) => _recomputeEta(),
                      decoration: const InputDecoration(
                        border: InputBorder.none,
                        hintText: 'Start speaking or type here…',
                      ),
                      maxLines: 10,
                      minLines: 5,
                    ),
                    if (_partialTranscript.isNotEmpty && _isRecording) ...[
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Icon(Icons.auto_fix_high, size: 18),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                _partialTranscript,
                                style: theme.textTheme.bodySmall,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            // Emojis
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _emojis
                  .map((e) => ChoiceChip(
                        label: Text(e),
                        selected: false,
                        onSelected: (_) => _insertEmoji(e),
                      ))
                  .toList(),
            ),
            const SizedBox(height: 16),
            // Timeline estimate + save
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.schedule, color: theme.colorScheme.primary),
                        const SizedBox(width: 8),
                        const TranslatedText('Processing timeline', contextKey: 'label.timeline'),
                        const Spacer(),
                        Text('~${_estimatedSeconds.toStringAsFixed(0)}s', style: theme.textTheme.labelSmall),
                      ],
                    ),
                    const SizedBox(height: 8),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: LinearProgressIndicator(
                        value: (_estimatedSeconds / 90).clamp(0.15, 0.9),
                        minHeight: 8,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                            child: FilledButton.icon(
                            onPressed: _saving ? null : _save,
                            icon: const Icon(Icons.check, color: Colors.white),
                              label: TranslatedText(_saving ? 'Saving…' : 'Save & Process', contextKey: 'button.save'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PulseDot extends StatefulWidget {
  final Color color;
  const _PulseDot({required this.color});

  @override
  State<_PulseDot> createState() => _PulseDotState();
}

class _PulseDotState extends State<_PulseDot> with SingleTickerProviderStateMixin {
  late final AnimationController _controller =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 900))..repeat(reverse: true);
  late final Animation<double> _anim = Tween<double>(begin: 0.6, end: 1.0).animate(
    CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ScaleTransition(
      scale: _anim,
      child: Icon(Icons.circle, size: 10, color: widget.color),
    );
  }
}
