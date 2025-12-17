import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:dreamweaver/firebase_options.dart';
import 'package:dreamweaver/theme.dart';
import 'package:dreamweaver/nav.dart';
import 'package:dreamweaver/auth/firebase_auth_manager.dart';
import 'package:dreamweaver/services/user_service.dart';
import 'package:dreamweaver/services/language_service.dart';
import 'package:dreamweaver/services/translation_service.dart';
import 'package:dreamweaver/services/dream_service.dart';
import 'package:dreamweaver/services/dream_analysis_service.dart';
import 'package:dreamweaver/services/push_messaging_service.dart';
import 'package:dreamweaver/services/prompts_service.dart';
import 'package:dreamweaver/services/billing_service.dart';
import 'package:dreamweaver/services/freemium_service.dart';
import 'package:dreamweaver/services/theme_service.dart';

/// Main entry point for the DreamWeaver application
///
/// This sets up:
/// - Firebase initialization (Auth, Firestore, Storage, Functions, Analytics, Messaging)
/// - Provider state management for services
/// - go_router navigation
/// - Material 3 theming with light/dark modes
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // Ensure Firebase is initialized in background isolate
  try {
    await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  } catch (e) {
    // Ignore if already initialized
  }
  debugPrint('FCM background message: ${message.messageId}');
}

void main() {
  runZonedGuarded(() async {
    WidgetsFlutterBinding.ensureInitialized();

    // Initialize Firebase
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );

    // Enable Firestore offline persistence (all platforms)
    try {
      FirebaseFirestore.instance.settings = const Settings(
        persistenceEnabled: true,
        cacheSizeBytes: Settings.CACHE_SIZE_UNLIMITED,
      );
    } catch (e) {
      debugPrint('Firestore persistence setup error: $e');
    }

    // Crashlytics: capture Flutter and Dart errors
    // Disable in debug to avoid noisy reports
    // Guard: Crashlytics is not supported on Web
    const crashlyticsSupported = !kIsWeb;
    if (crashlyticsSupported) {
      await FirebaseCrashlytics.instance.setCrashlyticsCollectionEnabled(!kDebugMode);
      FlutterError.onError = FirebaseCrashlytics.instance.recordFlutterFatalError;
      PlatformDispatcher.instance.onError = (error, stack) {
        FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
        return true;
      };
    } else {
      // On Web, log errors to console to avoid assertion from Crashlytics platform interface
      FlutterError.onError = (FlutterErrorDetails details) {
        FlutterError.presentError(details);
        debugPrint('Flutter error (web): ${details.exceptionAsString()}');
        if (details.stack != null) {
          debugPrint(details.stack.toString());
        }
      };
      PlatformDispatcher.instance.onError = (error, stack) {
        debugPrint('Uncaught error (web): $error');
        debugPrint(stack.toString());
        return true;
      };
    }

    // Register background handler for FCM (not supported on Web)
    if (!kIsWeb) {
      try {
        FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
      } catch (e) {
        debugPrint('FCM background handler registration error: $e');
      }
    } else {
      debugPrint('Skipping FirebaseMessaging.onBackgroundMessage on Web');
    }

    // Initialize Firebase Analytics (screen view events configured via GoRouter observers)
    // Access instance to ensure it is ready
    // ignore: unused_local_variable
    final FirebaseAnalytics analytics = FirebaseAnalytics.instance;

    // Initialize FCM foreground handling and permissions
    await PushMessagingService.instance.initialize();

    // Initialize Billing (RevenueCat on mobile)
    await BillingService.instance.initialize();

    runApp(const MyApp());
  }, (error, stack) {
    if (!kIsWeb) {
      FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
    } else {
      debugPrint('Zoned error (web): $error');
      debugPrint(stack.toString());
    }
  });
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        Provider<FirebaseAuthManager>(create: (_) => FirebaseAuthManager()),
        ChangeNotifierProvider<UserService>(create: (_) => UserService()),
        ChangeNotifierProvider<DreamService>(create: (_) => DreamService()),
        ChangeNotifierProvider<DreamAnalysisService>(
          create: (_) => DreamAnalysisService(),
        ),
        ChangeNotifierProvider<PromptsService>(create: (_) => PromptsService()),
        ChangeNotifierProvider<BillingService>(create: (_) => BillingService.instance),
        ChangeNotifierProvider<FreemiumService>(create: (_) => FreemiumService()),
        ChangeNotifierProvider<LanguageService>(create: (_) => LanguageService()),
        ChangeNotifierProvider<ThemeService>(create: (_) => ThemeService()),
        ChangeNotifierProxyProvider<LanguageService, TranslationService>(
          create: (ctx) => TranslationService(languageService: ctx.read<LanguageService>()),
          update: (ctx, lang, prev) => prev ?? TranslationService(languageService: lang),
        ),
      ],
      child: Consumer2<LanguageService, ThemeService>(
        builder: (context, lang, themeSvc, _) => MaterialApp.router(
          title: 'DreamWeaver',
          debugShowCheckedModeBanner: false,
          theme: lightTheme,
          darkTheme: darkTheme,
          themeMode: themeSvc.mode,
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          // Expand supported locales, including RTL languages
          supportedLocales: const [
            Locale('en'),
            Locale('es'),
            Locale('fr'),
            Locale('de'),
            Locale('it'),
            Locale('pt'),
            Locale('ru'),
            Locale('zh'),
            Locale('ja'),
            Locale('ko'),
            Locale('ar'),
            Locale('he'),
            Locale('fa'),
            Locale('ur'),
            Locale('hi'),
          ],
          locale: lang.locale,
          localeResolutionCallback: (device, supported) {
            if (device == null) return supported.first;
            for (final s in supported) {
              if (s.languageCode == device.languageCode) return s;
            }
            return supported.first;
          },
          routerConfig: AppRouter.router,
        ),
      ),
    );
  }
}
