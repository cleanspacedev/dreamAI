import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart' as firebase_auth;
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:go_router/go_router.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';
import 'package:flutter_sound/flutter_sound.dart';
import 'package:path_provider/path_provider.dart';

import 'package:dreamweaver/auth/firebase_auth_manager.dart';
import 'package:dreamweaver/services/openai_audio_service.dart';
import 'package:dreamweaver/services/tts_service.dart';
import 'package:dreamweaver/services/user_service.dart';
import 'package:dreamweaver/models/user_model.dart';
import 'package:dreamweaver/nav.dart';
import 'package:dreamweaver/services/language_service.dart';

class OnboardingWizard extends StatefulWidget {
  const OnboardingWizard({super.key});

  @override
  State<OnboardingWizard> createState() => _OnboardingWizardState();
}

class _OnboardingWizardState extends State<OnboardingWizard> {
  final PageController _controller = PageController();
  int _index = 0;

  // Step 1
  final TextEditingController _emailCtrl = TextEditingController();
  final TextEditingController _passCtrl = TextEditingController();
  bool _isSignUp = false;
  bool _authLoading = false;

  // Step 2
  final FlutterSoundRecorder _recorder = FlutterSoundRecorder();
  bool _isRecording = false;
  bool _recorderReady = false;
  String? _transcription;
  bool _transcribing = false;
  String? _recordPath;

  // Step 3
  String _theme = 'system'; // default to system, configurable later in Settings
  String _voiceStyle = 'default';
  String _language = WidgetsBinding.instance.platformDispatcher.locale.languageCode; // autodetected
  bool _savingPrefs = false;

  @override
  void initState() {
    super.initState();
    _initRecorder();
    // Narrate first step
    WidgetsBinding.instance.addPostFrameCallback((_) {
      TTSService.instance.speak('Welcome. Let\'s get you set up in three quick steps.');
    });
  }

  Future<void> _initRecorder() async {
    try {
      if (!kIsWeb) {
        await _recorder.openRecorder();
      }
      if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) {
        final status = await Permission.microphone.request();
        if (!status.isGranted) {
          debugPrint('Microphone permission not granted');
        }
      }
      setState(() => _recorderReady = true);
    } catch (e) {
      debugPrint('Recorder init error: $e');
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _emailCtrl.dispose();
    _passCtrl.dispose();
    if (!kIsWeb) {
      _recorder.closeRecorder();
    }
    super.dispose();
  }

  void _goNext() {
    if (_index < 2) {
      _controller.nextPage(duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
    }
  }

  void _goBack() {
    if (_index > 0) {
      _controller.previousPage(duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
    }
  }

  Future<void> _handleEmailAuth(FirebaseAuthManager auth) async {
    setState(() => _authLoading = true);
    firebase_auth.User? user;
    if (_isSignUp) {
      user = await auth.createAccountWithEmail(context, _emailCtrl.text.trim(), _passCtrl.text.trim());
    } else {
      user = await auth.signInWithEmail(context, _emailCtrl.text.trim(), _passCtrl.text.trim());
    }
    setState(() => _authLoading = false);
    if (user != null && mounted) {
      TTSService.instance.speak('Signed in. Nice!');
      _goNext();
    }
  }

  Future<void> _handleGoogle(FirebaseAuthManager auth) async {
    setState(() => _authLoading = true);
    final user = await auth.signInWithGoogle(context);
    setState(() => _authLoading = false);
    if (user != null && mounted) {
      TTSService.instance.speak('Google sign in successful.');
      _goNext();
    }
  }

  Future<void> _handleAnon(FirebaseAuthManager auth) async {
    setState(() => _authLoading = true);
    final user = await auth.signInAnonymously(context);
    setState(() => _authLoading = false);
    if (user != null && mounted) {
      TTSService.instance.speak('Continuing as guest.');
      _goNext();
    }
  }

  Future<void> _toggleRecording() async {
    if (!_recorderReady) return;
    if (kIsWeb) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Voice recording is not supported on web in this build.')),
      );
      return;
    }
    if (_isRecording) {
      final path = await _recorder.stopRecorder();
      setState(() {
        _isRecording = false;
        _recordPath = path;
      });
    } else {
      try {
        String filePath = 'onboarding_record.m4a';
        if (!kIsWeb) {
          final tmpDir = await getTemporaryDirectory();
          filePath = '${tmpDir.path}/onboarding_${DateTime.now().millisecondsSinceEpoch}.m4a';
        }
        await _recorder.startRecorder(
          toFile: filePath,
          codec: Codec.aacMP4,
        );
        setState(() {
          _isRecording = true;
          _transcription = null;
        });
      } catch (e) {
        debugPrint('Start recording error: $e');
      }
    }
  }

