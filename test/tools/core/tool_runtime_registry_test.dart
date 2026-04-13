import 'package:ai_chat/models/chat_message.dart';
import 'package:ai_chat/models/tool/tool_argument_property.dart';
import 'package:ai_chat/models/tool/tool_argument_schema.dart';
import 'package:ai_chat/models/tool/tool_definition.dart';
import 'package:ai_chat/models/tool/tool_result.dart';
import 'package:ai_chat/tools/handlers/create_calendar_event_tool_handler.dart';
import 'package:ai_chat/tools/handlers/create_reminder_tool_handler.dart';
import 'package:ai_chat/tools/handlers/fetch_webpage_tool_handler.dart';
import 'package:ai_chat/tools/handlers/save_note_tool_handler.dart';
import 'package:ai_chat/tools/handlers/search_chat_history_tool_handler.dart';
import 'package:ai_chat/tools/handlers/share_result_tool_handler.dart';
import 'package:ai_chat/tools/handlers/web_search_tool_handler.dart';
import 'package:ai_chat/tools/core/tool_argument_resolution.dart';
import 'package:ai_chat/tools/core/tool_execution_context.dart';
import 'package:ai_chat/tools/core/tool_handler.dart';
import 'package:ai_chat/tools/core/tool_runtime_registry.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ToolRuntimeRegistry', () {
    test('returns registered handler by tool name', () {
      final registry = ToolRuntimeRegistry(
        handlers: [
          _FakeToolHandler(toolName: 'web_search'),
        ],
      );

      expect(registry.findHandler('web_search'), isNotNull);
      expect(registry.findHandler('missing_tool'), isNull);
    });

    test('does not resolve unknown tool names that are not explicitly registered', () {
      final registry = ToolRuntimeRegistry(
        handlers: [
          _FakeToolHandler(toolName: 'web_search'),
        ],
      );

      expect(registry.findHandler('search_news'), isNull);
    });

    test('exposes all tool definitions for decision service', () {
      final registry = ToolRuntimeRegistry(
        handlers: [
          _FakeToolHandler(toolName: 'web_search'),
          _FakeToolHandler(toolName: 'create_reminder'),
        ],
      );

      expect(
        registry.getAllDefinitions().map((item) => item.name).toList(),
        ['web_search', 'create_reminder'],
      );
    });

    test('filters tool definitions by supported platform', () {
      final registry = ToolRuntimeRegistry(
        handlers: [
          _FakeToolHandler(
            toolName: 'web_search',
            supportedPlatforms: const ['web', 'ios'],
          ),
          _FakeToolHandler(
            toolName: 'create_reminder',
            supportedPlatforms: const ['ios'],
          ),
        ],
      );

      expect(
        registry.getDefinitionsForPlatform('web').map((item) => item.name).toList(),
        ['web_search'],
      );
    });

    test('built-in handlers expose rich planner metadata', () {
      final definitions = [
        SearchChatHistoryToolHandler(searcher: _noopSearchHistory).definition,
        WebSearchToolHandler(webSearcher: _noopWebSearch).definition,
        FetchWebpageToolHandler(webpageFetcher: _noopFetchWebpage).definition,
        SaveNoteToolHandler(noteSaver: _noopSaveNote).definition,
        CreateReminderToolHandler(reminderCreator: _noopCreateReminder).definition,
        CreateCalendarEventToolHandler(
          calendarEventCreator: _noopCreateCalendarEvent,
        ).definition,
        ShareResultToolHandler(resultSharer: _noopShareResult).definition,
      ];

      final webSearch = definitions.firstWhere((item) => item.name == 'web_search');
      final fetchWebpage =
          definitions.firstWhere((item) => item.name == 'fetch_webpage');
      final createReminder =
          definitions.firstWhere((item) => item.name == 'create_reminder');
      final shareResult =
          definitions.firstWhere((item) => item.name == 'share_result');

      expect(webSearch.descriptionForModel, contains('实时'));
      expect(webSearch.category, ToolCategory.retrieval);
      expect(webSearch.whenToUse, isNotEmpty);
      expect(webSearch.argumentSchema?.required, contains('query'));

      expect(fetchWebpage.descriptionForModel, contains('URL'));
      expect(fetchWebpage.whenNotToUse, isNotEmpty);
      expect(fetchWebpage.argumentSchema?.required, contains('url'));

      expect(createReminder.category, ToolCategory.productivity);
      expect(createReminder.descriptionForModel, contains('提醒'));
      expect(createReminder.whenToUse, isNotEmpty);
      expect(createReminder.argumentSchema?.required, containsAll(['title', 'dueAt']));

      expect(shareResult.category, ToolCategory.outputAction);
      expect(shareResult.descriptionForModel, contains('分享'));
      expect(shareResult.whenNotToUse, isNotEmpty);
      expect(shareResult.argumentSchema?.required, contains('text'));
    });
  });
}

