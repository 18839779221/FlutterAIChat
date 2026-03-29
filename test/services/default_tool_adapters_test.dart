import 'dart:convert';

import 'package:ai_chat/services/default_tool_adapters.dart';
import 'package:ai_chat/services/tool_executor.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('default tool adapters', () {
    test('webpage fetcher extracts readable text from html response', () async {
      final fetcher = buildDefaultWebpageFetcher(
        client: _FakeHttpClient(
          responses: {
            'https://example.com/article': http.Response(
              '''
              <html>
                <head>
                  <title>Example Article</title>
                  <style>.hidden { display:none; }</style>
                </head>
                <body>
                  <h1>Example Heading</h1>
                  <p>First paragraph.</p>
                  <script>console.log("skip");</script>
                  <p>Second paragraph.</p>
                </body>
              </html>
              ''',
              200,
              headers: {'content-type': 'text/html; charset=utf-8'},
            ),
          },
        ),
      );

      final result = await fetcher(url: 'https://example.com/article');

      expect(result.status, ToolExecutionStatus.success);
      expect(result.summary, '已读取网页：Example Article');
      expect(result.data['title'], 'Example Article');
      expect(result.data['content'], contains('Example Heading'));
      expect(result.data['content'], contains('First paragraph.'));
      expect(result.data['content'], isNot(contains('console.log')));
    });

    test('webpage fetcher returns failure for non-200 response', () async {
      final fetcher = buildDefaultWebpageFetcher(
        client: _FakeHttpClient(
          responses: {
            'https://example.com/missing': http.Response('missing', 404),
          },
        ),
      );

      final result = await fetcher(url: 'https://example.com/missing');

      expect(result.status, ToolExecutionStatus.failure);
      expect(result.errorMessage, 'http_404');
    });

    test('shared preferences note saver persists note records', () async {
      SharedPreferences.setMockInitialValues({});
      final preferences = await SharedPreferences.getInstance();
      final saver = buildSharedPreferencesNoteSaver(preferences);

      final first = await saver(
        title: 'ToolCall 设计',
        content: '第一版设计结论',
        folder: 'research',
      );
      final second = await saver(
        title: '后续动作',
        content: '继续补齐 tool adapter',
      );

      final stored = preferences.getStringList(kSavedNotesPreferenceKey);
      expect(first.status, ToolExecutionStatus.success);
      expect(second.status, ToolExecutionStatus.success);
      expect(stored, isNotNull);
      expect(stored, hasLength(2));

      final decoded = stored!
          .map((item) => jsonDecode(item) as Map<String, dynamic>)
          .toList();
      expect(decoded.first['title'], 'ToolCall 设计');
      expect(decoded.first['folder'], 'research');
      expect(decoded.last['title'], '后续动作');
    });
  });
}

class _FakeHttpClient extends http.BaseClient {
  _FakeHttpClient({required this.responses});

  final Map<String, http.Response> responses;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final response = responses[request.url.toString()] ??
        http.Response('not found', 404);
    return http.StreamedResponse(
      Stream.value(response.bodyBytes),
      response.statusCode,
      headers: response.headers,
      request: request,
    );
  }
}
