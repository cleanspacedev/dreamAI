import 'package:cloud_firestore/cloud_firestore.dart';

/// Dream Analysis model representing AI-generated analysis of a dream
class DreamAnalysisModel {
  final String id;
  final String dreamId;
  final String ownerId;
  final String interpretation;
  final List<String> symbols;
  final Map<String, dynamic> emotions;
  final String? recommendation;
  final DateTime createdAt;
  final DateTime updatedAt;

  DreamAnalysisModel({
    required this.id,
    required this.dreamId,
    required this.ownerId,
    required this.interpretation,
    this.symbols = const [],
    this.emotions = const {},
    this.recommendation,
    required this.createdAt,
    required this.updatedAt,
  });

  factory DreamAnalysisModel.fromJson(Map<String, dynamic> json) => DreamAnalysisModel(
        id: json['id'] as String,
        dreamId: json['dreamId'] as String,
        ownerId: json['ownerId'] as String,
        interpretation: json['interpretation'] as String,
        symbols: (json['symbols'] as List<dynamic>?)?.map((e) => e as String).toList() ?? [],
        emotions: json['emotions'] as Map<String, dynamic>? ?? {},
        recommendation: json['recommendation'] as String?,
        createdAt: (json['createdAt'] as Timestamp).toDate(),
        updatedAt: (json['updatedAt'] as Timestamp).toDate(),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'dreamId': dreamId,
        'ownerId': ownerId,
        'interpretation': interpretation,
        'symbols': symbols,
        'emotions': emotions,
        'recommendation': recommendation,
        'createdAt': Timestamp.fromDate(createdAt),
        'updatedAt': Timestamp.fromDate(updatedAt),
      };

  DreamAnalysisModel copyWith({
    String? id,
    String? dreamId,
    String? ownerId,
    String? interpretation,
    List<String>? symbols,
    Map<String, dynamic>? emotions,
    String? recommendation,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) =>
      DreamAnalysisModel(
        id: id ?? this.id,
        dreamId: dreamId ?? this.dreamId,
        ownerId: ownerId ?? this.ownerId,
        interpretation: interpretation ?? this.interpretation,
        symbols: symbols ?? this.symbols,
        emotions: emotions ?? this.emotions,
        recommendation: recommendation ?? this.recommendation,
        createdAt: createdAt ?? this.createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
      );
}
