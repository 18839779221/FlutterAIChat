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
    final latestToolResult = transcript.lastWhere(
      (event) => event.eventType == ChatEventType.toolResult,
      orElse: () => ChatEvent(
        turnId: turn.id ?? 0,
        groupId: turn.groupId,
        sequence: 0,
        eventType: ChatEventType.error,
      ),
    );

    final lines = <String>[
      '用户目标：${turn.userInput}',
    ];
    if ((latestToolResult.content ?? '').isNotEmpty) {
      lines.add('最新工具结果：${latestToolResult.content}');
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
      messages.add(
        ChatMessage(
          text: content,
          role: event.role ?? MessageRole.system,
          timestamp: event.createdAt,
          status: MessageStatus.completed,
        ),
      );
    }

    return messages;
  }
}
