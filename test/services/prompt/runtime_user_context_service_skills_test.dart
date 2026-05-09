import 'package:ai_chat/models/skill/skill_catalog_entry.dart';
import 'package:ai_chat/services/prompt/runtime_user_context_service.dart';
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
            qualifiedPath: '/tmp/skills/edge-to-edge',
            isEnabled: true,
          ),
          SkillCatalogEntry(
            id: 'verify',
            name: 'verify',
            description: 'Run project verification after code changes.',
            qualifiedPath: '/tmp/skills/verify',
            isEnabled: true,
          ),
        ],
      );

      final snapshot = await service.buildSnapshot();
      final combined = snapshot.additionalSections.join('\n');

      expect(
        combined,
        contains('The following skills are available for use with the Skill tool:'),
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
      final combined = snapshot.additionalSections.join('\n');

      expect(
        combined,
        isNot(contains('The following skills are available for use with the Skill tool:')),
      );
    });
  });
}
