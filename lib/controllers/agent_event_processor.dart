import 'dart:async';

import 'package:ai_chat/models/chat_event.dart';
import 'package:ai_chat/models/chat/assistant_turn_block.dart';
import 'package:ai_chat/models/chat/runtime_assistant_draft.dart';
import 'package:ai_chat/models/chat_message.dart';
import 'package:ai_chat/models/response/message_content_type.dart';
import 'package:ai_chat/models/tool/tool_invocation.dart';
import 'package:ai_chat/providers/chat_collection_providers.dart';
import 'package:ai_chat/providers/chat_dependency_providers.dart';
import 'package:ai_chat/providers/chat_send_state_providers.dart';
import 'package:ai_chat/providers/chat_ui_providers.dart';
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

  _AssistantDraftStage? _assistantDraftStage;
  int? _assistantMessageId;
  ChatMessage? _assistantMessage;
  int? _toolUseReasoningMessageId;
  ChatMessage? _toolUseReasoningMessage;
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
    await _ref.read(turnProjectionDispatcherProvider).dispatchTruthEvent(
      event,
      _handleTruthEvent,
    );
  }

  Future<void> _handleTruthEvent(ChatEvent event) async {
    final dbHelper = _ref.read(databaseProvider);
    if (event.eventType != ChatEventType.assistantReasoningDelta) {
      _toolUseReasoningMessageId = null;
      _toolUseReasoningMessage = null;
    }
    switch (event.eventType) {
      case ChatEventType.userMessage:
      case ChatEventType.assistantTextFinal:
      case ChatEventType.error:
        return;
      case ChatEventType.contextCompacted:
        await _insertSystemMarker(
          dbHelper: dbHelper,
          text: event.content ?? '已压缩历史上下文',
          contentType: MessageContentType.contextBoundary,
          payloadJson: _withIdentity(event.payloadJson),
        );
        return;
      case ChatEventType.assistantReasoningDelta:
        await _onAssistantReasoningDelta(dbHelper: dbHelper, event: event);
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
      case ChatEventType.assistantTurnSnapshot:
        // Round-trip-only event; UI processor has no work to do here.
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
    await _ref.read(turnProjectionDispatcherProvider).clearRuntimePreview();
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

  Future<void> _insertSystemMarker({
    required ChatStorage dbHelper,
    required String text,
    required MessageContentType contentType,
    required Map<String, dynamic>? payloadJson,
  }) async {
    final message = ChatMessage(
      text: text,
      role: MessageRole.system,
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
    _ensureAssistantDraftStage(_AssistantDraftStage.response);
    final hasRuntimePreview = _ref
        .read(runtimeStreamingPreviewStateProvider)
        .messages
        .isNotEmpty;
    if (!hasRuntimePreview && _assistantMessageId == null) {
      final placeholder = ChatMessage(
        text: '',
        role: MessageRole.assistant,
        status: MessageStatus.generating,
        payloadJson: _withIdentity(const {
          'draftStage': 'response',
        }),
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
    final activeId = _assistantMessageId;
    final activeMessage = _assistantMessage;
    if (activeId == null || activeMessage == null) {
      return;
    }
    _assistantStreamBuffer ??= _createAssistantStreamBuffer(
      messageId: activeId,
      message: activeMessage,
      dbHelper: dbHelper,
    );
    _assistantStreamBuffer!.onDelta(event.content ?? '');
  }

  Future<void> _onAssistantReasoningDelta({
    required ChatStorage dbHelper,
    required ChatEvent event,
  }) async {
    final content = event.content ?? '';
    if (content.isEmpty) {
      return;
    }

    final reasoningScope = event.payloadJson?['scope']?.toString();
    if (reasoningScope == 'tool_use') {
      await _appendToolUseReasoningMessage(
        dbHelper: dbHelper,
        content: content,
        reasoningScope: reasoningScope!,
      );
      return;
    }

    _assistantDraftStage ??= _AssistantDraftStage.reasoning;

    if (_assistantDraftStage == _AssistantDraftStage.response &&
        _assistantMessageId != null) {
      final activeId = _assistantMessageId!;
      final activeMessage = _assistantMessage!;
      _ref.read(messagesProvider.notifier).appendReasoningToMessage(
            activeId,
            content,
          );
      await dbHelper.updateMessageReasoning(
        activeId,
        activeMessage.reasoningContent,
      );
      return;
    }

    if (_assistantDraftStage != _AssistantDraftStage.reasoning) {
      _assistantDraftStage = _AssistantDraftStage.reasoning;
    }

    if (_assistantMessageId != null) {
      final id = _assistantMessageId!;
      _ref.read(messagesProvider.notifier).deleteMessageById(id);
      await dbHelper.deleteMessage(id);
      _assistantMessageId = null;
      _assistantMessage = null;
      await _assistantStreamBuffer?.cancel();
      _assistantStreamBuffer?.dispose();
      _assistantStreamBuffer = null;
    }

    final draft = _ref.read(runtimeAssistantDraftProvider);
    final now = DateTime.now();
    final nextPayload = _withIdentity({
      'draftStage': 'reasoning',
      if (reasoningScope != null) 'reasoningScope': reasoningScope,
    });
    if (draft == null || draft.turnId != _runtimeTurnId()) {
      _ref.read(runtimeAssistantDraftProvider.notifier).state =
          RuntimeAssistantDraft(
        turnId: _runtimeTurnId(),
        draftId: '${_runtimeTurnId()}-reasoning-draft',
        blockType: AssistantTurnBlockType.analysis,
        createdAt: now,
        updatedAt: now,
        reasoningText: content,
        payload: nextPayload,
      );
    } else {
      _ref.read(runtimeAssistantDraftProvider.notifier).state = draft.copyWith(
        updatedAt: now,
        reasoningText: '${draft.reasoningText ?? ''}$content',
        payload: {
          ...?draft.payload,
          ...nextPayload,
        },
      );
    }
  }

  Future<void> _onFinalAnswer({
    required ChatStorage dbHelper,
    required ChatEvent event,
  }) async {
    _receivedFinalAnswer = true;
    final previousAssistantMessageId = _assistantMessageId;
    final previousAssistantMessage = _assistantMessage;
    final runtimeDraft = _ref.read(runtimeAssistantDraftProvider);
    final finalText = previousAssistantMessageId == null
        ? (event.content ?? previousAssistantMessage?.text ?? '')
        : await _finalizeAssistantText(
            buffer: _assistantStreamBuffer,
            messageId: previousAssistantMessageId,
            message: previousAssistantMessage,
            dbHelper: dbHelper,
            fallbackText: event.content ?? previousAssistantMessage?.text ?? '',
            explicitText: event.content,
          );

    if (previousAssistantMessageId != null) {
      _ref
          .read(messagesProvider.notifier)
          .deleteMessageById(previousAssistantMessageId);
      await dbHelper.deleteMessage(previousAssistantMessageId);
    }

    final message = ChatMessage(
      text: finalText,
      role: MessageRole.assistant,
      status: MessageStatus.completed,
      reasoningContent: previousAssistantMessage?.reasoningContent ??
          _resolvedFinalAnswerReasoning(runtimeDraft),
      // Distinguish the genuine terminal answer from intermediate planner
      // messages. `ChatBlockBuilder` reads this to scope the `logicalId`
      // dedup contract so a mid-turn planner message cannot block the
      // streaming preview of a later iteration's final answer.
      payloadJson: const {'isFinalAnswer': true},
    );
    final insertedId = await dbHelper.insertMessage(message, _groupId);
    message.id = insertedId;
    _assistantDraftStage = _AssistantDraftStage.response;
    _assistantMessageId = insertedId;
    _assistantMessage = message;
    _ref.read(messagesProvider.notifier).addMessage(message);

    _assistantStreamBuffer?.dispose();
    _assistantStreamBuffer = null;
    _assistantDraftStage = null;
    _ref.read(runtimeAssistantDraftProvider.notifier).state = null;
    _ref.read(chatSendStateProvider.notifier).update(
          isGenerating: false,
          phase: ChatSendPhase.idle,
        );
  }

  Future<void> _appendToolUseReasoningMessage({
    required ChatStorage dbHelper,
    required String content,
    required String reasoningScope,
  }) async {
    if (_toolUseReasoningMessageId != null && _toolUseReasoningMessage != null) {
      final message = _toolUseReasoningMessage!;
      _ref
          .read(messagesProvider.notifier)
          .appendReasoningToMessage(_toolUseReasoningMessageId!, content);
      await dbHelper.updateMessageReasoning(
        _toolUseReasoningMessageId!,
        message.reasoningContent,
      );
      return;
    }

    final message = ChatMessage(
      text: '',
      role: MessageRole.assistant,
      status: MessageStatus.completed,
      reasoningContent: content,
      payloadJson: _withIdentity({
        'reasoningScope': reasoningScope,
      }),
    );
    final id = await dbHelper.insertMessage(message, _groupId);
    message.id = id;
    _toolUseReasoningMessageId = id;
    _toolUseReasoningMessage = message;
    _ref.read(messagesProvider.notifier).addMessage(message);
  }

  String? _resolvedFinalAnswerReasoning(RuntimeAssistantDraft? runtimeDraft) {
    if (runtimeDraft == null) {
      return null;
    }
    if (runtimeDraft.payload?['reasoningScope'] == 'tool_use') {
      return null;
    }
    return runtimeDraft.reasoningText;
  }

  void _ensureAssistantDraftStage(_AssistantDraftStage stage) {
    if (_assistantDraftStage == stage) {
      return;
    }
    _assistantDraftStage = stage;
    if (stage == _AssistantDraftStage.response &&
        _assistantMessage != null &&
        _assistantMessageId == null) {
      _assistantMessage = null;
    }
  }

  String _runtimeTurnId() {
    return '${_groupId}_runtime_${
        _agentTurnId ?? _traceTurnId.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_')
      }';
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

enum _AssistantDraftStage {
  reasoning,
  response,
}
