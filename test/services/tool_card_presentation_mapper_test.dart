import 'package:ai_chat/models/chat/tool_workflow_step.dart';
import 'package:ai_chat/models/tool/tool_result.dart';
import 'package:ai_chat/services/tool_card_presentation_mapper.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ToolCardPresentationMapper', () {
    test('maps web_search success to inlineStep', () {
      final result = ToolResult(
        toolName: 'web_search',
        status: ToolExecutionStatus.success,
        summary: '已执行联网搜索',
        data: const {
          'query': 'planner',
          'results': [],
        },
      );

      final model = ToolCardPresentationMapper.mapResult(result);

      expect(model.variant.name, 'inlineStep');
      expect(model.title, '联网搜索');
      expect(model.summary, '已执行联网搜索');
    });

    test('maps create_reminder success to outcomeCard', () {
      final result = ToolResult(
        toolName: 'create_reminder',
        status: ToolExecutionStatus.success,
        summary: '已发起提醒创建：设计评审',
        data: const {
          'title': '设计评审',
          'dueAt': '2026-04-18T09:00:00Z',
        },
      );

      final model = ToolCardPresentationMapper.mapResult(result);

      expect(model.variant.name, 'outcomeCard');
      expect(model.title, '创建提醒');
      expect(model.primaryFields['title'], '设计评审');
      expect(model.primaryFields['dueAt'], '2026-04-18T09:00:00Z');
    });

    test('maps awaiting confirmation workflow step to confirmationStep', () {
      const step = ToolWorkflowStep(
        stepId: 'step-1',
        turnId: 'turn-1',
        toolName: 'create_calendar_event',
        title: '准备创建日历事件',
        summary: '将创建设计评审日程',
        status: ToolWorkflowStepStatus.awaitingConfirmation,
        requiresConfirmation: true,
        details: {
          'title': '设计评审',
          'startAt': '2026-04-18T09:00:00Z',
        },
      );

      final model = ToolCardPresentationMapper.mapStep(step);

      expect(model.variant.name, 'confirmationStep');
      expect(model.title, '准备创建日历事件');
      expect(model.primaryFields['title'], '设计评审');
      expect(model.primaryFields['startAt'], '2026-04-18T09:00:00Z');
    });
  });
}
