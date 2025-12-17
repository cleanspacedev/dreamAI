import 'package:cloud_firestore/cloud_firestore.dart';

/// User profile model for /users collection
///
/// Firestore schema:
/// - userId (string)
/// - email (string)
/// - createdAt (timestamp)
/// - preferences (map: { theme, voiceStyle, language })
/// - subscriptionStatus (string: 'free' | 'premium' | 'premium_plus')
/// - dailyUsage (map: { dreams, videos, lastReset })
/// - language (string)
/// - fcmToken (string)
/// - analyticsSummary (map: { totalDreams, totalVideos, lastActive, conversionDate })
class UserModel {
  final String userId;
  final String email;
  final DateTime createdAt;
  final Map<String, dynamic> preferences;
  final String subscriptionStatus;
  final Map<String, dynamic> dailyUsage;
  final String language;
  final String? fcmToken;
  final Map<String, dynamic> analyticsSummary;

  UserModel({
    required this.userId,
    required this.email,
    required this.createdAt,
    required this.preferences,
    required this.subscriptionStatus,
    required this.dailyUsage,
    required this.language,
    required this.analyticsSummary,
    this.fcmToken,
  });

  factory UserModel.fromJson(Map<String, dynamic> json) {
    final Timestamp createdTs = json['createdAt'] as Timestamp? ?? Timestamp.now();
    final Map<String, dynamic> prefs = (json['preferences'] as Map?)?.cast<String, dynamic>() ?? {
      'theme': 'system',
      'voiceStyle': 'default',
      'language': (json['language'] as String?) ?? 'en',
    };
    final Map<String, dynamic> usage = (json['dailyUsage'] as Map?)?.cast<String, dynamic>() ?? {
      'dreams': 0,
      'videos': 0,
      'lastReset': Timestamp.now(),
    };
    final Map<String, dynamic> analytics = (json['analyticsSummary'] as Map?)?.cast<String, dynamic>() ?? {
      'totalDreams': 0,
      'totalVideos': 0,
      'lastActive': Timestamp.now(),
      'conversionDate': null,
    };
    return UserModel(
      userId: (json['userId'] as String?) ?? (json['id'] as String? ?? ''),
      email: (json['email'] as String?) ?? '',
      createdAt: createdTs.toDate(),
      preferences: prefs,
      subscriptionStatus: (json['subscriptionStatus'] as String?) ?? 'free',
      dailyUsage: usage,
      language: (json['language'] as String?) ?? (prefs['language'] as String? ?? 'en'),
      fcmToken: json['fcmToken'] as String?,
      analyticsSummary: analytics,
    );
  }

  Map<String, dynamic> toJson() => {
        'userId': userId,
        'email': email,
        'createdAt': Timestamp.fromDate(createdAt),
        'preferences': preferences,
        'subscriptionStatus': subscriptionStatus,
        'dailyUsage': {
          'dreams': dailyUsage['dreams'] ?? 0,
          'videos': dailyUsage['videos'] ?? 0,
          'lastReset': dailyUsage['lastReset'] is Timestamp
              ? dailyUsage['lastReset']
              : Timestamp.fromDate((dailyUsage['lastReset'] as DateTime?) ?? DateTime.now()),
        },
        'language': language,
        'fcmToken': fcmToken,
        'analyticsSummary': {
          'totalDreams': analyticsSummary['totalDreams'] ?? 0,
          'totalVideos': analyticsSummary['totalVideos'] ?? 0,
          'lastActive': analyticsSummary['lastActive'] is Timestamp
              ? analyticsSummary['lastActive']
              : Timestamp.fromDate((analyticsSummary['lastActive'] as DateTime?) ?? DateTime.now()),
          'conversionDate': analyticsSummary['conversionDate'],
        },
      };

  UserModel copyWith({
    String? userId,
    String? email,
    DateTime? createdAt,
    Map<String, dynamic>? preferences,
    String? subscriptionStatus,
    Map<String, dynamic>? dailyUsage,
    String? language,
    String? fcmToken,
    Map<String, dynamic>? analyticsSummary,
  }) =>
      UserModel(
        userId: userId ?? this.userId,
        email: email ?? this.email,
        createdAt: createdAt ?? this.createdAt,
        preferences: preferences ?? this.preferences,
        subscriptionStatus: subscriptionStatus ?? this.subscriptionStatus,
        dailyUsage: dailyUsage ?? this.dailyUsage,
        language: language ?? this.language,
        fcmToken: fcmToken ?? this.fcmToken,
        analyticsSummary: analyticsSummary ?? this.analyticsSummary,
      );
}
