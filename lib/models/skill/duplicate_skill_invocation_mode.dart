/// Controls how the skill tool behaves when the same skill is invoked again
/// within the current turn.
enum DuplicateSkillInvocationMode {
  /// Reuse the already loaded skill result and report success without reload.
  reuse,

  /// Re-read and reformat the skill again, still reporting success.
  reload,
}
