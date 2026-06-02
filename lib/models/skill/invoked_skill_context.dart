/// Structured payload describing one skill that was explicitly invoked.
class InvokedSkillContext {
  /// Stable local identifier of the installed skill.
  final String skillId;

  /// Human-readable skill name shown in reminders and debugging surfaces.
  final String name;

  /// Canonical agent path used to identify the invoked skill in context.
  final String qualifiedPath;

  /// Agent path of the directory that contains the installed skill files.
  final String baseDirectory;

  /// Full instruction body loaded from the local `SKILL.md` file.
  final String instructionBody;

  /// Whether the planner-visible skill instruction body was shortened.
  final bool instructionBodyTruncated;

  /// Original instruction body length before planner-visible truncation.
  final int? originalInstructionLength;

  const InvokedSkillContext({
    required this.skillId,
    required this.name,
    required this.qualifiedPath,
    required this.baseDirectory,
    required this.instructionBody,
    this.instructionBodyTruncated = false,
    this.originalInstructionLength,
  });

  Map<String, dynamic> toJson() {
    return {
      'skillId': skillId,
      'name': name,
      'qualifiedPath': qualifiedPath,
      'baseDirectory': baseDirectory,
      'instructionBody': instructionBody,
      if (instructionBodyTruncated)
        'instructionBodyTruncated': instructionBodyTruncated,
      if (originalInstructionLength != null)
        'originalInstructionLength': originalInstructionLength,
    };
  }
}
