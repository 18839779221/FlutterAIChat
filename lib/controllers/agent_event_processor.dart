import 'dart:async';

import 'package:ai_chat/models/chat_event.dart';
import 'package:ai_chat/models/chat_message.dart';
import 'package:ai_chat/models/response/message_content_type.dart';
import 'package:ai_chat/models/tool/tool_invocation.dart';
import 'package:ai_chat/providers/chat_collection_providers.dart';
import 'package:ai_chat/providers/chat_dependency_providers.dart';
import 'package:ai_chat/providers/chat_send_state_providers.dart';
import 'package:ai_chat/services/assistant_stream_output_buffer.dart';
import 'package:ai_chat/storage/chat_storage.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'chat_send_coordinator.dart' show traceTurnIdPayloadKey;

/// Hooks that let the three ChatEvent-consuming paths
/// (`sendMessage` / `submitQuestionAnswers` / `resumeAgentLoopConfirmation`)
/// customise behaviour without duplicating the switch-case.
///
/// - `onFinalAnswer` / `onAssistantToolConfirmation` run **after** the default
///   behaviour. They are only used for side effects (trace records,
///   scheduleAutoSummary). They cannot suppress the default.
/// - `onUserInteractionResult` / `transformFirstToolExecution` run **before**
///   the default. Returning `true` means the hook fully handled the event and
///   the processor will skip its default handling.
class AgentEventHooks {
  const AgentEventHooks({
    this.onFinalAnswer,
    this.onAssistantToolConfirmation,
    this.onUserInteractionResult,
    this.transformFirstToolExecution,
  });

  final FutureOr<void> Function(ChatEvent event)? onFinalAnswer;
  final FutureOr<void> Function(ChatEvent event)? onAssistantToolConfirmation;
  final FutureOr<bool> Function(ChatEvent event)? onUserInteractionResult;
  final FutureOr<bool> Function(ChatEvent event)? transformFirstToolExecution;
}

/// Consumes a `ChatEvent` stream from [TurnHarness] and keeps
/// `messagesProvider` / `chatSendStateProvider` / the underlying DB in sync.
///
/// Holds per-turn assistant state (`_assistantMessageId` /
/// `_assistantStreamBuffer`) so callers no longer need to replicate it.
///
/// Behaviour is the union of the three call sites. Path-specific differences
/// are injected through [AgentEventHooks]. See the design doc at
/// `docs/superpowers/specs/2026-04-24-chat-send-coordinator-event-dispatcher-design.md`.
class AgentEventProcessor {
  AgentEventProcessor({
    required Ref ref,
    required int groupId,
    required String traceTurnId,
    int? agentTurnId,
    AgentEventHooks hooks = const AgentEventHooks(),
  })  : _ref = ref,
        _groupId = groupId,
        _traceTurnId = traceTurnId,
        _agentTurnId = agentTurnId,
        _hooks = hooks;

  final Ref _ref;
  final int _groupId;
  final String _traceTurnId;
  final int? _agentTurnId;
  final AgentEventHooks _hooks;

  int? _assistantMessageId;
  ChatMessage? _assistantMessage;
  AssistantStreamOutputBuffer? _assistantStreamBuffer;
  bool _hasPendingConfirmation = false;
  bool _receivedFinalAnswer = false;
  bool _disposed = false;

  /// Whether the most recent [ChatEventType.assistantToolConfirmation] has
  /// not yet been resolved. Callers use this to decide the phase to fall back
  /// to on stream completion.
  bool get hasPendingConfirmation => _hasPendingConfirmation;

  /// Whether a final answer event has already been projected into the UI.
  bool get receivedFinalAnswer => _receivedFinalAnswer;

  /// The DB row id of the current assistant message placeholder, if any. Used
  /// by the `sendMessage` path to attach failure text on stream error.
  int? get assistantMessageId => _assistantMessageId;

