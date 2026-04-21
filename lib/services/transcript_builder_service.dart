import '../models/chat_event.dart';
import '../models/chat_message.dart';
import '../models/chat_turn.dart';
import '../repositories/chat_event_repository.dart';
import 'session_context_projector.dart';

class TranscriptBuilderService {
  final ChatEventRepository _eventRepository;
  final SessionContextProjector _contextProjector;

  TranscriptBuilderService({
    required ChatEventRepository eventRepository,
    SessionContextProjector? contextProjector,
  })  : _eventRepository = eventRepository,
        _contextProjector = contextProjector ?? SessionContextProjector();

  Future<List<ChatEvent>> loadTranscript(int turnId) {
    return _eventRepository.listEventsByTurn(turnId);
  }

  Future<String> buildPlannerContext({
    required ChatTurn turn,
    required List<ChatEvent> transcript,
  }) async {
    return buildPlannerContextText(
      turn: turn,
      transcript: transcript,
    );
  }

  /// Builds a compact planner-facing summary from the raw event transcript.
  static String buildPlannerContextText({
    required ChatTurn turn,
    required List<ChatEvent> transcript,
  }) {
    final lines = <String>[
      '用户目标：${turn.userInput}',
    ];

    final attemptedTools = transcript
        .where((event) => event.eventType == ChatEventType.assistantToolCall)
        .map((event) => event.payloadJson?['toolName'])
        .whereType<String>()
        .toList(growable: false);
    if (attemptedTools.isNotEmpty) {
      lines.add('已尝试工具：${attemptedTools.join(', ')}');
    }

    final latestToolResult = transcript.lastWhere(
      (event) => event.eventType == ChatEventType.toolResult,
      orElse: () => ChatEvent(
        turnId: turn.id ?? 0,
        groupId: turn.groupId,
        sequence: 0,
        eventType: ChatEventType.error,
      ),
    );
    if ((latestToolResult.content ?? '').isNotEmpty) {
      lines.add('最近一次工具结果：${latestToolResult.content}');
    }

    final latestToolError = transcript.lastWhere(
      (event) => event.eventType == ChatEventType.toolError,
      orElse: () => ChatEvent(
        turnId: turn.id ?? 0,
        groupId: turn.groupId,
        sequence: 0,
        eventType: ChatEventType.error,
      ),
    );
    final latestToolErrorCode = latestToolError.status?.trim() ?? '';
    if (latestToolErrorCode.isNotEmpty) {
      lines.add('最近一次工具失败：$latestToolErrorCode');
    }

    return lines.join('\n');
  }

  Future<List<ChatMessage>> buildFinalAnswerMessages({
    required int groupId,
    required ChatTurn turn,
    required List<ChatEvent> transcript,
    required String systemPrompt,
  }) async {
    final messages = <ChatMessage>[];
    if (systemPrompt.trim().isNotEmpty) {
      messages.add(
        ChatMessage(
          text: systemPrompt,
          role: MessageRole.system,
          status: MessageStatus.completed,
        ),
      );
    }

    for (final event in transcript) {
      final projected = _contextProjector.projectEventToContext(event);
      if (projected != null) {
        messages.add(projected);
      }
    }

    return messages;
  }
}
