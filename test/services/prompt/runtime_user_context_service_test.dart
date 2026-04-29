import 'package:ai_chat/services/prompt/runtime_user_context_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('RuntimeUserContextService', () {
    test('builds runtime user context with current date and optional AGENTS text',
        () async {
      final service = RuntimeUserContextService(
        nowProvider: () => DateTime(2026, 4, 24, 9, 30),
        agentsMdProvider: () async =>
            'Project rule: prefer AGENTS.md naming.',
        platformContextProvider: () => const [
          'Current runtime platform: Android phone app.',
          'Prefer compact, touch-friendly layouts that fit narrow mobile screens.',
        ],
      );

      final snapshot = await service.buildSnapshot();

      expect(snapshot.currentDateText, contains('2026-04-24'));
      expect(snapshot.agentsMdText, contains('AGENTS.md'));
      expect(
        snapshot.additionalSections.join('\n'),
        contains('Current runtime platform: Android phone app.'),
      );
    });

    test('buildCurrentMonthYearLabel returns stable English month-year text', () {
      final service = RuntimeUserContextService(
        nowProvider: () => DateTime(2026, 4, 24, 9, 30),
      );

      expect(service.buildCurrentMonthYearLabel(), 'April 2026');
    });
  });
}
