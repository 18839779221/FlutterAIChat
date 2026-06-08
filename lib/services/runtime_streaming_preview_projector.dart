import 'package:ai_chat/models/chat/runtime_streaming_preview_state.dart';
import 'package:ai_chat/models/llm/streaming_message_event.dart';
import 'package:ai_chat/utils/logger.dart';

/// Folds streaming preview events into one runtime-only read model.
class RuntimeStreamingPreviewProjector {
  RuntimeStreamingPreviewProjector({
    RuntimeStreamingPreviewState initialState =
        const RuntimeStreamingPreviewState(),
    void Function(
      RuntimeStreamingPreviewMessage message,
      StreamingMessageEvent event,
      DateTime timestamp,
    )? onEventConsumed,
  })  : _state = initialState,
        _onEventConsumed = onEventConsumed;

  RuntimeStreamingPreviewState _state;
  final void Function(
    RuntimeStreamingPreviewMessage message,
    StreamingMessageEvent event,
    DateTime timestamp,
  )? _onEventConsumed;

  RuntimeStreamingPreviewState currentState() => _state;

  void clear() {
    _state = const RuntimeStreamingPreviewState();
  }

  void removeMessage(String messageId) {
    final messages = _state.messages
        .where((message) => message.messageId != messageId)
        .toList(growable: false);
    if (messages.length == _state.messages.length) {
      return;
    }
    _state = _state.copyWith(messages: messages);
  }

