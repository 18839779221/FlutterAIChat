import 'package:ai_chat/models/agent/chat_turn_step.dart';
import 'package:ai_chat/models/chat_turn.dart';
import 'package:ai_chat/services/turn_ledger_builder_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('TurnLedgerBuilderService', () {
    test('builds planner summary with completed and pending steps', () {
      const service = TurnLedgerBuilderService();
      final summary = service.buildPlannerSummary(
        turn: ChatTurn(
          id: 1,
          groupId: 1,
          status: ChatTurnStatus.running,
          userInput: '先查历史、保存笔记、再创建提醒',
          goalSummary: '完成数据库确认闭环',
          providerStyle: ChatTurnProviderStyle.openaiResponses,
        ),
        steps: [
          ChatTurnStep(
            id: 1,
            turnId: 1,
            stepIndex: 1,
            toolName: 'search_chat_history',
            toolArgsJson: const {'query': '数据库版本 发版时间'},
            status: ChatTurnStepStatus.completed,
            resultSummary: '确认数据库版本 7，发版时间 4 月 20 日',
          ),
          ChatTurnStep(
            id: 2,
            turnId: 1,
            stepIndex: 2,
            toolName: 'save_note',
            toolArgsJson: const {'title': '数据库版本确认'},
            status: ChatTurnStepStatus.planned,
          ),
          ChatTurnStep(
            id: 3,
            turnId: 1,
            stepIndex: 3,
            toolName: 'create_reminder',
            toolArgsJson: const {'title': '同步结论给测试同学'},
            status: ChatTurnStepStatus.planned,
          ),
        ],
      );

      expect(summary, contains('用户目标：先查历史、保存笔记、再创建提醒'));
      expect(summary, contains('目标摘要：完成数据库确认闭环'));
      expect(summary, contains('已完成步骤：'));
      expect(summary, contains('1. search_chat_history'));
      expect(summary, contains('确认数据库版本 7，发版时间 4 月 20 日'));
      expect(summary, contains('待完成步骤：'));
      expect(summary, contains('2. save_note'));
      expect(summary, contains('3. create_reminder'));
    });

    test('builds final answer summary with only finished steps', () {
      const service = TurnLedgerBuilderService();
      final summary = service.buildFinalAnswerSummary(
        turn: ChatTurn(
          id: 2,
          groupId: 1,
          status: ChatTurnStatus.completed,
          userInput: '帮我完成数据库确认闭环',
          goalSummary: '数据库版本确认闭环',
          providerStyle: ChatTurnProviderStyle.openaiChatCompletions,
        ),
        steps: [
          ChatTurnStep(
            id: 1,
            turnId: 2,
            stepIndex: 1,
            toolName: 'search_chat_history',
            toolArgsJson: const {'query': '数据库版本 发版时间'},
            status: ChatTurnStepStatus.completed,
            resultSummary: '确认数据库版本 7，发版时间 4 月 20 日',
          ),
          ChatTurnStep(
            id: 2,
            turnId: 2,
            stepIndex: 2,
            toolName: 'save_note',
            toolArgsJson: const {'title': '数据库版本确认'},
            status: ChatTurnStepStatus.completed,
            resultSummary: '已保存笔记《数据库版本确认》',
          ),
          ChatTurnStep(
            id: 3,
            turnId: 2,
            stepIndex: 3,
            toolName: 'create_reminder',
            toolArgsJson: const {'title': '同步结论给测试同学'},
            status: ChatTurnStepStatus.completed,
            resultSummary: '已创建今晚 9 点提醒',
          ),
        ],
      );

      expect(summary, contains('本轮工具执行总结：'));
      expect(summary, contains('search_chat_history'));
      expect(summary, contains('save_note'));
      expect(summary, contains('create_reminder'));
      expect(summary, isNot(contains('待完成步骤')));
    });

    test('builds final answer summary with failed steps when present', () {
      const service = TurnLedgerBuilderService();
      final summary = service.buildFinalAnswerSummary(
        turn: ChatTurn(
          id: 3,
          groupId: 1,
          status: ChatTurnStatus.completed,
          userInput: '先保存结论，再分享给测试同学',
          goalSummary: '同步数据库版本确认',
          providerStyle: ChatTurnProviderStyle.openaiResponses,
        ),
        steps: [
          ChatTurnStep(
            id: 1,
            turnId: 3,
            stepIndex: 1,
            toolName: 'save_note',
            toolArgsJson: const {'title': '数据库版本确认'},
            status: ChatTurnStepStatus.completed,
            resultSummary: '已保存笔记《数据库版本确认》',
          ),
          ChatTurnStep(
            id: 2,
            turnId: 3,
            stepIndex: 2,
            toolName: 'share_result',
            toolArgsJson: const {'target': '测试同学'},
            status: ChatTurnStepStatus.failed,
            errorCode: 'share_failed',
            resultSummary: '分享失败，请稍后重试',
          ),
        ],
      );

      expect(summary, contains('本轮工具执行总结：'));
      expect(summary, contains('save_note'));
      expect(summary, contains('失败步骤：'));
      expect(summary, contains('share_result'));
      expect(summary, contains('share_failed'));
      expect(summary, contains('分享失败，请稍后重试'));
    });
  });
}
