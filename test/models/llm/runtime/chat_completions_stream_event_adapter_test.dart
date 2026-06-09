import 'package:ai_chat/models/llm/runtime/chat_completions_stream_event_adapter.dart';
import 'package:ai_chat/models/llm/streaming_message_event.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('chat completions adapter synthesizes text and tool blocks from deltas',
      () async {
    const adapter = ChatCompletionsStreamEventAdapter();
    final events = await adapter.adapt(
      Stream<Map<String, dynamic>>.fromIterable([
        {
          'id': 'chatcmpl_1',
          'choices': [
            {
              'delta': {
                'content': 'Hello',
                'tool_calls': [
                  {
                    'index': 0,
                    'id': 'call_1',
                    'type': 'function',
                    'function': {
                      'name': 'create_artifact',
                      'arguments': '{"id":"demo"}',
                    },
                  },
                ],
              },
            },
          ],
        },
      ]),
    ).toList();

    expect(events.whereType<StreamingMessageStartEvent>(), hasLength(1));
    expect(
      events.whereType<StreamingContentBlockStartEvent>().any(
            (event) =>
                event.blockType == StreamingContentBlockType.text &&
                event.contentBlockId == 'chatcmpl_1:text',
          ),
      isTrue,
    );
    expect(
      events.whereType<StreamingContentBlockStartEvent>().any(
            (event) =>
                event.blockType == StreamingContentBlockType.toolUse &&
                event.contentBlockId == 'chatcmpl_1:tool:call_1' &&
                event.toolUseId == 'call_1' &&
                event.toolName == 'create_artifact',
          ),
      isTrue,
    );
    expect(
      events.whereType<StreamingContentBlockDeltaEvent>().any(
            (event) =>
                event.deltaType == StreamingContentDeltaType.inputJson &&
                event.value == '{"id":"demo"}',
          ),
      isTrue,
    );
  });

  test('chat completions adapter synthesizes thinking block from reasoning delta',
      () async {
    const adapter = ChatCompletionsStreamEventAdapter();
    final events = await adapter.adapt(
      Stream<Map<String, dynamic>>.fromIterable([
        {
          'id': 'chatcmpl_2',
          'choices': [
            {
              'delta': {
                'reasoning_content': '先分析',
              },
            },
          ],
        },
      ]),
    ).toList();

    final reasoningDelta = events
        .whereType<StreamingContentBlockDeltaEvent>()
        .firstWhere((event) => event.deltaType == StreamingContentDeltaType.thinking);
    expect(reasoningDelta.contentBlockId, 'chatcmpl_2:thinking');
    expect(reasoningDelta.value, '先分析');
  });

  test(
      'continues the same tool block when later chunks omit tool id and name',
      () async {
    const adapter = ChatCompletionsStreamEventAdapter();
    final events = await adapter.adapt(
      Stream<Map<String, dynamic>>.fromIterable([
        {
          'id': 'chatcmpl_3',
          'choices': [
            {
              'delta': {
                'tool_calls': [
                  {
                    'index': 0,
                    'id': 'call_1',
                    'type': 'function',
                    'function': {
                      'name': 'create_artifact__guideline',
                      'arguments': '',
                    },
                  },
                ],
              },
            },
          ],
        },
        {
          'id': 'chatcmpl_3',
          'choices': [
            {
              'delta': {
                'tool_calls': [
                  {
                    'index': 0,
                    'function': {
                      'arguments': '{}',
                    },
                  },
                ],
              },
            },
          ],
        },
      ]),
    ).toList();

    final toolStarts = events
        .whereType<StreamingContentBlockStartEvent>()
        .where((event) => event.blockType == StreamingContentBlockType.toolUse)
        .toList();
    expect(toolStarts, hasLength(1));
    expect(toolStarts.single.contentBlockId, 'chatcmpl_3:tool:call_1');
    expect(toolStarts.single.toolUseId, 'call_1');
    expect(toolStarts.single.toolName, 'create_artifact__guideline');

    final toolDeltas = events
        .whereType<StreamingContentBlockDeltaEvent>()
        .where((event) => event.deltaType == StreamingContentDeltaType.inputJson)
        .toList();
    expect(toolDeltas, hasLength(1));
    expect(toolDeltas.single.contentBlockId, 'chatcmpl_3:tool:call_1');
    expect(toolDeltas.single.value, '{}');
  });
}
