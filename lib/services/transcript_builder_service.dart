import '../models/chat_event.dart';
import '../models/chat_message.dart';
import '../models/chat_turn.dart';
import '../repositories/chat_event_repository.dart';

class TranscriptBuilderService {
  final ChatEventRepository _eventRepository;

  TranscriptBuilderService({
    required ChatEventRepository eventRepository,
  }) : _eventRepository = eventRepository;

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
      final content = event.content;
      if (content == null || content.trim().isEmpty) {
        continue;
      }
      final projectedRole = _projectFinalAnswerRole(event);
      if (projectedRole == null) {
        continue;
      }
      messages.add(
        ChatMessage(
          text: content,
          role: projectedRole,
          timestamp: event.createdAt,
          status: MessageStatus.completed,
        ),
      );
    }

    return messages;
  }

  MessageRole? _projectFinalAnswerRole(ChatEvent event) {
    switch (event.eventType) {
      case ChatEventType.userMessage:
        return MessageRole.user;
      case ChatEventType.userInteractionResult:
        return MessageRole.user;
      case ChatEventType.assistantPlannerMessage:
      case ChatEventType.assistantQuestionPrompt:
      case ChatEventType.toolResult:
      case ChatEventType.toolError:
      case ChatEventType.finalAnswer:
        return MessageRole.assistant;
      case ChatEventType.assistantReasoningDelta:
      case ChatEventType.assistantTextDelta:
      case ChatEventType.assistantTextFinal:
      case ChatEventType.assistantToolCall:
      case ChatEventType.assistantToolConfirmation:
      case ChatEventType.toolExecutionStarted:
      case ChatEventType.turnStatus:
      case ChatEventType.error:
        return null;
    }
  }
}
