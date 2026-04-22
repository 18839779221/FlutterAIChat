import 'package:ai_chat/models/chat_message.dart';
import 'package:ai_chat/services/session_summary_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('SessionSummaryService', () {
    test('builds stable session summary prompt from projected history messages',
        () async {
      final service = SessionSummaryService(
        summaryGenerator: (messages) async {
          expect(messages.first.role, MessageRole.system);
          expect(messages.first.text, contains('当前目标：'));
          expect(messages.last.text, '我会先设计 SessionContextService');
          return '''
当前目标：实现 Session 上下文管理
已确认事实：需要按 token budget 自动压缩
用户偏好/限制：无
重要工具结论：无
未完成事项：接入 TurnHarness
风险与下一步：补齐 SessionContextService
''';
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

      expect(summary.summaryText, contains('当前目标'));
      expect(summary.summaryText, contains('未完成事项'));
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

    test('rolls previous summary together with newer historical messages',
        () async {
      final service = SessionSummaryService(
        summaryGenerator: (messages) async {
          expect(messages.first.role, MessageRole.system);
          expect(
              messages.map((item) => item.text).join('\n'), contains('最初需求'));
          expect(messages.map((item) => item.text).join('\n'),
              contains('仅 Android'));
          return '''
当前目标：最初需求
已确认事实：仅 Android
用户偏好/限制：无
已确认决策：无
已否决方案：无
重要工具结论：无
未完成事项：继续实现
风险与下一步：补齐滚动 summary
''';
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
  });
}
