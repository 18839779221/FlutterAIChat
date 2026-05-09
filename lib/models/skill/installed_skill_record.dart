enum InstalledSkillStatus {
  ok,
  invalid,
  disabled,
}

/// Local installation state tracked outside the prompt/runtime layer.
class InstalledSkillRecord {
  /// Stable local skill identifier.
  final String skillId;

  /// Current health and availability of this installed skill.
  final InstalledSkillStatus status;

  /// Optional explanation for invalid or degraded installs.
  final String? installNotes;

  const InstalledSkillRecord({
    required this.skillId,
    required this.status,
    this.installNotes,
  });
}
