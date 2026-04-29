import 'artifact_type.dart';

/// Read-model snapshot for rendering one artifact reference inside a turn.
class ArtifactTurnProjection {
  final String artifactId;
  final String turnId;
  final String title;
  final ArtifactType type;
  final String sourcePath;
  final String? source;
  final bool isStale;
  final int? sourceMessageId;
  final DateTime createdAt;
  final DateTime updatedAt;

  const ArtifactTurnProjection({
    required this.artifactId,
    required this.turnId,
    required this.title,
    required this.type,
    required this.sourcePath,
    required this.source,
    required this.isStale,
    required this.createdAt,
    required this.updatedAt,
    this.sourceMessageId,
  });
}
