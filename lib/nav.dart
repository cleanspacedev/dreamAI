import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:dreamweaver/screens/home_page.dart';
import 'package:dreamweaver/screens/splash_gate.dart';
import 'package:dreamweaver/screens/onboarding_wizard.dart';
import 'package:dreamweaver/screens/dream_logging_screen.dart';
import 'package:dreamweaver/screens/interpretation_screen.dart';
import 'package:dreamweaver/screens/film_generation_screen.dart';
import 'package:dreamweaver/screens/settings_screen.dart';
import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:firebase_analytics/observer.dart';

/// GoRouter configuration for app navigation
///
/// This uses go_router for declarative routing, which provides:
/// - Type-safe navigation
/// - Deep linking support (web URLs, app links)
/// - Easy route parameters
/// - Navigation guards and redirects
///
/// To add a new route:
/// 1. Add a route constant to AppRoutes below
/// 2. Add a GoRoute to the routes list
/// 3. Navigate using context.go() or context.push()
/// 4. Use context.pop() to go back.
class AppRouter {
  static final GoRouter router = GoRouter(
    initialLocation: AppRoutes.gate,
    observers: [
      FirebaseAnalyticsObserver(analytics: FirebaseAnalytics.instance),
    ],
    routes: [
      GoRoute(
        path: AppRoutes.home,
        name: 'home',
        pageBuilder: (context, state) => const NoTransitionPage(
          child: HomePage(),
        ),
      ),
      GoRoute(
        path: AppRoutes.gate,
        name: 'gate',
        pageBuilder: (context, state) => const NoTransitionPage(
          child: SplashGate(),
        ),
      ),
      GoRoute(
        path: AppRoutes.onboarding,
        name: 'onboarding',
        pageBuilder: (context, state) => const NoTransitionPage(
          child: OnboardingWizard(),
        ),
      ),
      GoRoute(
        path: AppRoutes.logDream,
        name: 'log_dream',
        pageBuilder: (context, state) {
          final extra = state.extra;
          return NoTransitionPage(
            child: DreamLoggingScreen(prefill: extra is DreamLogPrefill ? extra : null),
          );
        },
      ),
      GoRoute(
        path: AppRoutes.insights,
        name: 'insights',
        pageBuilder: (context, state) {
          final dreamId = state.pathParameters['dreamId']!;
          return NoTransitionPage(
            child: InterpretationScreen(dreamId: dreamId),
          );
        },
      ),
      GoRoute(
        path: AppRoutes.film,
        name: 'film',
        pageBuilder: (context, state) {
          final dreamId = state.pathParameters['dreamId']!;
          return NoTransitionPage(child: FilmGenerationScreen(dreamId: dreamId));
        },
      ),
      GoRoute(
        path: AppRoutes.filmFull,
        name: 'film_full',
        pageBuilder: (context, state) {
          final dreamId = state.pathParameters['dreamId']!;
          return NoTransitionPage(child: FilmFullscreenPage(dreamId: dreamId));
        },
      ),
      GoRoute(
        path: AppRoutes.settings,
        name: 'settings',
        pageBuilder: (context, state) => const NoTransitionPage(
          child: SettingsScreen(),
        ),
      ),
    ],
  );
}

/// Route path constants
/// Use these instead of hard-coding route strings
class AppRoutes {
  static const String home = '/';
  static const String gate = '/gate';
  static const String onboarding = '/onboarding';
  static const String logDream = '/log';
  static const String insights = '/insights/:dreamId';
  static const String film = '/film/:dreamId';
  static const String filmFull = '/film/:dreamId/full';
  static const String settings = '/settings';
}
