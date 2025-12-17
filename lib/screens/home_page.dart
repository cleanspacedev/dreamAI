import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart' as firebase_auth;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';

import 'package:dreamweaver/models/dream_model.dart';
import 'package:dreamweaver/models/user_model.dart';
import 'package:dreamweaver/services/dream_service.dart';
import 'package:dreamweaver/services/user_service.dart';
import 'package:dreamweaver/services/prompts_service.dart';
import 'package:dreamweaver/services/tts_service.dart';
import 'package:dreamweaver/theme.dart';
import 'package:dreamweaver/screens/journal_history_screen.dart';
import 'package:dreamweaver/screens/dream_logging_screen.dart';
import 'package:dreamweaver/widgets/admin_trends_sheet.dart';

/// Home/Dashboard with bottom tab bar (Home, Journal)
class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int _index = 0;

  firebase_auth.User? get _user => firebase_auth.FirebaseAuth.instance.currentUser;

  @override
  Widget build(BuildContext context) {
    // If user is not signed in, show a lightweight gate
    if (_user == null) {
      return const _SignedOutGate();
    }

    return Scaffold(
      // No AppBar to avoid mixing patterns; use only bottom navigation
      body: SafeArea(
        child: IndexedStack(
          index: _index,
          children: const [
            _HomeTab(),
            _JournalTab(),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push('/log'),
        icon: const Icon(Icons.add, color: Colors.white),
        label: const Text('New Dream'),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home), label: 'Home'),
          NavigationDestination(icon: Icon(Icons.menu_book_outlined), selectedIcon: Icon(Icons.menu_book), label: 'Journal'),
        ],
      ),
    );
  }

  Future<void> _showNewDreamSheet(BuildContext context) async {
    final titleController = TextEditingController();
    final descController = TextEditingController();
    final dreamService = context.read<DreamService>();
    final userId = _user!.uid;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (ctx) {
        final viewInsets = MediaQuery.of(ctx).viewInsets.bottom;
        return Padding(
          padding: EdgeInsets.fromLTRB(16, 16, 16, viewInsets + 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.nightlight_round, color: Theme.of(ctx).colorScheme.primary),
                  const SizedBox(width: 8),
                  Text('New Dream', style: Theme.of(ctx).textTheme.titleLarge),
                ],
              ),
              const SizedBox(height: 16),
              TextField(
                controller: titleController,
                decoration: const InputDecoration(
                  labelText: 'Title',
                  prefixIcon: Icon(Icons.title),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: descController,
                decoration: const InputDecoration(
                  labelText: 'What did you dream?',
                  prefixIcon: Icon(Icons.notes),
                ),
                maxLines: 5,
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: () async {
                        final now = DateTime.now();
                        final model = DreamModel(
                          id: 'temp',
                          ownerId: userId,
                          title: titleController.text.trim().isEmpty ? 'Untitled Dream' : titleController.text.trim(),
                          description: descController.text.trim(),
                          dreamDate: now,
                          createdAt: now,
                          updatedAt: now,
                          tags: const [],
                          audioUrl: null,
                          imageUrl: null,
                          metadata: const {
                            'status': 'draft',
                            'processing': false,
                            'progress': 0.0,
                          },
                        );
                        try {
                          await dreamService.createDream(model);
                          if (mounted) Navigator.of(ctx).pop();
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Dream created')),
                            );
                          }
                        } catch (e) {
                          debugPrint('Create dream error: $e');
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Failed to create dream')),
                            );
                          }
                        }
                      },
                      icon: const Icon(Icons.check, color: Colors.white),
                      label: const Text('Save'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => Navigator.of(ctx).pop(),
                      icon: const Icon(Icons.close),
                      label: const Text('Cancel'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}

class _HomeTab extends StatelessWidget {
  const _HomeTab();

  @override
  Widget build(BuildContext context) {
    final user = firebase_auth.FirebaseAuth.instance.currentUser!;
    final userService = context.watch<UserService>();
    final dreamService = context.watch<DreamService>();

    return StreamBuilder<UserModel?>(
      stream: userService.streamUser(user.uid),
      builder: (context, userSnap) {
        final profile = userSnap.data;
        return CustomScrollView(
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              sliver: SliverToBoxAdapter(
                child: _Header(profile: profile),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              sliver: SliverToBoxAdapter(
                child: _UsageSection(profile: profile),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              sliver: SliverToBoxAdapter(child: _DailyPromptCard(userId: user.uid, userLanguage: profile?.language)),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              sliver: SliverToBoxAdapter(
                child: _RecentDreamTeaser(dreamsStream: dreamService.streamUserDreams(user.uid)),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
              sliver: SliverToBoxAdapter(
                child: _ProcessingIndicators(dreamsStream: dreamService.streamUserDreams(user.uid)),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _JournalTab extends StatelessWidget {
  const _JournalTab();

  @override
  Widget build(BuildContext context) {
    return const JournalHistoryScreen();
  }
}

class _Header extends StatelessWidget {
  final UserModel? profile;
  const _Header({required this.profile});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final name = profile?.email.split('@').first ?? 'Dreamer';
    return GestureDetector(
      onLongPress: () async {
        // Hidden admin entry point. Backend enforces admin via auth claims.
        await showModalBottomSheet(
          context: context,
          isScrollControlled: true,
          useSafeArea: true,
          builder: (ctx) => DraggableScrollableSheet(
            expand: false,
            initialChildSize: 0.7,
            minChildSize: 0.5,
            maxChildSize: 0.95,
            builder: (context, controller) => SingleChildScrollView(
              controller: controller,
              child: Padding(
                padding: const EdgeInsets.only(bottom: 24),
                child: const AdminTrendsSheet(),
              ),
            ),
          ),
        );
      },
      child: Row(
        children: [
          const CircleAvatar(child: Icon(Icons.person)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Welcome back, $name', style: theme.textTheme.titleLarge),
                Text('What did you dream about last night?', style: theme.textTheme.bodyMedium),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _UsageSection extends StatelessWidget {
  final UserModel? profile;
  const _UsageSection({required this.profile});

  static const Map<String, Map<String, int>> planLimits = {
    'free': {'dreams': 5, 'videos': 3},
    'premium': {'dreams': 100, 'videos': 30},
    'premium_plus': {'dreams': 500, 'videos': 120},
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final status = profile?.subscriptionStatus ?? 'free';
    final usage = profile?.dailyUsage ?? const {'dreams': 0, 'videos': 0};
    final limits = planLimits[status] ?? planLimits['free']!;

    Widget bar(String label, int used, int total, IconData icon, Color color) {
      final pct = total > 0 ? (used / total).clamp(0.0, 1.0) : 0.0;
      return Card(
        clipBehavior: Clip.antiAlias,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(icon, color: color),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text('$label: $used/$total today', style: theme.textTheme.bodyMedium),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: LinearProgressIndicator(value: pct, minHeight: 8),
              ),
            ],
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Today\'s usage', style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: bar('Dreams', (usage['dreams'] as int? ?? 0), limits['dreams']!, Icons.nightlight_round, theme.colorScheme.primary),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: bar('Videos', (usage['videos'] as int? ?? 0), limits['videos']!, Icons.videocam, theme.colorScheme.tertiary),
            ),
          ],
        ),
      ],
    );
  }
}

class _DailyPromptCard extends StatelessWidget {
  final String userId;
  final String? userLanguage;
  const _DailyPromptCard({super.key, required this.userId, this.userLanguage});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final prompts = FirebaseFirestore.instance.collection('prompts');
    final streakStream = context.read<PromptsService>().streamPromptStreak(userId);
    // Fetch all and locally pick the most recent by 'date' or 'createdAt'
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: prompts.snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Card(child: SizedBox(height: 120, child: Center(child: CircularProgressIndicator())));
        }
        final docs = snapshot.data?.docs ?? [];
        if (docs.isEmpty) {
          return Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Icon(Icons.lightbulb_outline, color: theme.colorScheme.primary),
                  const SizedBox(width: 12),
                  Expanded(child: Text('No prompt for today yet.', style: theme.textTheme.bodyMedium)),
                  const SizedBox(width: 12),
                  FilledButton.icon(
                    onPressed: () async {
                      try {
                        await context.read<PromptsService>().ensureTodayPrompt(language: userLanguage);
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Generated today\'s prompt')));
                        }
                      } catch (e) {
                        debugPrint('Generate prompt error: $e');
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Failed to generate prompt')));
                        }
                      }
                    },
                    icon: const Icon(Icons.auto_awesome, color: Colors.white),
                    label: const Text('Generate'),
                  ),
                ],
              ),
            ),
          );
        }
        docs.sort((a, b) {
          final aData = a.data();
          final bData = b.data();
          final aTs = (aData['date'] ?? aData['createdAt']);
          final bTs = (bData['date'] ?? bData['createdAt']);
          final aDate = aTs is Timestamp ? aTs.toDate() : DateTime.fromMillisecondsSinceEpoch(0);
          final bDate = bTs is Timestamp ? bTs.toDate() : DateTime.fromMillisecondsSinceEpoch(0);
          return bDate.compareTo(aDate);
        });
        final latest = docs.first.data();
        final text = (latest['text'] as String?) ?? (latest['prompt'] as String?) ?? 'Reflect on your most vivid moment.';
        return StreamBuilder<int>(
          stream: streakStream,
          builder: (context, streakSnap) {
            final streak = streakSnap.data ?? 0;
            return Card(
              clipBehavior: Clip.antiAlias,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.lightbulb, color: theme.colorScheme.primary),
                        const SizedBox(width: 8),
                        Text('Daily Prompt', style: theme.textTheme.titleMedium),
                        const Spacer(),
                        if (streak > 0)
                          Chip(
                            avatar: const Icon(Icons.local_fire_department, color: Colors.orange, size: 18),
                            label: Text('Streak $streak'),
                          ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(text, style: theme.textTheme.bodyLarge),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        OutlinedButton.icon(
                          onPressed: () async {
                            try {
                              // Use local TTS for quick readout
                              await TTSService.instance.setLanguage(userLanguage ?? 'en-US');
                              await TTSService.instance.speak(text);
                            } catch (e) {
                              debugPrint('Prompt TTS error: $e');
                            }
                          },
                          icon: const Icon(Icons.volume_up),
                          label: const Text('Listen'),
                        ),
                        const Spacer(),
                        TextButton.icon(
                          onPressed: () {
                            final docId = docs.first.id;
                            final themeStr = (latest['theme'] as String?);
                            final tags = (latest['tags'] as List?)?.map((e) => e.toString()).toList();
                            final prefill = DreamLogPrefill(
                              promptId: docId,
                              promptText: text,
                              theme: themeStr,
                              tags: tags,
                            );
                            context.push('/log', extra: prefill);
                          },
                          icon: const Icon(Icons.playlist_add),
                          label: const Text('Use Prompt'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}

class _RecentDreamTeaser extends StatelessWidget {
  final Stream<List<DreamModel>> dreamsStream;
  const _RecentDreamTeaser({required this.dreamsStream});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return StreamBuilder<List<DreamModel>>(
      stream: dreamsStream,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Card(child: SizedBox(height: 110, child: Center(child: CircularProgressIndicator())));
        }
        final list = snapshot.data ?? const [];
        if (list.isEmpty) {
          return Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Icon(Icons.nights_stay_outlined, color: theme.colorScheme.primary),
                  const SizedBox(width: 12),
                  Expanded(child: Text('No dreams yet. Start your first one!', style: theme.textTheme.bodyMedium)),
                ],
              ),
            ),
          );
        }
        final latest = list.first;
        final processing = (latest.metadata?['processing'] as bool?) ?? false;
        final progress = (latest.metadata?['progress'] as num?)?.toDouble() ?? 0.0;
        return Card(
          clipBehavior: Clip.antiAlias,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.auto_stories, color: theme.colorScheme.primary),
                    const SizedBox(width: 8),
                    Text('Recent Dream', style: theme.textTheme.titleMedium),
                  ],
                ),
                const SizedBox(height: 8),
                Text(latest.title, style: theme.textTheme.titleLarge),
                const SizedBox(height: 4),
                Text(
                  latest.description.isEmpty ? 'No description' : latest.description,
                  style: theme.textTheme.bodyMedium,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
                if (processing) ...[
                  const SizedBox(height: 12),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: LinearProgressIndicator(value: progress > 0.0 ? progress : null, minHeight: 8),
                  ),
                  const SizedBox(height: 4),
                  Text('Processing...', style: theme.textTheme.labelSmall),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}

