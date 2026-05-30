import 'package:ai_chat/models/chat/active_turn_status_presentation.dart';
import 'package:ai_chat/models/chat/chat_timeline_projection.dart';
import 'package:ai_chat/models/chat/runtime_streaming_preview_state.dart';
import 'package:ai_chat/models/chat/tool_presentation_event.dart';
import 'package:ai_chat/models/chat_message.dart';
import 'package:ai_chat/models/llm/streaming_message_event.dart';
import 'package:ai_chat/models/response/message_content_type.dart';
import 'package:ai_chat/models/tool/tool_invocation.dart';
import 'package:ai_chat/providers/chat_send_state_providers.dart';
import 'package:ai_chat/services/active_turn_status_resolver.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ActiveTurnStatusResolver', () {
    const resolver = ActiveTurnStatusResolver();

    test('confirmation status wins over tool and streaming phases', () {
      final confirmationMessage = ChatMessage(
        id: 41,
        text: '准备执行工具',
        role: MessageRole.assistant,
        status: MessageStatus.completed,
        contentType: MessageContentType.actionConfirmation,
      );
      const invocation = ToolInvocation(
        toolName: 'Write',
        arguments: {'file_path': 'notes.txt'},
        status: ToolInvocationStatus.awaitingConfirmation,
        summary: '准备写入文件',
        requiresConfirmation: true,
      );
      final runningToolEvent = ToolPresentationEvent(
        toolName: 'web_search',
        phase: ToolPresentationEventPhase.running,
        turnId: 'turn-1',
        sourceContentType: MessageContentType.toolInvocation,
        timestamp: DateTime(2026, 5, 31, 10, 0, 1),
      );
      final previewState = RuntimeStreamingPreviewState(
        messages: [
          RuntimeStreamingPreviewMessage(
            messageId: 'preview-1',
            createdAt: DateTime(2026, 5, 31, 10, 0, 0),
            updatedAt: DateTime(2026, 5, 31, 10, 0, 2),
            blocks: [
              RuntimeStreamingPreviewBlock(
                contentBlockId: 'preview-1:text',
                blockType: StreamingContentBlockType.text,
                createdAt: DateTime(2026, 5, 31, 10, 0, 0),
                updatedAt: DateTime(2026, 5, 31, 10, 0, 2),
                text: '正在输出正文',
              ),
            ],
          ),
        ],
      );

      final status = resolver.resolve(
        projection: ChatTimelineProjection(
          pendingToolConfirmation: ProjectedPendingToolConfirmation(
            message: confirmationMessage,
            invocation: invocation,
          ),
          toolPresentationEvents: [runningToolEvent],
          runtimePreviewState: previewState,
        ),
        sendState: const ChatSendState(
          phase: ChatSendPhase.streamingResponse,
          isGenerating: true,
        ),
      );

      expect(status, isNotNull);
      expect(status?.phase, ActiveTurnStatusPhase.awaitingConfirmation);
      expect(status?.text, '准备写入文件');
    });

    test('running web_search maps to dedicated status copy', () {
      final status = resolver.resolve(
        projection: ChatTimelineProjection(
          toolPresentationEvents: [
            ToolPresentationEvent(
              toolName: 'web_search',
              phase: ToolPresentationEventPhase.running,
              turnId: 'turn-2',
              sourceContentType: MessageContentType.toolInvocation,
              sourceMessageId: 52,
              timestamp: DateTime(2026, 5, 31, 11, 0, 0),
            ),
          ],
        ),
        sendState: const ChatSendState(
          phase: ChatSendPhase.executingTool,
          isGenerating: false,
        ),
      );

      expect(status, isNotNull);
      expect(status?.phase, ActiveTurnStatusPhase.executingTool);
      expect(status?.toolName, 'web_search');
      expect(status?.text, '正在联网搜索');
    });

    test('tool result without active streaming falls back to planning next step', () {
      final status = resolver.resolve(
        projection: ChatTimelineProjection(
          toolPresentationEvents: [
            ToolPresentationEvent(
              toolName: 'fetch_webpage',
              phase: ToolPresentationEventPhase.result,
              turnId: 'turn-3',
              sourceContentType: MessageContentType.toolResult,
              sourceMessageId: 63,
              timestamp: DateTime(2026, 5, 31, 12, 0, 0),
            ),
          ],
        ),
        sendState: const ChatSendState(
          phase: ChatSendPhase.preparing,
          isGenerating: false,
        ),
      );

      expect(status, isNotNull);
      expect(status?.phase, ActiveTurnStatusPhase.planning);
      expect(status?.text, '正在规划下一步');
    });

    test('idle phase suppresses stale completed tool status', () {
      final status = resolver.resolve(
        projection: ChatTimelineProjection(
          toolPresentationEvents: [
            ToolPresentationEvent(
              toolName: 'create_artifact__guideline',
              phase: ToolPresentationEventPhase.result,
              turnId: 'turn-4',
              sourceContentType: MessageContentType.toolResult,
              sourceMessageId: 73,
              timestamp: DateTime(2026, 5, 31, 12, 30, 0),
            ),
          ],
        ),
        sendState: const ChatSendState(
          phase: ChatSendPhase.idle,
          isGenerating: false,
        ),
      );

      expect(status, isNull);
    });

    test('transient send status override wins over planning copy', () {
      final status = resolver.resolve(
        projection: ChatTimelineProjection(
          toolPresentationEvents: [
            ToolPresentationEvent(
              toolName: 'web_search',
              phase: ToolPresentationEventPhase.proposed,
              turnId: 'turn-5',
              sourceContentType: MessageContentType.toolInvocation,
              sourceMessageId: 81,
              timestamp: DateTime(2026, 5, 31, 13, 0, 0),
            ),
          ],
        ),
        sendState: const ChatSendState(
          phase: ChatSendPhase.preparing,
          isGenerating: false,
          statusText: '请求超时，正在重试 1/5',
        ),
      );

      expect(status, isNotNull);
      expect(status?.phase, ActiveTurnStatusPhase.planning);
      expect(status?.text, '请求超时，正在重试 1/5');
    });

    test('parallel active tools degrade to generic running copy', () {
      final status = resolver.resolve(
        projection: ChatTimelineProjection(
          toolPresentationEvents: [
            ToolPresentationEvent(
              toolName: 'web_search',
              phase: ToolPresentationEventPhase.running,
              turnId: 'turn-6',
              sourceContentType: MessageContentType.toolInvocation,
              sourceMessageId: 91,
              timestamp: DateTime(2026, 5, 31, 14, 0, 0),
            ),
            ToolPresentationEvent(
              toolName: 'fetch_webpage',
              phase: ToolPresentationEventPhase.running,
              turnId: 'turn-6',
              sourceContentType: MessageContentType.toolInvocation,
              sourceMessageId: 92,
              timestamp: DateTime(2026, 5, 31, 14, 0, 1),
            ),
          ],
        ),
        sendState: const ChatSendState(
          phase: ChatSendPhase.executingTool,
          isGenerating: false,
        ),
      );

      expect(status, isNotNull);
      expect(status?.phase, ActiveTurnStatusPhase.executingTool);
      expect(status?.toolName, isNull);
      expect(status?.text, '正在执行工具');
    });

    test('later result only clears the matching running tool', () {
      final status = resolver.resolve(
        projection: ChatTimelineProjection(
          toolPresentationEvents: [
            ToolPresentationEvent(
              toolName: 'web_search',
              phase: ToolPresentationEventPhase.running,
              turnId: 'turn-7',
              sourceContentType: MessageContentType.toolInvocation,
              sourceMessageId: 101,
              timestamp: DateTime(2026, 5, 31, 15, 0, 0),
            ),
            ToolPresentationEvent(
              toolName: 'fetch_webpage',
              phase: ToolPresentationEventPhase.running,
              turnId: 'turn-7',
              sourceContentType: MessageContentType.toolInvocation,
              sourceMessageId: 102,
              timestamp: DateTime(2026, 5, 31, 15, 0, 1),
            ),
            ToolPresentationEvent(
              toolName: 'web_search',
              phase: ToolPresentationEventPhase.result,
              turnId: 'turn-7',
              sourceContentType: MessageContentType.toolResult,
              sourceMessageId: 103,
              timestamp: DateTime(2026, 5, 31, 15, 0, 2),
            ),
          ],
        ),
        sendState: const ChatSendState(
          phase: ChatSendPhase.executingTool,
          isGenerating: false,
        ),
      );

      expect(status, isNotNull);
      expect(status?.phase, ActiveTurnStatusPhase.executingTool);
      expect(status?.toolName, 'fetch_webpage');
      expect(status?.text, '正在读取网页');
    });

    test('streaming phase falls back to generating reply when no richer signal exists', () {
      final status = resolver.resolve(
        projection: const ChatTimelineProjection(),
        sendState: const ChatSendState(
          phase: ChatSendPhase.streamingResponse,
          isGenerating: true,
        ),
      );

      expect(status, isNotNull);
      expect(status?.phase, ActiveTurnStatusPhase.streamingResponse);
      expect(status?.text, '正在生成回复');
    });
  });
}
