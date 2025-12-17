import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:firebase_auth/firebase_auth.dart' as firebase_auth;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:dreamweaver/auth/auth_manager.dart';
// Using FirebaseAuth OAuth provider for Google on mobile; no google_sign_in package required

/// Firebase implementation of AuthManager
class FirebaseAuthManager extends AuthManager
    with EmailSignInManager, GoogleSignInManager, AnonymousSignInManager {
  final firebase_auth.FirebaseAuth _auth = firebase_auth.FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  /// Get current Firebase user
  firebase_auth.User? get currentUser => _auth.currentUser;

  /// Stream of auth state changes
  Stream<firebase_auth.User?> get authStateChanges => _auth.authStateChanges();

  /// Create or update user document in Firestore aligning with required schema
  Future<void> _createOrUpdateUserDocument(firebase_auth.User user) async {
    try {
      final userDoc = _firestore.collection('users').doc(user.uid);
      final docSnapshot = await userDoc.get();
      final now = DateTime.now();
      final deviceLang = WidgetsBinding.instance.platformDispatcher.locale.languageCode;
      String? fcmToken;
      try {
        fcmToken = await FirebaseMessaging.instance.getToken();
      } catch (e) {
        debugPrint('FCM token fetch error during user doc setup: $e');
      }

      if (!docSnapshot.exists) {
        final data = <String, dynamic>{
          'userId': user.uid,
          'email': user.email ?? '',
          'createdAt': Timestamp.fromDate(now),
          'preferences': {
            'theme': 'system',
            'voiceStyle': 'default',
            'language': deviceLang,
          },
          'subscriptionStatus': 'free',
          'dailyUsage': {
            'dreams': 0,
            'videos': 0,
            'lastReset': Timestamp.fromDate(now),
          },
          'language': deviceLang,
          'fcmToken': fcmToken,
          'analyticsSummary': {
            'totalDreams': 0,
            'totalVideos': 0,
            'lastActive': Timestamp.fromDate(now),
            'conversionDate': null,
          },
          // Extra optional fields for convenience
          'displayName': user.displayName,
          'photoUrl': user.photoURL,
        };
        await userDoc.set(data, SetOptions(merge: true));
      } else {
        await userDoc.set({
          'email': user.email,
          'language': deviceLang,
          'fcmToken': fcmToken,
          'analyticsSummary': {
            'lastActive': Timestamp.fromDate(now),
          },
          'displayName': user.displayName,
          'photoUrl': user.photoURL,
        }, SetOptions(merge: true));
      }
    } catch (e) {
      debugPrint('Error creating/updating user document: $e');
    }
  }

  @override
  Future<firebase_auth.User?> signInWithEmail(
    BuildContext context,
    String email,
    String password,
  ) async {
    try {
      final userCredential = await _auth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );
      if (userCredential.user != null) {
        await _createOrUpdateUserDocument(userCredential.user!);
      }
      return userCredential.user;
    } on firebase_auth.FirebaseAuthException catch (e) {
      debugPrint('Sign in error: ${e.code} - ${e.message}');
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_getErrorMessage(e.code))),
        );
      }
      return null;
    }
  }

  @override
  Future<firebase_auth.User?> createAccountWithEmail(
    BuildContext context,
    String email,
    String password,
  ) async {
    try {
      final userCredential = await _auth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );
      if (userCredential.user != null) {
        await _createOrUpdateUserDocument(userCredential.user!);
      }
      return userCredential.user;
    } on firebase_auth.FirebaseAuthException catch (e) {
      debugPrint('Create account error: ${e.code} - ${e.message}');
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_getErrorMessage(e.code))),
        );
      }
      return null;
    }
  }

  @override
  Future<firebase_auth.User?> signInAnonymously(BuildContext context) async {
    try {
      final userCredential = await _auth.signInAnonymously();
      if (userCredential.user != null) {
        await _createOrUpdateUserDocument(userCredential.user!);
      }
      return userCredential.user;
    } on firebase_auth.FirebaseAuthException catch (e) {
      debugPrint('Anonymous sign in error: ${e.code} - ${e.message}');
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_getErrorMessage(e.code))),
        );
      }
      return null;
    }
  }

  @override
  Future<firebase_auth.User?> signInWithGoogle(BuildContext context) async {
    try {
      final googleProvider = firebase_auth.GoogleAuthProvider();
      if (kIsWeb) {
        final userCredential = await _auth.signInWithPopup(googleProvider);
        if (userCredential.user != null) {
          await _createOrUpdateUserDocument(userCredential.user!);
        }
        return userCredential.user;
      } else {
        final userCredential = await _auth.signInWithProvider(googleProvider);
        if (userCredential.user != null) {
          await _createOrUpdateUserDocument(userCredential.user!);
        }
        return userCredential.user;
      }
    } on firebase_auth.FirebaseAuthException catch (e) {
      debugPrint('Google sign in error: ${e.code} - ${e.message}');
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_getErrorMessage(e.code))),
        );
      }
      return null;
    }
  }

  @override
  Future<void> signOut() async {
    try {
      await _auth.signOut();
    } catch (e) {
      debugPrint('Sign out error: $e');
    }
  }

  @override
  Future<void> deleteUser(BuildContext context) async {
    try {
      final user = _auth.currentUser;
      if (user != null) {
        await _firestore.collection('users').doc(user.uid).delete();
        await user.delete();
      }
    } on firebase_auth.FirebaseAuthException catch (e) {
      debugPrint('Delete user error: ${e.code} - ${e.message}');
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_getErrorMessage(e.code))),
        );
      }
    }
  }

  @override
  Future<void> updateEmail({
    required String email,
    required BuildContext context,
  }) async {
    try {
      final user = _auth.currentUser;
      if (user != null) {
        await user.verifyBeforeUpdateEmail(email);
        await _createOrUpdateUserDocument(user);
      }
    } on firebase_auth.FirebaseAuthException catch (e) {
      debugPrint('Update email error: ${e.code} - ${e.message}');
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_getErrorMessage(e.code))),
        );
      }
    }
  }

  @override
  Future<void> resetPassword({
    required String email,
    required BuildContext context,
  }) async {
    try {
      await _auth.sendPasswordResetEmail(email: email);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Password reset email sent')),
        );
      }
    } on firebase_auth.FirebaseAuthException catch (e) {
      debugPrint('Reset password error: ${e.code} - ${e.message}');
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_getErrorMessage(e.code))),
        );
      }
    }
  }

  String _getErrorMessage(String code) {
    switch (code) {
      case 'user-not-found':
        return 'No user found with this email.';
      case 'wrong-password':
        return 'Wrong password provided.';
      case 'email-already-in-use':
        return 'An account already exists with this email.';
      case 'invalid-email':
        return 'The email address is not valid.';
      case 'weak-password':
        return 'The password is too weak.';
      case 'requires-recent-login':
        return 'Please sign in again to perform this action.';
      default:
        return 'An error occurred. Please try again.';
    }
  }
}
