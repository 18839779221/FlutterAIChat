import 'dart:convert';

import 'package:ai_chat/services/default_tool_adapters.dart';
import 'package:ai_chat/services/chat_service.dart';
import 'package:ai_chat/services/tool_executor.dart';
import 'package:ai_chat/models/agent/model_turn_decision.dart';
import 'package:ai_chat/models/agent/planner_tool_option.dart';
import 'package:ai_chat/models/chat_message.dart';
import 'package:ai_chat/models/chat_turn.dart';
import 'package:ai_chat/models/context/planner_context_carrier.dart';
import 'package:ai_chat/models/llm/base_llm.dart';
import 'package:ai_chat/models/llm/llm_config.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

void main() {
  group('default tool adapters', () {
    test('web search adapter maps tavily results into stable payload',
        () async {
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

      final result = await fetcher(
        groupId: 1,
        url: 'https://example.com/article',
        prompt: '提取页面核心内容',
      );

      expect(result.status, ToolExecutionStatus.success);
      expect(result.summary, '已返回网页处理结果');
      expect(result.data['title'], 'Example Article');
      expect(result.data['prompt'], '提取页面核心内容');
      expect(result.data['processedContent'], contains('Example Heading'));
      expect(result.data['processedContent'], contains('First paragraph.'));
      expect(
        result.data['processedContent'],
        isNot(contains('console.log')),
      );
    });

    test('webpage fetcher returns failure for non-200 response', () async {
      final fetcher = buildDefaultWebpageFetcher(
        client: _FakeHttpClient(
          responses: {
            'https://example.com/missing': http.Response('missing', 404),
          },
        ),
      );

      final result = await fetcher(
        groupId: 1,
        url: 'https://example.com/missing',
        prompt: '提取页面核心内容',
      );

      expect(result.status, ToolExecutionStatus.failure);
      expect(result.errorMessage, 'http_404');
    });

    test('webpage fetcher uses side runtime override when llm supports it',
        () async {
      final llm = _CapturingRuntimeConfigurableLlm();
      final fetcher = buildDefaultWebpageFetcher(
        client: _FakeHttpClient(
          responses: {
            'https://example.com/article': http.Response(
              '<html><body><p>Example page body.</p></body></html>',
              200,
              headers: {'content-type': 'text/html; charset=utf-8'},
            ),
          },
        ),
        sideModelLlm: llm,
      );

      final result = await fetcher(
        groupId: 42,
        url: 'https://example.com/article',
        prompt: '提取核心内容',
        sideRuntimeConfigOverride: const LLMConfig(
          apiKey: 'side-key',
          apiUrl: 'https://side.example/v1/messages',
          model: 'side-model',
        ),
      );

      expect(result.status, ToolExecutionStatus.success);
      expect(llm.capturedConfig, isNotNull);
      expect(
        llm.capturedConfig!.sideRuntimeConfigOverride?.apiUrl,
        'https://side.example/v1/messages',
      );
      expect(
        llm.capturedConfig!.sideRuntimeConfigOverride?.model,
        'side-model',
      );
    });

    test('web search adapter returns failure when tavily api key is missing',
        () async {
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

    group('image generator', () {
      test('posts to images generations endpoint and maps b64 response',
          () async {
        final client = _FakeHttpClient(
          responses: {
            'https://api.openai.com/v1/images/generations': http.Response(
              jsonEncode({
                'data': [
                  {'b64_json': 'AAAA'},
                ],
              }),
              200,
              headers: {'content-type': 'application/json'},
            ),
          },
        );
        final generator = buildOpenAIImageGenerator(client: client);

        final result = await generator(
          prompt: 'A small brass robot painting clouds',
          model: 'gpt-image-2',
          size: '1024x1024',
          quality: 'high',
          apiKey: 'key-1',
          baseUrl: 'https://api.openai.com/v1/chat/completions',
        );

        expect(result.status, ToolExecutionStatus.success);
        expect(result.summary, '已生成图片');
        expect(client.requests.single.url.toString(),
            'https://api.openai.com/v1/images/generations');
        expect(client.requests.single.headers['Authorization'], 'Bearer key-1');
        expect(client.singleJsonBody, {
          'model': 'gpt-image-2',
          'prompt': 'A small brass robot painting clouds',
          'size': '1024x1024',
          'quality': 'high',
        });
        final images = result.data['generatedImages'] as List;
        expect(images.single['dataUrl'], 'data:image/png;base64,AAAA');
        expect(images.single['mimeType'], 'image/png');
      });

      test('uses low quality and default image model when omitted', () async {
        final client = _FakeHttpClient(
          responses: {
            'https://api.openai.com/v1/images/generations': http.Response(
              jsonEncode({
                'data': [
                  {'b64_json': 'AAAA'},
                ],
              }),
              200,
              headers: {'content-type': 'application/json'},
            ),
          },
        );
        final generator = buildOpenAIImageGenerator(client: client);

        final result = await generator(
          prompt: 'A small brass robot painting clouds',
          model: null,
          size: '1024x1024',
          quality: null,
          apiKey: 'key-1',
          baseUrl: 'https://api.openai.com/v1',
        );

        expect(result.status, ToolExecutionStatus.success);
        expect(client.singleJsonBody['model'], 'gpt-image-2');
        expect(client.singleJsonBody['quality'], 'low');
        expect(result.data['model'], 'gpt-image-2');
        expect(result.data['quality'], 'low');
      });

      test('returns stable failure when image api key is missing', () async {
        final generator = buildOpenAIImageGenerator(
          client: _FakeHttpClient(responses: const {}),
        );

        final result = await generator(
          prompt: 'A calendar cover',
          model: 'gpt-image-2',
          size: '1024x1024',
          quality: 'auto',
          apiKey: '',
          baseUrl: 'https://api.openai.com/v1',
        );

        expect(result.status, ToolExecutionStatus.failure);
        expect(result.errorMessage, 'missing_api_key');
      });
    });

    test('result sharer returns success when share sheet is invoked', () async {
      final sharer = buildDefaultResultSharer(
        shareInvoker: ({required text, subject}) async =>
            const ShareAdapterResult(
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

    test('reminder creator returns success when host intent is launched',
        () async {
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

    test('calendar event creator returns success when host intent is launched',
        () async {
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

    test(
        'reminder creator falls back to clipboard instructions when host is unavailable',
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

    test('reminder creator reports calendar fallback launch explicitly',
        () async {
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

    test('reminder creator keeps local hour and minutes from iso dueAt',
        () async {
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

    test(
        'calendar creator falls back to clipboard instructions when host is unavailable',
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

class _CapturingRuntimeConfigurableLlm
    implements BaseLLM, RuntimeConfigurableBaseLlm {
  ChatConfig? capturedConfig;

  @override
  Map<String, dynamic> get config => const {};

  @override
  String getModelName(ChatConfig config) => 'test-model';

  @override
  Future<String> processWebpageContent({
    required String webpageContent,
    required String prompt,
  }) async {
    return 'legacy';
  }

  @override
  Future<String> processWebpageContentWithConfig({
    required String webpageContent,
    required String prompt,
    required ChatConfig config,
  }) async {
    capturedConfig = config;
    return 'processed with side runtime';
  }

  @override
  Future<String> summarizeConversation(List<ChatMessage> messages) async {
    return 'summary';
  }

  @override
  Future<String> summarizeConversationWithConfig(
    List<ChatMessage> messages, {
    required ChatConfig config,
  }) async {
    return 'summary';
  }

  @override
  Future<ModelTurnDecision?> planTurnDecision({
    required List<PlannerContextCarrier> carriers,
    required ChatTurnProviderStyle activeApiStyle,
    required bool currentTurnRunning,
    required ChatConfig config,
    required List<PlannerToolOption> availableTools,
    void Function(LlmRetryProgress progress)? onRetryScheduled,
  }) async =>
      null;
}

class _FakeHttpClient extends http.BaseClient {
  _FakeHttpClient({required this.responses});

  final Map<String, http.Response> responses;
  final List<http.Request> requests = <http.Request>[];

  Map<String, dynamic> get singleJsonBody {
    expect(requests, hasLength(1));
    return jsonDecode(requests.single.body) as Map<String, dynamic>;
  }

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    if (request is http.Request) {
      requests.add(request);
    }
    final response =
        responses[request.url.toString()] ?? http.Response('not found', 404);
    return http.StreamedResponse(
      Stream.value(response.bodyBytes),
      response.statusCode,
      headers: response.headers,
      request: request,
    );
  }
}
