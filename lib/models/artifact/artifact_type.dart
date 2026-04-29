/// Supported persisted artifact source kinds.
enum ArtifactType {
  html,
  svg,
}

extension ArtifactTypeX on ArtifactType {
  String get wireValue => name;

  static ArtifactType fromWireValue(String value) {
    return ArtifactType.values.firstWhere(
      (item) => item.name == value,
      orElse: () => ArtifactType.html,
    );
  }
}
