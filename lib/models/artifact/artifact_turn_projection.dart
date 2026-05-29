import 'artifact_type.dart';

/// Read-model snapshot for rendering one artifact reference inside a turn.
class ArtifactTurnProjection {
  final String artifactId;
  final String turnId;
  final String title;
  final ArtifactType type;
  /// Provider-native tool call id used to pair runtime preview and the
  /// persisted artifact result for the same create_artifact execution.
  final String? providerCallId;
  /// Whether this projection comes from transient streaming tool arguments
  /// instead of the persisted create_artifact result.
  final bool isRuntimePreview;
  final String sourcePath;
  final String? source;
  final int? sourceMessageId;
  final DateTime createdAt;
  final DateTime updatedAt;

  const ArtifactTurnProjection({
    required this.artifactId,
    required this.turnId,
    required this.title,
    required this.type,
    this.providerCallId,
    this.isRuntimePreview = false,
    required this.sourcePath,
    required this.source,
    required this.createdAt,
    required this.updatedAt,
    this.sourceMessageId,
  });
}
