import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'tool_executor.dart';

/// Preference key for the lightweight app-internal note store.
const String kSavedNotesPreferenceKey = 'tool.saved_notes';

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
