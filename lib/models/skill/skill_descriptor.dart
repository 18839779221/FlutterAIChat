enum SkillSourceType {
  localInstalled,
  githubInstalled,
}

/// Static metadata parsed from one installed skill directory.
class SkillDescriptor {
  /// Stable local identifier used for indexing and enable/disable settings.
  final String id;

  /// Human-readable skill name declared by the skill author.
  final String name;

  /// Short summary shown in settings and installer previews.
  final String description;

  /// Markdown body content used to guide the planner when the skill is active.
  final String bodyText;

  /// Absolute directory containing this installed skill.
  final String skillRootPath;

  /// Absolute path to the skill entry markdown file.
  final String entryFilePath;

  /// Installation source classification used for UI and future sync logic.
  final SkillSourceType sourceType;

  /// Whether the skill participates in runtime matching.
  final bool isEnabled;

  const SkillDescriptor({
    required this.id,
    required this.name,
    required this.description,
    required this.bodyText,
    required this.skillRootPath,
    required this.entryFilePath,
    required this.sourceType,
    required this.isEnabled,
  });
}
