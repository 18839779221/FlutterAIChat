import 'package:ai_chat/models/chat_message.dart';
import 'package:ai_chat/services/session_summary_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('SessionSummaryService', () {
    test('uses claude-style continuation summary prompt sections',
        () async {
      final service = SessionSummaryService(
        summaryGenerator: (messages) async {
          expect(messages.first.role, MessageRole.system);
          final prompt = messages.first.text;
          expect(prompt, contains('<analysis>'));
          expect(prompt, contains('<summary>'));
          expect(prompt, contains('Primary Request and Intent'));
          expect(prompt, contains('All user messages'));
          expect(prompt, contains('Context for Continuing Work'));
          expect(
            prompt,
            contains('If the current task does not involve code files'),
          );
          expect(messages.last.text, '我会先设计 SessionContextService');
          return '<summary>ok</summary>';
        },
      );

      final summary = await service.summarize(
        groupId: 1,
        projectedHistory: [
          ChatMessage(text: '我们需要支持多轮上下文', role: MessageRole.user),
          ChatMessage(
            text: '我会先设计 SessionContextService',
            role: MessageRole.assistant,
          ),
        ],
      );

      expect(summary.summaryText, 'ok');
      expect(summary.estimatedTokens, greaterThan(0));
    });

    test('throws when generator returns an empty summary', () async {
      final service = SessionSummaryService(
        summaryGenerator: (_) async => '   ',
      );

      expect(
        () => service.summarize(
          groupId: 1,
          projectedHistory: [
            ChatMessage(text: '继续', role: MessageRole.user),
          ],
        ),
        throwsA(isA<StateError>()),
      );
    });

    test('exposes stable summary instruction prompt for downstream callers',
        () async {
      expect(
        SessionSummaryService.summaryInstructionPrompt,
        contains('<analysis>'),
      );
      expect(
        SessionSummaryService.summaryInstructionPrompt,
        contains('<summary>'),
      );
      expect(
        SessionSummaryService.summaryInstructionPrompt,
        contains('Primary Request and Intent'),
      );
      expect(
        SessionSummaryService.summaryInstructionPrompt,
        contains('Context for Continuing Work'),
      );
    });

    test('rolls previous summary together with newer historical messages',
        () async {
      final service = SessionSummaryService(
        summaryGenerator: (messages) async {
          expect(messages.first.role, MessageRole.system);
          expect(
              messages.map((item) => item.text).join('\n'), contains('最初需求'));
          expect(messages.map((item) => item.text).join('\n'),
              contains('仅 Android'));
          return '<summary>Current Work: 最初需求\nContext for Continuing Work: 仅 Android</summary>';
        },
      );

      final summary = await service.summarizeHistory(
        previousSummary: '当前目标：最初需求',
        historicalMessages: [
          ChatMessage(text: '用户后来新增约束：仅 Android', role: MessageRole.user),
        ],
      );

      expect(summary.summaryText, contains('最初需求'));
      expect(summary.summaryText, contains('仅 Android'));
    });

    test('strips analysis block before persisting summary text', () async {
      final service = SessionSummaryService(
        summaryGenerator: (_) async => '''
<analysis>
internal scratchpad
</analysis>
<summary>
Primary Request and Intent: continue task
</summary>
''',
      );

      final summary = await service.summarizeHistory(
        historicalMessages: [
          ChatMessage(text: '继续', role: MessageRole.user),
        ],
      );

      expect(summary.summaryText, isNot(contains('internal scratchpad')));
      expect(summary.summaryText, contains('Primary Request and Intent'));
    });
  });
}
