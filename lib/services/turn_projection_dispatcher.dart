import 'dart:async';

import 'package:ai_chat/models/chat_event.dart';
import 'package:ai_chat/models/llm/streaming_message_event.dart';
import 'package:ai_chat/providers/chat_ui_providers.dart';
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
      _activePreviewMessageId = messageId;
      _ref.read(runtimeStreamingPreviewStateProvider.notifier).publish(event);
    });
  }

  Future<void> dispatchTruthEvent(
    ChatEvent event,
    Future<void> Function(ChatEvent event) applyTruthEvent,
  ) {
    return _enqueue(() async {
      if (event.eventType == ChatEventType.finalAnswer) {
        final finalizedMessageId =
            _resolvePreviewMessageIdForFinalAnswer(event) ?? _activePreviewMessageId;
        if (finalizedMessageId != null) {
          _finalizedPreviewMessageIds.add(finalizedMessageId);
        }
        _ref.read(runtimeStreamingPreviewStateProvider.notifier).clear();
        _activePreviewMessageId = null;
      }
      await applyTruthEvent(event);
    });
  }

  Future<void> clearRuntimePreview() {
    return _enqueue(() {
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

  Future<void> _enqueue(FutureOr<void> Function() operation) {
    final next = _tail.then((_) => operation());
    _tail = next.catchError((_) {});
    return next;
  }
}
