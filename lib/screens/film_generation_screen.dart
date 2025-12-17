import 'dart:async';
import 'dart:io' show File, Platform;
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:video_player/video_player.dart';

import 'package:dreamweaver/services/functions_service.dart';
import 'package:dreamweaver/services/billing_service.dart';
import 'package:dreamweaver/services/freemium_service.dart';
import 'package:dreamweaver/services/analytics_service.dart';
import 'package:dreamweaver/widgets/paywall_sheet.dart';
import 'package:firebase_auth/firebase_auth.dart' as fb;

/// Film Generation & Playback screen
/// - Streams /dreams/{dreamId} for visual generation status
/// - Shows an animated timeline/progress until ready
/// - Plays MP4 when available with simple custom controls and fullscreen mode
/// - Falls back to image slideshow (e.g., DALL·E frames) when video is unavailable
/// - Provides Refine action to iterate generation
/// - Export/Share options with watermark overlay for images; shares link/file for video
class FilmGenerationScreen extends StatefulWidget {
  final String dreamId;
  const FilmGenerationScreen({super.key, required this.dreamId});

  @override
  State<FilmGenerationScreen> createState() => _FilmGenerationScreenState();
}

class _FilmGenerationScreenState extends State<FilmGenerationScreen> {
  VideoPlayerController? _video;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _sub;
  String? _lastStage;
  bool _muted = false;
  bool _initializingVideo = false;

  @override
  void initState() {
    super.initState();
    _sub = FirebaseFirestore.instance.collection('dreams').doc(widget.dreamId).snapshots().listen(_onDreamUpdate,
        onError: (e, st) => debugPrint('Film stream error: $e'));
  }

  @override
  void dispose() {
    _sub?.cancel();
    _disposeVideo();
    super.dispose();
  }

  void _disposeVideo() {
    final v = _video;
    if (v != null) {
      v.removeListener(_videoListener);
      v.dispose();
    }
    _video = null;
  }

  Future<void> _onDreamUpdate(DocumentSnapshot<Map<String, dynamic>> snap) async {
    final data = snap.data();
    final meta = data?['metadata'] as Map<String, dynamic>?;
    final visual = meta?['visual'] as Map<String, dynamic>?;
    final status = (visual?['status'] as String?) ?? meta?['visualStatus'] as String?;
    final stage = (visual?['stage'] as String?) ?? status;
    final videoUrl = (visual?['videoUrl'] as String?) ?? data?['videoUrl'] as String?;
    final images = (visual?['images'] as List?)?.whereType<String>().toList() ?? const <String>[];

    // Haptics on stage change
    if (stage != null && stage != _lastStage) {
      _lastStage = stage;
      try {
        HapticFeedback.selectionClick();
      } catch (_) {}
    }

    // Initialize video player when url first appears
    if (videoUrl != null && ( _video == null || _video!.dataSource != videoUrl)) {
      await _initVideo(videoUrl);
      try { HapticFeedback.heavyImpact(); } catch (_) {}
    }

    // If status failed and we have no video but have images, ensure video disposed
    if (videoUrl == null && images.isNotEmpty && _video != null) {
      _disposeVideo();
      setState(() {});
    }

    if (mounted) setState(() {});
  }

  Future<void> _initVideo(String url) async {
    if (_initializingVideo) return;
    _initializingVideo = true;
    try {
      _disposeVideo();
      final controller = VideoPlayerController.networkUrl(Uri.parse(url));
      await controller.initialize();
      controller.setLooping(true);
      controller.addListener(_videoListener);
      _video = controller;
      // Log analytics: first time video becomes available
      try {
        final secs = controller.value.duration.inSeconds;
        unawaited(AnalyticsService.instance.logVideoGenerated(
          dreamId: widget.dreamId,
          durationSeconds: secs,
          quality: 'standard',
        ));
      } catch (e) {
        debugPrint('analytics video_generated error: $e');
      }
    } catch (e) {
      debugPrint('Video init error: $e');
    } finally {
      _initializingVideo = false;
      if (mounted) setState(() {});
    }
  }

  void _videoListener() {
    if (!mounted) return;
    setState(() {});
  }

