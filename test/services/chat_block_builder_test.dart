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

    test('keeps tool-use reasoning as analysis before workflow blocks', () {
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
            text: '准备读取文件',
            role: MessageRole.assistant,
            status: MessageStatus.completed,
            contentType: MessageContentType.toolInvocation,
            payloadJson: const {
              'toolName': 'read_file',
              'arguments': {'path': 'README.md'},
              'summary': '准备读取文件',
              'status': 'proposed',
              'requiresConfirmation': false,
            },
            timestamp: DateTime(2026, 3, 29, 10, 0, 2),
          ),
        ],
      );

      expect(blocks, hasLength(2));
      expect(blocks.first.type, AssistantTurnBlockType.analysis);
      expect(blocks.first.reasoningText, '需要先读取文件。');
      expect(blocks.last.type, AssistantTurnBlockType.toolWorkflow);
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
              'executionPolicy': 'require_confirmation',
              'toolAccess': {
                'toolName': 'create_reminder',
                'executionPolicy': 'require_confirmation',
                'isVisibleToPlanner': true,
              },
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
      expect(
        blocks.single.payload?['steps'][0]['executionPolicy'],
        'require_confirmation',
      );
      expect(
        blocks.single.payload?['steps'][0]['toolAccess']['executionPolicy'],
        'require_confirmation',
      );
    });

    test(
        'prefers execution policy from toolAccess snapshot when root field is absent',
        () {
      final blocks = builder.buildAssistantBlocks(
        messages: [
          ChatMessage(
            id: 31,
            text: '提醒我交周报',
            role: MessageRole.user,
            timestamp: DateTime(2026, 3, 29, 10, 0, 0),
          ),
          ChatMessage(
            id: 32,
            text: '准备执行工具：创建提醒',
            role: MessageRole.assistant,
            contentType: MessageContentType.actionConfirmation,
            payloadJson: const {
              'toolName': 'create_reminder',
              'arguments': {'title': '交周报'},
              'status': 'awaitingConfirmation',
              'summary': '准备执行工具：创建提醒',
              'requiresConfirmation': false,
              'toolAccess': {
                'toolName': 'create_reminder',
                'executionPolicy': 'require_confirmation',
                'isVisibleToPlanner': true,
              },
            },
            timestamp: DateTime(2026, 3, 29, 10, 0, 1),
          ),
        ],
      );

      expect(blocks.single.type, AssistantTurnBlockType.toolWorkflow);
      expect(
        blocks.single.payload?['steps'][0]['executionPolicy'],
        'require_confirmation',
      );
      expect(
        blocks.single.payload?['steps'][0]['toolAccess']['executionPolicy'],
        'require_confirmation',
      );
    });

    test('maps standalone tool result to tool result summary block', () {
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
              'executionPolicy': 'auto_run',
              'toolAccess': {
                'toolName': 'search_chat_history',
                'executionDecision': 'autoRun',
                'executionPolicy': 'auto_run',
                'isVisibleToPlanner': true,
              },
            },
            timestamp: DateTime(2026, 3, 29, 10, 0, 1),
          ),
        ],
      );

      expect(blocks.single.type, AssistantTurnBlockType.toolResultSummary);
      expect(blocks.single.title, 'search_chat_history');
      expect(blocks.single.payload?['data']['matchCount'], 1);
      expect(blocks.single.payload?['executionPolicy'], isNull);
      expect(
        blocks.single.payload?['toolAccess']['executionPolicy'],
        'auto_run',
      );
    });

    test('maps ask user question prompt message to structured output block',
        () {
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
      expect(blocks.single.payload?['type'], 'prompt');
    });

    test('maps ask user question result message to structured output block',
        () {
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
      expect(blocks.single.payload?['type'], 'result');
    });

    test(
        'maps blocked workflow payload without re-deriving policy from message type',
        () {
      final blocks = builder.buildAssistantBlocks(
        messages: [
          ChatMessage(
            id: 12,
            text: '帮我直接创建提醒',
            role: MessageRole.user,
            timestamp: DateTime(2026, 3, 29, 10, 0, 0),
          ),
          ChatMessage(
            id: 13,
            text: '工具执行已阻止：创建提醒',
            role: MessageRole.assistant,
            contentType: MessageContentType.toolInvocation,
            payloadJson: const {
              'toolName': 'create_reminder',
              'arguments': {'title': '交周报'},
              'status': 'cancelled',
              'summary': '工具执行已阻止：创建提醒',
              'requiresConfirmation': false,
              'executionPolicy': 'blocked',
              'toolAccess': {
                'toolName': 'create_reminder',
                'executionDecision': 'blocked',
                'executionPolicy': 'blocked',
                'isVisibleToPlanner': false,
              },
            },
            timestamp: DateTime(2026, 3, 29, 10, 0, 1),
          ),
        ],
      );

      expect(blocks.single.type, AssistantTurnBlockType.toolWorkflow);
      expect(blocks.single.status, 'cancelled');
      expect(
        blocks.single.payload?['steps'][0]['executionPolicy'],
        'blocked',
      );
      expect(
        blocks.single.payload?['steps'][0]['toolAccess']['executionPolicy'],
        'blocked',
      );
      expect(
        blocks.single.payload?['steps'][0]['requiresConfirmation'],
        isFalse,
      );
    });

    test('replaces adjacent workflow messages for the same step in one card',
        () {
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
              'executionPolicy': 'auto_run',
              'stepId': 1,
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
              'executionPolicy': 'auto_run',
              'stepId': 1,
            },
            timestamp: DateTime(2026, 3, 29, 10, 0, 2),
          ),
        ],
      );

      expect(blocks, hasLength(1));
      expect(blocks.single.type, AssistantTurnBlockType.toolWorkflow);
      expect(blocks.single.status, 'running');
      expect(blocks.single.title, '正在执行工具：联网搜索');
      expect(blocks.single.payload?['steps'], hasLength(1));
      expect(blocks.single.payload?['steps'][0]['status'], 'running');
      expect(blocks.single.payload?['steps'][0]['toolName'], 'web_search');
      expect(
        blocks.single.payload?['steps'][0]['executionPolicy'],
        'auto_run',
      );
    });

    test('does not merge sequential write invocations into one workflow block',
        () {
      final blocks = builder.buildAssistantBlocks(
        messages: [
          ChatMessage(
            id: 90,
            text: '连续写入两个文件',
            role: MessageRole.user,
            timestamp: DateTime(2026, 4, 25, 11, 0, 0),
          ),
          ChatMessage(
            id: 91,
            text: '正在执行工具：写入文件',
            role: MessageRole.assistant,
            contentType: MessageContentType.toolInvocation,
            payloadJson: const {
              'toolName': 'Write',
              'arguments': {
                'file_path': 'docs/a.md',
                'content': 'first file',
              },
              'status': 'running',
              'summary': '正在执行工具：写入文件',
              'requiresConfirmation': false,
              'stepId': 21,
            },
            timestamp: DateTime(2026, 4, 25, 11, 0, 1),
          ),
          ChatMessage(
            id: 92,
            text: '正在执行工具：写入文件',
            role: MessageRole.assistant,
            contentType: MessageContentType.toolInvocation,
            payloadJson: const {
              'toolName': 'Write',
              'arguments': {
                'file_path': 'docs/b.md',
                'content': 'second file',
              },
              'status': 'running',
              'summary': '正在执行工具：写入文件',
              'requiresConfirmation': false,
              'stepId': 22,
            },
            timestamp: DateTime(2026, 4, 25, 11, 0, 2),
          ),
        ],
      );

      expect(blocks, hasLength(2));
      expect(blocks[0].type, AssistantTurnBlockType.toolWorkflow);
      expect(blocks[1].type, AssistantTurnBlockType.toolWorkflow);
      expect(blocks[0].payload?['steps'], hasLength(1));
      expect(blocks[1].payload?['steps'], hasLength(1));
      expect(
        blocks[0].payload?['steps'][0]['details']['file_path'],
        'docs/a.md',
      );
      expect(
        blocks[1].payload?['steps'][0]['details']['file_path'],
        'docs/b.md',
      );
    });

    test(
        'merges tool result into the existing workflow card instead of appending',
        () {
      final blocks = builder.buildAssistantBlocks(
        messages: [
          ChatMessage(
            id: 40,
            text: '提醒我开会',
            role: MessageRole.user,
            timestamp: DateTime(2026, 3, 29, 10, 0, 0),
          ),
          ChatMessage(
            id: 41,
            text: '正在执行工具：创建提醒',
            role: MessageRole.assistant,
            contentType: MessageContentType.toolInvocation,
            payloadJson: const {
              'toolName': 'create_reminder',
              'arguments': {'title': '开会'},
              'status': 'running',
              'summary': '正在执行工具：创建提醒',
              'requiresConfirmation': false,
              'executionPolicy': 'require_confirmation',
              'stepId': 3,
            },
            timestamp: DateTime(2026, 3, 29, 10, 0, 1),
          ),
          ChatMessage(
            id: 42,
            text: '已创建提醒：开会',
            role: MessageRole.assistant,
            contentType: MessageContentType.toolResult,
            payloadJson: const {
              'toolName': 'create_reminder',
              'status': 'success',
              'summary': '已创建提醒：开会',
              'data': {'title': '开会'},
              'toolAccess': {
                'toolName': 'create_reminder',
                'executionPolicy': 'require_confirmation',
                'isVisibleToPlanner': true,
              },
            },
            timestamp: DateTime(2026, 3, 29, 10, 0, 2),
          ),
        ],
      );

      expect(blocks, hasLength(1));
      expect(blocks.single.type, AssistantTurnBlockType.toolWorkflow);
      expect(blocks.single.status, 'completed');
      expect(blocks.single.text, '已创建提醒：开会');
      expect(blocks.single.payload?['steps'], hasLength(1));
      expect(blocks.single.payload?['steps'][0]['status'], 'completed');
      expect(blocks.single.payload?['steps'][0]['summary'], '已创建提醒：开会');
      expect(blocks.single.payload?['steps'][0]['details']['title'], '开会');
    });

    test(
        'fetch_webpage result replaces workflow block in place and keeps prompt preview',
        () {
      final blocks = builder.buildAssistantBlocks(
        messages: [
          ChatMessage(
            id: 60,
            text: '读取这个网页',
            role: MessageRole.user,
            timestamp: DateTime(2026, 4, 25, 10, 0, 0),
          ),
          ChatMessage(
            id: 61,
            text: '正在执行工具：读取网页',
            role: MessageRole.assistant,
            contentType: MessageContentType.toolInvocation,
            payloadJson: const {
              'toolName': 'fetch_webpage',
              'arguments': {
                'url': 'https://flutter.dev',
                'prompt': '提取和焦点丢失相关的信息',
              },
              'status': 'running',
              'summary': '正在执行工具：读取网页',
              'requiresConfirmation': false,
              'executionPolicy': 'auto_run',
              'toolAccess': {
                'toolName': 'fetch_webpage',
                'executionDecision': 'autoRun',
                'executionPolicy': 'auto_run',
                'isVisibleToPlanner': true,
              },
            },
            timestamp: DateTime(2026, 4, 25, 10, 0, 1),
          ),
          ChatMessage(
            id: 62,
            text: '已返回网页处理结果',
            role: MessageRole.assistant,
            contentType: MessageContentType.toolResult,
            payloadJson: const {
              'toolName': 'fetch_webpage',
              'status': 'success',
              'summary': '已返回网页处理结果',
              'data': {
                'url': 'https://flutter.dev',
                'host': 'flutter.dev',
                'prompt': '提取和焦点丢失相关的信息',
                'resultPreview': '页面提到频繁 rebuild 可能导致焦点丢失。',
              },
              'toolAccess': {
                'toolName': 'fetch_webpage',
                'executionDecision': 'autoRun',
                'executionPolicy': 'auto_run',
                'isVisibleToPlanner': true,
              },
            },
            timestamp: DateTime(2026, 4, 25, 10, 0, 2),
          ),
        ],
      );

      expect(blocks, hasLength(1));
      expect(blocks.single.type, AssistantTurnBlockType.toolResultSummary);
      expect(blocks.single.payload?['data']['prompt'], contains('焦点丢失'));
      expect(
        blocks.single.payload?['data']['resultPreview'],
        contains('频繁 rebuild'),
      );
    });

    test(
        'parallel fetch_webpage steps stay as separate cards and result updates the matching one',
        () {
      final blocks = builder.buildAssistantBlocks(
        messages: [
          ChatMessage(
            id: 70,
            text: '帮我并行读取两个网页',
            role: MessageRole.user,
            timestamp: DateTime(2026, 4, 25, 10, 1, 0),
          ),
          ChatMessage(
            id: 71,
            text: '正在执行工具：读取网页',
            role: MessageRole.assistant,
            contentType: MessageContentType.toolInvocation,
            payloadJson: const {
              'toolName': 'fetch_webpage',
              'arguments': {
                'url': 'https://a.example.com/post',
                'prompt': '总结 A',
              },
              'status': 'running',
              'summary': '正在执行工具：读取网页',
              'requiresConfirmation': false,
              'stepId': 11,
            },
            timestamp: DateTime(2026, 4, 25, 10, 1, 1),
          ),
          ChatMessage(
            id: 72,
            text: '正在执行工具：读取网页',
            role: MessageRole.assistant,
            contentType: MessageContentType.toolInvocation,
            payloadJson: const {
              'toolName': 'fetch_webpage',
              'arguments': {
                'url': 'https://b.example.com/post',
                'prompt': '总结 B',
              },
              'status': 'running',
              'summary': '正在执行工具：读取网页',
              'requiresConfirmation': false,
              'stepId': 12,
            },
            timestamp: DateTime(2026, 4, 25, 10, 1, 2),
          ),
          ChatMessage(
            id: 73,
            text: 'A 已返回网页处理结果',
            role: MessageRole.assistant,
            contentType: MessageContentType.toolResult,
            payloadJson: const {
              'toolName': 'fetch_webpage',
              'status': 'success',
              'summary': 'A 已返回网页处理结果',
              'data': {
                'url': 'https://a.example.com/post',
                'host': 'a.example.com',
                'prompt': '总结 A',
                'resultPreview': 'A 摘要',
              },
            },
            timestamp: DateTime(2026, 4, 25, 10, 1, 3),
          ),
        ],
      );

      expect(blocks, hasLength(2));
      expect(blocks[0].type, AssistantTurnBlockType.toolResultSummary);
      expect(blocks[0].payload?['data']['url'], 'https://a.example.com/post');
      expect(blocks[0].payload?['data']['resultPreview'], 'A 摘要');
      expect(blocks[1].type, AssistantTurnBlockType.toolWorkflow);
      expect(blocks[1].payload?['steps'], hasLength(1));
      expect(blocks[1].payload?['steps'][0]['details']['url'],
          'https://b.example.com/post');
      expect(blocks[1].payload?['steps'][0]['status'], 'running');
    });
  });
}
