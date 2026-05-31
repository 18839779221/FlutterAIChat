import 'package:ai_chat/models/llm/streaming_message_event.dart';
import 'package:ai_chat/services/runtime_streaming_preview_projector.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('RuntimeStreamingPreviewProjector', () {
    test('folds block deltas into runtime preview message state', () {
      final projector = RuntimeStreamingPreviewProjector();
      final now = DateTime(2026, 5, 27, 12);

      projector.consume(
        const StreamingMessageStartEvent(messageId: 'm1'),
        now: now,
      );
      projector.consume(
        const StreamingContentBlockStartEvent(
          messageId: 'm1',
          contentBlockId: 'm1:text',
          blockType: StreamingContentBlockType.text,
        ),
        now: now,
      );
      projector.consume(
        const StreamingContentBlockDeltaEvent(
          messageId: 'm1',
          contentBlockId: 'm1:text',
          deltaType: StreamingContentDeltaType.text,
          value: 'hello',
        ),
        now: now,
      );

      final state = projector.currentState();
      expect(state.messages, hasLength(1));
      expect(state.messages.single.blocks, hasLength(1));
      expect(state.messages.single.blocks.single.text, 'hello');
    });

    test('keeps tool use block identity and accumulates input json', () {
      final projector = RuntimeStreamingPreviewProjector();
      final now = DateTime(2026, 5, 27, 12);

      projector.consume(
        const StreamingMessageStartEvent(messageId: 'm1'),
        now: now,
      );
      projector.consume(
        const StreamingContentBlockStartEvent(
          messageId: 'm1',
          contentBlockId: 'm1:tool:0',
          blockType: StreamingContentBlockType.toolUse,
          toolUseId: 'tool_1',
          toolName: 'create_artifact',
        ),
        now: now,
      );
      projector.consume(
        const StreamingContentBlockDeltaEvent(
          messageId: 'm1',
          contentBlockId: 'm1:tool:0',
          deltaType: StreamingContentDeltaType.inputJson,
          value: '{"source":"<div>Hello',
        ),
        now: now,
      );

      final block = projector.currentState().messages.single.blocks.single;
      expect(block.blockType, StreamingContentBlockType.toolUse);
      expect(block.toolUseId, 'tool_1');
      expect(block.toolName, 'create_artifact');
      expect(block.text, '{"source":"<div>Hello');
    });

    test('preserves runtime trace metadata on the preview message', () {
      final projector = RuntimeStreamingPreviewProjector();
      final now = DateTime(2026, 5, 27, 12);

      projector.consume(
        const StreamingMessageStartEvent(
          messageId: 'm1',
          runtimeMetadata: {
            'streamTraceId': 'trace_1',
            'streamTurnId': 'turn_1',
          },
        ),
        now: now,
      );
      projector.consume(
        const StreamingContentBlockDeltaEvent(
          messageId: 'm1',
          contentBlockId: 'm1:text',
          deltaType: StreamingContentDeltaType.text,
          value: 'hello',
          runtimeMetadata: {
            'streamTraceId': 'trace_1',
            'streamTurnId': 'turn_1',
          },
        ),
        now: now,
      );

      final message = projector.currentState().messages.single;
      expect(message.streamTraceId, 'trace_1');
      expect(message.streamTurnId, 'turn_1');
      expect(message.blocks.single.text, 'hello');
    });
  });
}
