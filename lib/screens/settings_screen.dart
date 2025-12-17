import 'package:firebase_auth/firebase_auth.dart' as fb;
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import 'package:dreamweaver/auth/firebase_auth_manager.dart';
import 'package:dreamweaver/nav.dart';
import 'package:dreamweaver/services/language_service.dart';
import 'package:dreamweaver/services/user_service.dart';
import 'package:dreamweaver/widgets/paywall_sheet.dart';
import 'package:dreamweaver/services/theme_service.dart';

/// Settings screen with account info, preferences, and sign out
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final user = fb.FirebaseAuth.instance.currentUser;
    final userService = context.read<UserService>();

    return Scaffold(
      appBar: AppBar(
        centerTitle: true,
        title: const Text('Settings'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          if (user != null)
            StreamBuilder(
              stream: userService.streamUser(user.uid),
              builder: (context, snapshot) {
                final data = snapshot.data;
                final email = user.email ?? data?.email ?? 'Unknown';
                final plan = data?.subscriptionStatus ?? 'free';
                return Card(
                  clipBehavior: Clip.antiAlias,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      children: [
                        CircleAvatar(
                          radius: 24,
                          child: Text(
                            (email.isNotEmpty ? email[0].toUpperCase() : 'D'),
                            style: theme.textTheme.titleMedium?.copyWith(color: Colors.white),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(email, style: theme.textTheme.titleMedium, overflow: TextOverflow.ellipsis),
                              const SizedBox(height: 4),
                              Row(
                                children: [
                                  const Icon(Icons.workspace_premium, size: 16, color: Colors.amber),
                                  const SizedBox(width: 6),
                                  Text('Plan: ${plan.replaceAll('_', ' ')}', style: theme.textTheme.bodySmall),
                                  const Spacer(),
                                  TextButton.icon(
                                    onPressed: () async {
                                      await showModalBottomSheet(
                                        context: context,
                                        isScrollControlled: true,
                                        useSafeArea: true,
                                        builder: (ctx) => const PaywallSheet(reason: 'settings'),
                                      );
                                    },
                                    icon: const Icon(Icons.upgrade),
                                    label: const Text('Upgrade'),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          const SizedBox(height: 12),
          _PreferencesCard(),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.info_outline, color: theme.colorScheme.primary),
                      const SizedBox(width: 8),
                      Text('About', style: theme.textTheme.titleMedium),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text('DreamWeaver v1.0.0', style: theme.textTheme.bodyMedium),
                  const SizedBox(height: 6),
                  Text('Build an insightful dream journal with AI-assisted interpretation.', style: theme.textTheme.bodySmall),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: () async {
              await _signOut(context);
            },
            icon: const Icon(Icons.logout, color: Colors.white),
            label: const Text('Sign out'),
          ),
        ],
      ),
    );
  }

  Future<void> _signOut(BuildContext context) async {
    try {
      await context.read<FirebaseAuthManager>().signOut();
      if (context.mounted) context.go(AppRoutes.gate);
    } catch (e) {
      debugPrint('Settings signOut error: $e');
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Failed to sign out. Please try again.')));
      }
    }
  }
}

class _PreferencesCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final lang = context.watch<LanguageService>();
    final themeSvc = context.watch<ThemeService>();

    final languages = const [
      'en', 'es', 'fr', 'de', 'it', 'pt', 'ru', 'zh', 'ja', 'ko', 'ar', 'he', 'fa', 'ur', 'hi'
    ];

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.tune, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Text('Preferences', style: theme.textTheme.titleMedium),
              ],
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<ThemeMode>(
              value: themeSvc.mode,
              decoration: const InputDecoration(
                labelText: 'App theme',
                prefixIcon: Icon(Icons.brightness_6),
              ),
              items: const [
                DropdownMenuItem(value: ThemeMode.system, child: Text('System')),
                DropdownMenuItem(value: ThemeMode.light, child: Text('Light')),
                DropdownMenuItem(value: ThemeMode.dark, child: Text('Dark')),
              ],
              onChanged: (mode) async {
                if (mode != null) {
                  await context.read<ThemeService>().setMode(mode);
                }
              },
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              value: lang.languageCode,
              decoration: const InputDecoration(
                labelText: 'App language',
                prefixIcon: Icon(Icons.language),
              ),
              items: languages
                  .map((code) => DropdownMenuItem(value: code, child: Text(_labelFor(code))))
                  .toList(),
              onChanged: (code) async {
                if (code != null) {
                  await context.read<LanguageService>().setLanguage(code);
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  String _labelFor(String code) {
    switch (code) {
      case 'en':
        return 'English';
      case 'es':
        return 'Español';
      case 'fr':
        return 'Français';
      case 'de':
        return 'Deutsch';
      case 'it':
        return 'Italiano';
      case 'pt':
        return 'Português';
      case 'ru':
        return 'Русский';
      case 'zh':
        return '中文';
      case 'ja':
        return '日本語';
      case 'ko':
        return '한국어';
      case 'ar':
        return 'العربية';
      case 'he':
        return 'עברית';
      case 'fa':
        return 'فارسی';
      case 'ur':
        return 'اردو';
      case 'hi':
        return 'हिन्दी';
      default:
        return code;
    }
  }
}
