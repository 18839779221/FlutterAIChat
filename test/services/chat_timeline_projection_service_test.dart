import 'dart:io';

import 'package:ai_chat/models/artifact/artifact_type.dart';
import 'package:ai_chat/models/chat/assistant_turn_block.dart';
import 'package:ai_chat/models/chat/runtime_assistant_draft.dart';
import 'package:ai_chat/models/chat/runtime_streaming_preview_state.dart';
import 'package:ai_chat/models/llm/streaming_message_event.dart';
import 'package:ai_chat/models/chat/tool_presentation_event.dart';
import 'package:ai_chat/models/response/message_content_type.dart';
import 'package:ai_chat/models/chat_message.dart';
import 'package:ai_chat/services/artifact/artifact_file_storage_service.dart';
import 'package:ai_chat/services/artifact/artifact_turn_resolver.dart';
import 'package:ai_chat/services/chat_timeline_projection_service.dart';
import 'package:ai_chat/services/tool_presentation_block_projector.dart';
import 'package:ai_chat/services/tool_ui_renderer_registry.dart';
import 'package:ai_chat/widgets/tool_renderers/create_artifact_tool_renderer.dart';
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
      expect(
        projection.assistantBlocks.where(
          (block) => block.type == AssistantTurnBlockType.toolWorkflow,
        ),
        hasLength(1),
      );
      expect(
        projection.assistantBlocks.where(
          (block) => block.type == AssistantTurnBlockType.analysis,
        ),
        isEmpty,
      );
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

      final resultBlocks = projection.assistantBlocks
          .where(
              (block) => block.type == AssistantTurnBlockType.toolResultSummary)
          .toList(growable: false);
      expect(resultBlocks, hasLength(1));
      expect(resultBlocks.single.toolResult, isNotNull);
      expect(
        resultBlocks.single.toolResult?.data['matchCount'],
        1,
      );
      expect(
        projection.assistantBlocks.where(
          (block) => block.type == AssistantTurnBlockType.analysis,
        ),
        isEmpty,
      );
    });

    test('builds standardized presentation events from invocation and result',
        () {
      final projection = service.build(
        groupId: 7,
        messages: [
          ChatMessage(
            id: 30,
            text: '帮我改文件',
            role: MessageRole.user,
            timestamp: DateTime(2026, 4, 30, 10, 0, 0),
          ),
          ChatMessage(
            id: 31,
            text: '准备写入文件',
            role: MessageRole.assistant,
            contentType: MessageContentType.toolInvocation,
            timestamp: DateTime(2026, 4, 30, 10, 0, 1),
            payloadJson: const {
              'toolName': 'Write',
              'arguments': {'file_path': 'lib/main.dart'},
              'status': 'proposed',
              'summary': '准备写入文件',
              'requiresConfirmation': false,
              'stepId': 9,
              'providerCallId': 'call_1',
            },
          ),
          ChatMessage(
            id: 32,
            text: '已写入文件',
            role: MessageRole.assistant,
            contentType: MessageContentType.toolResult,
            timestamp: DateTime(2026, 4, 30, 10, 0, 2),
            payloadJson: const {
              'toolName': 'Write',
              'status': 'success',
              'summary': '已写入文件',
              'data': {
                'filePath': 'lib/main.dart',
              },
              'stepId': 9,
              'providerCallId': 'call_1',
            },
          ),
        ],
      );

      expect(projection.toolPresentationEvents, hasLength(2));

      final invocationEvent = projection.toolPresentationEvents.first;
      expect(invocationEvent.toolName, 'Write');
      expect(invocationEvent.phase, ToolPresentationEventPhase.proposed);
      expect(invocationEvent.turnId, '7_30');
      expect(invocationEvent.stepId, '7_30-step-9');
      expect(invocationEvent.providerCallId, 'call_1');
      expect(
        invocationEvent.data['arguments'],
        containsPair('file_path', 'lib/main.dart'),
      );

      final resultEvent = projection.toolPresentationEvents.last;
      expect(resultEvent.phase, ToolPresentationEventPhase.result);
      expect(resultEvent.sourceContentType, MessageContentType.toolResult);
      expect(
          resultEvent.data['data'], containsPair('filePath', 'lib/main.dart'));
    });

    test('appends runtime reasoning draft as analysis block', () {
      final projection = service.build(
        groupId: 7,
        messages: [
          ChatMessage(
            id: 30,
            text: '帮我回答',
            role: MessageRole.user,
            timestamp: DateTime(2026, 4, 30, 10, 0, 0),
          ),
        ],
        runtimeDraft: RuntimeAssistantDraft(
          turnId: '7_30',
          draftId: '7_30-reasoning-draft',
          blockType: AssistantTurnBlockType.analysis,
          createdAt: DateTime(2026, 4, 30, 10, 0, 1),
          updatedAt: DateTime(2026, 4, 30, 10, 0, 2),
          reasoningText: '先整理答案结构。',
          payload: const {'reasoningScope': 'general'},
        ),
      );

      expect(
        projection.assistantBlocks.any(
          (block) =>
              block.type == AssistantTurnBlockType.analysis &&
              block.reasoningText == '先整理答案结构。' &&
              block.payload?['reasoningScope'] == 'general',
        ),
        isTrue,
      );
    });

    test(
        'runtime reasoning draft supersedes same-message preview reasoning via shared logicalId',
        () {
      final projection = service.build(
        groupId: 7,
        messages: [
          ChatMessage(
            id: 30,
            text: '帮我回答',
            role: MessageRole.user,
            timestamp: DateTime(2026, 4, 30, 10, 0, 0),
          ),
        ],
        runtimeDraft: RuntimeAssistantDraft(
          turnId: '7_30',
          draftId: '7_30-reasoning-draft',
          blockType: AssistantTurnBlockType.analysis,
          createdAt: DateTime(2026, 4, 30, 10, 0, 2),
          updatedAt: DateTime(2026, 4, 30, 10, 0, 3),
          reasoningText: '用户想要我用 HTML 可视化介绍 iOS 架构。',
          payload: const {
            'draftStage': 'reasoning',
            'logicalId': 'finalReasoning:7_30',
          },
        ),
        runtimePreviewState: RuntimeStreamingPreviewState(
          messages: [
            RuntimeStreamingPreviewMessage(
              messageId: 'message_reasoning_1',
              createdAt: DateTime(2026, 4, 30, 10, 0, 1),
              updatedAt: DateTime(2026, 4, 30, 10, 0, 2),
              blocks: [
                RuntimeStreamingPreviewBlock(
                  contentBlockId: 'message_reasoning_1:thinking',
                  blockType: StreamingContentBlockType.thinking,
                  createdAt: DateTime(2026, 4, 30, 10, 0, 1),
                  updatedAt: DateTime(2026, 4, 30, 10, 0, 2),
                  text: '用户想要我用 HTML 可视化介绍 iOS 架构。',
                ),
              ],
            ),
          ],
        ),
      );

      final analysisBlocks = projection.assistantBlocks
          .where((block) => block.type == AssistantTurnBlockType.analysis)
          .toList(growable: false);

      expect(analysisBlocks, hasLength(1));
      expect(analysisBlocks.single.payload?['isRuntimePreview'], isNot(true));
      expect(
        analysisBlocks.single.logicalId,
        'finalReasoning:7_30',
      );
      expect(
        analysisBlocks.single.reasoningText,
        '用户想要我用 HTML 可视化介绍 iOS 架构。',
      );
    });

    test('projects runtime text preview into final response block', () {
      final projection = service.build(
        groupId: 7,
        messages: [
          ChatMessage(
            id: 30,
            text: '帮我回答',
            role: MessageRole.user,
            timestamp: DateTime(2026, 4, 30, 10, 0, 0),
          ),
        ],
        runtimePreviewState: RuntimeStreamingPreviewState(
          messages: [
            RuntimeStreamingPreviewMessage(
              messageId: 'message_text_1',
              createdAt: DateTime(2026, 4, 30, 10, 0, 1),
              updatedAt: DateTime(2026, 4, 30, 10, 0, 2),
              blocks: [
                RuntimeStreamingPreviewBlock(
                  contentBlockId: 'message_text_1:text',
                  blockType: StreamingContentBlockType.text,
                  createdAt: DateTime(2026, 4, 30, 10, 0, 1),
                  updatedAt: DateTime(2026, 4, 30, 10, 0, 2),
                  text: '这是运行中的正文',
                ),
              ],
            ),
          ],
        ),
      );

      final runtimeResponseBlocks = projection.assistantBlocks
          .where((block) => block.type == AssistantTurnBlockType.finalResponse)
          .toList(growable: false);
      expect(runtimeResponseBlocks, hasLength(1));
      expect(runtimeResponseBlocks.single.text, '这是运行中的正文');
      expect(runtimeResponseBlocks.single.payload?['isRuntimePreview'], isTrue);
    });

    test('carries runtime trace metadata into projected preview payload', () {
      final projection = service.build(
        groupId: 7,
        messages: [
          ChatMessage(
            id: 30,
            text: '帮我回答',
            role: MessageRole.user,
            timestamp: DateTime(2026, 4, 30, 10, 0, 0),
          ),
        ],
        runtimePreviewState: RuntimeStreamingPreviewState(
          messages: [
            RuntimeStreamingPreviewMessage(
              messageId: 'message_text_1',
              streamTraceId: 'trace_1',
              streamTurnId: 'turn_1',
              createdAt: DateTime(2026, 4, 30, 10, 0, 1),
              updatedAt: DateTime(2026, 4, 30, 10, 0, 2),
              blocks: [
                RuntimeStreamingPreviewBlock(
                  contentBlockId: 'message_text_1:text',
                  blockType: StreamingContentBlockType.text,
                  createdAt: DateTime(2026, 4, 30, 10, 0, 1),
                  updatedAt: DateTime(2026, 4, 30, 10, 0, 2),
                  text: '这是运行中的正文',
                ),
              ],
            ),
          ],
        ),
      );

      final block = projection.assistantBlocks
          .where((entry) => entry.type == AssistantTurnBlockType.finalResponse)
          .single;
      expect(block.payload?['streamTraceId'], 'trace_1');
      expect(block.payload?['streamTurnId'], 'turn_1');
    });

    test('projects runtime thinking preview into analysis block', () {
      final projection = service.build(
        groupId: 7,
        messages: [
          ChatMessage(
            id: 30,
            text: '帮我回答',
            role: MessageRole.user,
            timestamp: DateTime(2026, 4, 30, 10, 0, 0),
          ),
        ],
        runtimePreviewState: RuntimeStreamingPreviewState(
          messages: [
            RuntimeStreamingPreviewMessage(
              messageId: 'message_thinking_1',
              createdAt: DateTime(2026, 4, 30, 10, 0, 1),
              updatedAt: DateTime(2026, 4, 30, 10, 0, 2),
              blocks: [
                RuntimeStreamingPreviewBlock(
                  contentBlockId: 'message_thinking_1:thinking',
                  blockType: StreamingContentBlockType.thinking,
                  createdAt: DateTime(2026, 4, 30, 10, 0, 1),
                  updatedAt: DateTime(2026, 4, 30, 10, 0, 2),
                  text: '先整理回答结构',
                ),
              ],
            ),
          ],
        ),
      );

      final runtimeAnalysisBlocks = projection.assistantBlocks
          .where((block) => block.type == AssistantTurnBlockType.analysis)
          .toList(growable: false);
      expect(runtimeAnalysisBlocks, hasLength(1));
      expect(runtimeAnalysisBlocks.single.reasoningText, '先整理回答结构');
      expect(runtimeAnalysisBlocks.single.payload?['isRuntimePreview'], isTrue);
    });

    test('splits think-tagged runtime text preview into reasoning and content', () {
      final projection = service.build(
        groupId: 7,
        messages: [
          ChatMessage(
            id: 30,
            text: '帮我回答',
            role: MessageRole.user,
            timestamp: DateTime(2026, 4, 30, 10, 0, 0),
          ),
        ],
        runtimePreviewState: RuntimeStreamingPreviewState(
          messages: [
            RuntimeStreamingPreviewMessage(
              messageId: 'message_text_2',
              createdAt: DateTime(2026, 4, 30, 10, 0, 1),
              updatedAt: DateTime(2026, 4, 30, 10, 0, 2),
              blocks: [
                RuntimeStreamingPreviewBlock(
                  contentBlockId: 'message_text_2:text',
                  blockType: StreamingContentBlockType.text,
                  createdAt: DateTime(2026, 4, 30, 10, 0, 1),
                  updatedAt: DateTime(2026, 4, 30, 10, 0, 2),
                  text: '<think>先整理答案结构</think>\n\n这是运行中的正文',
                ),
              ],
            ),
          ],
        ),
      );

      final block = projection.assistantBlocks
          .where((entry) => entry.type == AssistantTurnBlockType.finalResponse)
          .single;
      expect(block.reasoningText, '先整理答案结构');
      expect(block.text, '这是运行中的正文');
      expect(block.logicalId, 'final:7_30');
      expect(block.payload?['isRuntimePreview'], isTrue);
    });

    test(
        'suppresses generic runtime tool use preview so persisted toolInvocation owns the card',
        () {
      final projection = service.build(
        groupId: 7,
        messages: [
          ChatMessage(
            id: 30,
            text: '查一下天气',
            role: MessageRole.user,
            timestamp: DateTime(2026, 4, 30, 10, 0, 0),
          ),
        ],
        runtimePreviewState: RuntimeStreamingPreviewState(
          messages: [
            RuntimeStreamingPreviewMessage(
              messageId: 'message_tool_1',
              createdAt: DateTime(2026, 4, 30, 10, 0, 1),
              updatedAt: DateTime(2026, 4, 30, 10, 0, 2),
              blocks: [
                RuntimeStreamingPreviewBlock(
                  contentBlockId: 'message_tool_1:tool:call_weather_1',
                  blockType: StreamingContentBlockType.toolUse,
                  toolUseId: 'call_weather_1',
                  toolName: 'fetch_weather',
                  createdAt: DateTime(2026, 4, 30, 10, 0, 1),
                  updatedAt: DateTime(2026, 4, 30, 10, 0, 2),
                  text: '{"city":"Shanghai"}',
                ),
              ],
            ),
          ],
        ),
      );

      // The bare "正在执行工具：xxx" running card adds no information for the
      // user during streaming and is suppressed by default — the persisted
      // toolInvocation message owns the real workflow card.
      final runtimeWorkflowBlocks = projection.assistantBlocks
          .where((block) => block.type == AssistantTurnBlockType.toolWorkflow)
          .toList(growable: false);
      expect(runtimeWorkflowBlocks, isEmpty);
    });

    test(
        'hides runtime text preview once persisted final response carries same logicalId',
        () {
      final projection = service.build(
        groupId: 7,
        messages: [
          ChatMessage(
            id: 30,
            text: '帮我回答',
            role: MessageRole.user,
            timestamp: DateTime(2026, 4, 30, 10, 0, 0),
          ),
          ChatMessage(
            id: 31,
            text: '这是最终回答',
            role: MessageRole.assistant,
            timestamp: DateTime(2026, 4, 30, 10, 0, 3),
            payloadJson: const {
              'isFinalAnswer': true,
              'logicalId': 'final:7_30',
            },
          ),
        ],
        runtimePreviewState: RuntimeStreamingPreviewState(
          messages: [
            RuntimeStreamingPreviewMessage(
              messageId: 'message_text_1',
              createdAt: DateTime(2026, 4, 30, 10, 0, 1),
              updatedAt: DateTime(2026, 4, 30, 10, 0, 2),
              blocks: [
                RuntimeStreamingPreviewBlock(
                  contentBlockId: 'message_text_1:text',
                  blockType: StreamingContentBlockType.text,
                  createdAt: DateTime(2026, 4, 30, 10, 0, 1),
                  updatedAt: DateTime(2026, 4, 30, 10, 0, 2),
                  text: '这是运行中的正文',
                ),
              ],
            ),
          ],
        ),
      );

      final finalBlocks = projection.assistantBlocks
          .where((block) => block.type == AssistantTurnBlockType.finalResponse)
          .toList(growable: false);
      expect(finalBlocks, hasLength(1));
      expect(finalBlocks.single.text, '这是最终回答');
      expect(finalBlocks.single.payload?['isRuntimePreview'], isNot(true));
      expect(finalBlocks.single.logicalId, 'final:7_30');
    });

    test(
        'runtime thinking preview carries reasoning logicalId independent from persisted final response',
        () {
      final projection = service.build(
        groupId: 7,
        messages: [
          ChatMessage(
            id: 30,
            text: '帮我回答',
            role: MessageRole.user,
            timestamp: DateTime(2026, 4, 30, 10, 0, 0),
          ),
          ChatMessage(
            id: 31,
            text: '这是最终回答',
            role: MessageRole.assistant,
            timestamp: DateTime(2026, 4, 30, 10, 0, 3),
            payloadJson: const {
              'isFinalAnswer': true,
              'logicalId': 'final:7_30',
            },
          ),
        ],
        runtimePreviewState: RuntimeStreamingPreviewState(
          messages: [
            RuntimeStreamingPreviewMessage(
              messageId: 'message_thinking_1',
              createdAt: DateTime(2026, 4, 30, 10, 0, 1),
              updatedAt: DateTime(2026, 4, 30, 10, 0, 2),
              blocks: [
                RuntimeStreamingPreviewBlock(
                  contentBlockId: 'message_thinking_1:thinking',
                  blockType: StreamingContentBlockType.thinking,
                  createdAt: DateTime(2026, 4, 30, 10, 0, 1),
                  updatedAt: DateTime(2026, 4, 30, 10, 0, 2),
                  text: '先整理回答结构',
                ),
              ],
            ),
          ],
        ),
      );

      final previewAnalysisBlock = projection.assistantBlocks
          .where((block) => block.payload?['isRuntimePreview'] == true)
          .single;
      final truthFinalBlock = projection.assistantBlocks
          .where((block) =>
              block.type == AssistantTurnBlockType.finalResponse &&
              block.payload?['isRuntimePreview'] != true)
          .single;

      expect(previewAnalysisBlock.type, AssistantTurnBlockType.analysis);
      expect(previewAnalysisBlock.logicalId, 'finalReasoning:7_30');
      expect(truthFinalBlock.logicalId, 'final:7_30');
    });

    test(
        'tool-decision reasoning preview uses response-scoped logicalId even when toolUse is in a sibling preview message',
        () {
      final projection = service.build(
        groupId: 7,
        messages: [
          ChatMessage(
            id: 30,
            text: '帮我用HTML可视化iOS架构',
            role: MessageRole.user,
            timestamp: DateTime(2026, 4, 30, 10, 0, 0),
          ),
          ChatMessage(
            id: 31,
            text: '',
            role: MessageRole.assistant,
            reasoningContent: '先规划一个结构，再调用工具生成产物。',
            timestamp: DateTime(2026, 4, 30, 10, 0, 3),
            payloadJson: const {
              'logicalId': 'toolReasoning:resp_tool_1',
              'responseId': 'resp_tool_1',
              'reasoningScope': 'tool_use',
            },
          ),
        ],
        runtimePreviewState: RuntimeStreamingPreviewState(
          messages: [
            RuntimeStreamingPreviewMessage(
              messageId: 'resp_tool_1',
              responseId: 'resp_tool_1',
              createdAt: DateTime(2026, 4, 30, 10, 0, 1),
              updatedAt: DateTime(2026, 4, 30, 10, 0, 2),
              blocks: [
                RuntimeStreamingPreviewBlock(
                  contentBlockId: 'resp_tool_1:thinking',
                  blockType: StreamingContentBlockType.thinking,
                  createdAt: DateTime(2026, 4, 30, 10, 0, 1),
                  updatedAt: DateTime(2026, 4, 30, 10, 0, 2),
                  text: '先规划一个结构，再调用工具生成产物。',
                ),
              ],
            ),
            RuntimeStreamingPreviewMessage(
              messageId: 'resp_tool_1:tool',
              responseId: 'resp_tool_1',
              createdAt: DateTime(2026, 4, 30, 10, 0, 2),
              updatedAt: DateTime(2026, 4, 30, 10, 0, 2),
              blocks: [
                RuntimeStreamingPreviewBlock(
                  contentBlockId: 'resp_tool_1:tool:call_1',
                  blockType: StreamingContentBlockType.toolUse,
                  toolUseId: 'call_1',
                  toolName: 'create_artifact',
                  createdAt: DateTime(2026, 4, 30, 10, 0, 2),
                  updatedAt: DateTime(2026, 4, 30, 10, 0, 2),
                  text: '{"artifact_id":"ios-architecture"}',
                ),
              ],
            ),
          ],
        ),
      );

      final analysisBlocks = projection.assistantBlocks
          .where((block) => block.type == AssistantTurnBlockType.analysis)
          .toList(growable: false);

      expect(analysisBlocks, hasLength(1));
      expect(analysisBlocks.single.payload?['isRuntimePreview'], isNot(true));
      expect(analysisBlocks.single.logicalId, 'toolReasoning:resp_tool_1');
    });

    test(
        'persisted final response does not suppress preview reasoning by itself',
        () {
      final projection = service.build(
        groupId: 7,
        messages: [
          ChatMessage(
            id: 30,
            text: '帮我回答',
            role: MessageRole.user,
            timestamp: DateTime(2026, 4, 30, 10, 0, 0),
          ),
          ChatMessage(
            id: 31,
            text: '这是最终回答',
            role: MessageRole.assistant,
            reasoningContent: '先整理答案结构',
            timestamp: DateTime(2026, 4, 30, 10, 0, 3),
            payloadJson: const {
              'isFinalAnswer': true,
              'logicalId': 'final:7_30',
            },
          ),
        ],
        runtimePreviewState: RuntimeStreamingPreviewState(
          messages: [
            RuntimeStreamingPreviewMessage(
              messageId: 'message_text_same',
              createdAt: DateTime(2026, 4, 30, 10, 0, 1),
              updatedAt: DateTime(2026, 4, 30, 10, 0, 2),
              blocks: [
                RuntimeStreamingPreviewBlock(
                  contentBlockId: 'message_text_same:thinking',
                  blockType: StreamingContentBlockType.thinking,
                  createdAt: DateTime(2026, 4, 30, 10, 0, 1),
                  updatedAt: DateTime(2026, 4, 30, 10, 0, 2),
                  text: '先整理答案结构',
                ),
                RuntimeStreamingPreviewBlock(
                  contentBlockId: 'message_text_same:text',
                  blockType: StreamingContentBlockType.text,
                  createdAt: DateTime(2026, 4, 30, 10, 0, 1),
                  updatedAt: DateTime(2026, 4, 30, 10, 0, 2),
                  text: '这是运行中的正文',
                ),
              ],
            ),
          ],
        ),
      );

      final blocks = projection.assistantBlocks;
      expect(
        blocks.where((block) => block.payload?['isRuntimePreview'] == true),
        hasLength(1),
      );
      expect(
        blocks
            .where((block) => block.type == AssistantTurnBlockType.finalResponse)
            .single
            .reasoningText,
        '先整理答案结构',
      );
      expect(
        blocks
            .where((block) => block.payload?['isRuntimePreview'] == true)
            .single
            .logicalId,
        'finalReasoning:7_30',
      );
    });

    test(
        'lets iteration-2 streaming text through when only intermediate planner message exists',
        () {
      // Regression: an intermediate planner message between tool iterations
      // would previously claim `final:<turnId>` via the ChatBlockBuilder
      // post-hoc upgrade, hiding the next iteration's streaming preview
      // through over-aggressive logicalId dedup. Only messages tagged
      // `isFinalAnswer == true` may own the dedup id.
      final projection = service.build(
        groupId: 7,
        messages: [
          ChatMessage(
            id: 30,
            text: '帮我查',
            role: MessageRole.user,
            timestamp: DateTime(2026, 4, 30, 10, 0, 0),
          ),
          ChatMessage(
            id: 31,
            text: '先查询一下相关信息。',
            role: MessageRole.assistant,
            timestamp: DateTime(2026, 4, 30, 10, 0, 1),
            // Intermediate planner message — NOT tagged isFinalAnswer.
          ),
        ],
        runtimePreviewState: RuntimeStreamingPreviewState(
          messages: [
            RuntimeStreamingPreviewMessage(
              messageId: 'message_text_iter2',
              createdAt: DateTime(2026, 4, 30, 10, 0, 5),
              updatedAt: DateTime(2026, 4, 30, 10, 0, 6),
              blocks: [
                RuntimeStreamingPreviewBlock(
                  contentBlockId: 'message_text_iter2:text',
                  blockType: StreamingContentBlockType.text,
                  createdAt: DateTime(2026, 4, 30, 10, 0, 5),
                  updatedAt: DateTime(2026, 4, 30, 10, 0, 6),
                  text: '基于查询结果的回答',
                ),
              ],
            ),
          ],
        ),
      );

      // Two finalResponse blocks: the intermediate planner (no logicalId,
      // truth-origin) and the preview's streaming text. Both visible —
      // dedup does not fire because the intermediate planner does not
      // carry the dedup id.
      final finalBlocks = projection.assistantBlocks
          .where((block) => block.type == AssistantTurnBlockType.finalResponse)
          .toList(growable: false);
      expect(finalBlocks, hasLength(2));
      expect(
        finalBlocks
            .where((b) => b.payload?['isRuntimePreview'] == true)
            .single
            .text,
        '基于查询结果的回答',
      );
      expect(
        finalBlocks
            .where((b) => b.payload?['isRuntimePreview'] != true)
            .single
            .logicalId,
        isNull,
      );
    });

    test(
        'hides runtime tool preview once persisted toolInvocation carries same providerCallId',
        () {
      final projection = service.build(
        groupId: 7,
        messages: [
          ChatMessage(
            id: 30,
            text: '查一下天气',
            role: MessageRole.user,
            timestamp: DateTime(2026, 4, 30, 10, 0, 0),
          ),
          ChatMessage(
            id: 31,
            text: '准备执行工具：fetch_weather',
            role: MessageRole.assistant,
            contentType: MessageContentType.toolInvocation,
            timestamp: DateTime(2026, 4, 30, 10, 0, 2),
            payloadJson: const {
              'toolName': 'fetch_weather',
              'providerCallId': 'call_weather_1',
              'arguments': {'city': 'Shanghai'},
              'status': 'running',
              'summary': '正在查询天气',
              'requiresConfirmation': false,
            },
          ),
        ],
        runtimePreviewState: RuntimeStreamingPreviewState(
          messages: [
            RuntimeStreamingPreviewMessage(
              messageId: 'message_tool_1',
              createdAt: DateTime(2026, 4, 30, 10, 0, 1),
              updatedAt: DateTime(2026, 4, 30, 10, 0, 2),
              blocks: [
                RuntimeStreamingPreviewBlock(
                  contentBlockId: 'message_tool_1:tool:call_weather_1',
                  blockType: StreamingContentBlockType.toolUse,
                  toolUseId: 'call_weather_1',
                  toolName: 'fetch_weather',
                  createdAt: DateTime(2026, 4, 30, 10, 0, 1),
                  updatedAt: DateTime(2026, 4, 30, 10, 0, 2),
                  text: '{"city":"Shanghai"}',
                ),
              ],
            ),
          ],
        ),
      );

      final workflowBlocks = projection.assistantBlocks
          .where((block) => block.type == AssistantTurnBlockType.toolWorkflow)
          .toList(growable: false);
      expect(workflowBlocks, hasLength(1));
      expect(workflowBlocks.single.payload?['isRuntimePreview'], isNot(true));
      expect(workflowBlocks.single.logicalId, 'tool:call_weather_1');
    });

    test('projects artifact block into assistant timeline snapshot', () async {
      final tempDirectory = await Directory.systemTemp.createTemp(
        'timeline-artifact-',
      );
      final fileStorageService =
          ArtifactFileStorageService(rootDirectory: tempDirectory);
      await fileStorageService.saveArtifactSource(
        groupId: 7,
        artifactId: 'portfolio-pie',
        title: '投资组合饼图',
        type: ArtifactType.html,
        source: '<div>artifact body</div>',
      );
      final service = ChatTimelineProjectionService(
        artifactTurnResolver: ArtifactTurnResolver(
          fileStorageService: fileStorageService,
        ),
      );

      final projection = service.build(
        groupId: 7,
        messages: [
          ChatMessage(
            id: 30,
            text: '帮我画个图',
            role: MessageRole.user,
            timestamp: DateTime(2026, 4, 30, 10, 0, 0),
          ),
          ChatMessage(
            id: 31,
            text: '已创建 artifact：portfolio-pie',
            role: MessageRole.assistant,
            contentType: MessageContentType.toolResult,
            timestamp: DateTime(2026, 4, 30, 10, 0, 1),
            payloadJson: const {
              'toolName': 'create_artifact',
              'status': 'success',
              'summary': '已创建 artifact：portfolio-pie',
              'data': {
                'artifactId': 'portfolio-pie',
                'title': '投资组合饼图',
                'type': 'html',
                'sourcePath': 'artifacts/7/portfolio-pie.html',
              },
            },
          ),
        ],
      );

      expect(
        projection.assistantBlocks.any(
          (block) => block.type.name == 'artifact',
        ),
        isTrue,
      );

      await tempDirectory.delete(recursive: true);
    });

    test('projects runtime create_artifact preview from runtime preview state',
        () {
      final projection = service.build(
        groupId: 7,
        messages: [
          ChatMessage(
            id: 30,
            text: '帮我做个 artifact',
            role: MessageRole.user,
            timestamp: DateTime(2026, 4, 30, 10, 0, 0),
          ),
        ],
        runtimePreviewState: RuntimeStreamingPreviewState(
          messages: [
            RuntimeStreamingPreviewMessage(
              messageId: 'message_1',
              createdAt: DateTime(2026, 4, 30, 10, 0, 1),
              updatedAt: DateTime(2026, 4, 30, 10, 0, 1),
              blocks: [
                RuntimeStreamingPreviewBlock(
                  contentBlockId: 'message_1:tool:call_artifact_1',
                  blockType: StreamingContentBlockType.toolUse,
                  toolUseId: 'call_artifact_1',
                  toolName: 'create_artifact',
                  createdAt: DateTime(2026, 4, 30, 10, 0, 1),
                  updatedAt: DateTime(2026, 4, 30, 10, 0, 1),
                  text:
                      '{"id":"food-rank","type":"html","title":"中国美食","source":"<div>渐进预览</div>"}',
                ),
              ],
            ),
          ],
        ),
      );

      final runtimeArtifactBlocks = projection.assistantBlocks
          .where((block) => block.type == AssistantTurnBlockType.artifact)
          .toList(growable: false);
      expect(runtimeArtifactBlocks, hasLength(1));
      expect(runtimeArtifactBlocks.single.payload?['isRuntimePreview'], isTrue);
      expect(
        runtimeArtifactBlocks.single.artifactProjection?.isRuntimePreview,
        isTrue,
      );
      expect(
          runtimeArtifactBlocks.single.logicalId, 'artifact:call_artifact_1');
      expect(runtimeArtifactBlocks.single.text, contains('渐进预览'));
      expect(projection.runtimePreviewState.messages, hasLength(1));
      expect(
        projection.runtimePreviewState.messages.single.blocks.single.toolName,
        'create_artifact',
      );
    });

    test(
        'keeps generic runtime response preview alongside runtime create_artifact preview',
        () {
      final projection = service.build(
        groupId: 7,
        messages: [
          ChatMessage(
            id: 30,
            text: '边写说明边生成 artifact',
            role: MessageRole.user,
            timestamp: DateTime(2026, 4, 30, 10, 0, 0),
          ),
        ],
        runtimePreviewState: RuntimeStreamingPreviewState(
          messages: [
            RuntimeStreamingPreviewMessage(
              messageId: 'message_1',
              createdAt: DateTime(2026, 4, 30, 10, 0, 1),
              updatedAt: DateTime(2026, 4, 30, 10, 0, 2),
              blocks: [
                RuntimeStreamingPreviewBlock(
                  contentBlockId: 'message_1:text',
                  blockType: StreamingContentBlockType.text,
                  createdAt: DateTime(2026, 4, 30, 10, 0, 1),
                  updatedAt: DateTime(2026, 4, 30, 10, 0, 2),
                  text: '先给你正文说明',
                ),
                RuntimeStreamingPreviewBlock(
                  contentBlockId: 'message_1:tool:call_artifact_1',
                  blockType: StreamingContentBlockType.toolUse,
                  toolUseId: 'call_artifact_1',
                  toolName: 'create_artifact',
                  createdAt: DateTime(2026, 4, 30, 10, 0, 1),
                  updatedAt: DateTime(2026, 4, 30, 10, 0, 2),
                  text:
                      '{"id":"food-rank","type":"html","title":"中国美食","source":"<div>渐进预览</div>"}',
                ),
              ],
            ),
          ],
        ),
      );

      final runtimeResponseBlocks = projection.assistantBlocks
          .where((block) => block.type == AssistantTurnBlockType.finalResponse)
          .toList(growable: false);
      final runtimeArtifactBlocks = projection.assistantBlocks
          .where((block) => block.type == AssistantTurnBlockType.artifact)
          .toList(growable: false);

      expect(runtimeResponseBlocks, hasLength(1));
      expect(runtimeResponseBlocks.single.text, '先给你正文说明');
      expect(runtimeResponseBlocks.single.payload?['isRuntimePreview'], isTrue);
      expect(runtimeArtifactBlocks, hasLength(1));
      expect(runtimeArtifactBlocks.single.payload?['isRuntimePreview'], isTrue);
      expect(
        runtimeArtifactBlocks.single.artifactProjection?.isRuntimePreview,
        isTrue,
      );
    });

    test(
        'prefers persisted artifact over runtime preview for the same create_artifact tool call',
        () async {
      final tempDirectory = await Directory.systemTemp.createTemp(
        'timeline-artifact-takeover-',
      );
      final fileStorageService =
          ArtifactFileStorageService(rootDirectory: tempDirectory);
      final savedArtifact = await fileStorageService.saveArtifactSource(
        groupId: 7,
        artifactId: 'food-rank',
        title: '中国美食',
        type: ArtifactType.html,
        source: '<div>最终落盘内容</div>',
      );
      final service = ChatTimelineProjectionService(
        artifactTurnResolver: ArtifactTurnResolver(
          fileStorageService: fileStorageService,
        ),
      );

      final projection = service.build(
        groupId: 7,
        messages: [
          ChatMessage(
            id: 30,
            text: '帮我做个 artifact',
            role: MessageRole.user,
            timestamp: DateTime(2026, 4, 30, 10, 0, 0),
          ),
          ChatMessage(
            id: 31,
            text: '已创建 artifact：food-rank',
            role: MessageRole.assistant,
            contentType: MessageContentType.toolResult,
            timestamp: DateTime(2026, 4, 30, 10, 0, 2),
            payloadJson: const {
              'toolName': 'create_artifact',
              'status': 'success',
              'summary': '已创建 artifact：food-rank',
              'providerCallId': 'call_artifact_1',
              'data': {
                'artifactId': 'food-rank',
                'title': '中国美食',
                'type': 'html',
                'sourcePath': '/workspaces/.default/artifacts/food-rank.html',
              },
            },
          ),
        ],
        runtimePreviewState: RuntimeStreamingPreviewState(
          messages: [
            RuntimeStreamingPreviewMessage(
              messageId: 'message_1',
              createdAt: DateTime(2026, 4, 30, 10, 0, 1),
              updatedAt: DateTime(2026, 4, 30, 10, 0, 1),
              blocks: [
                RuntimeStreamingPreviewBlock(
                  contentBlockId: 'message_1:tool:call_artifact_1',
                  blockType: StreamingContentBlockType.toolUse,
                  toolUseId: 'call_artifact_1',
                  toolName: 'create_artifact',
                  createdAt: DateTime(2026, 4, 30, 10, 0, 1),
                  updatedAt: DateTime(2026, 4, 30, 10, 0, 1),
                  text:
                      '{"id":"food-rank","type":"html","title":"中国美食","source":"<div>渐进预览</div>"}',
                ),
              ],
            ),
          ],
        ),
      );

      final artifactBlocks = projection.assistantBlocks
          .where((block) => block.type == AssistantTurnBlockType.artifact)
          .toList(growable: false);
      expect(artifactBlocks, hasLength(1));
      expect(artifactBlocks.single.payload?['isRuntimePreview'], isNot(true));
      expect(
        artifactBlocks.single.artifactProjection?.isRuntimePreview,
        isFalse,
      );
      expect(
        artifactBlocks.single.artifactProjection?.sourcePath,
        savedArtifact.sourcePath,
      );
      expect(
        artifactBlocks.single.artifactProjection?.source,
        '<div>最终落盘内容</div>',
      );
      expect(artifactBlocks.single.logicalId, 'artifact:call_artifact_1');

      await tempDirectory.delete(recursive: true);
    });

    test(
        'keeps artifact relative order stable when persisted takeover replaces runtime artifact',
        () async {
      final tempDirectory = await Directory.systemTemp.createTemp(
        'timeline-artifact-order-',
      );
      final fileStorageService =
          ArtifactFileStorageService(rootDirectory: tempDirectory);
      await fileStorageService.saveArtifactSource(
        groupId: 7,
        artifactId: 'food-rank',
        title: '中国美食',
        type: ArtifactType.html,
        source: '<div>最终落盘内容</div>',
      );
      final service = ChatTimelineProjectionService(
        artifactTurnResolver: ArtifactTurnResolver(
          fileStorageService: fileStorageService,
        ),
        toolBlockProjector: const ToolPresentationBlockProjector(
          registry: ToolUiRendererRegistry(
            renderers: [CreateArtifactToolUiRenderer()],
          ),
        ),
      );

      final runtimeOnlyProjection = service.build(
        groupId: 7,
        messages: [
          ChatMessage(
            id: 30,
            text: '帮我做个 artifact',
            role: MessageRole.user,
            timestamp: DateTime(2026, 4, 30, 10, 0, 0),
          ),
          ChatMessage(
            id: 301,
            text: '天气搜索完成',
            role: MessageRole.assistant,
            contentType: MessageContentType.toolResult,
            timestamp: DateTime(2026, 4, 30, 10, 0, 1, 500),
            payloadJson: const {
              'toolName': 'fetch_weather',
              'status': 'success',
              'summary': '天气搜索完成',
              'data': {'city': 'Shanghai'},
            },
          ),
        ],
        runtimePreviewState: RuntimeStreamingPreviewState(
          messages: [
            RuntimeStreamingPreviewMessage(
              messageId: 'message_1',
              createdAt: DateTime(2026, 4, 30, 10, 0, 1),
              updatedAt: DateTime(2026, 4, 30, 10, 0, 3),
              blocks: [
                RuntimeStreamingPreviewBlock(
                  contentBlockId: 'message_1:thinking:0',
                  blockType: StreamingContentBlockType.thinking,
                  createdAt: DateTime(2026, 4, 30, 10, 0, 1),
                  updatedAt: DateTime(2026, 4, 30, 10, 0, 1),
                  text: '先规划结构',
                ),
                RuntimeStreamingPreviewBlock(
                  contentBlockId: 'message_1:tool:call_artifact_1',
                  blockType: StreamingContentBlockType.toolUse,
                  toolUseId: 'call_artifact_1',
                  toolName: 'create_artifact',
                  createdAt: DateTime(2026, 4, 30, 10, 0, 2),
                  updatedAt: DateTime(2026, 4, 30, 10, 0, 2),
                  text:
                      '{"id":"food-rank","type":"html","title":"中国美食","source":"<div>渐进预览</div>"}',
                ),
                RuntimeStreamingPreviewBlock(
                  contentBlockId: 'message_1:text:1',
                  blockType: StreamingContentBlockType.text,
                  createdAt: DateTime(2026, 4, 30, 10, 0, 3),
                  updatedAt: DateTime(2026, 4, 30, 10, 0, 3),
                  text: '先给你正文说明',
                ),
              ],
            ),
          ],
        ),
      );

      expect(
        runtimeOnlyProjection.assistantBlocks
            .map((block) => block.type)
            .toList(growable: false),
        [
          AssistantTurnBlockType.analysis,
          AssistantTurnBlockType.toolResultSummary,
          AssistantTurnBlockType.artifact,
          AssistantTurnBlockType.finalResponse,
        ],
      );

      final takeoverProjection = service.build(
        groupId: 7,
        messages: [
          ChatMessage(
            id: 30,
            text: '帮我做个 artifact',
            role: MessageRole.user,
            timestamp: DateTime(2026, 4, 30, 10, 0, 0),
          ),
          ChatMessage(
            id: 301,
            text: '天气搜索完成',
            role: MessageRole.assistant,
            contentType: MessageContentType.toolResult,
            timestamp: DateTime(2026, 4, 30, 10, 0, 1, 500),
            payloadJson: const {
              'toolName': 'fetch_weather',
              'status': 'success',
              'summary': '天气搜索完成',
              'data': {'city': 'Shanghai'},
            },
          ),
          ChatMessage(
            id: 31,
            text: '已创建 artifact：food-rank',
            role: MessageRole.assistant,
            contentType: MessageContentType.toolResult,
            timestamp: DateTime(2026, 4, 30, 10, 0, 4),
            payloadJson: const {
              'toolName': 'create_artifact',
              'status': 'success',
              'summary': '已创建 artifact：food-rank',
              'providerCallId': 'call_artifact_1',
              'data': {
                'artifactId': 'food-rank',
                'title': '中国美食',
                'type': 'html',
                'sourcePath': '/workspaces/.default/artifacts/food-rank.html',
              },
            },
          ),
        ],
        runtimePreviewState: RuntimeStreamingPreviewState(
          messages: [
            RuntimeStreamingPreviewMessage(
              messageId: 'message_1',
              createdAt: DateTime(2026, 4, 30, 10, 0, 1),
              updatedAt: DateTime(2026, 4, 30, 10, 0, 3),
              blocks: [
                RuntimeStreamingPreviewBlock(
                  contentBlockId: 'message_1:thinking:0',
                  blockType: StreamingContentBlockType.thinking,
                  createdAt: DateTime(2026, 4, 30, 10, 0, 1),
                  updatedAt: DateTime(2026, 4, 30, 10, 0, 1),
                  text: '先规划结构',
                ),
                RuntimeStreamingPreviewBlock(
                  contentBlockId: 'message_1:tool:call_artifact_1',
                  blockType: StreamingContentBlockType.toolUse,
                  toolUseId: 'call_artifact_1',
                  toolName: 'create_artifact',
                  createdAt: DateTime(2026, 4, 30, 10, 0, 2),
                  updatedAt: DateTime(2026, 4, 30, 10, 0, 2),
                  text:
                      '{"id":"food-rank","type":"html","title":"中国美食","source":"<div>渐进预览</div>"}',
                ),
                RuntimeStreamingPreviewBlock(
                  contentBlockId: 'message_1:text:1',
                  blockType: StreamingContentBlockType.text,
                  createdAt: DateTime(2026, 4, 30, 10, 0, 3),
                  updatedAt: DateTime(2026, 4, 30, 10, 0, 3),
                  text: '先给你正文说明',
                ),
              ],
            ),
          ],
        ),
      );

      expect(
        takeoverProjection.assistantBlocks
            .map((block) => block.type)
            .toList(growable: false),
        [
          AssistantTurnBlockType.analysis,
          AssistantTurnBlockType.toolResultSummary,
          AssistantTurnBlockType.artifact,
          AssistantTurnBlockType.finalResponse,
        ],
      );
      final artifactIndex = takeoverProjection.assistantBlocks.indexWhere(
        (block) => block.type == AssistantTurnBlockType.artifact,
      );
      expect(artifactIndex, 2);
      expect(
        takeoverProjection.assistantBlocks[artifactIndex]
            .payload?['isRuntimePreview'],
        isNot(true),
      );
      expect(
        takeoverProjection.assistantBlocks[artifactIndex]
            .artifactProjection
            ?.source,
        '<div>最终落盘内容</div>',
      );

      await tempDirectory.delete(recursive: true);
    });

    test(
        'keeps logical block order stable after runtime preview state is cleared',
        () async {
      final tempDirectory = await Directory.systemTemp.createTemp(
        'timeline-artifact-order-cleared-',
      );
      final fileStorageService =
          ArtifactFileStorageService(rootDirectory: tempDirectory);
      await fileStorageService.saveArtifactSource(
        groupId: 7,
        artifactId: 'ios-architecture-diagram',
        title: 'iOS 架构层次图',
        type: ArtifactType.svg,
        source: '<svg>final</svg>',
      );
      final service = ChatTimelineProjectionService(
        artifactTurnResolver: ArtifactTurnResolver(
          fileStorageService: fileStorageService,
        ),
        toolBlockProjector: const ToolPresentationBlockProjector(
          registry: ToolUiRendererRegistry(
            renderers: [CreateArtifactToolUiRenderer()],
          ),
        ),
      );

      service.build(
        groupId: 7,
        messages: [
          ChatMessage(
            id: 30,
            text: '帮我用HTML可视化iOS架构',
            role: MessageRole.user,
            timestamp: DateTime(2026, 4, 30, 10, 0, 0),
          ),
          ChatMessage(
            id: 301,
            text: '第一次工具结果',
            role: MessageRole.assistant,
            contentType: MessageContentType.toolResult,
            timestamp: DateTime(2026, 4, 30, 10, 0, 1, 500),
            payloadJson: const {
              'toolName': 'search_chat_history',
              'status': 'success',
              'summary': '第一次工具结果',
              'providerCallId': 'call_search_1',
              'data': {'items': []},
            },
          ),
          ChatMessage(
            id: 302,
            text: '',
            role: MessageRole.assistant,
            timestamp: DateTime(2026, 4, 30, 10, 0, 2, 100),
            reasoningContent: '补充 SVG 结构细节。',
            payloadJson: const {
              'logicalId': 'toolReasoning:resp_tool_2',
              'responseId': 'resp_tool_2',
              'reasoningScope': 'tool_use',
            },
          ),
        ],
        runtimePreviewState: RuntimeStreamingPreviewState(
          messages: [
            RuntimeStreamingPreviewMessage(
              messageId: 'resp_tool_2',
              responseId: 'resp_tool_2',
              createdAt: DateTime(2026, 4, 30, 10, 0, 2),
              updatedAt: DateTime(2026, 4, 30, 10, 0, 4),
              blocks: [
                RuntimeStreamingPreviewBlock(
                  contentBlockId: 'resp_tool_2:tool:call_artifact_1',
                  blockType: StreamingContentBlockType.toolUse,
                  toolUseId: 'call_artifact_1',
                  toolName: 'create_artifact',
                  createdAt: DateTime(2026, 4, 30, 10, 0, 2),
                  updatedAt: DateTime(2026, 4, 30, 10, 0, 4),
                  text:
                      '{"id":"ios-architecture-diagram","type":"svg","title":"iOS 架构层次图","source":"<svg>preview</svg>"}',
                ),
              ],
            ),
          ],
        ),
      );

      final settledProjection = service.build(
        groupId: 7,
        messages: [
          ChatMessage(
            id: 30,
            text: '帮我用HTML可视化iOS架构',
            role: MessageRole.user,
            timestamp: DateTime(2026, 4, 30, 10, 0, 0),
          ),
          ChatMessage(
            id: 301,
            text: '第一次工具结果',
            role: MessageRole.assistant,
            contentType: MessageContentType.toolResult,
            timestamp: DateTime(2026, 4, 30, 10, 0, 1, 500),
            payloadJson: const {
              'toolName': 'search_chat_history',
              'status': 'success',
              'summary': '第一次工具结果',
              'providerCallId': 'call_search_1',
              'data': {'items': []},
            },
          ),
          ChatMessage(
            id: 302,
            text: '',
            role: MessageRole.assistant,
            timestamp: DateTime(2026, 4, 30, 10, 0, 2, 100),
            reasoningContent: '补充 SVG 结构细节。',
            payloadJson: const {
              'logicalId': 'toolReasoning:resp_tool_2',
              'responseId': 'resp_tool_2',
              'reasoningScope': 'tool_use',
            },
          ),
          ChatMessage(
            id: 31,
            text: '已创建 artifact：ios-architecture-diagram',
            role: MessageRole.assistant,
            contentType: MessageContentType.toolResult,
            timestamp: DateTime(2026, 4, 30, 10, 0, 5),
            payloadJson: const {
              'toolName': 'create_artifact',
              'status': 'success',
              'summary': '已创建 artifact：ios-architecture-diagram',
              'providerCallId': 'call_artifact_1',
              'data': {
                'artifactId': 'ios-architecture-diagram',
                'title': 'iOS 架构层次图',
                'type': 'svg',
                'sourcePath':
                    '/workspaces/.default/artifacts/ios-architecture-diagram.svg',
              },
            },
          ),
        ],
        runtimePreviewState: const RuntimeStreamingPreviewState(),
      );

      expect(
        settledProjection.assistantBlocks
            .map((block) => block.type)
            .toList(growable: false),
        [
          AssistantTurnBlockType.toolResultSummary,
          AssistantTurnBlockType.artifact,
          AssistantTurnBlockType.analysis,
        ],
      );

      await tempDirectory.delete(recursive: true);
    });

    test(
        'create artifact renderer can hide tool phases while keeping artifact projection',
        () async {
      final tempDirectory = await Directory.systemTemp.createTemp(
        'timeline-artifact-hidden-',
      );
      final fileStorageService =
          ArtifactFileStorageService(rootDirectory: tempDirectory);
      await fileStorageService.saveArtifactSource(
        groupId: 7,
        artifactId: 'portfolio-pie',
        title: '投资组合饼图',
        type: ArtifactType.html,
        source: '<div>artifact body</div>',
      );
      final service = ChatTimelineProjectionService(
        artifactTurnResolver: ArtifactTurnResolver(
          fileStorageService: fileStorageService,
        ),
        toolBlockProjector: const ToolPresentationBlockProjector(
          registry: ToolUiRendererRegistry(
            renderers: [CreateArtifactToolUiRenderer()],
          ),
        ),
      );

      final projection = service.build(
        groupId: 7,
        messages: [
          ChatMessage(
            id: 30,
            text: '帮我画个图',
            role: MessageRole.user,
            timestamp: DateTime(2026, 4, 30, 10, 0, 0),
          ),
          ChatMessage(
            id: 31,
            text: '准备创建 artifact',
            role: MessageRole.assistant,
            contentType: MessageContentType.toolInvocation,
            timestamp: DateTime(2026, 4, 30, 10, 0, 1),
            payloadJson: const {
              'toolName': 'create_artifact',
              'arguments': {
                'id': 'portfolio-pie',
                'type': 'html',
              },
              'status': 'proposed',
              'summary': '准备创建 artifact',
              'requiresConfirmation': false,
            },
          ),
          ChatMessage(
            id: 32,
            text: '已创建 artifact：portfolio-pie',
            role: MessageRole.assistant,
            contentType: MessageContentType.toolResult,
            timestamp: DateTime(2026, 4, 30, 10, 0, 2),
            payloadJson: const {
              'toolName': 'create_artifact',
              'status': 'success',
              'summary': '已创建 artifact：portfolio-pie',
              'data': {
                'artifactId': 'portfolio-pie',
                'title': '投资组合饼图',
                'type': 'html',
                'sourcePath': 'artifacts/7/portfolio-pie.html',
              },
            },
          ),
        ],
      );

      expect(
        projection.assistantBlocks.where(
          (block) =>
              block.type == AssistantTurnBlockType.toolWorkflow ||
              block.type == AssistantTurnBlockType.toolResultSummary,
        ),
        isEmpty,
      );
      expect(
        projection.assistantBlocks.where(
          (block) => block.type == AssistantTurnBlockType.artifact,
        ),
        hasLength(1),
      );

      await tempDirectory.delete(recursive: true);
    });
  });
}
