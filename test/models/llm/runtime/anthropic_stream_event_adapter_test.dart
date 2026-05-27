import 'package:ai_chat/models/llm/runtime/anthropic_stream_event_adapter.dart';
import 'package:ai_chat/models/llm/streaming_message_event.dart';
import 'package:anthropic_sdk_dart/anthropic_sdk_dart.dart' as anthropic;
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('adapts anthropic tool_use events into preview tool lifecycle', () async {
    const adapter = AnthropicStreamEventAdapter();
    final previewEvents = await adapter
        .adaptPreview(
          Stream<anthropic.MessageStreamEvent>.fromIterable(const [
            anthropic.ContentBlockStartEvent(
              index: 0,
              contentBlock: anthropic.ToolUseBlock(
                id: 'toolu_1',
                name: 'web_search',
                input: {'query': 'google ai'},
              ),
            ),
            anthropic.ContentBlockDeltaEvent(
              index: 0,
              delta: anthropic.InputJsonDelta('{"query":"google ai"}'),
            ),
            anthropic.ContentBlockStopEvent(index: 0),
            anthropic.MessageStopEvent(),
          ]),
        )
        .toList();

    expect(
      previewEvents.whereType<StreamingContentBlockStartEvent>().any(
            (event) =>
                event.blockType == StreamingContentBlockType.toolUse &&
                event.toolUseId == 'toolu_1' &&
                event.toolName == 'web_search',
          ),
      isTrue,
    );
    expect(
      previewEvents.whereType<StreamingContentBlockDeltaEvent>().any(
            (event) =>
                event.deltaType == StreamingContentDeltaType.inputJson &&
                event.value == '{"query":"google ai"}',
          ),
      isTrue,
    );
    expect(
      previewEvents.whereType<StreamingContentBlockStopEvent>(),
      isNotEmpty,
    );
  });

  test('preserves tool metadata across anthropic tool_use delta lifecycle',
      () async {
    const adapter = AnthropicStreamEventAdapter();
    final previewEvents = await adapter
        .adaptPreview(
          Stream<anthropic.MessageStreamEvent>.fromIterable(const [
            anthropic.ContentBlockStartEvent(
              index: 2,
              contentBlock: anthropic.ToolUseBlock(
                id: 'toolu_meta',
                name: 'create_artifact',
                input: {'source': '<div>ok</div>'},
              ),
            ),
            anthropic.ContentBlockDeltaEvent(
              index: 2,
              delta: anthropic.InputJsonDelta('{"source":"<div>ok</div>"}'),
            ),
            anthropic.ContentBlockStopEvent(index: 2),
            anthropic.MessageStopEvent(),
          ]),
        )
        .toList();

    final toolStart = previewEvents
        .whereType<StreamingContentBlockStartEvent>()
        .firstWhere((event) => event.blockType == StreamingContentBlockType.toolUse);
    final toolDelta = previewEvents
        .whereType<StreamingContentBlockDeltaEvent>()
        .firstWhere((event) => event.deltaType == StreamingContentDeltaType.inputJson);

    expect(toolStart.toolUseId, 'toolu_meta');
    expect(toolStart.toolName, 'create_artifact');
    expect(toolDelta.value, '{"source":"<div>ok</div>"}');
  });

  test('captures anthropic thinking signature as signature delta', () async {
    const adapter = AnthropicStreamEventAdapter();
    final previewEvents = await adapter
        .adaptPreview(
          Stream<anthropic.MessageStreamEvent>.fromIterable(const [
            anthropic.ContentBlockDeltaEvent(
              index: 0,
              delta: anthropic.SignatureDelta('sig_thinking_1'),
            ),
            anthropic.MessageStopEvent(),
          ]),
        )
        .toList();

    final signatureDelta = previewEvents
        .whereType<StreamingContentBlockDeltaEvent>()
        .firstWhere((event) => event.deltaType == StreamingContentDeltaType.signature);
    expect(signatureDelta.value, 'sig_thinking_1');
  });

  test('captures anthropic message id from message_start', () async {
    const adapter = AnthropicStreamEventAdapter();
    final previewEvents = await adapter
        .adaptPreview(
          Stream<anthropic.MessageStreamEvent>.fromIterable([
            anthropic.MessageStartEvent(
              message: anthropic.Message(
                id: 'msg_stream_1',
                content: const [],
                model: 'claude-sonnet-4-6',
                usage: const anthropic.Usage(
                  inputTokens: 1,
                  outputTokens: 0,
                ),
              ),
            ),
            const anthropic.MessageStopEvent(),
          ]),
        )
        .toList();

    final messageStart = previewEvents.firstWhere(
      (event) => event is StreamingMessageStartEvent,
    ) as StreamingMessageStartEvent;
    expect(messageStart.messageId, 'msg_stream_1');
    expect(messageStart.providerMetadata?['message_id'], 'msg_stream_1');
  });
}
