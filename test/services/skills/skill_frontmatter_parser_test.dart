import 'package:ai_chat/services/skills/skill_frontmatter_parser.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('SkillFrontmatterParser', () {
    test('parses name description and body from a valid skill file', () {
      const source = '''
---
name: edge-to-edge
description: Improve Android edge-to-edge handling.
---
# Overview
Use Android edge-to-edge guidance.
''';

      final result = const SkillFrontmatterParser().parse(source);

      expect(result.name, 'edge-to-edge');
      expect(result.description, 'Improve Android edge-to-edge handling.');
      expect(result.body.trim(), startsWith('# Overview'));
    });

    test('throws when name is missing', () {
      const source = '''
---
description: Improve Android edge-to-edge handling.
---
# Overview
Use Android edge-to-edge guidance.
''';

      expect(
        () => const SkillFrontmatterParser().parse(source),
        throwsA(isA<SkillFrontmatterFormatException>()),
      );
    });

    test('throws when description is missing', () {
      const source = '''
---
name: edge-to-edge
---
# Overview
Use Android edge-to-edge guidance.
''';

      expect(
        () => const SkillFrontmatterParser().parse(source),
        throwsA(isA<SkillFrontmatterFormatException>()),
      );
    });

    test('parses multiline yaml description blocks', () {
      const source = '''
---
name: edge-to-edge
description: Use this skill to migrate your app to add adaptive edge-to-edge
  support and troubleshoot common issues.
metadata:
  author: Google LLC
---
# Overview
Use Android edge-to-edge guidance.
''';

      final result = const SkillFrontmatterParser().parse(source);

      expect(result.name, 'edge-to-edge');
      expect(
        result.description,
        contains('adaptive edge-to-edge support and troubleshoot'),
      );
    });
  });
}