  /// Dispatch a single event from the harness stream. Must be awaited to
  /// preserve DB/State insertion ordering.
  Future<void> handle(ChatEvent event) async {
    if (_disposed) {
      return;
    }
    final dbHelper = _ref.read(databaseProvider);
    switch (event.eventType) {
      case ChatEventType.userMessage:
      case ChatEventType.assistantTextFinal:
      case ChatEventType.error:
      case ChatEventType.assistantReasoningDelta:
        return;
      case ChatEventType.turnStatus:
        if (_isTerminalFailureStatus(event.content)) {
          _ref.read(chatSendStateProvider.notifier).update(
                isGenerating: false,
                phase: ChatSendPhase.idle,
              );
        }
        return;
      case ChatEventType.assistantPlannerMessage:
        await _insertPlainAssistant(
          dbHelper: dbHelper,
          text: event.content ?? '',
          payloadJson: _withIdentity(event.payloadJson),
        );
        return;
      case ChatEventType.assistantToolCall:
        await _insertStructuredAssistant(
          dbHelper: dbHelper,
          text: event.content ?? '准备执行工具',
          contentType: MessageContentType.toolInvocation,
          payloadJson: _withIdentity(event.payloadJson),
        );
        return;
      case ChatEventType.assistantToolConfirmation:
        _hasPendingConfirmation = true;
        _ref.read(chatSendStateProvider.notifier).update(
              isGenerating: false,
              phase: ChatSendPhase.awaitingConfirmation,
            );
        final payload = {
          ...?event.payloadJson,
          'status': ToolInvocationStatus.awaitingConfirmation.name,
          'summary': event.content ?? '准备执行工具',
          'requiresConfirmation': true,
          ..._identityFields(),
        };
        await _insertStructuredAssistant(
          dbHelper: dbHelper,
          text: event.content ?? '准备执行工具',
          contentType: MessageContentType.actionConfirmation,
          payloadJson: payload,
        );
        final onConfirm = _hooks.onAssistantToolConfirmation;
        if (onConfirm != null) {
          await onConfirm(event);
        }
        return;
      case ChatEventType.assistantQuestionPrompt:
        _ref.read(chatSendStateProvider.notifier).update(
              isGenerating: false,
              phase: ChatSendPhase.idle,
            );
        await _insertStructuredAssistant(
          dbHelper: dbHelper,
          text: event.content ?? '请先回答几个问题',
          contentType: MessageContentType.askUserQuestionPrompt,
          payloadJson: _withIdentity(event.payloadJson),
        );
        return;
      case ChatEventType.toolExecutionStarted:
        final hook = _hooks.transformFirstToolExecution;
        if (hook != null) {
          final handled = await hook(event);
          if (handled) {
            _ref.read(chatSendStateProvider.notifier).setPhase(
                  ChatSendPhase.executingTool,
                );
            return;
          }
        }
        _ref.read(chatSendStateProvider.notifier).setPhase(
              ChatSendPhase.executingTool,
            );
        await _insertStructuredAssistant(
          dbHelper: dbHelper,
          text: event.content ?? '正在执行工具',
          contentType: MessageContentType.toolInvocation,
          payloadJson: _withIdentity(event.payloadJson),
        );
        return;
      case ChatEventType.toolResult:
        await _appendToolResultMessage(
          dbHelper: dbHelper,
          event: event,
          fallbackText: '',
          payloadJson: event.payloadJson,
        );
        return;
      case ChatEventType.userInteractionResult:
        final hook = _hooks.onUserInteractionResult;
        if (hook != null) {
          final handled = await hook(event);
          if (handled) {
            return;
          }
        }
        await _insertStructuredAssistant(
          dbHelper: dbHelper,
          text: event.content ?? '',
          contentType: MessageContentType.askUserQuestionResult,
          payloadJson: _withIdentity(event.payloadJson),
        );
        return;
      case ChatEventType.toolError:
        await _appendToolResultMessage(
          dbHelper: dbHelper,
          event: event,
          fallbackText: '工具执行失败',
          payloadJson: _buildToolFailurePayload(event),
        );
        return;
      case ChatEventType.assistantTextDelta:
        await _onAssistantTextDelta(dbHelper: dbHelper, event: event);
        return;
      case ChatEventType.finalAnswer:
        await _onFinalAnswer(dbHelper: dbHelper, event: event);
        final onFinal = _hooks.onFinalAnswer;
        if (onFinal != null) {
          await onFinal(event);
        }
        return;
    }
  }

  /// Release the stream buffer. Idempotent; safe to call from onError/onDone
  /// and from a `finally`.
  Future<void> dispose() async {
    if (_disposed) {
      return;
    }
    _disposed = true;
    await _assistantStreamBuffer?.cancel();
    _assistantStreamBuffer?.dispose();
    _assistantStreamBuffer = null;
  }

  // --- Private helpers ------------------------------------------------------

  Map<String, dynamic> _identityFields() {
    return {
      if (_agentTurnId != null) 'agentTurnId': _agentTurnId,
      traceTurnIdPayloadKey: _traceTurnId,
    };
  }

  Map<String, dynamic> _withIdentity(Map<String, dynamic>? base) {
    return {
      ...?base,
      ..._identityFields(),
    };
  }

  Future<void> _insertPlainAssistant({
    required ChatStorage dbHelper,
    required String text,
    required Map<String, dynamic>? payloadJson,
  }) async {
    final message = ChatMessage(
      text: text,
      role: MessageRole.assistant,
      status: MessageStatus.completed,
      payloadJson: payloadJson,
    );
    final id = await dbHelper.insertMessage(message, _groupId);
    message.id = id;
    _ref.read(messagesProvider.notifier).addMessage(message);
  }

  Future<void> _insertStructuredAssistant({
    required ChatStorage dbHelper,
    required String text,
    required MessageContentType contentType,
    required Map<String, dynamic>? payloadJson,
  }) async {
    final message = ChatMessage(
      text: text,
      role: MessageRole.assistant,
      status: MessageStatus.completed,
      contentType: contentType,
      payloadJson: payloadJson,
    );
    final id = await dbHelper.insertMessage(message, _groupId);
    message.id = id;
    _ref.read(messagesProvider.notifier).addMessage(message);
  }

