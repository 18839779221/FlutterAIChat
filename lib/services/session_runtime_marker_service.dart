import '../models/chat_message.dart';
import '../models/session/session_runtime_marker.dart';
import '../repositories/session_runtime_marker_repository.dart';

typedef SessionRuntimeNowProvider = DateTime Function();

class SessionRuntimeMarkerPreparation {
  final String currentDate;
  final ChatMessage? reminderMessage;

  const SessionRuntimeMarkerPreparation({
    required this.currentDate,
    required this.reminderMessage,
  });
}

class SessionRuntimeMarkerService {
  static const String runtimeContextKey = 'runtime_context';
  static const String currentDateKey = 'current_date';
  static const String dateChangeReminderKey = 'date_change_reminder';
  static const String workspaceChangeReminderKey = 'workspace_change_reminder';

  SessionRuntimeMarkerService({
    required SessionRuntimeMarkerRepository repository,
    SessionRuntimeNowProvider? nowProvider,
  })  : _repository = repository,
        _nowProvider = nowProvider ?? DateTime.now;

  final SessionRuntimeMarkerRepository _repository;
  final SessionRuntimeNowProvider _nowProvider;

  Future<SessionRuntimeMarkerPreparation> prepareForUserMessage({
    required int groupId,
  }) async {
    final currentDate = _formatIsoDate(_nowProvider());
    final marker = await _repository.getLatestByGroup(groupId);
    if (marker == null || marker.lastInjectedDate == currentDate) {
      return SessionRuntimeMarkerPreparation(
        currentDate: currentDate,
        reminderMessage: null,
      );
    }

    return SessionRuntimeMarkerPreparation(
      currentDate: currentDate,
      reminderMessage: _buildReminderMessage(currentDate),
    );
  }

  Future<void> persistInjectedDate({
    required int groupId,
    required String currentDate,
  }) {
    return _repository.upsertLatest(
      SessionRuntimeMarker(
        groupId: groupId,
        lastInjectedDate: currentDate,
      ),
    );
  }

  Map<String, dynamic> buildTurnRuntimeContext(
    SessionRuntimeMarkerPreparation preparation, {
    String? workspaceChangeReminder,
  }) {
    return {
      runtimeContextKey: {
        currentDateKey: preparation.currentDate,
        if (preparation.reminderMessage != null)
          dateChangeReminderKey: preparation.reminderMessage!.text,
        if (workspaceChangeReminder != null &&
            workspaceChangeReminder.trim().isNotEmpty)
          workspaceChangeReminderKey: workspaceChangeReminder.trim(),
      },
    };
  }

  ChatMessage _buildReminderMessage(String currentDate) {
    return ChatMessage(
      text: '<system-reminder>\n'
          "The date has changed. Today's date is now $currentDate.\n"
          'DO NOT mention this to the user explicitly because they are already aware.\n'
          '</system-reminder>',
      role: MessageRole.user,
      status: MessageStatus.completed,
    );
  }

  static String _formatIsoDate(DateTime value) {
    final year = value.year.toString().padLeft(4, '0');
    final month = value.month.toString().padLeft(2, '0');
    final day = value.day.toString().padLeft(2, '0');
    return '$year-$month-$day';
  }
}
