import 'dart:convert';

import '../models/llm/base_llm.dart';
import '../models/llm/llm_config.dart';
import 'chat_service.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:share_plus/share_plus.dart';

import 'tool_executor.dart';
import '../utils/logger.dart';

const MethodChannel _hostToolsChannel = MethodChannel('ai_chat/host_tools');
const String _hostToolsTag = 'DefaultToolAdapters';

/// Low-level share adapter status used to normalize plugin output.
enum ShareAdapterStatus {
  success,
  dismissed,
  unavailable,
}

/// Raw result returned by the platform sharing adapter before conversion into
/// the user-facing tool result payload.
class ShareAdapterResult {
  /// Normalized share outcome for UI/state handling.
  final ShareAdapterStatus status;

  /// Optional raw platform/plugin value for debugging or analytics.
  final String? raw;

  const ShareAdapterResult({
    required this.status,
    this.raw,
  });
}

/// Host-level callback that performs the actual share-sheet invocation.
typedef ShareInvoker = Future<ShareAdapterResult> Function({
  required String text,
  String? subject,
});

/// Result status returned by the host intent bridge.
enum HostIntentStatus {
  launched,
  unavailable,
  failed,
}

/// Structured host intent request.
class HostIntentRequest {
  /// Logical action name consumed by the native bridge.
  final String action;

  /// Argument payload sent to the host platform.
  final Map<String, dynamic> arguments;

  const HostIntentRequest({
    required this.action,
    required this.arguments,
  });
}

/// Structured host intent response normalized for the adapter layer.
class HostIntentResult {
  /// Whether the host platform successfully launched the target intent.
  final HostIntentStatus status;

  /// Optional diagnostic message returned by the host.
  final String? message;

  const HostIntentResult({
    required this.status,
    this.message,
  });
}

/// Callback that asks the host platform to launch a native intent-like action.
typedef HostIntentLauncher = Future<HostIntentResult> Function(
  HostIntentRequest request,
);

/// Writes fallback instructions into the system clipboard.
typedef ClipboardWriter = Future<void> Function(String text);

/// Provider-level web search adapter that still allows runtime credential
/// injection from app settings.
typedef ProviderWebSearcher = Future<ToolResult> Function({
  required String query,
  String? apiKey,
  String? baseUrl,
  int? maxResults,
});

/// Builds an OpenAI-compatible image generation adapter.
ImageGenerator buildOpenAIImageGenerator({
  http.Client? client,
}) {
  final resolvedClient = client ?? http.Client();

  return ({
    required String prompt,
    required String? model,
    required String size,
    required String? quality,
    String? apiKey,
    String? baseUrl,
  }) async {
    final normalizedApiKey = apiKey?.trim() ?? '';
    if (normalizedApiKey.isEmpty) {
      return const ToolResult(
        toolName: 'generate_image',
        status: ToolExecutionStatus.failure,
        summary: '生成图片失败',
        data: {'reason': 'missing_api_key'},
        errorMessage: 'missing_api_key',
      );
    }

    final resolvedModel =
        (model == null || model.trim().isEmpty) ? 'gpt-image-2' : model.trim();
    final resolvedQuality =
        (quality == null || quality.trim().isEmpty) ? 'low' : quality.trim();

    final endpoint = _resolveOpenAIImagesEndpoint(baseUrl);
    if (endpoint == null) {
      return const ToolResult(
        toolName: 'generate_image',
        status: ToolExecutionStatus.failure,
        summary: '生成图片失败',
        data: {'reason': 'invalid_base_url'},
        errorMessage: 'invalid_base_url',
      );
    }

    try {
      final response = await resolvedClient.post(
        endpoint,
        headers: {
          'Authorization': 'Bearer $normalizedApiKey',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'model': resolvedModel,
          'prompt': prompt,
          'size': size,
          'quality': resolvedQuality,
        }),
      );

      if (response.statusCode < 200 || response.statusCode >= 300) {
        return ToolResult(
          toolName: 'generate_image',
          status: ToolExecutionStatus.failure,
          summary: '生成图片失败',
          data: {
            'reason': 'http_${response.statusCode}',
            'statusCode': response.statusCode,
          },
          errorMessage: 'http_${response.statusCode}',
        );
      }

      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic>) {
        return const ToolResult(
          toolName: 'generate_image',
          status: ToolExecutionStatus.failure,
          summary: '生成图片失败',
          data: {'reason': 'invalid_response'},
          errorMessage: 'invalid_response',
        );
      }

      final rawData = decoded['data'];
      final images = <Map<String, dynamic>>[];
      if (rawData is List) {
        for (var i = 0; i < rawData.length; i++) {
          final item = rawData[i];
          if (item is! Map) {
            continue;
          }
          final map = Map<String, dynamic>.from(item);
          final b64 = map['b64_json'];
          if (b64 is! String || b64.trim().isEmpty) {
            continue;
          }
          final fileName = 'generated-image-${i + 1}.png';
          images.add({
            'localId':
                'generated-image-${DateTime.now().microsecondsSinceEpoch}-$i',
            'fileName': fileName,
            'mimeType': 'image/png',
            'dataUrl': 'data:image/png;base64,${b64.trim()}',
            if (map['revised_prompt'] is String)
              'revisedPrompt': (map['revised_prompt'] as String).trim(),
          });
        }
      }

      if (images.isEmpty) {
        return const ToolResult(
          toolName: 'generate_image',
          status: ToolExecutionStatus.failure,
          summary: '生成图片失败',
          data: {'reason': 'missing_image_data'},
          errorMessage: 'missing_image_data',
        );
      }

      return ToolResult(
        toolName: 'generate_image',
        status: ToolExecutionStatus.success,
        summary: '已生成图片',
        data: {
          'prompt': prompt,
          'model': resolvedModel,
          'size': size,
          'quality': resolvedQuality,
          'generatedImages': images,
        },
      );
    } catch (_) {
      return const ToolResult(
        toolName: 'generate_image',
        status: ToolExecutionStatus.failure,
        summary: '生成图片失败',
        data: {'reason': 'network_error'},
        errorMessage: 'network_error',
      );
    }
  };
}

