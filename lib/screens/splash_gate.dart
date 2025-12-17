import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart' as firebase_auth;
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:dreamweaver/nav.dart';

import 'onboarding_wizard.dart';

class SplashGate extends StatefulWidget {
  const SplashGate({super.key});

  @override
  State<SplashGate> createState() => _SplashGateState();
}

class _SplashGateState extends State<SplashGate> {
  @override
  void initState() {
    super.initState();
    _decide();
  }

  Future<void> _decide() async {
    try {
      final auth = firebase_auth.FirebaseAuth.instance;
      final user = auth.currentUser;
      if (user == null) {
        if (mounted) context.go(AppRoutes.onboarding);
        return;
      }
      final doc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
      final data = doc.data() ?? {};
      final prefs = (data['preferences'] as Map?)?.cast<String, dynamic>() ?? {};
      // Consider onboarding complete if user marked onboarded or voiceStyle chosen.
      final hasPrefs = prefs.containsKey('voiceStyle');
      final onboarded = prefs['onboarded'] == true;
      if (mounted) {
        if (hasPrefs || onboarded) {
          context.go(AppRoutes.home);
        } else {
          context.go(AppRoutes.onboarding);
        }
      }
    } catch (e) {
      // On any error, default to onboarding to ensure setup completes
      if (mounted) context.go(AppRoutes.onboarding);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 16),
            Text('Loading...', style: theme.textTheme.bodyMedium),
          ],
        ),
      ),
    );
  }
}
