import 'artifact_type.dart';

/// Stable persisted registry entry for one inline artifact file.
///
/// This record is the durable identity/source-path truth used to rebuild
/// artifact projections after app restart or group switching.
class ArtifactRecord {
  final int? id;
  final String artifactId;
  final int groupId;
  final String title;
  final ArtifactType type;
  final String sourcePath;
  final int originTurnId;
  final DateTime createdAt;
  final DateTime lastUpdatedAt;

  const ArtifactRecord({
    this.id,
    required this.artifactId,
    required this.groupId,
    required this.title,
    required this.type,
    required this.sourcePath,
    required this.originTurnId,
    required this.createdAt,
    required this.lastUpdatedAt,
  });

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'artifact_id': artifactId,
      'group_id': groupId,
      'title': title,
      'type': type.wireValue,
      'source_path': sourcePath,
      'origin_turn_id': originTurnId,
      'created_at': createdAt.millisecondsSinceEpoch,
      'last_updated_at': lastUpdatedAt.millisecondsSinceEpoch,
    };
  }

  factory ArtifactRecord.fromMap(Map<String, dynamic> map) {
    return ArtifactRecord(
      id: map['id'] as int?,
      artifactId: map['artifact_id'] as String? ?? '',
      groupId: map['group_id'] as int,
      title: map['title'] as String? ?? '',
      type: ArtifactTypeX.fromWireValue(map['type'] as String? ?? 'html'),
      sourcePath: map['source_path'] as String? ?? '',
      originTurnId: map['origin_turn_id'] as int,
      createdAt: DateTime.fromMillisecondsSinceEpoch(map['created_at'] as int),
      lastUpdatedAt:
          DateTime.fromMillisecondsSinceEpoch(map['last_updated_at'] as int),
    );
  }

  ArtifactRecord copyWith({
    int? id,
    String? artifactId,
    int? groupId,
    String? title,
    ArtifactType? type,
    String? sourcePath,
    int? originTurnId,
    DateTime? createdAt,
    DateTime? lastUpdatedAt,
  }) {
    return ArtifactRecord(
      id: id ?? this.id,
      artifactId: artifactId ?? this.artifactId,
      groupId: groupId ?? this.groupId,
      title: title ?? this.title,
      type: type ?? this.type,
      sourcePath: sourcePath ?? this.sourcePath,
      originTurnId: originTurnId ?? this.originTurnId,
      createdAt: createdAt ?? this.createdAt,
      lastUpdatedAt: lastUpdatedAt ?? this.lastUpdatedAt,
    );
  }
}