/// Builds a Tavily-backed web search adapter.
///
/// Returned payload fields:
/// - `query`: normalized search query
/// - `provider`: concrete provider name, currently always `tavily`
/// - `results`: stable result list for downstream tool cards and prompts
///   - `title`: search result title
///   - `url`: canonical webpage url
///   - `snippet`: provider summary/excerpt mapped from Tavily `content`
///   - `source`: host extracted from `url`
///   - `score`: optional Tavily ranking score
///   - `publishedDate`: optional provider publication date
ProviderWebSearcher buildTavilyWebSearcher({
  http.Client? client,
}) {
  final resolvedClient = client ?? http.Client();

  return ({
    required String query,
    String? apiKey,
    String? baseUrl,
    int? maxResults,
  }) async {
    final normalizedApiKey = apiKey?.trim() ?? '';
    if (normalizedApiKey.isEmpty) {
      return const ToolResult(
        toolName: 'web_search',
        status: ToolExecutionStatus.failure,
        summary: '联网搜索失败',
        data: {
          'reason': 'missing_api_key',
        },
        errorMessage: 'missing_api_key',
      );
    }

    final endpoint = (baseUrl?.trim().isNotEmpty ?? false)
        ? baseUrl!.trim()
        : 'https://api.tavily.com/search';

    try {
      final response = await resolvedClient.post(
        Uri.parse(endpoint),
        headers: const {
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'query': query,
          'api_key': normalizedApiKey,
          'max_results': maxResults ?? 5,
        }),
      );

      if (response.statusCode < 200 || response.statusCode >= 300) {
        return ToolResult(
          toolName: 'web_search',
          status: ToolExecutionStatus.failure,
          summary: '联网搜索失败',
          data: {
            'query': query,
            'provider': 'tavily',
            'reason': 'http_${response.statusCode}',
          },
          errorMessage: 'http_${response.statusCode}',
        );
      }

      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic>) {
        return ToolResult(
          toolName: 'web_search',
          status: ToolExecutionStatus.failure,
          summary: '联网搜索失败',
          data: {
            'query': query,
            'provider': 'tavily',
            'reason': 'invalid_response',
          },
          errorMessage: 'invalid_response',
        );
      }

      final rawResults = decoded['results'];
      final results = rawResults is List
          ? rawResults
              .whereType<Map>()
              .map(
                (item) => _mapTavilySearchResult(
                  Map<String, dynamic>.from(item),
                ),
              )
              .toList()
          : <Map<String, dynamic>>[];

      return ToolResult(
        toolName: 'web_search',
        status: ToolExecutionStatus.success,
        summary: '已执行联网搜索',
        data: {
          'query': decoded['query'] is String &&
                  (decoded['query'] as String).trim().isNotEmpty
              ? (decoded['query'] as String).trim()
              : query,
          'provider': 'tavily',
          'results': results,
        },
      );
    } catch (_) {
      return ToolResult(
        toolName: 'web_search',
        status: ToolExecutionStatus.failure,
        summary: '联网搜索失败',
        data: {
          'query': query,
          'provider': 'tavily',
          'reason': 'network_error',
        },
        errorMessage: 'network_error',
      );
    }
  };
}

