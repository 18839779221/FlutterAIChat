import 'artifact_type.dart';

/// Structured outcome returned after persisting an inline artifact source.
class ArtifactCreateResult {
  final String artifactId;
  final String title;
  final ArtifactType type;
  final String sourcePath;
  final int bytes;
  final List<String> warnings;

  const ArtifactCreateResult({
    required this.artifactId,
    required this.title,
    required this.type,
    required this.sourcePath,
    required this.bytes,
    this.warnings = const <String>[],
  });

  Map<String, dynamic> toJson() {
    return {
      'artifactId': artifactId,
      'title': title,
      'type': type.wireValue,
      'sourcePath': sourcePath,
      'bytes': bytes,
      'warnings': warnings,
    };
  }
}