Future<ToolResult> _noopSearchHistory({
  required int groupId,
  required String query,
  required int maxResults,
}) async {
  return const ToolResult(
    toolName: 'search_chat_history',
    status: ToolExecutionStatus.success,
    summary: 'ok',
  );
}

Future<ToolResult> _noopWebSearch({
  required String query,
  int? maxResults,
}) async {
  return const ToolResult(
    toolName: 'web_search',
    status: ToolExecutionStatus.success,
    summary: 'ok',
  );
}

Future<ToolResult> _noopFetchWebpage({
  required String url,
  String? extractMode,
}) async {
  return const ToolResult(
    toolName: 'fetch_webpage',
    status: ToolExecutionStatus.success,
    summary: 'ok',
  );
}

Future<ToolResult> _noopSaveNote({
  required String title,
  required String content,
  String? folder,
}) async {
  return const ToolResult(
    toolName: 'save_note',
    status: ToolExecutionStatus.success,
    summary: 'ok',
  );
}

Future<ToolResult> _noopCreateReminder({
  required String title,
  String? dueAt,
  String? note,
}) async {
  return const ToolResult(
    toolName: 'create_reminder',
    status: ToolExecutionStatus.success,
    summary: 'ok',
  );
}

Future<ToolResult> _noopCreateCalendarEvent({
  required String title,
  required String startAt,
  String? endAt,
  String? location,
  String? notes,
}) async {
  return const ToolResult(
    toolName: 'create_calendar_event',
    status: ToolExecutionStatus.success,
    summary: 'ok',
  );
}

Future<ToolResult> _noopShareResult({
  required String text,
  String? subject,
}) async {
  return const ToolResult(
    toolName: 'share_result',
    status: ToolExecutionStatus.success,
    summary: 'ok',
  );
}

class _FakeToolHandler implements ToolHandler {
  _FakeToolHandler({
    required this.toolName,
    this.supportedPlatforms = const ['android', 'ios', 'web'],
  });

  final String toolName;
  final List<String> supportedPlatforms;

  @override
  ToolDefinition get definition => ToolDefinition(
        name: toolName,
        description: '$toolName description',
        descriptionForModel: '$toolName planner description',
        category: ToolCategory.retrieval,
        argumentSchema: const ToolArgumentSchema(
          properties: {
            'query': ToolArgumentProperty.string(
              description: 'query description',
            ),
          },
          required: ['query'],
        ),
        supportedPlatforms: supportedPlatforms,
      );

  @override
  List<ChatMessage> buildContextMessages({
    required ToolResult result,
    required ToolExecutionContext context,
  }) {
    return const [];
  }

  @override
  Future<ToolResult> execute(ToolExecutionContext context) async {
    return ToolResult(
      toolName: toolName,
      status: ToolExecutionStatus.success,
      summary: 'ok',
    );
  }

  @override
  Future<ToolArgumentResolution> normalizeArguments({
    required Map<String, dynamic> rawArguments,
    required String userMessage,
    required List<ChatMessage> history,
    required DateTime now,
  }) async {
    return ToolArgumentResolution.valid(rawArguments);
  }
}