Uri? _resolveOpenAIImagesEndpoint(String? baseUrl) {
  final normalized = (baseUrl?.trim().isNotEmpty ?? false)
      ? baseUrl!.trim()
      : 'https://api.openai.com/v1';
  final uri = Uri.tryParse(normalized);
  if (uri == null || !uri.hasScheme || uri.host.isEmpty) {
    return null;
  }

  final segments =
      uri.pathSegments.where((segment) => segment.isNotEmpty).toList();
  final versionIndex = segments.indexOf('v1');
  final baseSegments = versionIndex >= 0
      ? segments.take(versionIndex + 1).toList()
      : <String>[...segments, 'v1'];
  return uri.replace(
    pathSegments: [
      ...baseSegments,
      'images',
      'generations',
    ],
    query: null,
    fragment: null,
  );
}

/// Builds the default webpage fetch adapter used by the mobile tool pipeline.
///
/// Returned payload fields:
/// - `url`: requested webpage address
/// - `host`: host extracted from the requested url
/// - `prompt`: prompt used to process the page
/// - `processedContent`: side-model output derived from readable text
/// - `resultPreview`: compact preview derived from processed output
/// - `rawExcerpt`: truncated readable text kept as evidence
/// - `finalUrl`: final address used for this fetch
WebpageFetcher buildDefaultWebpageFetcher({
  http.Client? client,
  BaseLLM? sideModelLlm,
}) {
  final resolvedClient = client ?? http.Client();

  return ({
    required int groupId,
    required String url,
    required String prompt,
    LLMConfig? sideRuntimeConfigOverride,
  }) async {
    try {
      final requestUri = Uri.parse(url);
      final response = await resolvedClient.get(requestUri);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        final reason = 'http_${response.statusCode}';
        return ToolResult(
          toolName: 'fetch_webpage',
          status: ToolExecutionStatus.failure,
          summary: '读取失败：$reason',
          data: {
            'url': url,
            'host': requestUri.host,
            'prompt': prompt,
            'failureReason': reason,
            'finalUrl': url,
          },
          errorMessage: reason,
        );
      }

      final content = _extractReadableText(response.body);
      if (content.isEmpty) {
        return ToolResult(
          toolName: 'fetch_webpage',
          status: ToolExecutionStatus.failure,
          summary: '读取失败：empty_content',
          data: {
            'url': url,
            'host': requestUri.host,
            'prompt': prompt,
            'failureReason': 'empty_content',
            'finalUrl': url,
          },
          errorMessage: 'empty_content',
        );
      }

      final processedContent = await _processFetchedWebpageContentWithSideModel(
        sideModelLlm: sideModelLlm,
        prompt: prompt,
        content: content,
        sideRuntimeConfigOverride: sideRuntimeConfigOverride,
      );
      final normalizedProcessedContent = processedContent.trim().isEmpty
          ? content.trim()
          : processedContent.trim();
      final extractedTitle = _extractHtmlTitle(response.body);

      return ToolResult(
        toolName: 'fetch_webpage',
        status: ToolExecutionStatus.success,
        summary: '已返回网页处理结果',
        data: {
          'url': url,
          'host': requestUri.host,
          'prompt': prompt,
          'processedContent': normalizedProcessedContent,
          'resultPreview': _buildResultPreview(normalizedProcessedContent),
          'rawExcerpt': _buildRawExcerpt(content),
          'finalUrl': url,
          'message': _buildFetchWebpageContextText(
            url: url,
            prompt: prompt,
            processedContent: normalizedProcessedContent,
          ),
          if (extractedTitle != null && extractedTitle.trim().isNotEmpty)
            'title': extractedTitle.trim(),
        },
      );
    } catch (error) {
      return ToolResult(
        toolName: 'fetch_webpage',
        status: ToolExecutionStatus.failure,
        summary: '读取失败：network_error',
        data: {
          'url': url,
          'host': Uri.tryParse(url)?.host ?? '',
          'prompt': prompt,
          'failureReason': 'network_error',
          'finalUrl': url,
        },
        errorMessage: 'network_error',
      );
    }
  };
}

