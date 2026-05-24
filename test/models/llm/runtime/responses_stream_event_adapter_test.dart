import 'package:ai_chat/models/llm/runtime/responses_stream_event_adapter.dart';
import 'package:ai_chat/models/llm/streaming_planner_chunk.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openai_dart/openai_dart.dart' as oai;

void main() {
  test('adapts responses sdk events into planner chunks', () async {
    const adapter = ResponsesStreamEventAdapter();
    final events = Stream<oai.ResponseStreamEvent>.fromIterable([
      oai.OutputTextDeltaEvent(
        itemId: 'msg_1',
        outputIndex: 0,
        contentIndex: 0,
        delta: 'Hello',
      ),
      oai.ResponseStreamEvent.fromJson({
        'type': 'response.output_item.added',
        'output_index': 1,
        'item': {
          'type': 'function_call',
          'id': 'fc_1',
          'call_id': 'call_1',
          'name': 'web_search',
          'arguments': '',
        },
      }),
      oai.ResponseStreamEvent.fromJson({
        'type': 'response.function_call_arguments.delta',
        'output_index': 1,
        'call_id': 'call_1',
        'name': 'web_search',
        'delta': '{"query":"flutter"}',
      }),
    ]);

    final chunks = await adapter.adapt(events).toList();

    expect(chunks[0].type, StreamingPlannerChunkType.contentDelta);
    expect(chunks[0].content, 'Hello');
    expect(chunks[1].type, StreamingPlannerChunkType.toolCallStarted);
    expect(chunks[1].providerCallId, 'call_1');
    expect(chunks[2].type, StreamingPlannerChunkType.toolCallArgumentsDelta);
    expect(chunks[2].argumentsTextDelta, '{"query":"flutter"}');
    expect(chunks.last.type, StreamingPlannerChunkType.streamCompleted);
  });
}
