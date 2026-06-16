import '../models/chat_event.dart';
import '../models/chat/chat_attachment.dart';
import '../models/chat_message.dart';
import '../models/chat_turn.dart';
import '../models/interaction/ask_user_question_request.dart';
import '../models/interaction/ask_user_question_response.dart';
import '../models/tool/tool_invocation.dart';
import '../storage/chat_storage.dart';
import '../utils/logger.dart';

class ChatEventRepository {
  static const _tag = 'ChatEventRepository';
  final ChatStorage _storage;
  final Map<int, Future<void>> _turnLocks = {};

  ChatEventRepository(this._storage);

  Future<T> _withTurnLock<T>(int turnId, Future<T> Function() action) {
    final previous = _turnLocks[turnId] ?? Future<void>.value();
    final result = previous.then((_) => action());
    final tail = result.then<void>((_) {}, onError: (_) {});
    _turnLocks[turnId] = tail;
    tail.whenComplete(() {
      if (identical(_turnLocks[turnId], tail)) {
        _turnLocks.remove(turnId);
      }
    });
    return result;
  }

  Future<ChatEvent> appendUserMessage({
    required int turnId,
    required int groupId,
    required String content,
    ChatEventUserMessageKind kind = ChatEventUserMessageKind.start,
    List<ChatAttachment> attachments = const <ChatAttachment>[],
    Map<String, dynamic>? extraPayloadJson,
  }) {
    if (attachments.isNotEmpty) {
      Logger.temp(
        _tag,
        'attachments.user_event_appended',
        reason: 'diagnose_image_attachment_context_chain',
        data: {
          'turnId': turnId,
          'groupId': groupId,
          'attachmentCount': attachments.length,
          'localIds':
              attachments.map((attachment) => attachment.localId).toList(),
          'hasProviderDataUrl': attachments
              .map(
                (attachment) =>
                    attachment.providerFileRefJson?['data_url'] is String &&
                    (attachment.providerFileRefJson?['data_url'] as String)
                        .trim()
                        .isNotEmpty,
              )
              .toList(),
        },
      );
    }
    return _appendEvent(
      turnId: turnId,
      groupId: groupId,
      eventType: ChatEventType.userMessage,
      role: MessageRole.user,
      content: content,
      payloadJson: {
        'userMessageKind': kind.name,
        ...?extraPayloadJson,
        if (attachments.isNotEmpty)
          'attachments':
              attachments.map((attachment) => attachment.toJson()).toList(),
      },
    );
  }

  Future<ChatEvent> appendToolResult({
    required int turnId,
    required int groupId,
    required String content,
    Map<String, dynamic>? payloadJson,
  }) {
    return _appendEvent(
      turnId: turnId,
      groupId: groupId,
      eventType: ChatEventType.toolResult,
      role: MessageRole.system,
      content: content,
      payloadJson: payloadJson,
    );
  }

  Future<ChatEvent> appendToolCall({
    required int turnId,
    required int groupId,
    required String toolName,
    required Map<String, dynamic> arguments,
    required String summary,
    Map<String, dynamic>? payloadJson,
  }) {
    return _appendEvent(
      turnId: turnId,
      groupId: groupId,
      eventType: ChatEventType.assistantToolCall,
      role: MessageRole.assistant,
      content: summary,
      payloadJson: payloadJson ??
          {
            'toolName': toolName,
            'arguments': arguments,
            'status': ToolInvocationStatus.proposed.name,
            'summary': summary,
            'requiresConfirmation': false,
          },
    );
  }

  Future<ChatEvent> appendToolConfirmation({
    required int turnId,
    required int groupId,
    required String toolName,
    required Map<String, dynamic> arguments,
    required String summary,
    Map<String, dynamic>? payloadJson,
  }) {
    return _appendEvent(
      turnId: turnId,
      groupId: groupId,
      eventType: ChatEventType.assistantToolConfirmation,
      role: MessageRole.assistant,
      content: summary,
      payloadJson: payloadJson ??
          {
            'toolName': toolName,
            'arguments': arguments,
            'status': ToolInvocationStatus.awaitingConfirmation.name,
            'summary': summary,
            'requiresConfirmation': true,
          },
    );
  }

  Future<ChatEvent> appendToolExecutionStarted({
    required int turnId,
    required int groupId,
    required String content,
    Map<String, dynamic>? payloadJson,
  }) {
    return _appendEvent(
      turnId: turnId,
      groupId: groupId,
      eventType: ChatEventType.toolExecutionStarted,
      role: MessageRole.system,
      content: content,
      payloadJson: payloadJson,
    );
  }

  Future<ChatEvent> appendAssistantQuestionPrompt({
    required int turnId,
    required int groupId,
    required AskUserQuestionRequest request,
    required String content,
    Map<String, dynamic>? payloadJson,
  }) {
    return _appendEvent(
      turnId: turnId,
      groupId: groupId,
      eventType: ChatEventType.assistantQuestionPrompt,
      role: MessageRole.assistant,
      content: content,
      payloadJson: payloadJson ?? request.toJson(),
    );
  }