Future<String> _processFetchedWebpageContentWithSideModel({
  required BaseLLM? sideModelLlm,
  required String prompt,
  required String content,
  LLMConfig? sideRuntimeConfigOverride,
}) async {
  final llm = sideModelLlm;
  if (llm == null) {
    return content;
  }
  try {
    if (llm is RuntimeConfigurableBaseLlm) {
      return await (llm as RuntimeConfigurableBaseLlm)
          .processWebpageContentWithConfig(
        webpageContent: _truncateForSideModel(content),
        prompt: prompt,
        config: ChatConfig(
          systemPrompt: '',
          sideRuntimeConfigOverride: sideRuntimeConfigOverride,
        ),
      );
    }
    return await llm.processWebpageContent(
      webpageContent: _truncateForSideModel(content),
      prompt: prompt,
    );
  } catch (error) {
    Logger.w(_hostToolsTag, '网页 side model 处理失败，回退原始正文: $error');
    return content;
  }
}

String _truncateForSideModel(String content, {int maxLength = 12000}) {
  final normalized = content.trim();
  if (normalized.length <= maxLength) {
    return normalized;
  }
  return normalized.substring(0, maxLength);
}

String _buildResultPreview(String content, {int maxLength = 160}) {
  final normalized = content.replaceAll(RegExp(r'\s+'), ' ').trim();
  if (normalized.length <= maxLength) {
    return normalized;
  }
  return '${normalized.substring(0, maxLength)}...';
}

String _buildRawExcerpt(String content, {int maxLength = 320}) {
  final normalized = content.replaceAll(RegExp(r'\s+'), ' ').trim();
  if (normalized.length <= maxLength) {
    return normalized;
  }
  return '${normalized.substring(0, maxLength)}...';
}

String _buildFetchWebpageContextText({
  required String url,
  required String prompt,
  required String processedContent,
}) {
  return [
    '以下是工具 `fetch_webpage` 的执行结果，请结合这些信息回答用户。',
    '网页链接：$url',
    '处理目标：$prompt',
    '处理结果：${_buildRawExcerpt(processedContent, maxLength: 1200)}',
  ].join('\n');
}

/// Builds the default share adapter backed by `share_plus`.
///
/// Returned payload fields:
/// - `text`: shared body text
/// - `subject`: optional share title/subject
/// - `shareStatus`: normalized platform share result
/// - `rawStatus`: optional raw plugin response
ResultSharer buildDefaultResultSharer({
  ShareInvoker? shareInvoker,
}) {
  final resolvedInvoker = shareInvoker ?? _defaultShareInvoker;

  return ({
    required String text,
    String? subject,
  }) async {
    try {
      final result = await resolvedInvoker(text: text, subject: subject);
      final isSuccess = result.status == ShareAdapterStatus.success ||
          result.status == ShareAdapterStatus.dismissed;
      return ToolResult(
        toolName: 'share_result',
        status: isSuccess
            ? ToolExecutionStatus.success
            : ToolExecutionStatus.failure,
        summary: isSuccess ? '已发起分享' : '分享结果失败',
        data: {
          'text': text,
          'subject': subject,
          'shareStatus': result.status.name,
          if (result.raw != null) 'rawStatus': result.raw,
        },
        errorMessage: isSuccess ? null : 'share_unavailable',
      );
    } catch (_) {
      return ToolResult(
        toolName: 'share_result',
        status: ToolExecutionStatus.failure,
        summary: '分享结果失败',
        data: {
          'text': text,
          'subject': subject,
          'reason': 'share_failed',
        },
        errorMessage: 'share_failed',
      );
    }
  };
}

