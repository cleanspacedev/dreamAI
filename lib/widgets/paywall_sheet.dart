import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:provider/provider.dart';
import 'package:purchases_flutter/purchases_flutter.dart';
import 'package:firebase_auth/firebase_auth.dart' as fb;

import 'package:dreamweaver/services/billing_service.dart';

/// A modern bottom-sheet paywall with monthly/annual toggle and platform-aware flows.
class PaywallSheet extends StatefulWidget {
  final String reason; // e.g., 'free_lifetime_limit' or 'daily_limit'
  const PaywallSheet({super.key, required this.reason});

  @override
  State<PaywallSheet> createState() => _PaywallSheetState();
}

class _PaywallSheetState extends State<PaywallSheet> {
  bool _annual = true;
  Package? _premiumPkgMonthly;
  Package? _premiumPkgAnnual;
  Package? _plusPkgMonthly;
  Package? _plusPkgAnnual;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _loadPackages();
  }

  void _loadPackages() {
    final billing = context.read<BillingService>();
    final offerings = billing.offerings;
    if (offerings == null) return;
    // Heuristics: find packages whose identifier hints the target tier
    for (final off in offerings.all.values) {
      for (final pkg in off.availablePackages) {
        final id = pkg.identifier.toLowerCase();
        if (id.contains('premium_plus') || id.contains('plus')) {
          if (id.contains('annual') || id.contains('year')) {
            _plusPkgAnnual ??= pkg;
          } else {
            _plusPkgMonthly ??= pkg;
          }
        } else if (id.contains('premium')) {
          if (id.contains('annual') || id.contains('year')) {
            _premiumPkgAnnual ??= pkg;
          } else {
            _premiumPkgMonthly ??= pkg;
          }
        }
      }
    }
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final billing = context.watch<BillingService>();
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.workspace_premium_outlined, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                const Text('Go Premium'),
                const Spacer(),
                IconButton(onPressed: () => Navigator.of(context).pop(), icon: const Icon(Icons.close))
              ],
            ),
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  const Icon(Icons.info_outline, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      widget.reason == 'free_lifetime_limit'
                          ? 'You\'ve used your free film. Unlock daily films and longer durations.'
                          : 'Daily film limit reached. Upgrade to increase your daily films.',
                      style: theme.textTheme.bodySmall,
                    ),
                  )
                ],
              ),
            ),
            const SizedBox(height: 12),
            // Toggle
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                SegmentedButton<bool>(
                  segments: const [
                    ButtonSegment(value: false, label: Text('Monthly')),
                    ButtonSegment(value: true, label: Text('Annual • Save 20%')),
                  ],
                  selected: {_annual},
                  onSelectionChanged: (s) => setState(() => _annual = s.first),
                )
              ],
            ),
            const SizedBox(height: 12),
            // Plans
            Row(
              children: [
                Expanded(child: _PlanCard(
                  title: 'Premium',
                  subtitle: '3 films/day • up to 20s',
                  priceHint: _priceText(_annual ? _premiumPkgAnnual : _premiumPkgMonthly),
                  highlight: false,
                  onPressed: () async {
                    if (billing.isInitialized && !kIsWeb) {
                      final pkg = _annual ? _premiumPkgAnnual : _premiumPkgMonthly;
                      if (pkg != null) {
                        final ok = await billing.purchasePackage(pkg);
                        if (ok && mounted) {
                          final uid = fb.FirebaseAuth.instance.currentUser?.uid;
                          if (uid != null) {
                            await billing.syncUserTierToFirestore(uid);
                          }
                          Navigator.of(context).pop(true);
                        }
                      }
                    } else {
                      await billing.openStripeCheckout(annual: _annual);
                    }
                  },
                )),
                const SizedBox(width: 12),
                Expanded(child: _PlanCard(
                  title: 'Premium+',
                  subtitle: '8 films/day • up to 30s',
                  priceHint: _priceText(_annual ? _plusPkgAnnual : _plusPkgMonthly),
                  highlight: true,
                  onPressed: () async {
                    if (billing.isInitialized && !kIsWeb) {
                      final pkg = _annual ? _plusPkgAnnual : _plusPkgMonthly;
                      if (pkg != null) {
                        final ok = await billing.purchasePackage(pkg);
                        if (ok && mounted) {
                          final uid = fb.FirebaseAuth.instance.currentUser?.uid;
                          if (uid != null) {
                            await billing.syncUserTierToFirestore(uid);
                          }
                          Navigator.of(context).pop(true);
                        }
                      }
                    } else {
                      await billing.openStripeCheckout(annual: _annual);
                    }
                  },
                )),
              ],
            ),
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.center,
              child: TextButton.icon(
                onPressed: () => billing.restorePurchases(),
                icon: const Icon(Icons.restore),
                label: const Text('Restore purchases'),
              ),
            )
          ],
        ),
      ),
    );
  }

  String _priceText(Package? pkg) {
    if (pkg == null) return '';
    try {
      final p = pkg.storeProduct;
      final price = p.priceString;
      return price;
    } catch (_) {
      return '';
    }
  }
}

class _PlanCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final String priceHint;
  final bool highlight;
  final VoidCallback onPressed;
  const _PlanCard({
    super.key,
    required this.title,
    required this.subtitle,
    required this.priceHint,
    required this.highlight,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      elevation: highlight ? 1.5 : 0,
      color: highlight ? theme.colorScheme.surfaceContainerHighest : theme.colorScheme.surface,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.workspace_premium, color: highlight ? Colors.amber : theme.colorScheme.primary),
                const SizedBox(width: 8),
                Text(title, style: theme.textTheme.titleMedium),
              ],
            ),
            const SizedBox(height: 8),
            Text(subtitle, style: theme.textTheme.bodySmall),
            const SizedBox(height: 8),
            if (priceHint.isNotEmpty)
              Text(priceHint, style: theme.textTheme.titleLarge),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: onPressed,
              child: const Text('Continue'),
            )
          ],
        ),
      ),
    );
  }
}
