import 'package:ai_chat/models/chat/assistant_turn_block.dart';
import 'package:ai_chat/models/chat/tool_phase_visibility.dart';
import 'package:ai_chat/models/chat/tool_presentation_event.dart';
import 'package:ai_chat/models/chat/tool_workflow_step.dart';
import 'package:ai_chat/models/chat_message.dart';
import 'package:ai_chat/models/response/message_content_type.dart';
import 'package:ai_chat/models/tool/tool_result.dart';
import 'package:ai_chat/services/tool_presentation_block_projector.dart';
import 'package:ai_chat/services/tool_ui_renderer_registry.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ToolPresentationBlockProjector', () {
    const projector = ToolPresentationBlockProjector();

    test('projects proposed event into a workflow block', () {
      final blocks = projector.project(
        events: [
          ToolPresentationEvent(
            toolName: 'Write',
            phase: ToolPresentationEventPhase.proposed,
            turnId: '7_30',
            stepId: '7_30-step-9',
            sourceContentType: MessageContentType.toolInvocation,
            timestamp: DateTime(2026, 4, 30, 10, 0, 1),
            data: const {
              'summary': '准备写入文件',
              'arguments': {'file_path': 'lib/main.dart'},
              'requiresConfirmation': false,
            },
          ),
        ],
      );

      expect(blocks, hasLength(1));
      expect(blocks.single.type, AssistantTurnBlockType.toolWorkflow);
      expect(blocks.single.status, 'proposed');
      expect(blocks.single.payload?['steps'][0]['details']['file_path'],
          'lib/main.dart');
    });

    test('merges repeated step updates into the same workflow block', () {
      final blocks = projector.project(
        events: [
          ToolPresentationEvent(
            toolName: 'LS',
            phase: ToolPresentationEventPhase.proposed,
            turnId: '7_30',
            stepId: '7_30-step-9',
            providerCallId: 'call_1',
            sourceContentType: MessageContentType.toolInvocation,
            timestamp: DateTime(2026, 4, 30, 10, 0, 1),
            data: const {
              'summary': '准备列目录',
              'arguments': {'path': 'lib'},
            },
          ),
          ToolPresentationEvent(
            toolName: 'LS',
            phase: ToolPresentationEventPhase.running,
            turnId: '7_30',
            stepId: '7_30-step-9',
            providerCallId: 'call_1',
            sourceContentType: MessageContentType.toolInvocation,
            timestamp: DateTime(2026, 4, 30, 10, 0, 2),
            data: const {
              'summary': '正在执行工具：列出目录',
              'arguments': {'path': 'lib'},
            },
          ),
        ],
      );

      expect(blocks, hasLength(1));
      expect(blocks.single.type, AssistantTurnBlockType.toolWorkflow);
      expect(blocks.single.status, 'running');
      expect(blocks.single.payload?['steps'], hasLength(1));
      expect(blocks.single.payload?['steps'][0]['providerCallId'], 'call_1');
    });

    test('result replaces the matching workflow block by default', () {
      final blocks = projector.project(
        events: [
          ToolPresentationEvent(
            toolName: 'create_reminder',
            phase: ToolPresentationEventPhase.running,
            turnId: '7_40',
            stepId: '7_40-step-3',
            sourceContentType: MessageContentType.toolInvocation,
            timestamp: DateTime(2026, 4, 30, 10, 0, 1),
            data: const {
              'summary': '正在执行工具：创建提醒',
              'arguments': {'title': '开会'},
            },
          ),
          ToolPresentationEvent(
            toolName: 'create_reminder',
            phase: ToolPresentationEventPhase.result,
            turnId: '7_40',
            stepId: '7_40-step-3',
            sourceContentType: MessageContentType.toolResult,
            timestamp: DateTime(2026, 4, 30, 10, 0, 2),
            data: const {
              'status': 'success',
              'summary': '已创建提醒：开会',
              'data': {'title': '开会'},
            },
          ),
        ],
      );

      expect(blocks, hasLength(1));
      expect(blocks.single.type, AssistantTurnBlockType.toolResultSummary);
      expect(blocks.single.status, 'success');
      expect(blocks.single.text, '已创建提醒：开会');
      expect(blocks.single.payload?['data']['title'], '开会');
    });

    test(
        'context-gathering result collapses earlier workflow states into one result card',
        () {
      final blocks = projector.project(
        events: [
          ToolPresentationEvent(
            toolName: 'search_chat_history',
            phase: ToolPresentationEventPhase.proposed,
            turnId: '7_41',
            stepId: '7_41-step-1',
            sourceContentType: MessageContentType.toolInvocation,
            timestamp: DateTime(2026, 4, 30, 10, 0, 1),
            data: const {
              'summary': '准备执行工具：搜索历史记录',
              'arguments': {'query': '周报', 'maxResults': 3},
            },
          ),
          ToolPresentationEvent(
            toolName: 'search_chat_history',
            phase: ToolPresentationEventPhase.running,
            turnId: '7_41',
            stepId: '7_41-step-1',
            sourceContentType: MessageContentType.toolInvocation,
            timestamp: DateTime(2026, 4, 30, 10, 0, 2),
            data: const {
              'summary': '正在执行工具：搜索历史记录',
              'arguments': {'query': '周报', 'maxResults': 3},
            },
          ),
          ToolPresentationEvent(
            toolName: 'search_chat_history',
            phase: ToolPresentationEventPhase.result,
            turnId: '7_41',
            stepId: '7_41-step-1',
            sourceContentType: MessageContentType.toolResult,
            timestamp: DateTime(2026, 4, 30, 10, 0, 3),
            data: const {
              'status': 'success',
              'summary': '已执行：搜索历史记录',
              'data': {'matchCount': 2},
            },
          ),
        ],
      );

      expect(blocks, hasLength(1));
      expect(blocks.single.type, AssistantTurnBlockType.toolResultSummary);
      expect(blocks.single.text, '已执行：搜索历史记录');
      expect(blocks.single.payload?['data']['matchCount'], 2);
    });

    test('keeps parallel steps separate and matches result by provider call id',
        () {
      final blocks = projector.project(
        events: [
          ToolPresentationEvent(
            toolName: 'fetch_webpage',
            phase: ToolPresentationEventPhase.running,
            turnId: '7_70',
            stepId: '7_70-step-11',
            providerCallId: 'call_a',
            sourceContentType: MessageContentType.toolInvocation,
            timestamp: DateTime(2026, 4, 30, 10, 1, 1),
            data: const {
              'summary': '正在执行工具：读取网页',
              'arguments': {'url': 'https://a.example.com'},
            },
          ),
          ToolPresentationEvent(
            toolName: 'fetch_webpage',
            phase: ToolPresentationEventPhase.running,
            turnId: '7_70',
            stepId: '7_70-step-12',
            providerCallId: 'call_b',
            sourceContentType: MessageContentType.toolInvocation,
            timestamp: DateTime(2026, 4, 30, 10, 1, 2),
            data: const {
              'summary': '正在执行工具：读取网页',
              'arguments': {'url': 'https://b.example.com'},
            },
          ),
          ToolPresentationEvent(
            toolName: 'fetch_webpage',
            phase: ToolPresentationEventPhase.result,
            turnId: '7_70',
            stepId: '7_70-step-11',
            providerCallId: 'call_a',
            sourceContentType: MessageContentType.toolResult,
            timestamp: DateTime(2026, 4, 30, 10, 1, 3),
            data: const {
              'status': 'success',
              'summary': 'A 已返回网页处理结果',
              'data': {
                'url': 'https://a.example.com',
                'resultPreview': 'A 摘要',
              },
            },
          ),
        ],
      );

      expect(blocks, hasLength(2));
      final resultBlock = blocks.firstWhere(
        (block) => block.type == AssistantTurnBlockType.toolResultSummary,
      );
      final runningBlock = blocks.firstWhere(
        (block) => block.type == AssistantTurnBlockType.toolWorkflow,
      );
      expect(blocks.first, resultBlock);
      expect(blocks.last, runningBlock);
      expect(resultBlock.payload?['data']['url'], 'https://a.example.com');
      expect(runningBlock.payload?['steps'][0]['providerCallId'], 'call_b');
    });

    test('skips hidden phases declared by renderer visibility policy', () {
      const projector = ToolPresentationBlockProjector(
        registry: ToolUiRendererRegistry(
          renderers: [_HideProposedRenderer()],
        ),
      );
      final blocks = projector.project(
        events: [
          ToolPresentationEvent(
            toolName: 'Write',
            phase: ToolPresentationEventPhase.proposed,
            turnId: '7_30',
            stepId: '7_30-step-9',
            sourceContentType: MessageContentType.toolInvocation,
            timestamp: DateTime(2026, 4, 30, 10, 0, 1),
            data: const {
              'summary': '准备写入文件',
              'arguments': {'file_path': 'lib/main.dart'},
            },
          ),
          ToolPresentationEvent(
            toolName: 'Write',
            phase: ToolPresentationEventPhase.result,
            turnId: '7_30',
            stepId: '7_30-step-9',
            sourceContentType: MessageContentType.toolResult,
            timestamp: DateTime(2026, 4, 30, 10, 0, 2),
            data: const {
              'status': 'success',
              'summary': '已写入文件',
              'data': {'filePath': 'lib/main.dart'},
            },
          ),
        ],
      );

      expect(blocks, hasLength(1));
      expect(blocks.single.type, AssistantTurnBlockType.toolResultSummary);
    });
  });
}

class _HideProposedRenderer implements ToolUiRenderer {
  const _HideProposedRenderer();

  @override
  Widget? buildResult(
    BuildContext context, {
    required ToolResult result,
    required ChatMessage? sourceMessage,
  }) {
    return null;
  }

  @override
  Widget? buildWorkflowStep(
    BuildContext context, {
    required List<ToolWorkflowStep> steps,
    required ChatMessage? sourceMessage,
    required bool isExpanded,
    required VoidCallback? onTap,
  }) {
    return null;
  }

  @override
  bool supportsResult(String toolName) => toolName == 'Write';

  @override
  bool supportsWorkflowStep(String toolName) => toolName == 'Write';

  @override
  ToolPhaseVisibility visibilityForPhase(
    String toolName,
    ToolPresentationEventPhase phase,
  ) {
    if (toolName == 'Write' && phase == ToolPresentationEventPhase.proposed) {
      return ToolPhaseVisibility.hidden;
    }
    return ToolPhaseVisibility.visible;
  }
}