  Future<void> _refine(BuildContext context) async {
    final controller = TextEditingController();
    final style = ValueNotifier<String>('cinematic');
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) {
        final theme = Theme.of(ctx);
        return Padding(
          padding: EdgeInsets.only(
            left: 16,
            right: 16,
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 16,
            top: 16,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.tune, color: theme.colorScheme.primary),
                  const SizedBox(width: 8),
                  const Text('Refine Visual'),
                  const Spacer(),
                  IconButton(onPressed: () => Navigator.of(ctx).pop(), icon: const Icon(Icons.close)),
                ],
              ),
              const SizedBox(height: 8),
              TextField(
                controller: controller,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'What would you like to change?',
                  hintText: 'e.g., "More pastel colors, slower pacing, softer lighting"',
                ),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                children: [
                  for (final s in ['cinematic','dreamy','noir','watercolor','surreal'])
                    ValueListenableBuilder<String>(
                      valueListenable: style,
                      builder: (_, v, __) {
                        final selected = v == s;
                        return ChoiceChip(
                          label: Text(s),
                          selected: selected,
                          onSelected: (_) => style.value = s,
                        );
                      },
                    ),
                ],
              ),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: () async {
                  Navigator.of(ctx).pop();
                  final uid = fb.FirebaseAuth.instance.currentUser?.uid;
                  if (uid == null) return;
                  try {
                    final billing = BillingService.instance;
                    final tier = billing.currentTier();
                    final quotas = await FreemiumService().checkAndConsume(uid: uid, tier: tier);
                    if (!quotas.allowed) {
                      if (!mounted) return;
                      await showModalBottomSheet(
                        context: context,
                        isScrollControlled: true,
                        builder: (_) => PaywallSheet(reason: quotas.reason),
                      );
                      return;
                    }
                    await FunctionsService().generateDreamVisual({
                      'dreamId': widget.dreamId,
                      'refine': true,
                      'style': style.value,
                      'notes': controller.text.trim(),
                      'maxSeconds': quotas.maxSeconds,
                    });
                    if (!mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Refinement started')),
                    );
                  } catch (e) {
                    debugPrint('Refine error: $e');
                    if (!mounted) return;
                    ScaffoldMessenger.of(context)
                        .showSnackBar(const SnackBar(content: Text('Failed to start refinement')));
                  }
                },
                icon: const Icon(Icons.auto_fix_high, color: Colors.white),
                label: const Text('Start refinement'),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _exportShare({String? videoUrl, List<String> images = const []}) async {
    try {
      if (videoUrl != null) {
        // Try sharing the file on mobile; web falls back to sharing link
        if (kIsWeb) {
          await Share.share(videoUrl, subject: 'DreamWeaver film');
          return;
        }
        final temp = await _downloadToTemp(videoUrl, 'dream_film.mp4');
        if (temp != null) {
          await Share.shareXFiles([XFile(temp.path, mimeType: 'video/mp4', name: 'dream_film.mp4')],
              text: 'Made with DreamWeaver');
        } else {
          await Share.share(videoUrl, subject: 'DreamWeaver film');
        }
        return;
      }

      if (images.isNotEmpty) {
        // Build watermarked first image and share
        final bytes = await _buildWatermarkedImageBytes(images.first, watermark: 'DreamWeaver');
        if (bytes != null) {
          if (kIsWeb) {
            // On web, share as link instead after uploading? Fallback to share URL
            await Share.share(images.first, subject: 'DreamWeaver visual');
            return;
          }
          final dir = await getTemporaryDirectory();
          final file = File('${dir.path}/dreamweaver_visual.png');
          await file.writeAsBytes(bytes);
          await Share.shareXFiles([XFile(file.path, mimeType: 'image/png', name: 'dream_visual.png')],
              text: 'DreamWeaver • watermarked');
        } else {
          await Share.share(images.first, subject: 'DreamWeaver visual');
        }
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Nothing to share yet')));
    } catch (e) {
      debugPrint('Share error: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Share failed')));
    }
  }

  Future<File?> _downloadToTemp(String url, String filename) async {
    try {
      final resp = await http.get(Uri.parse(url));
      if (resp.statusCode == 200) {
        final dir = await getTemporaryDirectory();
        final file = File('${dir.path}/$filename');
        await file.writeAsBytes(resp.bodyBytes);
        return file;
      }
    } catch (e) {
      debugPrint('download error: $e');
    }
    return null;
  }

  Future<Uint8List?> _buildWatermarkedImageBytes(String url, {required String watermark}) async {
    try {
      final resp = await http.get(Uri.parse(url));
      if (resp.statusCode != 200) return null;
      final codec = await ui.instantiateImageCodec(resp.bodyBytes);
      final fi = await codec.getNextFrame();
      final image = fi.image;
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      final paint = Paint();
      // Draw base image
      canvas.drawImage(image, Offset.zero, paint);
      // Draw watermark text bottom-right
      final textPainter = TextPainter(
        text: TextSpan(
          text: watermark,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 24,
            fontWeight: FontWeight.w600,
            shadows: [Shadow(blurRadius: 3, color: Colors.black54, offset: Offset(1, 1))],
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      const padding = 12.0;
      final pos = Offset(image.width - textPainter.width - padding, image.height - textPainter.height - padding);
      textPainter.paint(canvas, pos);
      final picture = recorder.endRecording();
      final outImage = await picture.toImage(image.width, image.height);
      final bytes = await outImage.toByteData(format: ui.ImageByteFormat.png);
      return bytes?.buffer.asUint8List();
    } catch (e) {
      debugPrint('watermark build error: $e');
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final stream = FirebaseFirestore.instance.collection('dreams').doc(widget.dreamId).snapshots();
    return Scaffold(
      appBar: AppBar(
        title: const Text('Film'),
        centerTitle: true,
        actions: [
          IconButton(
            tooltip: 'Close',
            icon: const Icon(Icons.close, color: Colors.blue),
            onPressed: () => context.pop(),
          )
        ],
      ),
      body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: stream,
        builder: (context, snap) {
          final data = snap.data?.data();
          final meta = data?['metadata'] as Map<String, dynamic>?;
          final visual = meta?['visual'] as Map<String, dynamic>?;
          final status = (visual?['status'] as String?) ?? meta?['visualStatus'] as String? ?? 'queued';
          final progress = ((visual?['progress'] as num?)?.toDouble()) ?? 0.1;
          final stages = (visual?['stages'] as List?)?.whereType<Map>()
                  .map((e) => (e.cast<String, dynamic>()))
                  .toList() ??
              _defaultStages(status);
          final videoUrl = (visual?['videoUrl'] as String?) ?? data?['videoUrl'] as String?;
          final images = (visual?['images'] as List?)?.whereType<String>().toList() ?? const <String>[];

          final isReady = status == 'ready' && ((videoUrl != null) || images.isNotEmpty);

          return AnimatedSwitcher(
            duration: const Duration(milliseconds: 300),
            child: !isReady
                ? _BuildLoader(
                    key: const ValueKey('loader'),
                    progress: progress,
                    stages: stages,
                    onShare: () => _exportShare(images: images, videoUrl: videoUrl),
                  )
                : (videoUrl != null
                    ? _BuildVideo(
                        key: const ValueKey('video'),
                        controller: _video,
                        muted: _muted,
                        onTogglePlay: () async {
                          final v = _video;
                          if (v == null) return;
                          if (v.value.isPlaying) {
                            await v.pause();
                            try { HapticFeedback.selectionClick(); } catch (_) {}
                          } else {
                            await v.play();
                            try { HapticFeedback.mediumImpact(); } catch (_) {}
                          }
                          setState(() {});
                        },
                        onToggleMute: () {
                          final v = _video;
                          if (v == null) return;
                          _muted = !_muted;
                          v.setVolume(_muted ? 0.0 : 1.0);
                          setState(() {});
                        },
                        onFullscreen: () {
                          context.push('/film/${widget.dreamId}/full');
                        },
                        onShare: () => _exportShare(videoUrl: videoUrl),
                      )
                    : _BuildImages(
                        key: const ValueKey('images'),
                        images: images,
                        onShare: () => _exportShare(images: images),
                      )),
          );
        },
      ),
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        child: Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => _exportShare(),
                icon: const Icon(Icons.ios_share, color: Colors.blue),
                label: const Text('Export / Share'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: FilledButton.icon(
                onPressed: () => _refine(context),
                icon: const Icon(Icons.auto_fix_high, color: Colors.white),
                label: const Text('Refine'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<Map<String, dynamic>> _defaultStages(String status) {
    // Define a simple timeline based on current status
    final names = [
      'Queued',
      'Storyboarding',
      'Animating',
      'Stitching',
      'Rendering',
      'Uploading',
      'Ready',
    ];
    int idx = names.indexWhere((e) => e.toLowerCase() == status.toLowerCase());
    if (idx == -1) idx = 0;
    return [
      for (int i = 0; i < names.length; i++)
        {
          'name': names[i],
          'done': i <= idx,
        }
    ];
  }
}

class _BuildLoader extends StatelessWidget {
  final double progress;
  final List<Map<String, dynamic>> stages;
  final VoidCallback onShare;
  const _BuildLoader({super.key, required this.progress, required this.stages, required this.onShare});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.movie_creation_outlined, color: theme.colorScheme.primary),
                    const SizedBox(width: 8),
                    Text('Generating your film…', style: theme.textTheme.titleLarge),
                    const Spacer(),
                    IconButton(
                      tooltip: 'Share',
                      onPressed: onShare,
                      icon: const Icon(Icons.ios_share, color: Colors.blue),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: LinearProgressIndicator(
                    value: progress.clamp(0.05, 0.98),
                    minHeight: 8,
                  ),
                ),
                const SizedBox(height: 16),
                Column(
                  children: [
                    for (final s in stages)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        child: Row(
                          children: [
                            Icon(
                              s['done'] == true ? Icons.check_circle : Icons.radio_button_unchecked,
                              color: s['done'] == true ? Colors.green : theme.colorScheme.outline,
                              size: 20,
                            ),
                            const SizedBox(width: 8),
                            Expanded(child: Text(s['name']?.toString() ?? '-', style: theme.textTheme.bodyMedium)),
                          ],
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _BuildVideo extends StatelessWidget {
  final VideoPlayerController? controller;
  final bool muted;
  final VoidCallback onTogglePlay;
  final VoidCallback onToggleMute;
  final VoidCallback onFullscreen;
  final VoidCallback onShare;

  const _BuildVideo({
    super.key,
    required this.controller,
    required this.muted,
    required this.onTogglePlay,
    required this.onToggleMute,
    required this.onFullscreen,
    required this.onShare,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final v = controller;
    if (v == null || !v.value.isInitialized) {
      return const Center(child: CircularProgressIndicator());
    }
    final duration = v.value.duration;
    final pos = v.value.position;
    final aspect = v.value.aspectRatio == 0 ? 16 / 9 : v.value.aspectRatio;
    return Column(
      children: [
        Expanded(
          child: Stack(
            children: [
              Center(
                child: AspectRatio(
                  aspectRatio: aspect,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      VideoPlayer(v),
                      // Watermark overlay
                      Positioned(
                        right: 12,
                        bottom: 12,
                        child: Opacity(
                          opacity: 0.75,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.4),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: const Text('DreamWeaver', style: TextStyle(color: Colors.white, fontSize: 12)),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              // Controls overlay
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.bottomCenter,
                      end: Alignment.topCenter,
                      colors: [
                        Colors.black.withValues(alpha: 0.6),
                        Colors.black.withValues(alpha: 0.0),
                      ],
                    ),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          IconButton(
                            onPressed: onTogglePlay,
                            icon: Icon(v.value.isPlaying ? Icons.pause_circle_filled : Icons.play_circle_fill,
                                color: Colors.white,
                                size: 30),
                          ),
                          IconButton(
                            onPressed: onToggleMute,
                            icon: Icon(muted ? Icons.volume_off : Icons.volume_up, color: Colors.white),
                          ),
                          IconButton(
                            onPressed: onShare,
                            icon: const Icon(Icons.ios_share, color: Colors.white),
                          ),
                          const Spacer(),
                          IconButton(
                            onPressed: onFullscreen,
                            icon: const Icon(Icons.fullscreen, color: Colors.white),
                          ),
                        ],
                      ),
                      Row(
                        children: [
                          Text(_fmt(pos), style: const TextStyle(color: Colors.white, fontSize: 12)),
                          Expanded(
                            child: Slider(
                              value: pos.inMilliseconds.clamp(0, duration.inMilliseconds).toDouble(),
                              min: 0,
                              max: math.max(1, duration.inMilliseconds).toDouble(),
                              onChanged: (vms) => v.seekTo(Duration(milliseconds: vms.toInt())),
                            ),
                          ),
                          Text(_fmt(duration), style: const TextStyle(color: Colors.white, fontSize: 12)),
                        ],
                      ),
                    ],
                  ),
                ),
              )
            ],
          ),
        ),
      ],
    );
  }

  String _fmt(Duration d) {
    final mm = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final ss = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    final hh = d.inHours;
    return hh > 0 ? '$hh:$mm:$ss' : '$mm:$ss';
  }
}

class _BuildImages extends StatefulWidget {
  final List<String> images;
  final VoidCallback onShare;
  const _BuildImages({super.key, required this.images, required this.onShare});

  @override
  State<_BuildImages> createState() => _BuildImagesState();
}

class _BuildImagesState extends State<_BuildImages> {
  late final PageController _page = PageController();
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 3), (_) {
      if (!mounted || widget.images.isEmpty) return;
      final next = (_page.page?.round() ?? 0) + 1;
      _page.animateToPage(next % widget.images.length, duration: const Duration(milliseconds: 450), curve: Curves.easeInOut);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _page.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      children: [
        Expanded(
          child: Stack(
            children: [
              PageView.builder(
                controller: _page,
                itemCount: widget.images.length,
                itemBuilder: (_, i) {
                  final url = widget.images[i];
                  return Padding(
                    padding: const EdgeInsets.all(12),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          Image.network(url, fit: BoxFit.cover),
                          Positioned(
                            right: 12,
                            bottom: 12,
                            child: Opacity(
                              opacity: 0.8,
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  color: Colors.black.withValues(alpha: 0.4),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: const Text('DreamWeaver', style: TextStyle(color: Colors.white, fontSize: 12)),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
              Positioned(
                bottom: 18,
                left: 0,
                right: 0,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    for (int i = 0; i < widget.images.length; i++)
                      AnimatedBuilder(
                        animation: _page,
                        builder: (_, __) {
                          final current = _page.page?.round() ?? 0;
                          final active = current == i;
                          return Container(
                            width: active ? 10 : 6,
                            height: 6,
                            margin: const EdgeInsets.symmetric(horizontal: 3),
                            decoration: BoxDecoration(
                              color: active ? Colors.white : theme.colorScheme.surfaceContainerHigh,
                              borderRadius: BorderRadius.circular(3),
                            ),
                          );
                        },
                      ),
                  ],
                ),
              ),
              Positioned(
                top: 10,
                right: 10,
                child: IconButton(
                  onPressed: widget.onShare,
                  icon: const Icon(Icons.ios_share, color: Colors.white),
                ),
              )
            ],
          ),
        ),
      ],
    );
  }
}

class FilmFullscreenPage extends StatefulWidget {
  final String dreamId;
  const FilmFullscreenPage({super.key, required this.dreamId});

  @override
  State<FilmFullscreenPage> createState() => _FilmFullscreenPageState();
}

class _FilmFullscreenPageState extends State<FilmFullscreenPage> {
  VideoPlayerController? _controller;

  @override
  void initState() {
    super.initState();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
  }

  @override
  void dispose() {
    _controller?.dispose();
    SystemChrome.setPreferredOrientations(DeviceOrientation.values);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  Future<void> _init(String url) async {
    try {
      final c = VideoPlayerController.networkUrl(Uri.parse(url));
      await c.initialize();
      c.setLooping(true);
      await c.play();
      setState(() => _controller = c);
    } catch (e) {
      debugPrint('Fullscreen video init error: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance.collection('dreams').doc(widget.dreamId).snapshots(),
        builder: (context, snap) {
          final data = snap.data?.data();
          final meta = data?['metadata'] as Map<String, dynamic>?;
          final visual = meta?['visual'] as Map<String, dynamic>?;
          final videoUrl = (visual?['videoUrl'] as String?) ?? data?['videoUrl'] as String?;
          if (videoUrl != null && _controller == null) {
            // Trigger init
            _init(videoUrl);
          }
          return Stack(
            children: [
              if (_controller != null && _controller!.value.isInitialized)
                Center(child: AspectRatio(aspectRatio: _controller!.value.aspectRatio, child: VideoPlayer(_controller!)))
              else
                const Center(child: CircularProgressIndicator()),
              Positioned(
                top: 24,
                left: 12,
                child: IconButton(
                  onPressed: () => context.pop(),
                  icon: const Icon(Icons.close, color: Colors.white),
                ),
              )
            ],
          );
        },
      ),
    );
  }
}