/// Builds the default reminder creator backed by a host intent bridge.
///
/// Returned payload fields:
/// - `title`: reminder title
/// - `dueAt`: original ISO8601 reminder time
/// - `note`: optional note body
/// - `launchStatus`: normalized host launch result
ReminderCreator buildDefaultReminderCreator({
  HostIntentLauncher? launchIntent,
  ClipboardWriter? clipboardWriter,
}) {
  final resolvedLauncher = launchIntent ?? _defaultHostIntentLauncher;
  final resolvedClipboardWriter = clipboardWriter ?? _defaultClipboardWriter;

  return ({
    required String title,
    String? dueAt,
    String? note,
  }) async {
    final parsedDueAt = dueAt == null ? null : DateTime.tryParse(dueAt);
    final reminderTime = dueAt == null ? null : _extractClockTime(dueAt);
    if (parsedDueAt == null) {
      return ToolResult(
        toolName: 'create_reminder',
        status: ToolExecutionStatus.failure,
        summary: '创建提醒失败',
        data: {
          'title': title,
          'dueAt': dueAt,
          'reason': 'missing_due_at',
        },
        errorMessage: 'missing_due_at',
      );
    }

    final result = await resolvedLauncher(
      HostIntentRequest(
        action: 'create_reminder',
        arguments: {
          'title': title,
          'dueAt': dueAt,
          'note': note,
          'hour': reminderTime?.hour ?? parsedDueAt.hour,
          'minutes': reminderTime?.minutes ?? parsedDueAt.minute,
        },
      ),
    );

    final launchMode = result.message == 'calendar_fallback_launched'
        ? 'calendar_fallback'
        : 'alarm';
    if (result.status != HostIntentStatus.launched) {
      final fallbackText = _buildReminderFallbackText(
        title: title,
        dueAt: dueAt!,
        note: note,
      );
      await resolvedClipboardWriter(fallbackText);
      return ToolResult(
        toolName: 'create_reminder',
        status: ToolExecutionStatus.success,
        summary: '宿主提醒不可用，已复制提醒信息：$title',
        data: {
          'title': title,
          'dueAt': dueAt,
          'note': note,
          'launchStatus': result.status.name,
          'launchMode': 'clipboard_fallback',
          'fallbackAction': 'clipboard',
          'fallbackText': fallbackText,
          if (result.message != null) 'hostMessage': result.message,
        },
      );
    }

    return ToolResult(
      toolName: 'create_reminder',
      status: ToolExecutionStatus.success,
      summary: launchMode == 'calendar_fallback'
          ? '已改为日历事件创建：$title'
          : '已发起提醒创建：$title',
      data: {
        'title': title,
        'dueAt': dueAt,
        'note': note,
        'launchStatus': result.status.name,
        'launchMode': launchMode,
        if (result.message != null) 'hostMessage': result.message,
      },
    );
  };
}

