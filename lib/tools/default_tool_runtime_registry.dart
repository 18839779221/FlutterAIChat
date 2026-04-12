import '../services/tool_executor.dart';
import 'core/tool_runtime_registry.dart';
import 'handlers/create_calendar_event_tool_handler.dart';
import 'handlers/create_reminder_tool_handler.dart';
import 'handlers/fetch_webpage_tool_handler.dart';
import 'handlers/save_note_tool_handler.dart';
import 'handlers/search_chat_history_tool_handler.dart';
import 'handlers/share_result_tool_handler.dart';
import 'handlers/web_search_tool_handler.dart';

/// Builds the default runtime registry by wiring built-in tool handlers to the
/// host adapters exposed by [ToolExecutor].
ToolRuntimeRegistry buildDefaultToolRuntimeRegistry({
  required ToolExecutor toolExecutor,
}) {
  return ToolRuntimeRegistry(
    handlers: [
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
      SaveNoteToolHandler(
        noteSaver: ({
          required title,
          required content,
          folder,
        }) {
          return toolExecutor.executeSaveNote(
            title: title,
            content: content,
            folder: folder,
          );
        },
      ),
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
