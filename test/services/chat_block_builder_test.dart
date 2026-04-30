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

    test('carries assistant reasoning content to the final response block', () {
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
            reasoningContent: '先确认上下文，再给出答案。',
            timestamp: DateTime(2026, 3, 29, 10, 0, 1),
          ),
        ],
      );

      expect(blocks.single.type, AssistantTurnBlockType.finalResponse);
      expect(blocks.single.reasoningText, '先确认上下文，再给出答案。');
    });

    test('keeps tool-use reasoning as analysis without promoting it', () {
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
            text: '',
            role: MessageRole.assistant,
            status: MessageStatus.completed,
            reasoningContent: '需要先读取文件。',
            payloadJson: const {'reasoningScope': 'tool_use'},
            timestamp: DateTime(2026, 3, 29, 10, 0, 1),
          ),
          ChatMessage(
            id: 12,
            text: '最终回答',
            role: MessageRole.assistant,
            status: MessageStatus.completed,
            timestamp: DateTime(2026, 3, 29, 10, 0, 2),
          ),
        ],
      );

      expect(blocks, hasLength(2));
      expect(blocks.first.type, AssistantTurnBlockType.analysis);
      expect(blocks.first.reasoningText, '需要先读取文件。');
      expect(blocks.last.type, AssistantTurnBlockType.finalResponse);
      expect(blocks.last.text, '最终回答');
    });

    test('maps ask user question prompt message to structured output block', () {
      final blocks = builder.buildAssistantBlocks(
        messages: [
          ChatMessage(
            id: 41,
            text: 'Which storage layer should we use?',
            role: MessageRole.assistant,
            contentType: MessageContentType.askUserQuestionPrompt,
            payloadJson: const {
              'type': 'prompt',
              'agentTurnId': 42,
              'status': 'awaitingResponse',
              'questions': [
                {
                  'id': 'storage_layer',
                  'header': 'Storage',
                  'question': 'Which storage layer should we use?',
                  'multiSelect': false,
                  'options': [
                    {
                      'label': 'SQLite',
                      'description': 'Local relational store',
                    },
                  ],
                },
              ],
            },
            timestamp: DateTime(2026, 4, 15, 10, 0, 1),
          ),
        ],
      );

      expect(blocks.single.type, AssistantTurnBlockType.structuredOutput);
      expect(blocks.single.title, 'Question');
      expect(blocks.single.askUserQuestionRequest, isNotNull);
      expect(blocks.single.askUserQuestionRequest?.agentTurnId, 42);
      expect(blocks.single.payload?['type'], 'prompt');
    });

    test('maps ask user question result message to structured output block', () {
      final blocks = builder.buildAssistantBlocks(
        messages: [
          ChatMessage(
            id: 42,
            text: 'User answered AskUserQuestion:\n- Storage: SQLite',
            role: MessageRole.assistant,
            contentType: MessageContentType.askUserQuestionResult,
            payloadJson: const {
              'type': 'result',
              'agentTurnId': 42,
              'status': 'submitted',
              'submittedAnswers': {
                'answersByQuestionId': {
                  'storage_layer': 'SQLite',
                },
              },
            },
            timestamp: DateTime(2026, 4, 15, 10, 0, 2),
          ),
        ],
      );

      expect(blocks.single.type, AssistantTurnBlockType.structuredOutput);
      expect(blocks.single.title, 'Answer');
      expect(blocks.single.askUserQuestionResponse, isNotNull);
      expect(
        blocks.single.askUserQuestionResponse?.answersByQuestionId,
        containsPair('storage_layer', 'SQLite'),
      );
      expect(blocks.single.payload?['type'], 'result');
    });
  });
}
