import 'artifact_type.dart';

/// Runtime-only inline artifact preview derived from streamed tool arguments.
///
/// This model is transient UI state. It is not persisted and does not replace
/// the final artifact projection rebuilt from tool results and storage.
class RuntimeArtifactPreview {
  final String turnId;
  final String entryId;
  final String artifactId;
  final String title;
  final ArtifactType type;
  final String? source;
  final String sourcePath;
  final DateTime createdAt;
  final DateTime updatedAt;

  const RuntimeArtifactPreview({
    required this.turnId,
    required this.entryId,
    required this.artifactId,
    required this.title,
    required this.type,
    required this.source,
    required this.sourcePath,
    required this.createdAt,
    required this.updatedAt,
  });
}
