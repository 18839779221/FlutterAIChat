import 'dart:convert';

import 'package:ai_chat/models/llm/api_protocol_resolver.dart';
import 'package:ai_chat/models/llm/api_stream_parser.dart';
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
  });
}
