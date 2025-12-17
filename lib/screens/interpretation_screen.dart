import 'dart:async';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
// FlutterSound is avoided on Web to prevent duplicate JS includes; TTS uses TTSService
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import 'package:dreamweaver/models/dream_analysis_model.dart';
import 'package:dreamweaver/openai/openai_config.dart';
import 'package:dreamweaver/services/functions_service.dart';
import 'package:dreamweaver/services/billing_service.dart';
import 'package:dreamweaver/services/freemium_service.dart';
import 'package:dreamweaver/widgets/paywall_sheet.dart';
import 'package:firebase_auth/firebase_auth.dart' as fb;
import 'package:dreamweaver/widgets/translated_text.dart';
import 'package:dreamweaver/services/translation_service.dart';
import 'package:dreamweaver/services/tts_service.dart';

/// Interpretation & Insights screen
/// - Streams dream doc for processing status and ETA
/// - Streams first analysis doc for a dream and renders content
/// - Provides TTS playback of the analysis via OpenAI TTS API
/// - Offers a "Generate Visual" action that triggers a Cloud Function
class InterpretationScreen extends StatefulWidget {
  final String dreamId;
  const InterpretationScreen({super.key, required this.dreamId});

  @override
  State<InterpretationScreen> createState() => _InterpretationScreenState();
}

class _InterpretationScreenState extends State<InterpretationScreen> {
  // Countdown
  Timer? _timer;
  Duration _remaining = Duration.zero;
  DateTime? _eta;

  // TTS playback state
  bool _isPlaying = false;
  
  // Retry handling for stuck processing
  bool _retrying = false;

  @override
  void initState() {
    super.initState();
    // No-op init for TTS is handled inside TTSService
  }

