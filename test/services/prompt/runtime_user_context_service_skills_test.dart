import 'package:ai_chat/models/skill/skill_catalog_entry.dart';
import 'package:ai_chat/services/prompt/runtime_user_context_service.dart';
import 'package:ai_chat/services/skills/skill_context_formatter.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('RuntimeUserContextService skills', () {
    test('builds skills list reminder block from enabled skills', () async {
      final service = RuntimeUserContextService(
        nowProvider: () => DateTime(2026, 5, 9, 10, 0),
        skillCatalogProvider: () async => const [
          SkillCatalogEntry(
            id: 'edge-to-edge',
            name: 'edge-to-edge',
            description: 'Improve Android edge-to-edge handling.',
            qualifiedPath: '/skills/installed/edge-to-edge',
            isEnabled: true,
          ),
          SkillCatalogEntry(
            id: 'verify',
            name: 'verify',
            description: 'Run project verification after code changes.',
            qualifiedPath: '/skills/installed/verify',
            isEnabled: true,
          ),
        ],
      );

      final snapshot = await service.buildSnapshot();
      final combined = snapshot.skillsSectionText;

      expect(
        combined,
        contains(
            'The following skills are available for use with the Skill tool:'),
      );
      expect(
        combined,
        contains('- edge-to-edge: Improve Android edge-to-edge handling.'),
      );
      expect(
        combined,
        contains('- verify: Run project verification after code changes.'),
      );
    });

    test('omits skills list block when there are no enabled skills', () async {
      final service = RuntimeUserContextService(
        nowProvider: () => DateTime(2026, 5, 9, 10, 0),
        skillCatalogProvider: () async => const [],
      );

      final snapshot = await service.buildSnapshot();
      final combined = snapshot.skillsSectionText;

      expect(
        combined,
        isEmpty,
      );
    });

    test('truncates skills list reminder with stable ordering', () async {
      final service = RuntimeUserContextService(
        nowProvider: () => DateTime(2026, 5, 9, 10, 0),
        skillContextFormatter: const SkillContextFormatter(maxCatalogItems: 2),
        skillCatalogProvider: () async => const [
          SkillCatalogEntry(
            id: 'zeta',
            name: 'zeta',
            description: 'Last skill.',
            qualifiedPath: '/skills/installed/zeta',
            isEnabled: true,
          ),
          SkillCatalogEntry(
            id: 'alpha',
            name: 'alpha',
            description: 'First skill.',
            qualifiedPath: '/skills/installed/alpha',
            isEnabled: true,
          ),
          SkillCatalogEntry(
            id: 'beta',
            name: 'beta',
            description: 'Second skill.',
            qualifiedPath: '/skills/installed/beta',
            isEnabled: true,
          ),
        ],
      );

      final snapshot = await service.buildSnapshot();
      final combined = snapshot.skillsSectionText;

      expect(combined, contains('- alpha: First skill.'));
      expect(combined, contains('- beta: Second skill.'));
      expect(combined, contains('... 1 more skill omitted.'));
      expect(combined, isNot(contains('zeta')));
    });
  });
}
