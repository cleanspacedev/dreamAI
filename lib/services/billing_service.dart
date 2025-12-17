import 'dart:io' show Platform;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:purchases_flutter/purchases_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

/// BillingService wraps RevenueCat for native platforms and Stripe Checkout for web.
///
/// Env-configured keys/urls (define at build time):
/// - REVENUECAT_PUBLIC_SDK_KEY_ANDROID
/// - REVENUECAT_PUBLIC_SDK_KEY_IOS
/// - STRIPE_CHECKOUT_MONTHLY_URL
/// - STRIPE_CHECKOUT_ANNUAL_URL
///
/// This service also syncs the app's `/users/{uid}.subscriptionStatus` to
/// 'free' | 'premium' | 'premium_plus' based on RevenueCat entitlements.
class BillingService extends ChangeNotifier {
  BillingService._();
  static final BillingService instance = BillingService._();

  static const _rcKeyAndroid = String.fromEnvironment('REVENUECAT_PUBLIC_SDK_KEY_ANDROID');
  static const _rcKeyIos = String.fromEnvironment('REVENUECAT_PUBLIC_SDK_KEY_IOS');
  static const _stripeMonthlyUrl = String.fromEnvironment('STRIPE_CHECKOUT_MONTHLY_URL');
  static const _stripeAnnualUrl = String.fromEnvironment('STRIPE_CHECKOUT_ANNUAL_URL');

  Offerings? _offerings;
  CustomerInfo? _customerInfo;
  bool _initialized = false;

  Offerings? get offerings => _offerings;
  CustomerInfo? get customerInfo => _customerInfo;
  bool get isInitialized => _initialized;

  /// Initialize RevenueCat on iOS/Android. On web we skip.
  Future<void> initialize() async {
    if (_initialized) return;
    try {
      if (!kIsWeb) {
        final key = Platform.isAndroid ? _rcKeyAndroid : _rcKeyIos;
        if (key.isEmpty) {
          debugPrint('RevenueCat SDK key is not set for this platform.');
        } else {
          await Purchases.configure(PurchasesConfiguration(key));
          try {
            _customerInfo = await Purchases.getCustomerInfo();
          } catch (e) {
            debugPrint('getCustomerInfo error: $e');
          }
          try {
            _offerings = await Purchases.getOfferings();
          } catch (e) {
            debugPrint('getOfferings error: $e');
          }
          Purchases.addCustomerInfoUpdateListener((info) {
            _customerInfo = info;
            notifyListeners();
          });
        }
      }
    } catch (e) {
      debugPrint('Billing init error: $e');
    } finally {
      _initialized = true;
      notifyListeners();
    }
  }

  /// Determine app tier based on entitlements.
  /// RevenueCat entitlements expected: 'premium' and 'premium_plus'.
  String currentTier() {
    final info = _customerInfo;
    if (info == null) return 'free';
    final plus = info.entitlements.all['premium_plus'];
    if (plus != null && plus.isActive) return 'premium_plus';
    final premium = info.entitlements.all['premium'];
    if (premium != null && premium.isActive) return 'premium';
    return 'free';
  }

  /// Return the daily video limit and max seconds for the active tier.
  ({int dailyLimit, int maxSeconds}) limitsForTier([String? tier]) {
    final t = tier ?? currentTier();
    switch (t) {
      case 'premium_plus':
        return (dailyLimit: 8, maxSeconds: 30);
      case 'premium':
        return (dailyLimit: 3, maxSeconds: 20);
      default:
        // Free: 1 lifetime video; no daily limit (handled elsewhere)
        return (dailyLimit: 0, maxSeconds: 0);
    }
  }

  /// Purchase a package via RevenueCat. Returns true on success.
  Future<bool> purchasePackage(Package pkg) async {
    try {
      final purchase = await Purchases.purchasePackage(pkg);
      // purchases_flutter >=9 returns PurchaseResult
      try {
        _customerInfo = purchase.customerInfo;
      } catch (_) {
        // Older versions may return CustomerInfo directly
        if (purchase is CustomerInfo) {
          _customerInfo = purchase as CustomerInfo;
        }
      }
      notifyListeners();
      return true;
    } catch (e) {
      debugPrint('purchasePackage error: $e');
      return false;
    }
  }

  /// Restore purchases and refresh tier.
  Future<void> restorePurchases() async {
    try {
      _customerInfo = await Purchases.restorePurchases();
      notifyListeners();
    } catch (e) {
      debugPrint('restorePurchases error: $e');
    }
  }

  /// On web, open Stripe Checkout. Monthly or Annual.
  Future<void> openStripeCheckout({required bool annual}) async {
    final url = annual ? _stripeAnnualUrl : _stripeMonthlyUrl;
    if (url.isEmpty) {
      debugPrint('Stripe Checkout URL not configured.');
      return;
    }
    final uri = Uri.parse(url);
    if (!await canLaunchUrl(uri)) return;
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  /// Sync the user subscriptionStatus field in Firestore to match entitlements.
  Future<void> syncUserTierToFirestore(String uid) async {
    try {
      final tier = currentTier();
      await FirebaseFirestore.instance.collection('users').doc(uid).set(
        {
          'subscriptionStatus': tier,
          'analyticsSummary': {
            'lastActive': FieldValue.serverTimestamp(),
            // conversionDate set only on first non-free
          }
        },
        SetOptions(merge: true),
      );
      if (tier != 'free') {
        await FirebaseFirestore.instance.collection('users').doc(uid).set(
          {
            'analyticsSummary': {
              'conversionDate': FieldValue.serverTimestamp(),
            }
          },
          SetOptions(merge: true),
        );
      }
    } catch (e) {
      debugPrint('syncUserTierToFirestore error: $e');
    }
  }
}
