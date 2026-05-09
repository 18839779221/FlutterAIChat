/// Structured payload describing one skill that was explicitly invoked.
class InvokedSkillContext {
  /// Stable local identifier of the installed skill.
  final String skillId;

  /// Human-readable skill name shown in reminders and debugging surfaces.
  final String name;

  /// Canonical path hint used to identify the invoked skill in context.
  final String qualifiedPath;

  /// Absolute directory that contains the installed skill files.
  final String baseDirectory;

  /// Full instruction body loaded from the local `SKILL.md` file.
  final String instructionBody;

  const InvokedSkillContext({
    required this.skillId,
    required this.name,
    required this.qualifiedPath,
    required this.baseDirectory,
    required this.instructionBody,
  });

  Map<String, dynamic> toJson() {
    return {
      'skillId': skillId,
      'name': name,
      'qualifiedPath': qualifiedPath,
      'baseDirectory': baseDirectory,
      'instructionBody': instructionBody,
    };
  }
}
