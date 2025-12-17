import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:firebase_auth/firebase_auth.dart' as firebase_auth;
import 'package:cloud_firestore/cloud_firestore.dart';

/// Service to manage Firebase Cloud Messaging permissions, token, and listeners
class PushMessagingService {
  PushMessagingService._();
  static final PushMessagingService instance = PushMessagingService._();

  final FirebaseMessaging _messaging = FirebaseMessaging.instance;
  final firebase_auth.FirebaseAuth _auth = firebase_auth.FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  Future<void> initialize() async {
    try {
      // Request notifications permission (iOS/web)
      final settings = await _messaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
        provisional: false,
      );
      debugPrint('FCM permission status: ${settings.authorizationStatus}');

      // Get FCM token
      final token = await _messaging.getToken();
      debugPrint('FCM token: $token');
      await _persistToken(token);

      // Listen for token refreshes
      _messaging.onTokenRefresh.listen((newToken) async {
        debugPrint('FCM token refreshed: $newToken');
        await _persistToken(newToken);
      });

      // Foreground message handling
      FirebaseMessaging.onMessage.listen((RemoteMessage message) {
        debugPrint('FCM onMessage id=${message.messageId}, data=${message.data}');
      });

      // When the app is opened from a notification
      FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
        debugPrint('FCM onMessageOpenedApp id=${message.messageId}');
      });
    } catch (e) {
      debugPrint('Error initializing FCM: $e');
    }
  }

  Future<void> _persistToken(String? token) async {
    if (token == null) return;
    try {
      final user = _auth.currentUser;
      if (user != null) {
        await _firestore.collection('users').doc(user.uid).set(
              {'fcmToken': token},
              SetOptions(merge: true),
            );
      }
    } catch (e) {
      debugPrint('Error persisting FCM token: $e');
    }
  }
}
