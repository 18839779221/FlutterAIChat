/// Lightweight skill list entry exposed to runtime reminders and the Skill tool.
class SkillCatalogEntry {
  /// Stable local identifier derived from the installed skill directory.
  final String id;

  /// Human-readable skill name shown to the model and settings UI.
  final String name;

  /// Short description displayed in the available skills reminder.
  final String description;

  /// Canonical local path hint for resolving this installed skill.
  final String qualifiedPath;

  /// Whether the skill is currently enabled for runtime use.
  final bool isEnabled;

  const SkillCatalogEntry({
    required this.id,
    required this.name,
    required this.description,
    required this.qualifiedPath,
    required this.isEnabled,
  });
}
