import '../../models/skill/github_skill_source.dart';

class GitHubSkillSourceFormatException implements Exception {
  final String message;

  const GitHubSkillSourceFormatException(this.message);

  @override
  String toString() => 'GitHubSkillSourceFormatException: $message';
}

class GitHubSkillSourceResolver {
  const GitHubSkillSourceResolver();

  GitHubSkillSource resolve(String input) {
    final uri = Uri.tryParse(input.trim());
    if (uri == null ||
        uri.scheme != 'https' ||
        uri.host != 'github.com' ||
        uri.pathSegments.length < 2) {
      throw const GitHubSkillSourceFormatException('Unsupported GitHub URL.');
    }

    final owner = uri.pathSegments[0];
    final repo = uri.pathSegments[1];
    if (owner.isEmpty || repo.isEmpty) {
      throw const GitHubSkillSourceFormatException('Unsupported GitHub URL.');
    }

    if (uri.pathSegments.length == 2) {
      return GitHubSkillSource(owner: owner, repo: repo);
    }

    if (uri.pathSegments.length >= 5 && uri.pathSegments[2] == 'tree') {
      final ref = uri.pathSegments[3];
      final subdirectory = uri.pathSegments.sublist(4).join('/');
      if (ref.isEmpty || subdirectory.isEmpty) {
        throw const GitHubSkillSourceFormatException('Unsupported GitHub URL.');
      }
      return GitHubSkillSource(
        owner: owner,
        repo: repo,
        ref: ref,
        subdirectory: subdirectory,
      );
    }

    throw const GitHubSkillSourceFormatException('Unsupported GitHub URL.');
  }
}