/// Builds the default calendar event creator backed by a host intent bridge.
///
/// Returned payload fields:
/// - `title`: event title
/// - `startAt`: ISO8601 event start time
/// - `endAt`: ISO8601 event end time
/// - `location`: optional location
/// - `notes`: optional event notes
/// - `launchStatus`: normalized host launch result
CalendarEventCreator buildDefaultCalendarEventCreator({
  HostIntentLauncher? launchIntent,
  ClipboardWriter? clipboardWriter,
}) {
  final resolvedLauncher = launchIntent ?? _defaultHostIntentLauncher;
  final resolvedClipboardWriter = clipboardWriter ?? _defaultClipboardWriter;

  return ({
    required String title,
    required String startAt,
    String? endAt,
    String? location,
    String? notes,
  }) async {
    final parsedStartAt = DateTime.tryParse(startAt);
    if (parsedStartAt == null) {
      return ToolResult(
        toolName: 'create_calendar_event',
        status: ToolExecutionStatus.failure,
        summary: '创建日历事件失败',
        data: {
          'title': title,
          'startAt': startAt,
          'reason': 'invalid_start_at',
        },
        errorMessage: 'invalid_start_at',
      );
    }

    final parsedEndAt = endAt == null
        ? parsedStartAt.add(const Duration(hours: 1))
        : DateTime.tryParse(endAt);
    if (parsedEndAt == null) {
      return ToolResult(
        toolName: 'create_calendar_event',
        status: ToolExecutionStatus.failure,
        summary: '创建日历事件失败',
        data: {
          'title': title,
          'startAt': startAt,
          'endAt': endAt,
          'reason': 'invalid_end_at',
        },
        errorMessage: 'invalid_end_at',
      );
    }

    final result = await resolvedLauncher(
      HostIntentRequest(
        action: 'create_calendar_event',
        arguments: {
          'title': title,
          'startAt': startAt,
          'endAt': parsedEndAt.toIso8601String(),
          'location': location,
          'notes': notes,
          'beginTimeMillis': parsedStartAt.millisecondsSinceEpoch,
          'endTimeMillis': parsedEndAt.millisecondsSinceEpoch,
        },
      ),
    );

    if (result.status != HostIntentStatus.launched) {
      final fallbackText = _buildCalendarEventFallbackText(
        title: title,
        startAt: startAt,
        endAt: parsedEndAt.toIso8601String(),
        location: location,
        notes: notes,
      );
      await resolvedClipboardWriter(fallbackText);
      return ToolResult(
        toolName: 'create_calendar_event',
        status: ToolExecutionStatus.success,
        summary: '宿主日历不可用，已复制事件信息：$title',
        data: {
          'title': title,
          'startAt': startAt,
          'endAt': parsedEndAt.toIso8601String(),
          'location': location,
          'notes': notes,
          'launchStatus': result.status.name,
          'launchMode': 'clipboard_fallback',
          'fallbackAction': 'clipboard',
          'fallbackText': fallbackText,
          if (result.message != null) 'hostMessage': result.message,
        },
      );
    }

    return ToolResult(
      toolName: 'create_calendar_event',
      status: ToolExecutionStatus.success,
      summary: '已发起日历事件创建：$title',
      data: {
        'title': title,
        'startAt': startAt,
        'endAt': parsedEndAt.toIso8601String(),
        'location': location,
        'notes': notes,
        'launchStatus': result.status.name,
        if (result.message != null) 'hostMessage': result.message,
      },
    );
  };
}

String? _extractHtmlTitle(String html) {
  final match = RegExp(
    r'<title[^>]*>(.*?)</title>',
    caseSensitive: false,
    dotAll: true,
  ).firstMatch(html);
  if (match == null) {
    return null;
  }

  final rawTitle = match.group(1)?.trim() ?? '';
  if (rawTitle.isEmpty) {
    return null;
  }
  return _decodeBasicHtmlEntities(rawTitle);
}

String _extractReadableText(String html) {
  final withoutScript = html
      .replaceAll(
        RegExp(r'<script[^>]*>.*?</script>',
            caseSensitive: false, dotAll: true),
        ' ',
      )
      .replaceAll(
        RegExp(r'<style[^>]*>.*?</style>', caseSensitive: false, dotAll: true),
        ' ',
      );

  final withLineHints = withoutScript
      .replaceAll(
          RegExp(r'</(p|div|section|article|h1|h2|h3|li|br)>',
              caseSensitive: false),
          '\n')
      .replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n');

  final withoutTags = withLineHints.replaceAll(
    RegExp(r'<[^>]+>', caseSensitive: false, dotAll: true),
    ' ',
  );

  final decoded = _decodeBasicHtmlEntities(withoutTags)
      .replaceAll(RegExp(r'[ \t]+'), ' ')
      .replaceAll(RegExp(r'\n\s+'), '\n')
      .replaceAll(RegExp(r'\n{3,}'), '\n\n')
      .trim();

  return decoded;
}

Map<String, dynamic> _mapTavilySearchResult(Map<String, dynamic> item) {
  final url = (item['url'] as String? ?? '').trim();
  final title = (item['title'] as String? ?? url).trim();
  final snippet = (item['content'] as String? ?? '').trim();
  final source = _extractHost(url);
  final score = item['score'];
  final publishedDate = _normalizePublishedDate(
    item['published_date'] ?? item['publishedDate'],
  );

  return {
    'title': title,
    'url': url,
    'snippet': snippet,
    'source': source,
    if (score is num) 'score': score,
    if (publishedDate != null) 'publishedDate': publishedDate,
  };
}

String _extractHost(String url) {
  final uri = Uri.tryParse(url);
  if (uri == null || uri.host.trim().isEmpty) {
    return '';
  }
  return uri.host.trim();
}

