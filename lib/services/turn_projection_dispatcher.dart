import 'dart:async';

import 'package:ai_chat/models/chat_event.dart';
import 'package:ai_chat/models/debug/streaming_trace_snapshot.dart';
import 'package:ai_chat/models/llm/streaming_message_event.dart';
import 'package:ai_chat/providers/chat_ui_providers.dart';
import 'package:ai_chat/providers/streaming_trace_providers.dart';
import 'package:ai_chat/services/debug/streaming_trace_recorder.dart';
import 'package:ai_chat/utils/logger.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Serializes runtime preview commits and truth-event commits for one active UI
/// projection pipeline.
///
/// This dispatcher keeps preview clear/final append ordering deterministic:
/// - preview deltas are published in arrival order
/// - `finalAnswer` clears runtime preview first
/// - late preview events for the finalized preview message are dropped
class TurnProjectionDispatcher {
  TurnProjectionDispatcher(this._ref);

  static const _tag = 'TurnProjectionDispatcher';

  final Ref _ref;
  Future<void> _tail = Future<void>.value();
  String? _activePreviewMessageId;
  final Set<String> _finalizedPreviewMessageIds = <String>{};

  Future<void> dispatchPreviewEvent(StreamingMessageEvent event) {
    return _enqueue(() {
      final messageId = event.messageId;
      if (_finalizedPreviewMessageIds.contains(messageId)) {
        Logger.i(
          _tag,
          'drop late preview event for finalized messageId=$messageId type=${event.runtimeType}',
        );
        return;
      }
      final traceId = _readRuntimeMetadataValue(
        event.runtimeMetadata,
        key: 'streamTraceId',
      );
      final turnId = _readRuntimeMetadataValue(
        event.runtimeMetadata,
        key: 'streamTurnId',
      );
      if (traceId != null && turnId != null) {
        _ref.read(streamingTraceRecorderProvider.notifier).recordStage(
          traceId: traceId,
          turnId: turnId,
          stage: StreamingTraceStage.streamEventReceived,
          timestamp: DateTime.now(),
          details: {
            'messageId': messageId,
            'eventType': event.runtimeType.toString(),
          },
        );
      }
      _activePreviewMessageId = messageId;
      _ref.read(runtimeStreamingPreviewStateProvider.notifier).publish(event);
    });
  }

  Future<void> dispatchTruthEvent(
    ChatEvent event,
    Future<void> Function(ChatEvent event) applyTruthEvent,
  ) {
    return _enqueue(() async {
      _recordTruthStage(event);
      if (event.eventType == ChatEventType.finalAnswer) {
        final finalizedMessageId =
            _resolvePreviewMessageIdForFinalAnswer(event) ?? _activePreviewMessageId;
        final finalizedTraceId = streamingTraceIdForTurn(event.turnId);
        if (finalizedMessageId != null) {
          _finalizedPreviewMessageIds.add(finalizedMessageId);
        }
        _ref.read(runtimeStreamingPreviewStateProvider.notifier).clear();
        _activePreviewMessageId = null;
        if (finalizedTraceId.isNotEmpty) {
          _ref.read(streamingTraceRecorderProvider.notifier).recordStage(
            traceId: finalizedTraceId,
            turnId: event.turnId.toString(),
            stage: StreamingTraceStage.finalTakeover,
            timestamp: DateTime.now(),
            details: {
              'eventType': event.eventType.name,
              'previewText': event.content ?? '',
              if (finalizedMessageId != null)
                'previewMessageId': finalizedMessageId,
            },
          );
          _ref.read(streamingTraceRecorderProvider.notifier).markCompleted(
                traceId: finalizedTraceId,
                takeoverAt: DateTime.now(),
              );
        }
      }
      await applyTruthEvent(event);
    });
  }

  void _recordTruthStage(ChatEvent event) {
    final recorder = _ref.read(streamingTraceRecorderProvider.notifier);
    final traceId = streamingTraceIdForTurn(event.turnId);
    final timestamp = event.createdAt;
    final payload = event.payloadJson;
    switch (event.eventType) {
      case ChatEventType.assistantToolCall:
      case ChatEventType.assistantToolConfirmation:
      case ChatEventType.toolExecutionStarted:
        final toolName = _readToolName(payload);
        if (toolName == null) {
          return;
        }
        recorder.recordStage(
          traceId: traceId,
          turnId: event.turnId.toString(),
          stage: StreamingTraceStage.toolCallStarted,
          timestamp: timestamp,
          details: {
            'toolName': toolName,
          },
        );
        return;
      case ChatEventType.toolResult:
        final toolName = _readToolName(payload);
        if (toolName == null) {
          return;
        }
        recorder.recordStage(
          traceId: traceId,
          turnId: event.turnId.toString(),
          stage: StreamingTraceStage.toolCallCompleted,
          timestamp: timestamp,
          details: {
            'toolName': toolName,
          },
        );
        return;
      case ChatEventType.toolError:
        final toolName = _readToolName(payload);
        if (toolName == null) {
          return;
        }
        recorder.recordStage(
          traceId: traceId,
          turnId: event.turnId.toString(),
          stage: StreamingTraceStage.toolCallFailed,
          timestamp: timestamp,
          details: {
            'toolName': toolName,
          },
        );
        return;
      case ChatEventType.userMessage:
      case ChatEventType.assistantPlannerMessage:
      case ChatEventType.assistantReasoningDelta:
      case ChatEventType.assistantTextDelta:
      case ChatEventType.assistantTextFinal:
      case ChatEventType.assistantQuestionPrompt:
      case ChatEventType.assistantTurnSnapshot:
      case ChatEventType.userInteractionResult:
      case ChatEventType.turnStatus:
      case ChatEventType.finalAnswer:
      case ChatEventType.error:
        return;
    }
  }

  Future<void> clearRuntimePreview() {
    return _enqueue(() {
      final snapshot = _ref.read(streamingTraceSnapshotProvider);
      if (snapshot != null &&
          snapshot.status == StreamingTraceLifecycleStatus.running) {
        _ref.read(streamingTraceRecorderProvider.notifier).markAborted(
              traceId: snapshot.traceId,
            );
      }
      _activePreviewMessageId = null;
      _ref.read(runtimeStreamingPreviewStateProvider.notifier).clear();
    });
  }

  String? _resolvePreviewMessageIdForFinalAnswer(ChatEvent event) {
    final payload = event.payloadJson;
    final value = payload?['previewMessageId'];
    if (value is String && value.trim().isNotEmpty) {
      return value.trim();
    }
    return null;
  }

  String? _readToolName(Map<String, dynamic>? payload) {
    final value = payload?['toolName'];
    if (value is! String) {
      return null;
    }
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  Future<void> _enqueue(FutureOr<void> Function() operation) {
    final next = _tail.then((_) => operation());
    _tail = next.catchError((_) {});
    return next;
  }

  String? _readRuntimeMetadataValue(
    Map<String, dynamic>? metadata, {
    required String key,
  }) {
    final value = metadata?[key];
    if (value is! String) {
      return null;
    }
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }
}
