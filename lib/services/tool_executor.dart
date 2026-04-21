import '../models/chat_message.dart';
import '../models/tool/tool_result.dart';
import '../storage/chat_storage.dart';

export '../models/tool/tool_result.dart';

/// Fetches webpage content and returns a normalized tool result payload.
typedef WebpageFetcher = Future<ToolResult> Function({
  required String url,
  String? extractMode,
});

/// Searches the web and returns a normalized result list payload.
typedef WebSearcher = Future<ToolResult> Function({
  required String query,
  int? maxResults,
});

/// Creates a reminder entry in the host platform and returns a tool result.
typedef ReminderCreator = Future<ToolResult> Function({
  required String title,
  String? dueAt,
  String? note,
});

/// Creates a calendar event in the host platform and returns a tool result.
typedef CalendarEventCreator = Future<ToolResult> Function({
  required String title,
  required String startAt,
  String? endAt,
  String? location,
  String? notes,
});

/// Shares a prepared text result via the host platform share surface.
typedef ResultSharer = Future<ToolResult> Function({
  required String text,
  String? subject,
});

class ToolExecutor {
  ToolExecutor({
    required ChatStorage chatStorage,
    WebSearcher? webSearcher,
    WebpageFetcher? webpageFetcher,
    ReminderCreator? reminderCreator,
    CalendarEventCreator? calendarEventCreator,
    ResultSharer? resultSharer,
  })  : _chatStorage = chatStorage,
        _webSearcher = webSearcher,
        _webpageFetcher = webpageFetcher,
        _reminderCreator = reminderCreator,
        _calendarEventCreator = calendarEventCreator,
        _resultSharer = resultSharer;

  final ChatStorage _chatStorage;
  final WebSearcher? _webSearcher;
  final WebpageFetcher? _webpageFetcher;
  final ReminderCreator? _reminderCreator;
  final CalendarEventCreator? _calendarEventCreator;
  final ResultSharer? _resultSharer;

  /// Searches messages in the current group and returns compact match previews.
  Future<ToolResult> executeSearchChatHistory({
    required int groupId,
    required String query,
    int maxResults = 3,
  }) async {
    final normalizedQuery = query.trim();
    if (normalizedQuery.isEmpty) {
      return const ToolResult(
        toolName: 'search_chat_history',
        status: ToolExecutionStatus.failure,
        summary: '搜索失败：查询内容不能为空',
        data: {
          'reason': 'empty_query',
        },
        errorMessage: 'empty_query',
      );
    }

    final messages = await _chatStorage.getMessagesByGroup(groupId);
    final matches = messages
        .where((message) => _isSearchableMessage(message, normalizedQuery))
        .take(maxResults)
        .map(_buildMatchPayload)
        .toList();

    return ToolResult(
      toolName: 'search_chat_history',
      status: ToolExecutionStatus.success,
      summary: '已执行：搜索历史记录',
      data: {
        'query': normalizedQuery,
        'matchCount': matches.length,
        'matches': matches,
      },
    );
  }

  /// Runs an external web search through an injected search adapter.
  Future<ToolResult> executeWebSearch({
    required String query,
    int? maxResults,
  }) async {
    final searcher = _webSearcher;
    if (searcher == null) {
      return _unsupportedToolResult('web_search');
    }
    return searcher(query: query, maxResults: maxResults);
  }

  /// Loads webpage content through an injected fetcher to keep platform code out
  /// of the executor itself.
  Future<ToolResult> executeFetchWebpage({
    required String url,
    String? extractMode,
  }) async {
    final fetcher = _webpageFetcher;
    if (fetcher == null) {
      return _unsupportedToolResult('fetch_webpage');
    }
    return fetcher(url: url, extractMode: extractMode);
  }

  /// Creates a reminder through an injected platform adapter.
  Future<ToolResult> executeCreateReminder({
    required String title,
    String? dueAt,
    String? note,
  }) async {
    final creator = _reminderCreator;
    if (creator == null) {
      return _unsupportedToolResult('create_reminder');
    }
    return creator(title: title, dueAt: dueAt, note: note);
  }

  /// Creates a calendar event through an injected platform adapter.
  Future<ToolResult> executeCreateCalendarEvent({
    required String title,
    required String startAt,
    String? endAt,
    String? location,
    String? notes,
  }) async {
    final creator = _calendarEventCreator;
    if (creator == null) {
      return _unsupportedToolResult('create_calendar_event');
    }
    return creator(
      title: title,
      startAt: startAt,
      endAt: endAt,
      location: location,
      notes: notes,
    );
  }

  /// Shares a text result through an injected platform adapter.
  Future<ToolResult> executeShareResult({
    required String text,
    String? subject,
  }) async {
    final sharer = _resultSharer;
    if (sharer == null) {
      return _unsupportedToolResult('share_result');
    }
    return sharer(text: text, subject: subject);
  }

  bool _isSearchableMessage(ChatMessage message, String query) {
    return message.text.trim().isNotEmpty && message.text.contains(query);
  }

  Map<String, dynamic> _buildMatchPayload(ChatMessage message) {
    return {
      'id': message.id,
      'text': _truncatePreview(message.text),
      'role': message.role.name,
      'timestamp': message.timestamp.toIso8601String(),
    };
  }

  String _truncatePreview(String text) {
    final normalized = text.trim();
    if (normalized.length <= 80) {
      return normalized;
    }
    return '${normalized.substring(0, 80)}...';
  }

  /// Normalizes the "adapter not wired yet" case into a stable failure result
  /// so the UI can render it without special-case exception handling.
  ToolResult _unsupportedToolResult(String toolName) {
    return ToolResult(
      toolName: toolName,
      status: ToolExecutionStatus.failure,
      summary: '工具暂不可用：$toolName',
      data: const {
        'reason': 'unsupported_tool',
      },
      errorMessage: 'unsupported_tool',
    );
  }
}
