import 'dart:async';

import 'package:ai_chat/models/chat_event.dart';
import 'package:ai_chat/models/chat/assistant_turn_block.dart';
import 'package:ai_chat/models/chat/chat_attachment.dart';
import 'package:ai_chat/models/chat/runtime_assistant_draft.dart';
import 'package:ai_chat/models/chat/runtime_streaming_preview_state.dart';
import 'package:ai_chat/models/chat_message.dart';
import 'package:ai_chat/models/llm/adapters/adapter_utils.dart';
import 'package:ai_chat/models/llm/streaming_message_event.dart';
import 'package:ai_chat/models/response/message_content_type.dart';
import 'package:ai_chat/models/tool/tool_invocation.dart';
import 'package:ai_chat/providers/chat_collection_providers.dart';
import 'package:ai_chat/providers/chat_dependency_providers.dart';
import 'package:ai_chat/providers/chat_send_state_providers.dart';
import 'package:ai_chat/providers/chat_ui_providers.dart';
import 'package:ai_chat/services/attachments/chat_attachment_storage_service.dart';
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
        _hooks = hooks {
    _runtimePreviewSubscription = _ref.listen<RuntimeStreamingPreviewState>(
      runtimeStreamingPreviewStateProvider,
      (previous, next) {
        unawaited(_handleRuntimePreviewStateChanged(next));
      },
      fireImmediately: true,
    );
  }

  final Ref _ref;
  final int _groupId;
  final String _traceTurnId;
  final int? _agentTurnId;
  final AgentEventHooks _hooks;

  _AssistantDraftStage? _assistantDraftStage;
  int? _toolUseReasoningMessageId;
  ChatMessage? _toolUseReasoningMessage;
  bool _hasPendingConfirmation = false;
  bool _receivedFinalAnswer = false;
  bool _responseOwnedByRuntimePreview = false;
  String? _latestRuntimePreviewResponseText;
  bool _disposed = false;
  ProviderSubscription<RuntimeStreamingPreviewState>?
      _runtimePreviewSubscription;

  /// Whether the most recent [ChatEventType.assistantToolConfirmation] has
  /// not yet been resolved. Callers use this to decide the phase to fall back
  /// to on stream completion.
  bool get hasPendingConfirmation => _hasPendingConfirmation;

  /// Whether a final answer event has already been projected into the UI.
  bool get receivedFinalAnswer => _receivedFinalAnswer;

  /// Legacy placeholder integration has been retired; callers should not
  /// expect an in-flight assistant row id here anymore.
  int? get assistantMessageId => null;

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
    _runtimePreviewSubscription?.close();
    _runtimePreviewSubscription = null;
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
    final attachments = await _generatedImageAttachmentsFromToolResult(
      payloadJson,
    );
    final message = ChatMessage(
      text: event.content ?? fallbackText,
      role: MessageRole.assistant,
      status: MessageStatus.completed,
      contentType: MessageContentType.toolResult,
      payloadJson: payloadJson,
      attachments: attachments,
    );
    final id = await dbHelper.insertMessage(message, _groupId);
    message.id = id;
    if (attachments.isNotEmpty) {
      await dbHelper.insertMessageAttachments(id, attachments);
    }
    _ref.read(messagesProvider.notifier).addMessage(message);
  }

  Future<List<ChatAttachment>> _generatedImageAttachmentsFromToolResult(
    Map<String, dynamic>? payloadJson,
  ) async {
    if (payloadJson?['toolName'] != 'generate_image') {
      return const <ChatAttachment>[];
    }
    final data = payloadJson?['data'];
    if (data is! Map) {
      return const <ChatAttachment>[];
    }
    final images = data['generatedImages'];
    if (images is! List) {
      return const <ChatAttachment>[];
    }
    final model = data['model']?.toString().trim();
    final prompt = data['prompt']?.toString().trim();
    final attachmentStorage = _ref.read(chatAttachmentStorageServiceProvider);
    if (attachmentStorage == null) {
      return const <ChatAttachment>[];
    }

    final attachments = <ChatAttachment>[];
    for (final rawItem in images.whereType<Map>()) {
      final item = Map<String, dynamic>.from(rawItem);
      final dataUrl = item['dataUrl']?.toString().trim() ?? '';
      if (dataUrl.isEmpty) {
        continue;
      }
      final localId = item['localId']?.toString().trim();
      final fileName = item['fileName']?.toString().trim();
      final mimeType = item['mimeType']?.toString().trim();
      final attachment = await attachmentStorage.persistGeneratedImageDataUrl(
        localId: localId?.isNotEmpty == true
            ? localId!
            : 'generated-image-${DateTime.now().microsecondsSinceEpoch}',
        fileName: fileName?.isNotEmpty == true ? fileName! : 'generated.png',
        mimeType: mimeType?.isNotEmpty == true ? mimeType! : 'image/png',
        dataUrl: dataUrl,
        providerFileRefJson: {
          if (model != null && model.isNotEmpty) 'model': model,
          if (prompt != null && prompt.isNotEmpty) 'prompt': prompt,
          if (item['revisedPrompt'] is String)
            'revised_prompt': (item['revisedPrompt'] as String).trim(),
        },
      );
      attachments.add(attachment);
    }
    return attachments;
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
    if (_currentTurnHasVisibleRuntimePreviewResponse()) {
      _responseOwnedByRuntimePreview = true;
      _ref.read(chatSendStateProvider.notifier).update(
            isGenerating: true,
            phase: ChatSendPhase.streamingResponse,
          );
      return;
    }
    _ref.read(chatSendStateProvider.notifier).update(
          isGenerating: true,
          phase: ChatSendPhase.streamingResponse,
        );
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
        payloadJson: event.payloadJson,
      );
      return;
    }

    _assistantDraftStage ??= _AssistantDraftStage.reasoning;

    final draft = _ref.read(runtimeAssistantDraftProvider);
    final now = DateTime.now();
    final nextPayload = _withIdentity({
      'draftStage': 'reasoning',
      if (reasoningScope != null) 'reasoningScope': reasoningScope,
      if ((event.payloadJson?['logicalId'] ?? '').toString().trim().isNotEmpty)
        'logicalId': event.payloadJson!['logicalId'],
      if ((event.payloadJson?['previewMessageId'] ?? '')
          .toString()
          .trim()
          .isNotEmpty)
        'previewMessageId': event.payloadJson!['previewMessageId'],
      if ((event.payloadJson?['previewContentBlockId'] ?? '')
          .toString()
          .trim()
          .isNotEmpty)
        'previewContentBlockId': event.payloadJson!['previewContentBlockId'],
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
    final runtimeDraft = _ref.read(runtimeAssistantDraftProvider);
    final finalText = event.content ?? _latestRuntimePreviewResponseText ?? '';

    final message = ChatMessage(
      text: finalText,
      role: MessageRole.assistant,
      status: MessageStatus.completed,
      reasoningContent: _resolvedFinalAnswerReasoning(runtimeDraft),
      // Distinguish the genuine terminal answer from intermediate planner
      // messages. `ChatBlockBuilder` reads this to scope the `logicalId`
      // dedup contract so a mid-turn planner message cannot block the
      // streaming preview of a later iteration's final answer.
      payloadJson: _withIdentity({
        'isFinalAnswer': true,
        if ((event.payloadJson?['logicalId'] ?? '')
            .toString()
            .trim()
            .isNotEmpty)
          'logicalId': event.payloadJson!['logicalId'],
        if ((event.payloadJson?['previewMessageId'] ?? '')
            .toString()
            .trim()
            .isNotEmpty)
          'previewMessageId': event.payloadJson!['previewMessageId'],
        if ((event.payloadJson?['previewContentBlockId'] ?? '')
            .toString()
            .trim()
            .isNotEmpty)
          'previewContentBlockId': event.payloadJson!['previewContentBlockId'],
      }),
    );
    final insertedId = await dbHelper.insertMessage(message, _groupId);
    message.id = insertedId;
    _assistantDraftStage = _AssistantDraftStage.response;
    _ref.read(messagesProvider.notifier).addMessage(message);

    _assistantDraftStage = null;
    _ref.read(runtimeAssistantDraftProvider.notifier).state = null;
    _ref.read(chatSendStateProvider.notifier).update(
          isGenerating: false,
          phase: ChatSendPhase.idle,
        );
  }

  Future<void> _handleRuntimePreviewStateChanged(
    RuntimeStreamingPreviewState state,
  ) async {
    if (_disposed) {
      return;
    }

    final responseText = _resolvePairedRuntimePreviewResponseText(state);
    if (responseText == null) {
      return;
    }
    _latestRuntimePreviewResponseText = responseText;
    if (_responseOwnedByRuntimePreview) {
      return;
    }

    _responseOwnedByRuntimePreview = true;
  }

  bool _currentTurnHasVisibleRuntimePreviewResponse() {
    final responseText = _resolvePairedRuntimePreviewResponseText(
      _ref.read(runtimeStreamingPreviewStateProvider),
    );
    if (responseText == null) {
      return false;
    }
    _latestRuntimePreviewResponseText = responseText;
    return true;
  }

  String? _resolvePairedRuntimePreviewResponseText(
    RuntimeStreamingPreviewState state,
  ) {
    final agentTurnId = _agentTurnId;
    if (agentTurnId == null) {
      return null;
    }
    final matchedMessages = state.messages
        .where((message) => message.streamTurnId?.trim() == '$agentTurnId')
        .toList(growable: false);
    for (final message in matchedMessages.reversed) {
      for (final block in message.blocks.reversed) {
        if (block.blockType != StreamingContentBlockType.text) {
          continue;
        }
        final extraction = extractThinkTaggedText(block.text);
        final content = extraction.content?.trim();
        if (content == null || content.isEmpty) {
          continue;
        }
        return extraction.content;
      }
    }
    return null;
  }

  Future<void> _appendToolUseReasoningMessage({
    required ChatStorage dbHelper,
    required String content,
    required String reasoningScope,
    Map<String, dynamic>? payloadJson,
  }) async {
    if (_toolUseReasoningMessageId != null &&
        _toolUseReasoningMessage != null &&
        _sameToolUseReasoningThread(
          left: _toolUseReasoningMessage!.payloadJson,
          right: payloadJson,
        )) {
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
        if ((payloadJson?['logicalId'] ?? '').toString().trim().isNotEmpty)
          'logicalId': payloadJson!['logicalId'],
        if ((payloadJson?['responseId'] ?? '').toString().trim().isNotEmpty)
          'responseId': payloadJson!['responseId'],
      }),
    );
    final id = await dbHelper.insertMessage(message, _groupId);
    message.id = id;
    _toolUseReasoningMessageId = id;
    _toolUseReasoningMessage = message;
    _ref.read(messagesProvider.notifier).addMessage(message);
  }

  bool _sameToolUseReasoningThread({
    required Map<String, dynamic>? left,
    required Map<String, dynamic>? right,
  }) {
    final leftLogicalId = _trimmedPayloadValue(left, 'logicalId');
    final rightLogicalId = _trimmedPayloadValue(right, 'logicalId');
    if (leftLogicalId != null || rightLogicalId != null) {
      return leftLogicalId != null &&
          rightLogicalId != null &&
          leftLogicalId == rightLogicalId;
    }
    final leftResponseId = _trimmedPayloadValue(left, 'responseId');
    final rightResponseId = _trimmedPayloadValue(right, 'responseId');
    if (leftResponseId != null || rightResponseId != null) {
      return leftResponseId != null &&
          rightResponseId != null &&
          leftResponseId == rightResponseId;
    }
    return false;
  }

  String? _trimmedPayloadValue(Map<String, dynamic>? payload, String key) {
    final value = payload?[key];
    if (value is! String) {
      return null;
    }
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
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
  }

  String _runtimeTurnId() {
    return '${_groupId}_runtime_${_agentTurnId ?? _traceTurnId.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_')}';
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
}

enum _AssistantDraftStage {
  reasoning,
  response,
}
