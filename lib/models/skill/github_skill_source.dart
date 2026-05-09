/// Normalized GitHub source for a skill install request.
class GitHubSkillSource {
  final String owner;
  final String repo;
  final String? ref;
  final String? subdirectory;

  const GitHubSkillSource({
    required this.owner,
    required this.repo,
    this.ref,
    this.subdirectory,
  });
}
