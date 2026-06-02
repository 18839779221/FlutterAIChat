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

    test('injects default workspace section when group workspace is null',
        () async {
      final service = RuntimeUserContextService(
        workspaceIdResolver: (_) async => null,
        platformContextProvider: () => const [],
      );

      final snapshot = await service.buildSnapshot(groupId: 1);
      final combined = snapshot.additionalSections.join('\n');

      expect(
        combined,
        contains(
          '# currentWorkspace\nCurrent workspace: .default (default workspace).\nFile root: /workspaces/.default',
        ),
      );
    });

    test('injects explicit workspace section when group workspace is set',
        () async {
      final service = RuntimeUserContextService(
        workspaceIdResolver: (_) async => 'ws_20260602_a3k9qx',
        platformContextProvider: () => const [],
      );

      final snapshot = await service.buildSnapshot(groupId: 9);
      final combined = snapshot.additionalSections.join('\n');

      expect(
        combined,
        contains(
          '# currentWorkspace\nCurrent workspace: ws_20260602_a3k9qx.\nFile root: /workspaces/ws_20260602_a3k9qx',
        ),
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
