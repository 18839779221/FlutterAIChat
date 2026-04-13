import 'package:ai_chat/models/chat/assistant_turn_block.dart';
import 'package:ai_chat/models/chat_message.dart';
import 'package:ai_chat/models/response/message_content_type.dart';
import 'package:ai_chat/services/chat_block_builder.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ChatBlockBuilder', () {
    final builder = ChatBlockBuilder();

    test('maps plain assistant text to final response block', () {
      final blocks = builder.buildAssistantBlocks(
        groupId: 7,
        messages: [
          ChatMessage(
            id: 10,
            text: '用户问题',
            role: MessageRole.user,
            timestamp: DateTime(2026, 3, 29, 10, 0, 0),
          ),
          ChatMessage(
            id: 11,
            text: '最终回答',
            role: MessageRole.assistant,
            status: MessageStatus.completed,
            timestamp: DateTime(2026, 3, 29, 10, 0, 1),
          ),
        ],
      );

      expect(blocks, hasLength(1));
      expect(blocks.single.turnId, '7_10');
      expect(blocks.single.type, AssistantTurnBlockType.finalResponse);
      expect(blocks.single.text, '最终回答');
    });

    test('maps structured payload to structured output block', () {
      final blocks = builder.buildAssistantBlocks(
        messages: [
          ChatMessage(
            id: 1,
            text: '问题',
            role: MessageRole.user,
            timestamp: DateTime(2026, 3, 29, 10, 0, 0),
          ),
          ChatMessage(
            id: 2,
            text: '结构化摘要',
            role: MessageRole.assistant,
            contentType: MessageContentType.structuredCard,
            payloadJson: const {
              'title': '研究摘要',
              'summary': '摘要',
            },
            timestamp: DateTime(2026, 3, 29, 10, 0, 1),
          ),
        ],
      );

      expect(blocks.single.type, AssistantTurnBlockType.structuredOutput);
      expect(blocks.single.title, '研究摘要');
      expect(blocks.single.payload?['summary'], '摘要');
    });

    test('maps confirmation message to workflow block', () {
      final blocks = builder.buildAssistantBlocks(
        messages: [
          ChatMessage(
            id: 3,
            text: '提醒我交周报',
            role: MessageRole.user,
            timestamp: DateTime(2026, 3, 29, 10, 0, 0),
          ),
          ChatMessage(
            id: 4,
            text: '准备执行工具：创建提醒',
            role: MessageRole.assistant,
            contentType: MessageContentType.actionConfirmation,
            payloadJson: const {
              'toolName': 'create_reminder',
              'arguments': {'title': '交周报'},
              'status': 'awaitingConfirmation',
              'summary': '准备执行工具：创建提醒',
              'requiresConfirmation': true,
            },
            timestamp: DateTime(2026, 3, 29, 10, 0, 1),
          ),
        ],
      );

      expect(blocks.single.type, AssistantTurnBlockType.toolWorkflow);
      expect(blocks.single.status, 'awaitingConfirmation');
      expect(
        blocks.single.payload?['steps'][0]['requiresConfirmation'],
        isTrue,
      );
    });

    test('maps tool result to tool result summary block', () {
      final blocks = builder.buildAssistantBlocks(
        messages: [
          ChatMessage(
            id: 5,
            text: '查一下历史',
            role: MessageRole.user,
            timestamp: DateTime(2026, 3, 29, 10, 0, 0),
          ),
          ChatMessage(
            id: 6,
            text: '已执行：搜索历史记录',
            role: MessageRole.assistant,
            contentType: MessageContentType.toolResult,
            payloadJson: const {
              'toolName': 'search_chat_history',
              'status': 'success',
              'summary': '已执行：搜索历史记录',
              'data': {'matchCount': 1},
            },
            timestamp: DateTime(2026, 3, 29, 10, 0, 1),
          ),
        ],
      );

      expect(blocks.single.type, AssistantTurnBlockType.toolResultSummary);
      expect(blocks.single.title, 'search_chat_history');
      expect(blocks.single.payload?['data']['matchCount'], 1);
    });

    test('merges adjacent workflow messages for the same tool into one card', () {
      final blocks = builder.buildAssistantBlocks(
        messages: [
          ChatMessage(
            id: 7,
            text: '帮我联网查最新 Claude 进展',
            role: MessageRole.user,
            timestamp: DateTime(2026, 3, 29, 10, 0, 0),
          ),
          ChatMessage(
            id: 8,
            text: '准备执行工具：联网搜索',
            role: MessageRole.assistant,
            contentType: MessageContentType.toolInvocation,
            payloadJson: const {
              'toolName': 'web_search',
              'arguments': {'query': 'Claude latest'},
              'status': 'proposed',
              'summary': '准备执行工具：联网搜索',
              'requiresConfirmation': false,
            },
            timestamp: DateTime(2026, 3, 29, 10, 0, 1),
          ),
          ChatMessage(
            id: 9,
            text: '正在执行工具：联网搜索',
            role: MessageRole.assistant,
            contentType: MessageContentType.toolInvocation,
            payloadJson: const {
              'toolName': 'web_search',
              'arguments': {'query': 'Claude latest'},
              'status': 'running',
              'summary': '正在执行工具：联网搜索',
              'requiresConfirmation': false,
            },
            timestamp: DateTime(2026, 3, 29, 10, 0, 2),
          ),
        ],
      );

      expect(blocks, hasLength(1));
      expect(blocks.single.type, AssistantTurnBlockType.toolWorkflow);
      expect(blocks.single.status, 'running');
      expect(blocks.single.title, '正在执行工具：联网搜索');
      expect(blocks.single.payload?['steps'], hasLength(2));
      expect(blocks.single.payload?['steps'][0]['status'], 'proposed');
      expect(blocks.single.payload?['steps'][1]['status'], 'running');
      expect(blocks.single.payload?['steps'][0]['toolName'], 'web_search');
      expect(blocks.single.payload?['steps'][1]['toolName'], 'web_search');
    });
  });
}
