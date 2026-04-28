import 'package:ai_chat/models/response/message_content_type.dart';
import 'package:ai_chat/models/chat_message.dart';
import 'package:ai_chat/services/chat_timeline_projection_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ChatTimelineProjectionService', () {
    final service = ChatTimelineProjectionService();

    test(
        'returns active ask-user-question from projection instead of message scan',
        () {
      final projection = service.build(
        messages: [
          ChatMessage(
            id: 1,
            text: 'Need more details',
            role: MessageRole.assistant,
            contentType: MessageContentType.askUserQuestionPrompt,
            payloadJson: const {
              'type': 'prompt',
              'agentTurnId': 41,
              'status': 'awaitingResponse',
              'questions': [
                {
                  'id': 'storage_layer',
                  'header': 'Storage',
                  'question': 'Which storage layer should we use?',
                  'options': [
                    {'label': 'SQLite', 'description': 'Local store'},
                  ],
                },
              ],
            },
          ),
        ],
      );

      expect(projection.activeAskUserQuestionMessage?.id, 1);
    });

    test('returns pending confirmation from projection instead of message scan',
        () {
      final projection = service.build(
        messages: [
          ChatMessage(
            id: 2,
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
          ),
        ],
      );

      expect(projection.pendingToolConfirmation, isNotNull);
      expect(
        projection.pendingToolConfirmation?.invocation.toolName,
        'create_reminder',
      );
    });

    test(
        'keeps timeline blocks and waiting state derived from one projection snapshot',
        () {
      final projection = service.build(
        groupId: 7,
        messages: [
          ChatMessage(
            id: 10,
            text: '提醒我交周报',
            role: MessageRole.user,
          ),
          ChatMessage(
            id: 11,
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
          ),
        ],
      );

      expect(projection.assistantBlocks, isNotEmpty);
      expect(projection.pendingToolConfirmation?.message.id, 11);
      expect(projection.assistantBlocks.single.type.name, 'toolWorkflow');
    });

    test(
        'prefers typed workflow and result data when blocks already carry projection fields',
        () {
      final projection = service.build(
        groupId: 7,
        messages: [
          ChatMessage(
            id: 20,
            text: '查一下历史',
            role: MessageRole.user,
          ),
          ChatMessage(
            id: 21,
            text: '已执行：搜索历史记录',
            role: MessageRole.assistant,
            contentType: MessageContentType.toolResult,
            payloadJson: const {
              'toolName': 'search_chat_history',
              'status': 'success',
              'summary': '已执行：搜索历史记录',
              'data': {'matchCount': 1},
            },
          ),
        ],
      );

      expect(projection.assistantBlocks.single.toolResult, isNotNull);
      expect(
        projection.assistantBlocks.single.toolResult?.data['matchCount'],
        1,
      );
    });
  });
}