  Future<ChatEvent> appendUserInteractionResult({
    required int turnId,
    required int groupId,
    required AskUserQuestionResponse response,
    required String content,
    Map<String, dynamic>? payloadJson,
  }) {
    return _appendEvent(
      turnId: turnId,
      groupId: groupId,
      eventType: ChatEventType.userInteractionResult,
      role: MessageRole.system,
      content: content,
      payloadJson: payloadJson ?? response.toJson(),
    );
  }

  Future<ChatEvent> appendToolError({
    required int turnId,
    required int groupId,
    required String content,
    String? errorCode,
    Map<String, dynamic>? payloadJson,
  }) {
    return _appendEvent(
      turnId: turnId,
      groupId: groupId,
      eventType: ChatEventType.toolError,
      role: MessageRole.system,
      content: content,
      status: errorCode,
      payloadJson: payloadJson,
    );
  }

  Future<ChatEvent> appendAssistantTextDelta({
    required int turnId,
    required int groupId,
    required String content,
  }) {
    return _appendEvent(
      turnId: turnId,
      groupId: groupId,
      eventType: ChatEventType.assistantTextDelta,
      role: MessageRole.assistant,
      content: content,
    );
  }

  Future<ChatEvent> appendAssistantReasoningDelta({
    required int turnId,
    required int groupId,
    required String content,
    required String scope,
    Map<String, dynamic>? payloadJson,
  }) {
    return _appendEvent(
      turnId: turnId,
      groupId: groupId,
      eventType: ChatEventType.assistantReasoningDelta,
      role: MessageRole.assistant,
      content: content,
      payloadJson: {
        'scope': scope,
        ...?payloadJson,
      },
    );
  }

  Future<ChatEvent> appendAssistantPlannerMessage({
    required int turnId,
    required int groupId,
    required String content,
    Map<String, dynamic>? payloadJson,
  }) {
    return _appendEvent(
      turnId: turnId,
      groupId: groupId,
      eventType: ChatEventType.assistantPlannerMessage,
      role: MessageRole.assistant,
      content: content,
      payloadJson: payloadJson,
    );
  }

  Future<ChatEvent> appendAssistantTextFinal({
    required int turnId,
    required int groupId,
    required String content,
    Map<String, dynamic>? payloadJson,
  }) {
    return _appendEvent(
      turnId: turnId,
      groupId: groupId,
      eventType: ChatEventType.assistantTextFinal,
      role: MessageRole.assistant,
      content: content,
      payloadJson: payloadJson,
    );
  }

  /// Persists the provider's raw assistant message for round-trip replay on
  /// the next outbound planner request. One event per planner iteration that
  /// produced any provider content. UI rendering uses the fragmented events
  /// (textDelta / reasoningDelta / toolCall), not this snapshot.
  Future<ChatEvent> appendAssistantTurnSnapshot({
    required int turnId,
    required int groupId,
    required ChatTurnProviderStyle apiStyle,
    required Map<String, dynamic> rawAssistantMessageJson,
  }) {
    return _appendEvent(
      turnId: turnId,
      groupId: groupId,
      eventType: ChatEventType.assistantTurnSnapshot,
      role: MessageRole.assistant,
      content: '',
      payloadJson: {
        'apiStyle': apiStyle.name,
        'rawAssistantMessage': rawAssistantMessageJson,
      },
    );
  }

  Future<ChatEvent> appendFinalAnswer({
    required int turnId,
    required int groupId,
    required String content,
    Map<String, dynamic>? payloadJson,
  }) {
    return _appendEvent(
      turnId: turnId,
      groupId: groupId,
      eventType: ChatEventType.finalAnswer,
      role: MessageRole.assistant,
      content: content,
      payloadJson: payloadJson,
    );
  }

  Future<ChatEvent> appendContextCompacted({
    required int turnId,
    required int groupId,
    required String content,
    Map<String, dynamic>? payloadJson,
  }) {
    return _appendEvent(
      turnId: turnId,
      groupId: groupId,
      eventType: ChatEventType.contextCompacted,
      role: MessageRole.system,
      content: content,
      payloadJson: payloadJson,
    );
  }

  Future<ChatEvent> appendTurnStatus({
    required int turnId,
    required int groupId,
    required String content,
  }) {
    return _appendEvent(
      turnId: turnId,
      groupId: groupId,
      eventType: ChatEventType.turnStatus,
      role: MessageRole.system,
      content: content,
    );
  }

  Future<List<ChatEvent>> listEventsByTurn(int turnId) {
    return _storage.getEventsByTurn(turnId);
  }

  Future<List<ChatEvent>> listEventsByGroup(int groupId) {
    return _storage.getEventsByGroup(groupId);
  }

  Future<ChatEvent> _appendEvent({
    required int turnId,
    required int groupId,
    required ChatEventType eventType,
    MessageRole? role,
    String? content,
    String? status,
    Map<String, dynamic>? payloadJson,
  }) {
    return _withTurnLock(turnId, () async {
      final sequence = await _storage.getNextEventSequence(turnId);
      final event = ChatEvent(
        turnId: turnId,
        groupId: groupId,
        sequence: sequence,
        eventType: eventType,
        role: role,
        status: status,
        content: content,
        payloadJson: payloadJson,
      );
      final id = await _storage.insertEvent(event);
      return event.copyWith(id: id);
    });
  }
}
