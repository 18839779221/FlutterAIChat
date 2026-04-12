import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'tool_executor.dart';
import '../utils/logger.dart';

/// Preference key for the lightweight app-internal note store.
const String kSavedNotesPreferenceKey = 'tool.saved_notes';
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
          'query': decoded['query'] is String && (decoded['query'] as String).trim().isNotEmpty
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

/// Builds the default webpage fetch adapter used by the mobile tool pipeline.
///
/// Returned payload fields:
/// - `url`: requested webpage address
/// - `title`: extracted HTML title when available
/// - `content`: normalized readable text
/// - `extractMode`: adapter mode used for this fetch
WebpageFetcher buildDefaultWebpageFetcher({
  http.Client? client,
}) {
  final resolvedClient = client ?? http.Client();

  return ({
    required String url,
    String? extractMode,
  }) async {
    try {
      final response = await resolvedClient.get(Uri.parse(url));
      if (response.statusCode < 200 || response.statusCode >= 300) {
        return ToolResult(
          toolName: 'fetch_webpage',
          status: ToolExecutionStatus.failure,
          summary: '读取网页失败',
          data: {
            'url': url,
            'reason': 'http_${response.statusCode}',
          },
          errorMessage: 'http_${response.statusCode}',
        );
      }

      final title = _extractHtmlTitle(response.body) ?? url;
      final content = _extractReadableText(response.body);
      if (content.isEmpty) {
        return ToolResult(
          toolName: 'fetch_webpage',
          status: ToolExecutionStatus.failure,
          summary: '读取网页失败',
          data: {
            'url': url,
            'reason': 'empty_content',
          },
          errorMessage: 'empty_content',
        );
      }

      return ToolResult(
        toolName: 'fetch_webpage',
        status: ToolExecutionStatus.success,
        summary: '已读取网页：$title',
        data: {
          'url': url,
          'title': title,
          'content': content,
          'extractMode': extractMode ?? 'readable_text',
        },
      );
    } catch (error) {
      return ToolResult(
        toolName: 'fetch_webpage',
        status: ToolExecutionStatus.failure,
        summary: '读取网页失败',
        data: {
          'url': url,
          'reason': 'network_error',
        },
        errorMessage: 'network_error',
      );
    }
  };
}

/// Builds a minimal app-internal note saver backed by SharedPreferences.
///
/// Saved note fields:
/// - `id`: generated stable storage id
/// - `title`: user-visible note title
/// - `content`: note body
/// - `folder`: optional logical grouping label
/// - `createdAt`: ISO8601 timestamp
NoteSaver buildSharedPreferencesNoteSaver(SharedPreferences preferences) {
  return ({
    required String title,
    required String content,
    String? folder,
  }) async {
    final trimmedTitle = title.trim();
    final trimmedContent = content.trim();
    final createdAt = DateTime.now().toIso8601String();
    final noteRecord = {
      'id': '$createdAt-$trimmedTitle',
      'title': trimmedTitle,
      'content': trimmedContent,
      'folder': folder?.trim(),
      'createdAt': createdAt,
    };

    final current = preferences.getStringList(kSavedNotesPreferenceKey) ?? [];
    final next = [
      ...current,
      jsonEncode(noteRecord),
    ];
    await preferences.setStringList(kSavedNotesPreferenceKey, next);

    return ToolResult(
      toolName: 'save_note',
      status: ToolExecutionStatus.success,
      summary: '已保存笔记：$trimmedTitle',
      data: noteRecord,
    );
  };
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

    final launchMode =
        result.message == 'calendar_fallback_launched' ? 'calendar_fallback' : 'alarm';
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
        RegExp(r'<script[^>]*>.*?</script>', caseSensitive: false, dotAll: true),
        ' ',
      )
      .replaceAll(
        RegExp(r'<style[^>]*>.*?</style>', caseSensitive: false, dotAll: true),
        ' ',
      );

  final withLineHints = withoutScript
      .replaceAll(RegExp(r'</(p|div|section|article|h1|h2|h3|li|br)>', caseSensitive: false), '\n')
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