  void consume(
    StreamingMessageEvent event, {
    DateTime? now,
  }) {
    final timestamp = now ?? DateTime.now();
    final responseId = _resolvePreviewResponseId(event);
    final traceId = _readRuntimeMetadataValue(
      event.runtimeMetadata,
      key: 'streamTraceId',
    );
    final turnId = _readRuntimeMetadataValue(
      event.runtimeMetadata,
      key: 'streamTurnId',
    );
    if (event is StreamingMessageStartEvent) {
      _upsertMessage(
        event.messageId,
        (current) => RuntimeStreamingPreviewMessage(
          messageId: event.messageId,
          createdAt: current?.createdAt ?? timestamp,
          updatedAt: timestamp,
          responseId: responseId ?? current?.responseId,
          streamTraceId: traceId ?? current?.streamTraceId,
          streamTurnId: turnId ?? current?.streamTurnId,
          isCompleted: false,
          blocks: current?.blocks ?? const <RuntimeStreamingPreviewBlock>[],
        ),
      );
      _emitConsumedEvent(
        messageId: event.messageId,
        event: event,
        timestamp: timestamp,
      );
      return;
    }
    if (event is StreamingMessageStopEvent) {
      _upsertMessage(
        event.messageId,
        (current) => (current ??
            RuntimeStreamingPreviewMessage(
                  messageId: event.messageId,
                  createdAt: timestamp,
                  updatedAt: timestamp,
                ))
            .copyWith(
          updatedAt: timestamp,
          responseId: responseId ?? current?.responseId,
          streamTraceId: traceId ?? current?.streamTraceId,
          streamTurnId: turnId ?? current?.streamTurnId,
          isCompleted: true,
        ),
      );
      _emitConsumedEvent(
        messageId: event.messageId,
        event: event,
        timestamp: timestamp,
      );
      return;
    }
    if (event is StreamingContentBlockStartEvent) {
      _upsertMessage(event.messageId, (current) {
        final base = current ??
            RuntimeStreamingPreviewMessage(
              messageId: event.messageId,
              createdAt: timestamp,
              updatedAt: timestamp,
            );
        final blocks = List<RuntimeStreamingPreviewBlock>.from(base.blocks);
        final existingIndex = blocks.indexWhere(
          (block) => block.contentBlockId == event.contentBlockId,
        );
        final block = RuntimeStreamingPreviewBlock(
          contentBlockId: event.contentBlockId,
          blockType: event.blockType,
          createdAt: existingIndex == -1
              ? timestamp
              : blocks[existingIndex].createdAt,
          updatedAt: timestamp,
          isCompleted: false,
          text: existingIndex == -1 ? '' : blocks[existingIndex].text,
          toolUseId: event.toolUseId,
          toolName: event.toolName,
        );
        if (existingIndex == -1) {
          blocks.add(block);
        } else {
          blocks[existingIndex] = block;
        }
        return base.copyWith(
          updatedAt: timestamp,
          responseId: responseId ?? base.responseId,
          streamTraceId: traceId ?? base.streamTraceId,
          streamTurnId: turnId ?? base.streamTurnId,
          isCompleted: false,
          blocks: blocks,
        );
      });
      _emitConsumedEvent(
        messageId: event.messageId,
        event: event,
        timestamp: timestamp,
      );
      return;
    }
    if (event is StreamingContentBlockDeltaEvent) {
      Logger.temp(
        'RuntimeStreamingPreviewProjector',
        'delta consumed',
        reason: 'diagnose streaming performance',
        data: {
          'deltaType': event.deltaType.name,
          'timestampMicros': timestamp.microsecondsSinceEpoch,
          'valueLength': event.value.length,
        },
      );
      if (event.deltaType == StreamingContentDeltaType.signature) {
        _upsertMessage(event.messageId, (current) {
          final base = current ??
              RuntimeStreamingPreviewMessage(
                messageId: event.messageId,
                createdAt: timestamp,
                updatedAt: timestamp,
              );
          return base.copyWith(
            updatedAt: timestamp,
            responseId: responseId ?? base.responseId,
            streamTraceId: traceId ?? base.streamTraceId,
            streamTurnId: turnId ?? base.streamTurnId,
            isCompleted: false,
          );
        });
        _emitConsumedEvent(
          messageId: event.messageId,
          event: event,
          timestamp: timestamp,
        );
        return;
      }
      _upsertMessage(event.messageId, (current) {
        final base = current ??
            RuntimeStreamingPreviewMessage(
              messageId: event.messageId,
              createdAt: timestamp,
              updatedAt: timestamp,
            );
        final blocks = List<RuntimeStreamingPreviewBlock>.from(base.blocks);
        final existingIndex = blocks.indexWhere(
          (block) => block.contentBlockId == event.contentBlockId,
        );
        final previous = existingIndex == -1
            ? RuntimeStreamingPreviewBlock(
                contentBlockId: event.contentBlockId,
                blockType: _inferBlockType(event.deltaType),
                createdAt: timestamp,
                updatedAt: timestamp,
              )
            : blocks[existingIndex];
        final nextBlock = previous.copyWith(
          updatedAt: timestamp,
          isCompleted: false,
          text: previous.text + event.value,
        );
        if (existingIndex == -1) {
          blocks.add(nextBlock);
        } else {
          blocks[existingIndex] = nextBlock;
        }
        return base.copyWith(
          updatedAt: timestamp,
          responseId: responseId ?? base.responseId,
          streamTraceId: traceId ?? base.streamTraceId,
          streamTurnId: turnId ?? base.streamTurnId,
          isCompleted: false,
          blocks: blocks,
        );
      });
      _emitConsumedEvent(
        messageId: event.messageId,
        event: event,
        timestamp: timestamp,
      );
      return;
    }
    if (event is StreamingContentBlockStopEvent) {
      _upsertMessage(event.messageId, (current) {
        final base = current ??
            RuntimeStreamingPreviewMessage(
              messageId: event.messageId,
              createdAt: timestamp,
              updatedAt: timestamp,
            );
        final blocks = List<RuntimeStreamingPreviewBlock>.from(base.blocks);
        final existingIndex = blocks.indexWhere(
          (block) => block.contentBlockId == event.contentBlockId,
        );
        if (existingIndex == -1) {
          blocks.add(
            RuntimeStreamingPreviewBlock(
              contentBlockId: event.contentBlockId,
              blockType: StreamingContentBlockType.text,
              createdAt: timestamp,
              updatedAt: timestamp,
              isCompleted: true,
            ),
          );
        } else {
          blocks[existingIndex] = blocks[existingIndex].copyWith(
            updatedAt: timestamp,
            isCompleted: true,
          );
        }
        return base.copyWith(
          updatedAt: timestamp,
          responseId: responseId ?? base.responseId,
          streamTraceId: traceId ?? base.streamTraceId,
          streamTurnId: turnId ?? base.streamTurnId,
          blocks: blocks,
        );
      });
      _emitConsumedEvent(
        messageId: event.messageId,
        event: event,
        timestamp: timestamp,
      );
    }
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

  StreamingContentBlockType _inferBlockType(StreamingContentDeltaType deltaType) {
    switch (deltaType) {
      case StreamingContentDeltaType.text:
        return StreamingContentBlockType.text;
      case StreamingContentDeltaType.thinking:
        return StreamingContentBlockType.thinking;
      case StreamingContentDeltaType.inputJson:
      case StreamingContentDeltaType.signature:
        return StreamingContentBlockType.toolUse;
    }
  }

  String? _readProviderResponseId(StreamingMessageEvent event) {
    final value =
        event.providerMetadata?['response_id'] ??
        event.providerMetadata?['message_id'] ??
        event.providerMetadata?['id'];
    if (value is! String) {
      return null;
    }
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  String? _resolvePreviewResponseId(StreamingMessageEvent event) {
    final providerResponseId = _readProviderResponseId(event);
    if (providerResponseId != null && providerResponseId.isNotEmpty) {
      return providerResponseId;
    }
    final messageId = event.messageId.trim();
    return messageId.isEmpty ? null : messageId;
  }

  void _upsertMessage(
    String messageId,
    RuntimeStreamingPreviewMessage Function(
      RuntimeStreamingPreviewMessage? current,
    ) updater,
  ) {
    final messages = List<RuntimeStreamingPreviewMessage>.from(_state.messages);
    final index = messages.indexWhere((message) => message.messageId == messageId);
    final current = index == -1 ? null : messages[index];
    final next = updater(current);
    if (index == -1) {
      messages.add(next);
    } else {
      messages[index] = next;
    }
    _state = _state.copyWith(messages: messages);
  }

  void _emitConsumedEvent({
    required String messageId,
    required StreamingMessageEvent event,
    required DateTime timestamp,
  }) {
    final callback = _onEventConsumed;
    if (callback == null) {
      return;
    }
    final message = _state.messages
        .where((entry) => entry.messageId == messageId)
        .lastOrNull;
    if (message == null) {
      return;
    }
    callback(message, event, timestamp);
  }
}
