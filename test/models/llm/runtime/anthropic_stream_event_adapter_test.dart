import 'package:ai_chat/models/llm/runtime/anthropic_stream_event_adapter.dart';
import 'package:ai_chat/models/llm/streaming_planner_chunk.dart';
import 'package:anthropic_sdk_dart/anthropic_sdk_dart.dart' as anthropic;
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('adapts anthropic tool_use chunks into planner tool call deltas', () async {
    const adapter = AnthropicStreamEventAdapter();
    final chunks = await adapter
        .adapt(
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

    expect(chunks.where((c) => c.type == StreamingPlannerChunkType.toolCallStarted), isNotEmpty);
    expect(chunks.where((c) => c.type == StreamingPlannerChunkType.toolCallArgumentsDelta), isNotEmpty);
    expect(chunks.where((c) => c.type == StreamingPlannerChunkType.toolCallCompleted), isNotEmpty);
  });

  test('preserves tool metadata across anthropic tool_use delta lifecycle',
      () async {
    const adapter = AnthropicStreamEventAdapter();
    final chunks = await adapter
        .adapt(
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

    final argsChunk = chunks.firstWhere(
      (c) => c.type == StreamingPlannerChunkType.toolCallArgumentsDelta,
    );
    final doneChunk = chunks.firstWhere(
      (c) => c.type == StreamingPlannerChunkType.toolCallCompleted,
    );

    expect(argsChunk.toolCallIndex, 2);
    expect(argsChunk.providerCallId, 'toolu_meta');
    expect(argsChunk.toolName, 'create_artifact');
    expect(doneChunk.toolCallIndex, 2);
    expect(doneChunk.providerCallId, 'toolu_meta');
    expect(doneChunk.toolName, 'create_artifact');
  });

  test('captures anthropic thinking signature and ping as keepalive chunks',
      () async {
    const adapter = AnthropicStreamEventAdapter();
    final chunks = await adapter
        .adapt(
          Stream<anthropic.MessageStreamEvent>.fromIterable(const [
            anthropic.ContentBlockDeltaEvent(
              index: 0,
              delta: anthropic.SignatureDelta('sig_thinking_1'),
            ),
            anthropic.PingEvent(),
            anthropic.MessageStopEvent(),
          ]),
        )
        .toList();

    final keepaliveChunks = chunks
        .where((c) => c.type == StreamingPlannerChunkType.keepalive)
        .toList();
    expect(keepaliveChunks, hasLength(2));
    expect(
      keepaliveChunks.first.providerMetadata?['anthropic_thinking_signature'],
      'sig_thinking_1',
    );
    expect(
      keepaliveChunks.last.providerMetadata?['anthropic_event_type'],
      'ping',
    );
  });

  test('captures anthropic message id from message_start for continuation',
      () async {
    const adapter = AnthropicStreamEventAdapter();
    final chunks = await adapter
        .adapt(
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

    final keepaliveChunk = chunks.firstWhere(
      (c) =>
          c.type == StreamingPlannerChunkType.keepalive &&
          c.providerMetadata?['message_id'] == 'msg_stream_1',
    );
    expect(keepaliveChunk.providerMetadata?['message_id'], 'msg_stream_1');
  });
}
