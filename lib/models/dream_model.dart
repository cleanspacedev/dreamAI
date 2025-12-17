import 'package:cloud_firestore/cloud_firestore.dart';

/// Dream model representing a user's dream entry
class DreamModel {
  final String id;
  final String ownerId;
  final String title;
  final String description;
  final List<String> tags;
  final String? audioUrl;
  final String? imageUrl;
  final DateTime dreamDate;
  final DateTime createdAt;
  final DateTime updatedAt;
  final Map<String, dynamic>? metadata;
  final bool archived;

  DreamModel({
    required this.id,
    required this.ownerId,
    required this.title,
    required this.description,
    this.tags = const [],
    this.audioUrl,
    this.imageUrl,
    required this.dreamDate,
    required this.createdAt,
    required this.updatedAt,
    this.metadata,
    this.archived = false,
  });

  factory DreamModel.fromJson(Map<String, dynamic> json) => DreamModel(
        id: json['id'] as String,
        ownerId: json['ownerId'] as String,
        title: json['title'] as String,
        description: json['description'] as String,
        tags: (json['tags'] as List<dynamic>?)?.map((e) => e as String).toList() ?? [],
        audioUrl: json['audioUrl'] as String?,
        imageUrl: json['imageUrl'] as String?,
        dreamDate: (json['dreamDate'] as Timestamp).toDate(),
        createdAt: (json['createdAt'] as Timestamp).toDate(),
        updatedAt: (json['updatedAt'] as Timestamp).toDate(),
        metadata: json['metadata'] as Map<String, dynamic>?,
        archived: (json['archived'] as bool?) ?? false,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'ownerId': ownerId,
        'title': title,
        'description': description,
        'tags': tags,
        'audioUrl': audioUrl,
        'imageUrl': imageUrl,
        'dreamDate': Timestamp.fromDate(dreamDate),
        'createdAt': Timestamp.fromDate(createdAt),
        'updatedAt': Timestamp.fromDate(updatedAt),
        'metadata': metadata,
        'archived': archived,
      };

  DreamModel copyWith({
    String? id,
    String? ownerId,
    String? title,
    String? description,
    List<String>? tags,
    String? audioUrl,
    String? imageUrl,
    DateTime? dreamDate,
    DateTime? createdAt,
    DateTime? updatedAt,
    Map<String, dynamic>? metadata,
    bool? archived,
  }) =>
      DreamModel(
        id: id ?? this.id,
        ownerId: ownerId ?? this.ownerId,
        title: title ?? this.title,
        description: description ?? this.description,
        tags: tags ?? this.tags,
        audioUrl: audioUrl ?? this.audioUrl,
        imageUrl: imageUrl ?? this.imageUrl,
        dreamDate: dreamDate ?? this.dreamDate,
        createdAt: createdAt ?? this.createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
        metadata: metadata ?? this.metadata,
        archived: archived ?? this.archived,
      );
}
