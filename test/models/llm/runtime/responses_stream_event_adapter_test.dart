import 'package:ai_chat/models/llm/runtime/responses_stream_event_adapter.dart';
import 'package:ai_chat/models/llm/streaming_message_event.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openai_dart/openai_dart.dart' as oai;

void main() {
  test('adapts responses sdk events into preview events', () async {
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

    final previewEvents = await adapter.adaptPreview(events).toList();

    expect(previewEvents.first, isA<StreamingMessageStartEvent>());

    final textDelta = previewEvents.whereType<StreamingContentBlockDeltaEvent>()
        .firstWhere((event) => event.deltaType == StreamingContentDeltaType.text);
    expect(textDelta.value, 'Hello');

    final toolStart = previewEvents.whereType<StreamingContentBlockStartEvent>()
        .firstWhere((event) => event.blockType == StreamingContentBlockType.toolUse);
    expect(toolStart.toolUseId, 'call_1');
    expect(toolStart.toolName, 'web_search');

    final toolDelta = previewEvents.whereType<StreamingContentBlockDeltaEvent>()
        .firstWhere((event) => event.deltaType == StreamingContentDeltaType.inputJson);
    expect(toolDelta.value, '{"query":"flutter"}');

    expect(previewEvents.last, isA<StreamingMessageStopEvent>());
  });
}