String? _normalizePublishedDate(dynamic value) {
  if (value is! String) {
    return null;
  }
  final trimmed = value.trim();
  return trimmed.isEmpty ? null : trimmed;
}

String _decodeBasicHtmlEntities(String value) {
  return value
      .replaceAll('&nbsp;', ' ')
      .replaceAll('&amp;', '&')
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&quot;', '"')
      .replaceAll('&#39;', "'");
}

Future<ShareAdapterResult> _defaultShareInvoker({
  required String text,
  String? subject,
}) async {
  final result = await Share.share(
    text,
    subject: subject,
  );

  final status = switch (result.status) {
    ShareResultStatus.success => ShareAdapterStatus.success,
    ShareResultStatus.dismissed => ShareAdapterStatus.dismissed,
    ShareResultStatus.unavailable => ShareAdapterStatus.unavailable,
  };

  return ShareAdapterResult(
    status: status,
    raw: result.raw,
  );
}

Future<HostIntentResult> _defaultHostIntentLauncher(
  HostIntentRequest request,
) async {
  try {
    Logger.i(
      _hostToolsTag,
      '发起宿主 Intent: action=${request.action}, arguments=${request.arguments}',
    );
    final response = await _hostToolsChannel.invokeMapMethod<String, dynamic>(
      'launchHostIntent',
      {
        'action': request.action,
        'arguments': request.arguments,
      },
    );

    final statusName = response?['status'] as String? ?? 'failed';
    final status = HostIntentStatus.values.firstWhere(
      (value) => value.name == statusName,
      orElse: () => HostIntentStatus.failed,
    );
    Logger.i(
      _hostToolsTag,
      '宿主 Intent 返回: action=${request.action}, status=${status.name}, message=${response?['message']}',
    );

    return HostIntentResult(
      status: status,
      message: response?['message'] as String?,
    );
  } on PlatformException catch (error) {
    Logger.e(
      _hostToolsTag,
      '宿主 Intent 调用失败: action=${request.action}',
      error,
    );
    return HostIntentResult(
      status: HostIntentStatus.failed,
      message: error.message,
    );
  }
}

Future<void> _defaultClipboardWriter(String text) async {
  await Clipboard.setData(ClipboardData(text: text));
}

class _ClockTime {
  final int hour;
  final int minutes;

  const _ClockTime({
    required this.hour,
    required this.minutes,
  });
}

_ClockTime? _extractClockTime(String rawIsoText) {
  final match = RegExp(r'T(\d{2}):(\d{2})').firstMatch(rawIsoText);
  if (match == null) {
    return null;
  }

  return _ClockTime(
    hour: int.parse(match.group(1)!),
    minutes: int.parse(match.group(2)!),
  );
}

String _buildReminderFallbackText({
  required String title,
  required String dueAt,
  String? note,
}) {
  final lines = <String>[
    '提醒事项',
    '标题：$title',
    '时间：${_formatIsoWallTime(dueAt)}',
  ];
  if (note != null && note.trim().isNotEmpty) {
    lines.add('备注：${note.trim()}');
  }
  return lines.join('\n');
}

String _buildCalendarEventFallbackText({
  required String title,
  required String startAt,
  required String endAt,
  String? location,
  String? notes,
}) {
  final lines = <String>[
    '日历事件',
    '标题：$title',
    '开始：${_formatIsoWallTime(startAt)}',
    '结束：${_formatIsoWallTime(endAt)}',
  ];
  if (location != null && location.trim().isNotEmpty) {
    lines.add('地点：${location.trim()}');
  }
  if (notes != null && notes.trim().isNotEmpty) {
    lines.add('备注：${notes.trim()}');
  }
  return lines.join('\n');
}

String _formatIsoWallTime(String rawIsoText) {
  final match = RegExp(
    r'^(\d{4}-\d{2}-\d{2})T(\d{2}:\d{2})(?::\d{2}(?:\.\d+)?)?(Z|[+-]\d{2}:\d{2})?$',
  ).firstMatch(rawIsoText);
  if (match == null) {
    return rawIsoText;
  }

  final offset = match.group(3) == null
      ? ''
      : ' GMT${match.group(3) == 'Z' ? '+00:00' : match.group(3)!}';
  return '${match.group(1)!} ${match.group(2)!}$offset';
}
