import 'package:ai_chat/models/skill/invoked_skill_context.dart';
import 'package:ai_chat/models/skill/skill_catalog_entry.dart';
import 'package:ai_chat/services/skills/skill_context_formatter.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('SkillContextFormatter', () {
    test('formats catalog reminder with stable sorting and omission notice',
        () {
      const formatter = SkillContextFormatter(maxCatalogItems: 2);

      final reminder = formatter.formatCatalogReminder(const [
        SkillCatalogEntry(
          id: 'zeta',
          name: 'zeta',
          description: 'Last skill.',
          qualifiedPath: '/skills/zeta',
          isEnabled: true,
        ),
        SkillCatalogEntry(
          id: 'alpha',
          name: 'alpha',
          description: 'First skill.',
          qualifiedPath: '/skills/alpha',
          isEnabled: true,
        ),
        SkillCatalogEntry(
          id: 'disabled',
          name: 'disabled',
          description: 'Should not appear.',
          qualifiedPath: '/skills/disabled',
          isEnabled: false,
        ),
        SkillCatalogEntry(
          id: 'beta',
          name: 'beta',
          description: 'Second skill.',
          qualifiedPath: '/skills/beta',
          isEnabled: true,
        ),
      ]);

      expect(
        reminder,
        contains(
            'The following skills are available for use with the Skill tool:'),
      );
      expect(reminder.indexOf('- alpha: First skill.'),
          lessThan(reminder.indexOf('- beta: Second skill.')));
      expect(reminder, isNot(contains('zeta')));
      expect(reminder, isNot(contains('disabled')));
      expect(reminder, contains('... 1 more skill omitted.'));
    });

    test('returns empty catalog reminder when no skills are enabled', () {
      const formatter = SkillContextFormatter();

      final reminder = formatter.formatCatalogReminder(const [
        SkillCatalogEntry(
          id: 'disabled',
          name: 'disabled',
          description: 'Should not appear.',
          qualifiedPath: '/skills/disabled',
          isEnabled: false,
        ),
      ]);

      expect(reminder, isEmpty);
    });

    test(
        'truncates invoked skill instructions with metadata and reminder notice',
        () {
      const formatter = SkillContextFormatter(maxInstructionCharacters: 24);
      const originalBody = '012345678901234567890123456789tail-sentinel';
      const context = InvokedSkillContext(
        skillId: 'edge-to-edge',
        name: 'edge-to-edge',
        qualifiedPath: '/skills/edge-to-edge',
        baseDirectory: '/skills/edge-to-edge',
        instructionBody: originalBody,
      );

      final prepared = formatter.prepareInvokedContext(context);
      final reminder = formatter.formatInvokedReminder(prepared);

      expect(context.instructionBody, originalBody);
      expect(prepared.instructionBodyTruncated, isTrue);
      expect(prepared.originalInstructionLength, originalBody.length);
      expect(prepared.instructionBody, isNot(contains('tail-sentinel')));
      expect(reminder, contains('### Skill: edge-to-edge'));
      expect(reminder, contains('Path: /skills/edge-to-edge'));
      expect(reminder,
          contains('Base directory for this skill: /skills/edge-to-edge'));
      expect(reminder, contains('[truncated]'));
    });
  });
}
