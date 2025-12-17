import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart' as firebase_auth;
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import 'package:dreamweaver/models/dream_model.dart';
import 'package:dreamweaver/services/dream_service.dart';

/// Journal History screen: searchable timeline of dreams with basic trends chart
class JournalHistoryScreen extends StatefulWidget {
  const JournalHistoryScreen({super.key});

  @override
  State<JournalHistoryScreen> createState() => _JournalHistoryScreenState();
}

class _JournalHistoryScreenState extends State<JournalHistoryScreen> {
  final TextEditingController _search = TextEditingController();
  final Set<String> _selectedTags = <String>{};
  final Set<String> _selectedMoods = <String>{};

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final user = firebase_auth.FirebaseAuth.instance.currentUser!;
    final dreamService = context.watch<DreamService>();

    return StreamBuilder<List<DreamModel>>(
      stream: dreamService.streamUserDreams(user.uid),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        var dreams = (snapshot.data ?? const <DreamModel>[])..sort((a, b) => b.dreamDate.compareTo(a.dreamDate));

        // Exclude archived by default
        dreams = dreams.where((d) => d.archived == false).toList();

        // Aggregate tags and moods from data
        final allTags = <String>{};
        final allMoods = <String>{};
        for (final d in dreams) {
          allTags.addAll(d.tags);
          final moods = _extractMoods(d);
          allMoods.addAll(moods);
        }

        // Apply search filters (tags, moods, and text in title/description)
        final query = _search.text.trim().toLowerCase();
        List<DreamModel> filtered = dreams.where((d) {
          // Tag/mood filters
          final tagOk = _selectedTags.isEmpty || d.tags.any((t) => _selectedTags.contains(t));
          final moods = _extractMoods(d);
          final moodOk = _selectedMoods.isEmpty || moods.any((m) => _selectedMoods.contains(m));
          // Free text (match tags/moods/title/description)
          final text = '${d.title}\n${d.description}\n${d.tags.join(' ')}\n${moods.join(' ')}'.toLowerCase();
          final queryOk = query.isEmpty || text.contains(query);
          return tagOk && moodOk && queryOk;
        }).toList();

        return CustomScrollView(
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              sliver: SliverToBoxAdapter(child: _TrendsChart(dreams: dreams)),
            ),
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              sliver: SliverToBoxAdapter(
                child: _SearchAndChips(
                  controller: _search,
                  allTags: allTags.toList()..sort(),
                  allMoods: allMoods.toList()..sort(),
                  selectedTags: _selectedTags,
                  selectedMoods: _selectedMoods,
                  onChanged: () => setState(() {}),
                ),
              ),
            ),
            if (filtered.isEmpty)
              const SliverFillRemaining(
                hasScrollBody: false,
                child: Center(child: Text('No dreams match your filters')), 
              )
            else
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 96),
                sliver: SliverList.builder(
                  itemCount: filtered.length,
                  itemBuilder: (context, i) {
                    final d = filtered[i];
                    return _TimelineItem(
                      dream: d,
                      onArchive: () => _archiveDream(context, dreamService, d),
                    );
                  },
                ),
              ),
          ],
        );
      },
    );
  }

  Future<void> _archiveDream(BuildContext context, DreamService service, DreamModel dream) async {
    try {
      await service.setArchived(dream.id, true);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Moved to archive'),
          action: SnackBarAction(
            label: 'Undo',
            onPressed: () => service.setArchived(dream.id, false),
          ),
        ),
      );
    } catch (e) {
      debugPrint('Archive error: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Failed to archive dream')));
    }
  }

  List<String> _extractMoods(DreamModel d) {
    final analysis = (d.metadata?['analysis'] as Map<String, dynamic>?) ?? const {};
    final emotions = (analysis['emotions'] as List?)?.whereType<String>().toList() ?? const <String>[];
    return emotions;
  }
}

class _SearchAndChips extends StatelessWidget {
  final TextEditingController controller;
  final List<String> allTags;
  final List<String> allMoods;
  final Set<String> selectedTags;
  final Set<String> selectedMoods;
  final VoidCallback onChanged;

