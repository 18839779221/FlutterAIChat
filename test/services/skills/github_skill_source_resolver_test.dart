import 'package:ai_chat/services/skills/github_skill_source_resolver.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('GitHubSkillSourceResolver', () {
    test('parses a repository root url', () {
      final source = const GitHubSkillSourceResolver().resolve(
        'https://github.com/android/skills',
      );

      expect(source.owner, 'android');
      expect(source.repo, 'skills');
      expect(source.ref, isNull);
      expect(source.subdirectory, isNull);
    });

    test('parses a tree url with ref and subdirectory', () {
      final source = const GitHubSkillSourceResolver().resolve(
        'https://github.com/android/skills/tree/main/edge-to-edge',
      );

      expect(source.owner, 'android');
      expect(source.repo, 'skills');
      expect(source.ref, 'main');
      expect(source.subdirectory, 'edge-to-edge');
    });

    test('throws for a non GitHub url', () {
      expect(
        () => const GitHubSkillSourceResolver().resolve(
          'https://example.com/foo',
        ),
        throwsA(isA<GitHubSkillSourceFormatException>()),
      );
    });
  });
}
