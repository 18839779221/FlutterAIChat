import '../services/tool_executor.dart';
import 'core/tool_runtime_registry.dart';
import 'handlers/ask_user_question_tool_handler.dart';
import 'handlers/create_calendar_event_tool_handler.dart';
import 'handlers/create_reminder_tool_handler.dart';
import 'handlers/edit_tool_handler.dart';
import 'handlers/fetch_webpage_tool_handler.dart';
import 'handlers/glob_tool_handler.dart';
import 'handlers/grep_tool_handler.dart';
import 'handlers/ls_tool_handler.dart';
import 'handlers/read_tool_handler.dart';
import 'handlers/search_chat_history_tool_handler.dart';
import 'handlers/share_result_tool_handler.dart';
import 'handlers/web_search_tool_handler.dart';
import 'handlers/write_tool_handler.dart';

/// Builds the default runtime registry by wiring built-in tool handlers to the
/// host adapters exposed by [ToolExecutor].
ToolRuntimeRegistry buildDefaultToolRuntimeRegistry({
  required ToolExecutor toolExecutor,
}) {
  return ToolRuntimeRegistry(
    handlers: [
      AskUserQuestionToolHandler(),
      SearchChatHistoryToolHandler(
        searcher: ({
          required groupId,
          required query,
          required maxResults,
        }) {
          return toolExecutor.executeSearchChatHistory(
            groupId: groupId,
            query: query,
            maxResults: maxResults,
          );
        },
      ),
      WebSearchToolHandler(
        webSearcher: ({
          required query,
          maxResults,
        }) {
          return toolExecutor.executeWebSearch(
            query: query,
            maxResults: maxResults,
          );
        },
      ),
      FetchWebpageToolHandler(
        webpageFetcher: ({
          required url,
          extractMode,
        }) {
          return toolExecutor.executeFetchWebpage(
            url: url,
            extractMode: extractMode,
          );
        },
      ),
      LsToolHandler(),
      GlobToolHandler(),
      GrepToolHandler(),
      ReadToolHandler(),
      WriteToolHandler(),
      EditToolHandler(),
      CreateReminderToolHandler(
        reminderCreator: ({
          required title,
          dueAt,
          note,
        }) {
          return toolExecutor.executeCreateReminder(
            title: title,
            dueAt: dueAt,
            note: note,
          );
        },
      ),
      CreateCalendarEventToolHandler(
        calendarEventCreator: ({
          required title,
          required startAt,
          endAt,
          location,
          notes,
        }) {
          return toolExecutor.executeCreateCalendarEvent(
            title: title,
            startAt: startAt,
            endAt: endAt,
            location: location,
            notes: notes,
          );
        },
      ),
      ShareResultToolHandler(
        resultSharer: ({
          required text,
          subject,
        }) {
          return toolExecutor.executeShareResult(
            text: text,
            subject: subject,
          );
        },
      ),
    ],
  );
}
