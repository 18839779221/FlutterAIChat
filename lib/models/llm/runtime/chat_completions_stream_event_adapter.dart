import '../streaming_message_event.dart';

/// Converts normalized Chat Completions SSE payload chunks into unified
/// streaming preview events.
class ChatCompletionsStreamEventAdapter {
  const ChatCompletionsStreamEventAdapter();

  Stream<StreamingMessageEvent> adapt(
    Stream<Map<String, dynamic>> chunks,
  ) async* {
    String? messageId;
    var startedText = false;
    var startedThinking = false;
    final startedToolBlocks = <String>{};

    await for (final chunk in chunks) {
      final currentMessageId = _normalizeText(chunk['id']) ?? messageId ?? 'chatcmpl';
      final providerMetadata = _providerMetadata(chunk);
      if (messageId == null) {
        messageId = currentMessageId;
        yield StreamingMessageStartEvent(
          messageId: currentMessageId,
          providerMetadata: providerMetadata,
        );
      }

      final choices = chunk['choices'];
      if (choices is! List || choices.isEmpty) {
        continue;
      }
      final firstChoice = choices.first;
      if (firstChoice is! Map) {
        continue;
      }
      final delta = firstChoice['delta'];
      if (delta is! Map) {
        continue;
      }

      final content = _normalizeText(delta['content']);
      if (content != null) {
        final blockId = '$currentMessageId:text';
        if (!startedText) {
          startedText = true;
          yield StreamingContentBlockStartEvent(
            messageId: currentMessageId,
            contentBlockId: blockId,
            blockType: StreamingContentBlockType.text,
            providerMetadata: providerMetadata,
          );
        }
        yield StreamingContentBlockDeltaEvent(
          messageId: currentMessageId,
          contentBlockId: blockId,
          deltaType: StreamingContentDeltaType.text,
          value: content,
          providerMetadata: providerMetadata,
        );
      }

      final reasoning = _normalizeText(
        delta['reasoning_content'] ?? delta['reasoning'] ?? delta['thinking'],
      );
      if (reasoning != null) {
        final blockId = '$currentMessageId:thinking';
        if (!startedThinking) {
          startedThinking = true;
          yield StreamingContentBlockStartEvent(
            messageId: currentMessageId,
            contentBlockId: blockId,
            blockType: StreamingContentBlockType.thinking,
            providerMetadata: providerMetadata,
          );
        }
        yield StreamingContentBlockDeltaEvent(
          messageId: currentMessageId,
          contentBlockId: blockId,
          deltaType: StreamingContentDeltaType.thinking,
          value: reasoning,
          providerMetadata: providerMetadata,
        );
      }

      final toolCalls = delta['tool_calls'];
      if (toolCalls is! List) {
        continue;
      }
      for (var i = 0; i < toolCalls.length; i += 1) {
        final toolCall = toolCalls[i];
        if (toolCall is! Map) {
          continue;
        }
        final function = toolCall['function'];
        final index = _normalizeInt(toolCall['index']) ?? i;
        final toolUseId = _normalizeText(toolCall['id']);
        final stableToolAnchor = toolUseId ?? 'index_$index';
        final blockId = '$currentMessageId:tool:$stableToolAnchor';
        final toolName =
            function is Map ? _normalizeText(function['name']) : null;
        if (startedToolBlocks.add(blockId)) {
          yield StreamingContentBlockStartEvent(
            messageId: currentMessageId,
            contentBlockId: blockId,
            blockType: StreamingContentBlockType.toolUse,
            toolUseId: toolUseId,
            toolName: toolName,
            providerMetadata: providerMetadata,
          );
        }
        final argumentsDelta =
            function is Map ? _normalizeText(function['arguments']) : null;
        if (argumentsDelta != null) {
          yield StreamingContentBlockDeltaEvent(
            messageId: currentMessageId,
            contentBlockId: blockId,
            deltaType: StreamingContentDeltaType.inputJson,
            value: argumentsDelta,
            providerMetadata: providerMetadata,
          );
        }
      }
    }
  }

  Map<String, dynamic>? _providerMetadata(Map<String, dynamic> chunk) {
    final responseId = _normalizeText(chunk['id']);
    if (responseId == null) {
      return null;
    }
    return {'response_id': responseId};
  }

  String? _normalizeText(dynamic value) {
    if (value is! String) {
      return null;
    }
    return value.isEmpty ? null : value;
  }

  int? _normalizeInt(Object? value) {
    if (value is int) {
      return value;
    }
    if (value is String) {
      return int.tryParse(value.trim());
    }
    return null;
  }
}
