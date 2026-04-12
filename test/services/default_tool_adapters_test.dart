import 'dart:convert';

import 'package:ai_chat/services/default_tool_adapters.dart';
import 'package:ai_chat/services/tool_executor.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('default tool adapters', () {
    test('web search adapter maps tavily results into stable payload', () async {
      final searcher = buildTavilyWebSearcher(
        client: _FakeHttpClient(
          responses: {
            'https://api.tavily.com/search': http.Response(
              jsonEncode({
                'query': 'OpenAI 最新消息',
                'results': [
                  {
                    'title': 'OpenAI launches new feature',
                    'url': 'https://example.com/openai',
                    'content': 'Latest OpenAI update.',
                    'score': 0.92,
                    'published_date': '2026-04-12',
                  },
                ],
              }),
              200,
              headers: {'content-type': 'application/json'},
            ),
          },
        ),
      );

      final result = await searcher(
        query: 'OpenAI 最新消息',
        apiKey: 'tavily-key',
      );

      expect(result.status, ToolExecutionStatus.success);
      expect(result.summary, '已执行联网搜索');
      expect(result.data['provider'], 'tavily');
      expect(result.data['query'], 'OpenAI 最新消息');
      expect((result.data['results'] as List).single, {
        'title': 'OpenAI launches new feature',
        'url': 'https://example.com/openai',
        'snippet': 'Latest OpenAI update.',
        'source': 'example.com',
        'score': 0.92,
        'publishedDate': '2026-04-12',
      });
    });

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

    test('web search adapter returns failure when tavily api key is missing', () async {
      final searcher = buildTavilyWebSearcher(
        client: _FakeHttpClient(responses: const {}),
      );

      final result = await searcher(
        query: 'OpenAI 最新消息',
        apiKey: '',
      );

      expect(result.status, ToolExecutionStatus.failure);
      expect(result.errorMessage, 'missing_api_key');
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

    test('result sharer returns success when share sheet is invoked', () async {
      final sharer = buildDefaultResultSharer(
        shareInvoker: ({required text, subject}) async => const ShareAdapterResult(
          status: ShareAdapterStatus.success,
          raw: 'share-sheet-opened',
        ),
      );

      final result = await sharer(
        text: '这是一段要分享的内容',
        subject: '分享标题',
      );

      expect(result.status, ToolExecutionStatus.success);
      expect(result.summary, '已发起分享');
      expect(result.data['subject'], '分享标题');
      expect(result.data['shareStatus'], 'success');
    });

    test('result sharer maps plugin failure into stable tool result', () async {
      final sharer = buildDefaultResultSharer(
        shareInvoker: ({required text, subject}) async {
          throw Exception('share failed');
        },
      );

      final result = await sharer(text: '分享内容');

      expect(result.status, ToolExecutionStatus.failure);
      expect(result.summary, '分享结果失败');
      expect(result.errorMessage, 'share_failed');
    });

    test('reminder creator returns success when host intent is launched', () async {
      final creator = buildDefaultReminderCreator(
        launchIntent: (request) async {
          expect(request.action, 'create_reminder');
          expect(request.arguments['title'], '交周报');
          expect(request.arguments['dueAt'], '2026-03-31T20:00:00+08:00');
          return const HostIntentResult(
            status: HostIntentStatus.launched,
            message: 'reminder-intent-opened',
          );
        },
      );

      final result = await creator(
        title: '交周报',
        dueAt: '2026-03-31T20:00:00+08:00',
        note: '提前十分钟',
      );

      expect(result.status, ToolExecutionStatus.success);
      expect(result.summary, '已发起提醒创建：交周报');
      expect(result.data['launchStatus'], 'launched');
    });

    test('calendar event creator returns success when host intent is launched', () async {
      final creator = buildDefaultCalendarEventCreator(
        launchIntent: (request) async {
          expect(request.action, 'create_calendar_event');
          expect(request.arguments['title'], '项目评审');
          expect(request.arguments['startAt'], '2026-03-31T15:00:00+08:00');
          return const HostIntentResult(
            status: HostIntentStatus.launched,
            message: 'calendar-intent-opened',
          );
        },
      );

      final result = await creator(
        title: '项目评审',
        startAt: '2026-03-31T15:00:00+08:00',
        endAt: '2026-03-31T16:00:00+08:00',
        location: '会议室 A',
        notes: '带上周报',
      );

      expect(result.status, ToolExecutionStatus.success);
      expect(result.summary, '已发起日历事件创建：项目评审');
      expect(result.data['launchStatus'], 'launched');
    });

    test('host intent failure falls back to clipboard for reminder', () async {
      final creator = buildDefaultReminderCreator(
        launchIntent: (request) async => const HostIntentResult(
          status: HostIntentStatus.unavailable,
          message: 'intent-unavailable',
        ),
        clipboardWriter: (text) async {},
      );

      final result = await creator(
        title: '交周报',
        dueAt: '2026-03-31T20:00:00+08:00',
      );

      expect(result.status, ToolExecutionStatus.success);
      expect(result.summary, '宿主提醒不可用，已复制提醒信息：交周报');
      expect(result.data['launchMode'], 'clipboard_fallback');
    });

    test('reminder creator falls back to clipboard instructions when host is unavailable',
        () async {
      String? copiedText;
      final creator = buildDefaultReminderCreator(
        launchIntent: (request) async => const HostIntentResult(
          status: HostIntentStatus.unavailable,
          message: 'activity_not_resolved',
        ),
        clipboardWriter: (text) async {
          copiedText = text;
        },
      );

      final result = await creator(
        title: '交周报',
        dueAt: '2026-03-31T20:00:00+08:00',
        note: '提前十分钟',
      );

      expect(result.status, ToolExecutionStatus.success);
      expect(result.summary, '宿主提醒不可用，已复制提醒信息：交周报');
      expect(result.data['launchMode'], 'clipboard_fallback');
      expect(result.data['fallbackAction'], 'clipboard');
      expect(copiedText, contains('交周报'));
      expect(copiedText, contains('2026-03-31 20:00 GMT+08:00'));
    });

    test('reminder creator reports calendar fallback launch explicitly', () async {
      final creator = buildDefaultReminderCreator(
        launchIntent: (request) async => const HostIntentResult(
          status: HostIntentStatus.launched,
          message: 'calendar_fallback_launched',
        ),
      );

      final result = await creator(
        title: '交周报',
        dueAt: '2026-03-31T20:00:00+08:00',
      );

      expect(result.status, ToolExecutionStatus.success);
      expect(result.summary, '已改为日历事件创建：交周报');
      expect(result.data['launchMode'], 'calendar_fallback');
    });

    test('reminder creator keeps local hour and minutes from iso dueAt', () async {
      late HostIntentRequest capturedRequest;
      final creator = buildDefaultReminderCreator(
        launchIntent: (request) async {
          capturedRequest = request;
          return const HostIntentResult(
            status: HostIntentStatus.launched,
            message: 'intent_launched',
          );
        },
      );

      final result = await creator(
        title: '交周报',
        dueAt: '2026-03-31T20:00:00+08:00',
      );

      expect(result.status, ToolExecutionStatus.success);
      expect(capturedRequest.arguments['hour'], 20);
      expect(capturedRequest.arguments['minutes'], 0);
    });

    test('reminder creator rejects non-iso dueAt text', () async {
      final creator = buildDefaultReminderCreator(
        launchIntent: (request) async => throw UnimplementedError(),
      );

      final result = await creator(
        title: 'submit weekly report',
        dueAt: 'today at 8pm',
      );

      expect(result.status, ToolExecutionStatus.failure);
      expect(result.errorMessage, 'missing_due_at');
    });

    test('calendar creator rejects non-iso startAt text', () async {
      final creator = buildDefaultCalendarEventCreator(
        launchIntent: (request) async => throw UnimplementedError(),
      );

      final result = await creator(
        title: 'project review',
        startAt: 'tomorrow at 3pm',
      );

      expect(result.status, ToolExecutionStatus.failure);
      expect(result.errorMessage, 'invalid_start_at');
    });

    test('calendar creator falls back to clipboard instructions when host is unavailable',
        () async {
      String? copiedText;
      final creator = buildDefaultCalendarEventCreator(
        launchIntent: (request) async => const HostIntentResult(
          status: HostIntentStatus.unavailable,
          message: 'activity_not_resolved',
        ),
        clipboardWriter: (text) async {
          copiedText = text;
        },
      );

      final result = await creator(
        title: '项目评审',
        startAt: '2026-04-01T15:00:00+08:00',
        endAt: '2026-04-01T16:30:00+08:00',
        location: '会议室 A',
        notes: '带上周报',
      );

      expect(result.status, ToolExecutionStatus.success);
      expect(result.summary, '宿主日历不可用，已复制事件信息：项目评审');
      expect(result.data['launchMode'], 'clipboard_fallback');
      expect(result.data['fallbackAction'], 'clipboard');
      expect(copiedText, contains('项目评审'));
      expect(copiedText, contains('2026-04-01 15:00 GMT+08:00'));
      expect(copiedText, contains('会议室 A'));
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