  const _SearchAndChips({
    required this.controller,
    required this.allTags,
    required this.allMoods,
    required this.selectedTags,
    required this.selectedMoods,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: controller,
          onChanged: (_) => onChanged(),
          decoration: const InputDecoration(
            labelText: 'Search tags, moods…',
            prefixIcon: Icon(Icons.search),
          ),
        ),
        const SizedBox(height: 8),
        if (allTags.isNotEmpty) ...[
          Row(
            children: [
              Icon(Icons.sell_outlined, color: theme.colorScheme.primary),
              const SizedBox(width: 6),
              Text('Tags', style: theme.textTheme.labelSmall),
            ],
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final t in allTags)
                FilterChip(
                  label: Text(t),
                  selected: selectedTags.contains(t),
                  onSelected: (v) {
                    if (v) {
                      selectedTags.add(t);
                    } else {
                      selectedTags.remove(t);
                    }
                    onChanged();
                  },
                ),
            ],
          ),
        ],
        if (allMoods.isNotEmpty) ...[
          const SizedBox(height: 12),
          Row(
            children: [
              Icon(Icons.mood_outlined, color: theme.colorScheme.tertiary),
              const SizedBox(width: 6),
              Text('Moods', style: theme.textTheme.labelSmall),
            ],
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final m in allMoods)
                FilterChip(
                  label: Text(m),
                  selected: selectedMoods.contains(m),
                  onSelected: (v) {
                    if (v) {
                      selectedMoods.add(m);
                    } else {
                      selectedMoods.remove(m);
                    }
                    onChanged();
                  },
                ),
            ],
          ),
        ],
      ],
    );
  }
}

class _TrendsChart extends StatelessWidget {
  final List<DreamModel> dreams;
  const _TrendsChart({required this.dreams});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (dreams.isEmpty) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Icon(Icons.insights_outlined, color: theme.colorScheme.primary),
              const SizedBox(width: 8),
              Expanded(child: Text('No activity yet', style: theme.textTheme.bodyMedium)),
            ],
          ),
        ),
      );
    }

    // Group by ISO week for last 8 weeks
    final now = DateTime.now();
    final buckets = <String, int>{};
    for (int i = 7; i >= 0; i--) {
      final weekStart = _startOfWeek(now.subtract(Duration(days: i * 7)));
      buckets[_key(weekStart)] = 0;
    }
    for (final d in dreams) {
      final key = _key(_startOfWeek(d.dreamDate));
      if (buckets.containsKey(key)) {
        buckets[key] = (buckets[key] ?? 0) + 1;
      }
    }
    final keys = buckets.keys.toList();
    final values = keys.map((k) => buckets[k]!.toDouble()).toList();
    final spots = [
      for (int i = 0; i < values.length; i++) FlSpot(i.toDouble(), values[i])
    ];

    return Card(
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.insights, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Text('Trends (8 weeks)', style: theme.textTheme.titleMedium),
              ],
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 160,
              child: LineChart(
                LineChartData(
                  minX: 0,
                  maxX: (spots.isEmpty ? 0 : spots.length - 1).toDouble(),
                  minY: 0,
                  lineTouchData: const LineTouchData(enabled: false),
                  gridData: FlGridData(show: true, drawVerticalLine: false, horizontalInterval: 1),
                  titlesData: FlTitlesData(
                    leftTitles: AxisTitles(
                      sideTitles: SideTitles(showTitles: true, reservedSize: 28, interval: 1),
                    ),
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        interval: 1,
                        getTitlesWidget: (value, meta) {
                          final idx = value.toInt();
                          if (idx < 0 || idx >= keys.length) return const SizedBox.shrink();
                          final label = keys[idx].split('-W').last; // show week number only
                          return Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: Text(label, style: Theme.of(context).textTheme.labelSmall),
                          );
                        },
                      ),
                    ),
                    rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  ),
                  borderData: FlBorderData(show: false),
                  lineBarsData: [
                    LineChartBarData(
                      spots: spots,
                      isCurved: true,
                      color: theme.colorScheme.primary,
                      barWidth: 3,
                      dotData: const FlDotData(show: false),
                      belowBarData: BarAreaData(show: true, color: theme.colorScheme.primary.withValues(alpha: 0.15)),
                    )
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  DateTime _startOfWeek(DateTime d) {
    final day = d.weekday; // 1=Mon
    return DateTime(d.year, d.month, d.day).subtract(Duration(days: day - 1));
  }

  String _key(DateTime weekStart) {
    final weekOfYear = ((DateTime(weekStart.year, weekStart.month, weekStart.day).difference(DateTime(weekStart.year, 1, 1)).inDays) / 7).floor() + 1;
    return '${weekStart.year}-W$weekOfYear';
  }
}

