import 'dart:convert';

import 'package:ai_chat/models/llm/api_protocol_resolver.dart';
import 'package:ai_chat/models/llm/api_stream_parser.dart';
import 'package:ai_chat/models/llm/streaming_planner_chunk.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

void main() {
  group('ApiStreamParser chat completions', () {
    test('splits inline think tags from streamed content deltas', () async {
      const parser = ApiStreamParser();
      final response = http.StreamedResponse(
        Stream<List<int>>.fromIterable([
          utf8.encode(
            'data: {"choices":[{"delta":{"content":"<think>先"}}]}\n\n'
            'data: {"choices":[{"delta":{"content":"分析</think>答"}}]}\n\n'
            'data: {"choices":[{"delta":{"content":"案"}}]}\n\n'
            'data: [DONE]\n',
          ),
        ]),
        200,
      );

      final chunks =
          await parser.parse(response, ApiStyle.chatCompletions).toList();
      final decoded = chunks
          .map((chunk) => jsonDecode(chunk) as Map<String, dynamic>)
          .toList(growable: false);
      final reasoning = decoded
          .where((item) => item['type'] == 'reasoning')
          .map((item) => item['content'] as String)
          .join();
      final content = decoded
          .where((item) => item['type'] == 'content')
          .map((item) => item['content'] as String)
          .join();

      expect(reasoning, '先分析');
      expect(content, '答案');
    });
  });

  group('ApiStreamParser anthropic messages', () {
    test('parses text and thinking deltas', () async {
      const parser = ApiStreamParser();
      final response = http.StreamedResponse(
        Stream<List<int>>.fromIterable([
          utf8.encode(
            'event: content_block_delta\n'
            'data: {"type":"content_block_delta","delta":{"type":"text_delta","text":"你好"}}\n\n'
            'event: content_block_delta\n'
            'data: {"type":"content_block_delta","delta":{"type":"thinking_delta","thinking":"先分析"}}\n\n'
            'data: [DONE]\n',
          ),
        ]),
        200,
      );

      final chunks =
          await parser.parse(response, ApiStyle.anthropicMessages).toList();

      expect(
        chunks,
        contains(jsonEncode({'type': 'content', 'content': '你好'})),
      );
      expect(
        chunks,
        contains(jsonEncode({'type': 'reasoning', 'content': '先分析'})),
      );
    });

    test('parses anthropic planner tool use chunks', () async {
      const parser = ApiStreamParser();
      final response = http.StreamedResponse(
        Stream<List<int>>.fromIterable([
          utf8.encode(
            'event: content_block_start\n'
            'data: {"type":"content_block_start","index":0,"content_block":{"type":"tool_use","id":"toolu_1","name":"write_file"}}\n\n'
            'event: content_block_delta\n'
            'data: {"type":"content_block_delta","index":0,"delta":{"type":"input_json_delta","partial_json":"{\\"path\\":\\"a.txt\\","}}\n\n'
            'event: content_block_delta\n'
            'data: {"type":"content_block_delta","index":0,"delta":{"type":"input_json_delta","partial_json":"\\"content\\":\\"hello\\"}"}}\n\n'
            'event: content_block_stop\n'
            'data: {"type":"content_block_stop","index":0}\n\n'
            'data: [DONE]\n',
          ),
        ]),
        200,
      );

      final chunks = await parser
          .parsePlannerChunks(response, ApiStyle.anthropicMessages)
          .toList();

      expect(
        chunks.any(
          (chunk) =>
              chunk.type == StreamingPlannerChunkType.toolCallStarted &&
              chunk.providerCallId == 'toolu_1' &&
              chunk.toolName == 'write_file',
        ),
        isTrue,
      );
      expect(
        chunks.where(
          (chunk) =>
              chunk.type == StreamingPlannerChunkType.toolCallArgumentsDelta &&
              chunk.providerCallId == 'toolu_1',
        ),
        hasLength(2),
      );
      expect(
        chunks.any(
          (chunk) =>
              chunk.type == StreamingPlannerChunkType.toolCallCompleted &&
              chunk.providerCallId == 'toolu_1',
        ),
        isTrue,
      );
    });
  });

  group('ApiStreamParser chat completions planner', () {
    test('parses tool call argument deltas into planner chunks', () async {
      const parser = ApiStreamParser();
      final firstChunk = jsonEncode({
        'id': 'chatcmpl_stream',
        'choices': [
          {
            'delta': {
              'tool_calls': [
                {
                  'id': 'call_1',
                  'type': 'function',
                  'function': {
                    'name': 'search_chat_history',
                    'arguments': '{"query":"数据',
                  },
                },
              ],
            },
          },
        ],
      });
      final secondChunk = jsonEncode({
        'id': 'chatcmpl_stream',
        'choices': [
          {
            'delta': {
              'tool_calls': [
                {
                  'id': 'call_1',
                  'type': 'function',
                  'function': {
                    'arguments': '库版本"}',
                  },
                },
              ],
            },
          },
        ],
      });
      final response = http.StreamedResponse(
        Stream<List<int>>.fromIterable([
          utf8.encode('data: $firstChunk\n\n'),
          utf8.encode('data: $secondChunk\n\n'),
          utf8.encode('data: [DONE]\n'),
        ]),
        200,
      );

      final chunks = await parser
          .parsePlannerChunks(response, ApiStyle.chatCompletions)
          .toList();

      expect(
        chunks.any(
          (chunk) =>
              chunk.type == StreamingPlannerChunkType.toolCallStarted &&
              chunk.providerCallId == 'call_1' &&
              chunk.toolName == 'search_chat_history',
        ),
        isTrue,
      );
      expect(
        chunks.where(
          (chunk) =>
              chunk.type == StreamingPlannerChunkType.toolCallArgumentsDelta &&
              chunk.providerCallId == 'call_1',
        ),
        hasLength(2),
      );
      expect(
        chunks.last.type,
        StreamingPlannerChunkType.streamCompleted,
      );
    });
  });

  group('ApiStreamParser responses planner', () {
    test('parses function call argument deltas and completion chunks',
        () async {
      const parser = ApiStreamParser();
      final addedChunk = jsonEncode({
        'type': 'response.output_item.added',
        'response': {'id': 'resp_stream'},
        'item': {
          'type': 'function_call',
          'call_id': 'fc_1',
          'name': 'web_search',
        },
      });
      final firstArgsChunk = jsonEncode({
        'type': 'response.function_call_arguments.delta',
        'response': {'id': 'resp_stream'},
        'call_id': 'fc_1',
        'name': 'web_search',
        'delta': '{"query":"OpenAI',
      });
      final secondArgsChunk = jsonEncode({
        'type': 'response.function_call_arguments.delta',
        'response': {'id': 'resp_stream'},
        'call_id': 'fc_1',
        'name': 'web_search',
        'delta': ' 最新发布"}',
      });
      final doneChunk = jsonEncode({
        'type': 'response.function_call_arguments.done',
        'response': {'id': 'resp_stream'},
        'call_id': 'fc_1',
        'name': 'web_search',
      });
      final response = http.StreamedResponse(
        Stream<List<int>>.fromIterable([
          utf8.encode('data: $addedChunk\n\n'),
          utf8.encode('data: $firstArgsChunk\n\n'),
          utf8.encode('data: $secondArgsChunk\n\n'),
          utf8.encode('data: $doneChunk\n\n'),
          utf8.encode('data: [DONE]\n'),
        ]),
        200,
      );

      final chunks =
          await parser.parsePlannerChunks(response, ApiStyle.responses).toList();

      expect(
        chunks.any(
          (chunk) =>
              chunk.type == StreamingPlannerChunkType.toolCallStarted &&
              chunk.providerCallId == 'fc_1' &&
              chunk.toolName == 'web_search',
        ),
        isTrue,
      );
      expect(
        chunks.where(
          (chunk) =>
              chunk.type == StreamingPlannerChunkType.toolCallArgumentsDelta &&
              chunk.providerCallId == 'fc_1',
        ),
        hasLength(2),
      );
      expect(
        chunks.any(
          (chunk) =>
              chunk.type == StreamingPlannerChunkType.toolCallCompleted &&
              chunk.providerCallId == 'fc_1',
        ),
        isTrue,
      );
      expect(
        chunks.last.type,
        StreamingPlannerChunkType.streamCompleted,
      );
    });
  });
}
