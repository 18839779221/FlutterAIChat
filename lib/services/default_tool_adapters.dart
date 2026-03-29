import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'tool_executor.dart';

/// Preference key for the lightweight app-internal note store.
const String kSavedNotesPreferenceKey = 'tool.saved_notes';

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