class _ProcessingIndicators extends StatelessWidget {
  final Stream<List<DreamModel>> dreamsStream;
  const _ProcessingIndicators({required this.dreamsStream});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return StreamBuilder<List<DreamModel>>(
      stream: dreamsStream,
      builder: (context, snapshot) {
        final dreams = (snapshot.data ?? const [])
            .where((d) => (d.metadata?['processing'] as bool?) == true || ((d.metadata?['status'] as String?) ?? '') == 'processing')
            .toList();
        if (dreams.isEmpty) return const SizedBox.shrink();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Active Processing', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            ...dreams.take(3).map((d) {
              final progress = (d.metadata?['progress'] as num?)?.toDouble() ?? 0.0;
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: [
                    const Icon(Icons.sync, color: Colors.blue),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(d.title, style: theme.textTheme.bodyMedium, maxLines: 1, overflow: TextOverflow.ellipsis),
                          const SizedBox(height: 6),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: LinearProgressIndicator(value: progress > 0.0 ? progress : null, minHeight: 6),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            }),
          ],
        );
      },
    );
  }
}

class _DreamListItem extends StatelessWidget {
  final DreamModel dream;
  const _DreamListItem({required this.dream});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final processing = (dream.metadata?['processing'] as bool?) ?? false;
    final progress = (dream.metadata?['progress'] as num?)?.toDouble() ?? 0.0;
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.nights_stay, color: theme.colorScheme.primary),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(dream.title, style: theme.textTheme.titleMedium),
                  const SizedBox(height: 4),
                  Text(
                    dream.description.isEmpty ? 'No description' : dream.description,
                    style: theme.textTheme.bodyMedium,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (processing) ...[
                    const SizedBox(height: 8),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: LinearProgressIndicator(value: progress > 0.0 ? progress : null, minHeight: 6),
                    ),
                  ]
                ],
              ),
            ),
            const SizedBox(width: 8),
            Icon(Icons.chevron_right, color: theme.colorScheme.outline),
          ],
        ),
      ),
    );
  }
}

class _SignedOutGate extends StatelessWidget {
  const _SignedOutGate();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.lock_outline, size: 48, color: Theme.of(context).colorScheme.primary),
          const SizedBox(height: 12),
          Text('Please sign in to continue', style: Theme.of(context).textTheme.titleMedium),
        ],
      ),
    );
  }
}