  Future<void> _retryProcessing() async {
    final uid = fb.FirebaseAuth.instance.currentUser?.uid;
    if (uid == null || _retrying) return;
    setState(() => _retrying = true);
    try {
      // Optimistically mark as processing again
      await FirebaseFirestore.instance.collection('dreams').doc(widget.dreamId).update({
        'metadata.status': 'processing',
        'metadata.processing': true,
        'metadata.progress': 0.1,
        'metadata.timelineEstSec': 45,
        'updatedAt': Timestamp.now(),
      });
      await FunctionsService().processDream({'dreamId': widget.dreamId, 'ownerId': uid});
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Retry started')));
    } catch (e) {
      debugPrint('retry processDream error: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Failed to retry processing')));
    } finally {
      if (mounted) setState(() => _retrying = false);
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _startCountdownFromSeconds(double seconds) {
    if (seconds <= 0) return;
    _eta = DateTime.now().add(Duration(seconds: seconds.ceil()));
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      final now = DateTime.now();
      final rem = _eta!.difference(now);
      setState(() => _remaining = rem.isNegative ? Duration.zero : rem);
      if (rem.isNegative) _timer?.cancel();
    });
  }

  Future<void> _playTts(String text) async {
    try {
      if (_isPlaying) {
        await TTSService.instance.stop();
        setState(() => _isPlaying = false);
        return;
      }
      // Translate to user's language before TTS, then speak
      final translator = context.read<TranslationService>();
      final translated = await translator.translate(text, contextKey: 'insights.tts') ?? text;
      await TTSService.instance.speak(translated);
      setState(() => _isPlaying = true);
    } catch (e) {
      debugPrint('TTS play error: $e');
    }
  }

  Future<void> _triggerVisualGeneration() async {
    final uid = fb.FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    try {
      final billing = BillingService.instance;
      final tier = billing.currentTier();
      final quotas = await FreemiumService().checkAndConsume(uid: uid, tier: tier);
      if (!quotas.allowed) {
        if (!mounted) return;
        await showModalBottomSheet(context: context, isScrollControlled: true, builder: (_) => PaywallSheet(reason: quotas.reason));
        return;
      }

      await FunctionsService().generateDreamVisual({
        'dreamId': widget.dreamId,
        // Enforce max duration where backend supports it
        'maxSeconds': quotas.maxSeconds,
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Visual generation started')));
      context.push('/film/${widget.dreamId}');
    } catch (e) {
      debugPrint('generateDreamVisual error: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Failed to start visual generation')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dreamDocStream = FirebaseFirestore.instance.collection('dreams').doc(widget.dreamId).snapshots();
    final analysisStream = FirebaseFirestore.instance
        .collection('dream_analyses')
        .where('dreamId', isEqualTo: widget.dreamId)
        .limit(1)
        .snapshots();

    return Scaffold(
      appBar: AppBar(
        centerTitle: true,
        title: const TranslatedText('Interpretation & Insights', contextKey: 'appbar.insights'),
        actions: [
          IconButton(
            tooltip: 'Done',
            icon: const Icon(Icons.check_circle_outline, color: Colors.blue),
            onPressed: () => context.pop(),
          ),
        ],
      ),
      body: SafeArea(
        child: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          stream: dreamDocStream,
          builder: (context, dreamSnap) {
            final meta = dreamSnap.data?.data()?['metadata'] as Map<String, dynamic>?;
            final isProcessing = (meta?['processing'] as bool?) ?? true;
            final progress = (meta?['progress'] as num?)?.toDouble() ?? 0.1;
            final timelineEstSec = (meta?['timelineEstSec'] as num?)?.toDouble() ?? 30;

            // Start a short countdown for quick jobs
            if (timelineEstSec <= 45 && _eta == null) {
              _startCountdownFromSeconds(timelineEstSec);
            }

            return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: analysisStream,
              builder: (context, analysisSnap) {
                DreamAnalysisModel? analysis;
                if (analysisSnap.data != null && analysisSnap.data!.docs.isNotEmpty) {
                  analysis = DreamAnalysisModel.fromJson(analysisSnap.data!.docs.first.data());
                }

                return AnimatedSwitcher(
                  duration: const Duration(milliseconds: 300),
                  child: analysis == null
                      ? _ProcessingView(
                          key: const ValueKey('processing'),
                          isProcessing: isProcessing,
                          progress: progress,
                          remaining: _remaining,
                          timelineEstSec: timelineEstSec,
                          onRetry: _retryProcessing,
                          retrying: _retrying,
                        )
                      : _AnalysisView(
                          key: const ValueKey('analysis'),
                          analysis: analysis,
                          onPlayTts: () => _playTts(analysis!.interpretation),
                          isPlaying: _isPlaying,
                          onGenerateVisual: _triggerVisualGeneration,
                        ),
                );
              },
            );
          },
        ),
      ),
    );
  }
}

class _ProcessingView extends StatelessWidget {
  final bool isProcessing;
  final double progress;
  final Duration remaining;
  final double timelineEstSec;
  final VoidCallback onRetry;
  final bool retrying;