class _TimelineItem extends StatelessWidget {
  final DreamModel dream;
  final VoidCallback onArchive;
  const _TimelineItem({required this.dream, required this.onArchive});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final date = dream.dreamDate;
    final visual = (dream.metadata?['visual'] as Map<String, dynamic>?) ?? const {};
    final videoUrl = (visual['videoUrl'] as String?);
    final images = (visual['images'] as List?)?.whereType<String>().toList() ?? const <String>[];
    final thumb = images.isNotEmpty ? images.first : (dream.imageUrl ?? '');

    final leftBar = Container(
      width: 32,
      alignment: Alignment.topCenter,
      child: Column(
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              color: theme.colorScheme.primary,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(height: 8),
          Container(width: 2, height: 80, color: theme.colorScheme.outline.withValues(alpha: 0.3)),
        ],
      ),
    );

    final contentCard = Card(
      clipBehavior: Clip.antiAlias,
      margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
      child: InkWell(
        onTap: () {
          if (videoUrl != null && videoUrl.isNotEmpty) {
            context.push('/film/${dream.id}');
          } else {
            context.push('/insights/${dream.id}');
          }
        },
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(_formatDate(date), style: theme.textTheme.labelSmall),
                        const SizedBox(height: 4),
                        Text(dream.title, style: theme.textTheme.titleMedium, maxLines: 1, overflow: TextOverflow.ellipsis),
                        const SizedBox(height: 4),
                        Text(
                          dream.description.isEmpty ? 'No description' : dream.description,
                          style: theme.textTheme.bodyMedium,
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  _Thumb(thumbUrl: thumb, hasVideo: (videoUrl != null && videoUrl.isNotEmpty)),
                ],
              ),
              const SizedBox(height: 8),
              _TagRow(tags: dream.tags),
            ],
          ),
        ),
      ),
    );

    return Dismissible(
      key: ValueKey('dream-${dream.id}'),
      direction: DismissDirection.endToStart,
      background: _dismissBg(context: context, alignEnd: false),
      secondaryBackground: _dismissBg(context: context, alignEnd: true),
      onDismissed: (_) => onArchive(),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          leftBar,
          Expanded(child: contentCard),
        ],
      ),
    );
  }

  Widget _dismissBg({required BuildContext context, required bool alignEnd}) {
    return Container(
      alignment: alignEnd ? Alignment.centerRight : Alignment.centerLeft,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      color: Theme.of(context).colorScheme.secondary.withValues(alpha: 0.2),
      child: Icon(Icons.archive_outlined, color: Theme.of(context).colorScheme.secondary),
    );
  }

  String _formatDate(DateTime d) {
    // Simple date like Mon, Jan 2
    const weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    final wd = weekdays[d.weekday - 1];
    final m = months[d.month - 1];
    return '$wd, $m ${d.day}';
  }
}

class _Thumb extends StatelessWidget {
  final String thumbUrl;
  final bool hasVideo;
  const _Thumb({required this.thumbUrl, required this.hasVideo});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final placeholder = Container(
      width: 96,
      height: 72,
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: const Icon(Icons.image, color: Colors.grey),
    );

    Widget image;
    if (thumbUrl.isNotEmpty) {
      image = ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Stack(
          alignment: Alignment.center,
          children: [
            AspectRatio(
              aspectRatio: 4 / 3,
              child: Image.network(thumbUrl, fit: BoxFit.cover, errorBuilder: (_, __, ___) => placeholder),
            ),
            if (hasVideo)
              Container(
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.3),
                  shape: BoxShape.circle,
                ),
                padding: const EdgeInsets.all(8),
                child: const Icon(Icons.play_arrow, color: Colors.white),
              ),
          ],
        ),
      );
    } else {
      image = placeholder;
    }

    return SizedBox(width: 96, height: 72, child: image);
  }
}

class _TagRow extends StatelessWidget {
  final List<String> tags;
  const _TagRow({required this.tags});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (tags.isEmpty) return const SizedBox.shrink();
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final t in tags)
          Chip(
            label: Text(t),
            avatar: Icon(Icons.sell, size: 16, color: theme.colorScheme.primary),
          ),
      ],
    );
  }
}
