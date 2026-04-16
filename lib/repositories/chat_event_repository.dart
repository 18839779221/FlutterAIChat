import '../models/chat_event.dart';
import '../models/chat_message.dart';
import '../models/interaction/ask_user_question_request.dart';
import '../models/interaction/ask_user_question_response.dart';
import '../models/tool/tool_invocation.dart';
import '../storage/chat_storage.dart';

class ChatEventRepository {
  final ChatStorage _storage;

  ChatEventRepository(this._storage);

  Future<int> appendUserMessage({
    required int turnId,
    required int groupId,
    required String content,
  }) {
    return _appendEvent(
      turnId: turnId,
      groupId: groupId,
      eventType: ChatEventType.userMessage,
      role: MessageRole.user,
      content: content,
    );
  }

  Future<int> appendToolResult({
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

  Future<int> appendToolCall({
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

  Future<int> appendToolConfirmation({
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

  Future<int> appendToolExecutionStarted({
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

  Future<int> appendAssistantQuestionPrompt({
    required int turnId,
    required int groupId,
    required AskUserQuestionRequest request,
    required String content,
  }) {
    return _appendEvent(
      turnId: turnId,
      groupId: groupId,
      eventType: ChatEventType.assistantQuestionPrompt,
      role: MessageRole.assistant,
      content: content,
      payloadJson: request.toJson(),
    );
  }

  Future<int> appendUserInteractionResult({
    required int turnId,
    required int groupId,
    required AskUserQuestionResponse response,
    required String content,
  }) {
    return _appendEvent(
      turnId: turnId,
      groupId: groupId,
      eventType: ChatEventType.userInteractionResult,
      role: MessageRole.system,
      content: content,
      payloadJson: response.toJson(),
    );
  }

  Future<int> appendToolError({
    required int turnId,
    required int groupId,
    required String content,
    String? errorCode,
  }) {
    return _appendEvent(
      turnId: turnId,
      groupId: groupId,
      eventType: ChatEventType.toolError,
      role: MessageRole.system,
      content: content,
      status: errorCode,
    );
  }

  Future<int> appendAssistantTextDelta({
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

  Future<int> appendAssistantPlannerMessage({
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

  Future<int> appendAssistantTextFinal({
    required int turnId,
    required int groupId,
    required String content,
  }) {
    return _appendEvent(
      turnId: turnId,
      groupId: groupId,
      eventType: ChatEventType.assistantTextFinal,
      role: MessageRole.assistant,
      content: content,
    );
  }

  Future<int> appendFinalAnswer({
    required int turnId,
    required int groupId,
    required String content,
  }) {
    return _appendEvent(
      turnId: turnId,
      groupId: groupId,
      eventType: ChatEventType.finalAnswer,
      role: MessageRole.assistant,
      content: content,
    );
  }

  Future<int> appendTurnStatus({
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

  Future<int> _appendEvent({
    required int turnId,
    required int groupId,
    required ChatEventType eventType,
    MessageRole? role,
    String? content,
    String? status,
    Map<String, dynamic>? payloadJson,
  }) async {
    final existingEvents = await _storage.getEventsByTurn(turnId);
    final event = ChatEvent(
      turnId: turnId,
      groupId: groupId,
      sequence: existingEvents.length + 1,
      eventType: eventType,
      role: role,
      status: status,
      content: content,
      payloadJson: payloadJson,
    );
    return _storage.insertEvent(event);
  }
}