  const _ProcessingView({
    super.key,
    required this.isProcessing,
    required this.progress,
    required this.remaining,
    required this.timelineEstSec,
    required this.onRetry,
    required this.retrying,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final short = timelineEstSec <= 45;
    final remStr = '${remaining.inSeconds}s';

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
                    Icon(Icons.auto_awesome, color: theme.colorScheme.primary),
                    const SizedBox(width: 8),
                    const TranslatedText('Analyzing your dream…', contextKey: 'status.analyzing'),
                    const Spacer(),
                    if (short)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text('~${timelineEstSec.toStringAsFixed(0)}s', style: theme.textTheme.labelSmall),
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: LinearProgressIndicator(
                    value: isProcessing ? progress.clamp(0.05, 0.95) : 1.0,
                    minHeight: 8,
                  ),
                ),
                const SizedBox(height: 12),
                if (short) ...[
                  Row(
                    children: [
                      const Icon(Icons.timer_outlined, size: 18),
                      const SizedBox(width: 6),
                      Text('Finishing in $remStr', style: theme.textTheme.bodySmall),
                    ],
                  ),
                ] else ...[
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.notifications_active_outlined, size: 18),
                      const SizedBox(width: 6),
                      const Expanded(
                        child: TranslatedText(
                          "This might take a minute. We'll notify you when it's ready. You can close this screen.",
                          contextKey: 'helper.long_job',
                        ),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: 12),
                Row(
                  children: [
                    const Icon(Icons.help_outline, size: 18),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        'Stuck for too long? You can retry the analysis.',
                        style: theme.textTheme.bodySmall,
                      ),
                    ),
                    const SizedBox(width: 8),
                    OutlinedButton.icon(
                      onPressed: retrying ? null : onRetry,
                      icon: retrying
                          ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.refresh),
                      label: const Text('Retry'),
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

class _AnalysisView extends StatelessWidget {
  final DreamAnalysisModel analysis;
  final VoidCallback onPlayTts;
  final bool isPlaying;
  final VoidCallback onGenerateVisual;

  const _AnalysisView({
    super.key,
    required this.analysis,
    required this.onPlayTts,
    required this.isPlaying,
    required this.onGenerateVisual,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      children: [
        Card(
          clipBehavior: Clip.antiAlias,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.psychology_alt_outlined, color: theme.colorScheme.primary),
                    const SizedBox(width: 8),
                    const TranslatedText('Interpretation', contextKey: 'section.interpretation'),
                    const Spacer(),
                    IconButton(
                      tooltip: isPlaying ? 'Stop' : 'Play narration',
                      onPressed: onPlayTts,
                      icon: Icon(isPlaying ? Icons.stop_circle_outlined : Icons.play_circle_fill_rounded,
                          color: Colors.blue),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                 FutureBuilder<String>(
                   future: context.read<TranslationService>().translate(
                         analysis.interpretation,
                         contextKey: 'insights.text',
                       ),
                   initialData: analysis.interpretation,
                   builder: (context, snap) => Text(
                     snap.data ?? analysis.interpretation,
                     style: theme.textTheme.bodyMedium,
                     textAlign: TextAlign.start,
                   ),
                 ),
                const SizedBox(height: 8),
                if (analysis.recommendation != null && analysis.recommendation!.isNotEmpty)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(Icons.lightbulb_outline, size: 18),
                        const SizedBox(width: 8),
                         Expanded(
                           child: FutureBuilder<String>(
                             future: context
                                 .read<TranslationService>()
                                 .translate(analysis.recommendation!, contextKey: 'insights.reco'),
                             initialData: analysis.recommendation!,
                             builder: (c, s) => Text(s.data ?? analysis.recommendation!, style: theme.textTheme.bodySmall),
                           ),
                         ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        ExpansionTile(
          initiallyExpanded: true,
          leading: const Icon(Icons.category_outlined, color: Colors.blue),
          title: const TranslatedText('Symbols & Motifs', contextKey: 'section.symbols'),
          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          children: [
            if (analysis.symbols.isEmpty)
              const TranslatedText('No symbols extracted', contextKey: 'empty.symbols')
            else
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: analysis.symbols
                    .map((s) => Chip(
                          label: Text(s),
                          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ))
                    .toList(),
              ),
          ],
        ),
        const SizedBox(height: 8),
        ExpansionTile(
          leading: const Icon(Icons.mood_outlined, color: Colors.blue),
          title: const TranslatedText('Emotions', contextKey: 'section.emotions'),
          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          children: [
            if (analysis.emotions.isEmpty)
              const TranslatedText('No emotions detected', contextKey: 'empty.emotions')
            else
              Column(
                children: analysis.emotions.entries.map((e) {
                  final score = (e.value as num?)?.toDouble() ?? 0;
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Row(
                      children: [
                        SizedBox(width: 92, child: Text(e.key, style: theme.textTheme.labelSmall)),
                        Expanded(
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(6),
                            child: LinearProgressIndicator(
                              value: score.clamp(0, 1),
                              minHeight: 8,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text('${(score * 100).toStringAsFixed(0)}%', style: theme.textTheme.labelSmall),
                      ],
                    ),
                  );
                }).toList(),
              ),
          ],
        ),
        const SizedBox(height: 20),
        FilledButton.icon(
          onPressed: onGenerateVisual,
          icon: const Icon(Icons.auto_fix_high, color: Colors.white),
          label: const TranslatedText('Generate Visual', contextKey: 'button.generate_visual'),
        ),
      ],
    );
  }
}
