import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:dreamweaver/services/functions_service.dart';

/// Bottom sheet that loads and visualizes admin analytics trends.
/// Calls the callable Cloud Function `adminGetTrends`.
class AdminTrendsSheet extends StatefulWidget {
  const AdminTrendsSheet({super.key});

  @override
  State<AdminTrendsSheet> createState() => _AdminTrendsSheetState();
}

class _AdminTrendsSheetState extends State<AdminTrendsSheet> {
  final _fn = FunctionsService();
  bool _loading = true;
  String? _error;
  Map<String, dynamic>? _data;
  String _range = '30d';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final res = await _fn.adminGetTrends(range: _range);
      if (!mounted) return;
      setState(() {
        _data = res;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.query_stats, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Text('Admin Trends', style: theme.textTheme.titleLarge),
                const Spacer(),
                DropdownButton<String>(
                  value: _range,
                  items: const [
                    DropdownMenuItem(value: '7d', child: Text('7d')),
                    DropdownMenuItem(value: '30d', child: Text('30d')),
                    DropdownMenuItem(value: '90d', child: Text('90d')),
                  ],
                  onChanged: (v) {
                    if (v == null) return;
                    setState(() => _range = v);
                    _load();
                  },
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (_loading)
              const Center(child: Padding(padding: EdgeInsets.all(24), child: CircularProgressIndicator()))
            else if (_error != null)
              Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    const Icon(Icons.error_outline, color: Colors.red),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Failed to load trends. Ensure backend is deployed and you have admin access.\n$_error',
                        style: theme.textTheme.bodyMedium,
                      ),
                    ),
                  ],
                ),
              )
            else ...[
              _DailyLineChart(data: (_data?['dailyDreams'] as List?)?.cast<Map<String, dynamic>>() ?? const []),
              const SizedBox(height: 16),
              _TopTags(tags: (_data?['topTags'] as List?)?.cast<Map<String, dynamic>>() ?? const []),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(child: _MetricTile(label: 'Avg Processing (s)', value: (_data?['avgProcessingSeconds'] ?? 0).toString())),
                  const SizedBox(width: 12),
                  Expanded(child: _MetricTile(label: 'DAU', value: (_data?['activeUsersToday'] ?? 0).toString())),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _DailyLineChart extends StatelessWidget {
  final List<Map<String, dynamic>> data;
  const _DailyLineChart({required this.data});

  @override
  Widget build(BuildContext context) {
    if (data.isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final spots = <FlSpot>[];
    for (var i = 0; i < data.length; i++) {
      final m = data[i];
      final count = (m['count'] as num?)?.toDouble() ?? 0.0;
      spots.add(FlSpot(i.toDouble(), count));
    }
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.show_chart, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Text('Dreams per day', style: theme.textTheme.titleMedium),
              ],
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 160,
              child: LineChart(
                LineChartData(
                  gridData: const FlGridData(show: false),
                  titlesData: const FlTitlesData(show: false),
                  borderData: FlBorderData(show: false),
                  lineBarsData: [
                    LineChartBarData(
                      spots: spots,
                      isCurved: true,
                      color: theme.colorScheme.primary,
                      barWidth: 3,
                      dotData: const FlDotData(show: false),
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

class _TopTags extends StatelessWidget {
  final List<Map<String, dynamic>> tags;
  const _TopTags({required this.tags});

  @override
  Widget build(BuildContext context) {
    if (tags.isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.local_offer, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Text('Top tags', style: theme.textTheme.titleMedium),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final m in tags.take(12))
                  Chip(
                    avatar: const Icon(Icons.tag, size: 16),
                    label: Text('${m['tag'] ?? '#'} (${m['count'] ?? 0})'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _MetricTile extends StatelessWidget {
  final String label;
  final String value;
  const _MetricTile({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: theme.textTheme.labelSmall),
            const SizedBox(height: 6),
            Text(value, style: theme.textTheme.titleLarge),
          ],
        ),
      ),
    );
  }
}