  Future<void> _transcribe() async {
    if (_recordPath == null) return;
    setState(() => _transcribing = true);
    try {
      Uint8List bytes;
      if (kIsWeb) {
        debugPrint('Recorded path on web: $_recordPath');
        // On web, some recorders return base64-like URLs; unsupported here
        setState(() {
          _transcription = 'Recording not supported on web in this build.';
        });
        return;
      } else {
        bytes = await File(_recordPath!).readAsBytes();
      }
      final text = await OpenAIAudioService.instance.transcribeBytes(
        bytes: bytes,
        fileName: 'voice.m4a',
        mimeType: 'audio/m4a',
        language: _language,
      );
      setState(() => _transcription = text ?? 'No transcription received.');
      if (text != null && text.isNotEmpty) {
        TTSService.instance.speak('I heard: $text');
      }
    } catch (e) {
      debugPrint('Transcription failed: $e');
      setState(() => _transcription = 'Transcription failed.');
    } finally {
      setState(() => _transcribing = false);
    }
  }

  Future<void> _savePreferences() async {
    setState(() => _savingPrefs = true);
    try {
      final user = firebase_auth.FirebaseAuth.instance.currentUser;
      if (user == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Please sign in to save preferences.')),
          );
        }
        return;
      }
      final userService = context.read<UserService>();
      final snap = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
      final existing = snap.data() ?? {};
      final model = UserModel.fromJson({
        ...existing,
        'userId': user.uid,
        'email': user.email ?? existing['email'] ?? '',
        'createdAt': existing['createdAt'] ?? Timestamp.now(),
        'preferences': {
          ...(existing['preferences'] as Map? ?? {}),
          'theme': _theme,
          'voiceStyle': _voiceStyle,
          'language': _language,
          'onboarded': true,
        },
        'language': _language,
      });
      await userService.createOrMergeUser(model);
      // Apply language immediately in app UI
      try {
        if (mounted) await context.read<LanguageService>().setLanguage(_language);
      } catch (e) {
        debugPrint('Apply language error: $e');
      }
      if (mounted) {
        context.go(AppRoutes.home);
      }
    } catch (e) {
      debugPrint('Save preferences failed: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not save preferences.')),
        );
      }
    } finally {
      setState(() => _savingPrefs = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.read<FirebaseAuthManager>();
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Welcome'),
        actions: [
          TextButton(
            onPressed: () => context.go(AppRoutes.home),
            child: const Text('Skip'),
          ),
        ],
      ),
      body: Column(
        children: [
          const SizedBox(height: 8),
          _Indicators(index: _index, count: 3),
          const SizedBox(height: 8),
          Expanded(
            child: PageView(
              controller: _controller,
              onPageChanged: (i) async {
                setState(() => _index = i);
                if (i == 1) {
                  await TTSService.instance.speak('Step two. Say something and I will transcribe it.');
                } else if (i == 2) {
                  await TTSService.instance.speak('Final step. Choose a voice style you like.');
                }
              },
              children: [
                _buildAuthStep(auth, theme),
                _buildVoiceStep(theme),
                _buildVoiceStyleStep(theme),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: Row(
              children: [
                if (_index > 0)
                  OutlinedButton.icon(
                    onPressed: _goBack,
                    icon: const Icon(Icons.arrow_back, color: Colors.white),
                    label: const Text('Back'),
                  ),
                const Spacer(),
                if (_index < 2)
                  FilledButton.icon(
                    onPressed: () => _goNext(),
                    icon: const Icon(Icons.arrow_forward, color: Colors.white),
                    label: const Text('Next'),
                  )
                else
                  FilledButton.icon(
                    onPressed: _savingPrefs ? null : _savePreferences,
                    icon: const Icon(Icons.check_circle, color: Colors.white),
                    label: Text(_savingPrefs ? 'Saving...' : 'Finish'),
                  ),
              ],
            ),
          )
        ],
      ),
    );
  }

  Widget _buildAuthStep(FirebaseAuthManager auth, ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Step 1 of 3', style: theme.textTheme.titleLarge),
              const SizedBox(height: 8),
              Text('Sign in to sync your dreams across devices.', style: theme.textTheme.bodyMedium),
              const SizedBox(height: 24),
              TextField(
                controller: _emailCtrl,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(
                  labelText: 'Email',
                  prefixIcon: Icon(Icons.email),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _passCtrl,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'Password',
                  prefixIcon: Icon(Icons.lock),
                ),
              ),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: _authLoading ? null : () => _handleEmailAuth(auth),
                child: Text(_authLoading ? 'Please wait...' : (_isSignUp ? 'Create account' : 'Sign in')),
              ),
              TextButton(
                onPressed: () => setState(() => _isSignUp = !_isSignUp),
                child: Text(_isSignUp ? 'Have an account? Sign in' : 'New here? Create an account'),
              ),
              const Divider(height: 32),
              FilledButton.icon(
                onPressed: _authLoading ? null : () => _handleGoogle(auth),
                icon: const Icon(Icons.login, color: Colors.white),
                label: const Text('Continue with Google'),
              ),
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed: _authLoading ? null : () => _handleAnon(auth),
                child: const Text('Continue as guest'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildVoiceStep(ThemeData theme) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 960),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('Step 2 of 3', style: theme.textTheme.titleLarge),
                  const SizedBox(height: 8),
                  Text(
                    'Record a short phrase, then we\'ll transcribe it so you can confirm audio works.',
                    style: theme.textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 16),
                  Expanded(
                    child: Card(
                      clipBehavior: Clip.antiAlias,
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              _isRecording ? 'Listening...' : 'Tap to record',
                              style: theme.textTheme.titleLarge,
                            ),
                            const SizedBox(height: 20),
                            SizedBox(
                              height: 120,
                              child: AspectRatio(
                                aspectRatio: 1,
                                child: InkResponse(
                                  radius: 120,
                                  onTap: !_recorderReady ? null : _toggleRecording,
                                  child: AnimatedContainer(
                                    duration: const Duration(milliseconds: 250),
                                    decoration: BoxDecoration(
                                      color: _isRecording
                                          ? theme.colorScheme.primary.withValues(alpha: 0.15)
                                          : theme.colorScheme.surfaceContainerHighest,
                                      shape: BoxShape.circle,
                                      border: Border.all(color: theme.colorScheme.primary, width: 2),
                                    ),
                                    child: Center(
                                      child: Icon(
                                        _isRecording ? Icons.stop : Icons.mic,
                                        size: 48,
                                        color: theme.colorScheme.primary,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 24),
                            FilledButton.icon(
                              onPressed: (_recordPath != null && !_transcribing) ? _transcribe : null,
                              icon: const Icon(Icons.auto_awesome, color: Colors.white),
                              label: Text(_transcribing ? 'Transcribing…' : 'Transcribe recording'),
                            ),
                            const SizedBox(height: 20),
                            if (_transcription != null)
                              Container(
                                width: double.infinity,
                                padding: const EdgeInsets.all(16),
                                decoration: BoxDecoration(
                                  color: theme.colorScheme.surfaceContainerLow,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Text(
                                  _transcription!,
                                  style: theme.textTheme.bodyMedium,
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildVoiceStyleStep(ThemeData theme) {
    final voices = const [
      ('default', Icons.record_voice_over, 'Balanced, natural narration'),
      ('warm', Icons.wb_twilight, 'Gentle and friendly tone'),
      ('bright', Icons.waves, 'Energetic and clear delivery'),
      ('calm', Icons.self_improvement, 'Relaxed and steady pacing'),
    ];
    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth > 720;
        final crossAxisCount = isWide ? 2 : 1;
        return Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1000),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('Step 3 of 3', style: theme.textTheme.titleLarge),
                  const SizedBox(height: 8),
                  Text('Choose a voice style. We\'ll play a quick sample.', style: theme.textTheme.bodyMedium),
                  const SizedBox(height: 16),
                  Expanded(
                    child: GridView.builder(
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: crossAxisCount,
                        crossAxisSpacing: 16,
                        mainAxisSpacing: 16,
                        childAspectRatio: isWide ? 2.6 : 2.0,
                      ),
                      itemCount: voices.length,
                      itemBuilder: (context, idx) {
                        final (id, icon, desc) = voices[idx];
                        final selected = _voiceStyle == id;
                        return InkWell(
                          borderRadius: BorderRadius.circular(16),
                          onTap: () async {
                            setState(() => _voiceStyle = id);
                            await TTSService.instance.speakSampleForStyle(id);
                          },
                          child: Card(
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                              side: BorderSide(
                                color: selected
                                    ? theme.colorScheme.primary
                                    : theme.colorScheme.outline.withValues(alpha: 0.25),
                              ),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.all(20),
                              child: Row(
                                children: [
                                  Container(
                                    width: 56,
                                    height: 56,
                                    decoration: BoxDecoration(
                                      color: theme.colorScheme.primary.withValues(alpha: 0.12),
                                      borderRadius: BorderRadius.circular(14),
                                    ),
                                    child: Icon(icon, color: theme.colorScheme.primary, size: 28),
                                  ),
                                  const SizedBox(width: 16),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        Text(_displayName(id), style: theme.textTheme.titleMedium),
                                        const SizedBox(height: 6),
                                        Text(desc, style: theme.textTheme.bodySmall),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  FilledButton.icon(
                                    onPressed: () async {
                                      setState(() => _voiceStyle = id);
                                      await TTSService.instance.speakSampleForStyle(id);
                                    },
                                    icon: const Icon(Icons.play_arrow, color: Colors.white),
                                    label: const Text('Preview'),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  String _displayName(String id) {
    switch (id) {
      case 'warm':
        return 'Warm';
      case 'bright':
        return 'Bright';
      case 'calm':
        return 'Calm';
      default:
        return 'Default';
    }
  }
}

class _Indicators extends StatelessWidget {
  final int index;
  final int count;
  const _Indicators({required this.index, required this.count});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (int i = 0; i < count; i++)
          AnimatedContainer(
            duration: const Duration(milliseconds: 250),
            margin: const EdgeInsets.symmetric(horizontal: 6),
            height: 8,
            width: i == index ? 20 : 8,
            decoration: BoxDecoration(
              color: i == index ? theme.colorScheme.primary : theme.colorScheme.outline.withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(99),
            ),
          ),
      ],
    );
  }
}
