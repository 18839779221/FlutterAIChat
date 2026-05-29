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
          .where((block) => block.type == AssistantTurnBlockType.toolResultSummary)
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
      expect(resultEvent.data['data'], containsPair('filePath', 'lib/main.dart'));
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

    test(
        'projects runtime create_artifact preview from runtime preview state',
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
                  contentBlockId: 'message_1:tool:0',
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
      expect(runtimeArtifactBlocks.single.text, contains('渐进预览'));
      expect(projection.runtimePreviewState.messages, hasLength(1));
      expect(
        projection.runtimePreviewState.messages.single.blocks.single.toolName,
        'create_artifact',
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
                'sourcePath': 'artifacts/7/food-rank.html',
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
                  contentBlockId: 'message_1:tool:0',
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
        'artifacts/7/food-rank.html',
      );
      expect(
        artifactBlocks.single.artifactProjection?.source,
        '<div>最终落盘内容</div>',
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