  Future<void> _appendToolResultMessage({
    required ChatStorage dbHelper,
    required ChatEvent event,
    required String fallbackText,
    required Map<String, dynamic>? payloadJson,
  }) async {
    final message = ChatMessage(
      text: event.content ?? fallbackText,
      role: MessageRole.assistant,
      status: MessageStatus.completed,
      contentType: MessageContentType.toolResult,
      payloadJson: payloadJson,
    );
    final id = await dbHelper.insertMessage(message, _groupId);
    message.id = id;
    _ref.read(messagesProvider.notifier).addMessage(message);
  }

  Map<String, dynamic> _buildToolFailurePayload(ChatEvent event) {
    return {
      ...?event.payloadJson,
      'status': event.payloadJson?['status'] ?? 'failure',
      'errorMessage':
          event.payloadJson?['errorMessage'] ?? event.status ?? 'unknown_error',
    };
  }

  Future<void> _onAssistantTextDelta({
    required ChatStorage dbHelper,
    required ChatEvent event,
  }) async {
    if (_assistantMessageId == null) {
      final placeholder = ChatMessage(
        text: '',
        role: MessageRole.assistant,
        status: MessageStatus.generating,
      );
      _assistantMessageId =
          await dbHelper.insertMessage(placeholder, _groupId);
      placeholder.id = _assistantMessageId;
      _assistantMessage = placeholder;
      _ref.read(messagesProvider.notifier).addMessage(placeholder);
    }
    _ref.read(chatSendStateProvider.notifier).update(
          isGenerating: true,
          phase: ChatSendPhase.streamingResponse,
        );
    final activeId = _assistantMessageId!;
    final activeMessage = _assistantMessage!;
    _assistantStreamBuffer ??= _createAssistantStreamBuffer(
      messageId: activeId,
      message: activeMessage,
      dbHelper: dbHelper,
    );
    _assistantStreamBuffer!.onDelta(event.content ?? '');
  }

  Future<void> _onFinalAnswer({
    required ChatStorage dbHelper,
    required ChatEvent event,
  }) async {
    _receivedFinalAnswer = true;
    if (_assistantMessageId == null) {
      final message = ChatMessage(
        text: event.content ?? '',
        role: MessageRole.assistant,
        status: MessageStatus.completed,
      );
      _assistantMessageId = await dbHelper.insertMessage(message, _groupId);
      message.id = _assistantMessageId;
      _assistantMessage = message;
      _ref.read(messagesProvider.notifier).addMessage(message);
    } else {
      final id = _assistantMessageId!;
      await _finalizeAssistantText(
        buffer: _assistantStreamBuffer,
        messageId: id,
        message: _assistantMessage,
        dbHelper: dbHelper,
        fallbackText: event.content ?? _assistantMessage?.text ?? '',
        explicitText: event.content,
      );
      _ref
          .read(messagesProvider.notifier)
          .updateMessageStatus(id, MessageStatus.completed);
      await dbHelper.updateMessageStatus(id, MessageStatus.completed);
    }
    _assistantStreamBuffer?.dispose();
    _assistantStreamBuffer = null;
    _ref.read(chatSendStateProvider.notifier).update(
          isGenerating: false,
          phase: ChatSendPhase.idle,
        );
  }

  bool _isTerminalFailureStatus(String? status) {
    switch (status) {
      case 'max_iterations_reached':
      case 'max_tool_calls_reached':
      case 'max_duration_reached':
      case 'planner_no_terminal_decision':
        return true;
      default:
        return false;
    }
  }

  AssistantStreamOutputBuffer _createAssistantStreamBuffer({
    required int messageId,
    required ChatMessage message,
    required ChatStorage dbHelper,
  }) {
    return AssistantStreamOutputBuffer(
      onUiFlush: (text) {
        message.text = text;
        _ref.read(messagesProvider.notifier).updateMessage(messageId, text);
      },
      onPersistFlush: (text) async {
        message.text = text;
        await dbHelper.updateMessage(messageId, text);
      },
      uiFlushInterval: const Duration(milliseconds: 16),
    );
  }

  Future<String> _finalizeAssistantText({
    required AssistantStreamOutputBuffer? buffer,
    required int messageId,
    required ChatMessage? message,
    required ChatStorage dbHelper,
    required String fallbackText,
    String? explicitText,
  }) async {
    await buffer?.finish();
    final finalText = explicitText ?? buffer?.fullText ?? fallbackText;
    if (message != null && message.text != finalText) {
      message.text = finalText;
      _ref.read(messagesProvider.notifier).updateMessage(messageId, finalText);
      await dbHelper.updateMessage(messageId, finalText);
    }
    return finalText;
  }
}
