import 'dart:convert';

import 'package:ai_chat/models/llm/api_protocol_resolver.dart';
import 'package:ai_chat/models/llm/api_stream_parser.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

void main() {
  group('ApiStreamParser.parse', () {
    test('Responses reasoning item summary_text 会被解析为推理内容', () async {
      final parser = ApiStreamParser();
      final response = _buildStreamedResponse([
        'data: {"type":"response.output_item.added","item":{"type":"reasoning","summary":[{"type":"summary_text","text":"first"},{"type":"summary_text","text":" second"}]}}',
      ]);

      final chunks = await parser.parse(response, ApiStyle.responses).toList();

      expect(
        chunks,
        equals([
          jsonEncode({'type': 'reasoning', 'content': 'first'}),
          jsonEncode({'type': 'reasoning', 'content': ' second'}),
        ]),
      );
    });

    test('Responses reasoning item 只有 encrypted_content 时不会产出推理内容', () async {
      final parser = ApiStreamParser();
      final response = _buildStreamedResponse([
        'data: {"type":"response.output_item.added","item":{"type":"reasoning","encrypted_content":"secret","summary":[]}}',
      ]);

      final chunks = await parser.parse(response, ApiStyle.responses).toList();

      expect(chunks, isEmpty);
    });

    test('Responses 同一 reasoning item 在 added 和 done 中重复 summary 时只产出一次', () async {
      final parser = ApiStreamParser();
      final response = _buildStreamedResponse([
        'data: {"type":"response.output_item.added","item":{"id":"rs_1","type":"reasoning","summary":[{"type":"summary_text","text":"reasoning summary"}]}}',
        'data: {"type":"response.output_item.done","item":{"id":"rs_1","type":"reasoning","summary":[{"type":"summary_text","text":"reasoning summary"}]}}',
      ]);

      final chunks = await parser.parse(response, ApiStyle.responses).toList();

      expect(
        chunks,
        equals([
          jsonEncode({'type': 'reasoning', 'content': 'reasoning summary'}),
        ]),
      );
    });
  });
}

http.StreamedResponse _buildStreamedResponse(List<String> lines) {
  final bytes = lines.map((line) => utf8.encode('$line\n'));
  return http.StreamedResponse(Stream<List<int>>.fromIterable(bytes), 200);
}
