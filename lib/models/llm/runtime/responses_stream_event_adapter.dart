import 'package:openai_dart/openai_dart.dart' as oai;

import '../streaming_message_event.dart';

/// Converts `openai_dart` responses stream events into unified preview events.
class ResponsesStreamEventAdapter {
  const ResponsesStreamEventAdapter();

  Stream<StreamingMessageEvent> adaptPreview(
    Stream<oai.ResponseStreamEvent> events,
  ) async* {
    String? messageId;
    final startedBlocks = <String>{};
    final blocksWithArgumentDelta = <String>{};
    final toolBlockIdsByOutputIndex = <int, String>{};
    final toolUseIdsByBlockId = <String, String?>{};
    final toolNamesByBlockId = <String, String?>{};

    await for (final event in events) {
      final data = event.toJson();
      final providerMetadata = _extractProviderMetadata(data);
      final currentMessageId =
          _normalizeText(
            data['response_id'] ??
                (data['response'] is Map<String, dynamic>
                    ? (data['response'] as Map<String, dynamic>)['id']
                    : null),
          ) ??
          messageId ??
          'response_stream';

      if (messageId == null) {
        messageId = currentMessageId;
        yield StreamingMessageStartEvent(
          messageId: currentMessageId,
          providerMetadata: providerMetadata,
        );
      } else if (providerMetadata != null && providerMetadata.isNotEmpty) {
        yield StreamingMessageStartEvent(
          messageId: currentMessageId,
          providerMetadata: providerMetadata,
        );
      }

      final type = data['type'];
      final delta = data['delta'];

      if (type == 'response.output_text.delta' &&
          delta is String &&
          delta.isNotEmpty) {
        final blockId =
            '$currentMessageId:item:${data['item_id'] ?? data['output_index'] ?? 'text'}:content:${data['content_index'] ?? 0}';
        if (startedBlocks.add(blockId)) {
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
          value: delta,
          providerMetadata: providerMetadata,
        );
        continue;
      }

      if ((type == 'response.reasoning.delta' ||
              type == 'response.reasoning_summary_text.delta') &&
          delta is String &&
          delta.isNotEmpty) {
        final blockId =
            '$currentMessageId:item:${data['item_id'] ?? data['output_index'] ?? 'reasoning'}:summary:0';
        if (startedBlocks.add(blockId)) {
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
          value: delta,
          providerMetadata: providerMetadata,
        );
        continue;
      }

      if (type == 'response.output_item.added') {
        final item = data['item'];
        if (item is Map<String, dynamic> && item['type'] == 'function_call') {
          final blockId = _toolBlockId(
            currentMessageId: currentMessageId,
            callId: item['call_id'],
            itemId: item['id'],
            outputIndex: data['output_index'],
          );
          final outputIndex = _normalizeInt(data['output_index']);
          if (outputIndex != null) {
            toolBlockIdsByOutputIndex[outputIndex] = blockId;
          }
          toolUseIdsByBlockId[blockId] =
              _normalizeText(item['call_id'] ?? item['id']);
          toolNamesByBlockId[blockId] = _normalizeText(item['name']);
          if (startedBlocks.add(blockId)) {
            yield StreamingContentBlockStartEvent(
              messageId: currentMessageId,
              contentBlockId: blockId,
              blockType: StreamingContentBlockType.toolUse,
              toolUseId: toolUseIdsByBlockId[blockId],
              toolName: toolNamesByBlockId[blockId],
              providerMetadata: providerMetadata,
            );
          }
        }
        continue;
      }

      if (type == 'response.function_call_arguments.delta' &&
          delta is String &&
          delta.isNotEmpty) {
        final outputIndex = _normalizeInt(data['output_index']);
        final blockId = (outputIndex != null &&
                toolBlockIdsByOutputIndex.containsKey(outputIndex))
            ? toolBlockIdsByOutputIndex[outputIndex]!
            : _toolBlockId(
                currentMessageId: currentMessageId,
                callId: data['call_id'],
                itemId: data['item_id'] ?? data['id'],
                outputIndex: data['output_index'],
              );
        if (startedBlocks.add(blockId)) {
          yield StreamingContentBlockStartEvent(
            messageId: currentMessageId,
            contentBlockId: blockId,
            blockType: StreamingContentBlockType.toolUse,
            toolUseId: toolUseIdsByBlockId[blockId] ??
                _normalizeText(data['call_id'] ?? data['item_id'] ?? data['id']),
            toolName:
                toolNamesByBlockId[blockId] ?? _normalizeText(data['name']),
            providerMetadata: providerMetadata,
          );
        }
        yield StreamingContentBlockDeltaEvent(
          messageId: currentMessageId,
          contentBlockId: blockId,
          deltaType: StreamingContentDeltaType.inputJson,
          value: delta,
          providerMetadata: providerMetadata,
        );
        blocksWithArgumentDelta.add(blockId);
        continue;
      }

      if (type == 'response.function_call_arguments.done') {
        final outputIndex = _normalizeInt(data['output_index']);
        final blockId = (outputIndex != null &&
                toolBlockIdsByOutputIndex.containsKey(outputIndex))
            ? toolBlockIdsByOutputIndex[outputIndex]!
            : _toolBlockId(
                currentMessageId: currentMessageId,
                callId: data['call_id'],
                itemId: data['item_id'] ?? data['id'],
                outputIndex: data['output_index'],
              );
        final fullArguments = _normalizeText(data['arguments']);
        if (!blocksWithArgumentDelta.contains(blockId) &&
            fullArguments != null &&
            fullArguments.isNotEmpty) {
          if (startedBlocks.add(blockId)) {
            yield StreamingContentBlockStartEvent(
              messageId: currentMessageId,
              contentBlockId: blockId,
              blockType: StreamingContentBlockType.toolUse,
              toolUseId: toolUseIdsByBlockId[blockId] ??
                  _normalizeText(data['call_id'] ?? data['item_id'] ?? data['id']),
              toolName:
                  toolNamesByBlockId[blockId] ?? _normalizeText(data['name']),
              providerMetadata: providerMetadata,
            );
          }
          yield StreamingContentBlockDeltaEvent(
            messageId: currentMessageId,
            contentBlockId: blockId,
            deltaType: StreamingContentDeltaType.inputJson,
            value: fullArguments,
            providerMetadata: providerMetadata,
          );
        }
        yield StreamingContentBlockStopEvent(
          messageId: currentMessageId,
          contentBlockId: blockId,
          providerMetadata: providerMetadata,
        );
      }
    }

    if (messageId != null) {
      yield StreamingMessageStopEvent(messageId: messageId!);
    }
  }

  List<String> _extractReasoningSummaries(Map<String, dynamic> item) {
    if (item['type'] != 'reasoning') return const [];
    final summaries = item['summary'];
    if (summaries is! List) return const [];
    final chunks = <String>[];
    for (final entry in summaries) {
      if (entry is! Map) continue;
      final text = _normalizeText(entry['text'] ?? entry['summary_text']);
      if (text != null) {
        chunks.add(text);
      }
    }
    return chunks;
  }

  int? _normalizeInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '');
  }

  String? _normalizeText(dynamic value) {
    if (value is! String) return null;
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  Map<String, dynamic>? _extractProviderMetadata(Map<String, dynamic> data) {
    final response = data['response'];
    if (response is Map<String, dynamic>) {
      final responseId = _normalizeText(response['id']);
      if (responseId != null) {
        return <String, dynamic>{'response_id': responseId};
      }
    }
    final responseId = _normalizeText(data['response_id'] ?? data['id']);
    if (responseId == null) {
      return null;
    }
    return <String, dynamic>{'response_id': responseId};
  }

  String _toolBlockId({
    required String currentMessageId,
    dynamic callId,
    dynamic itemId,
    dynamic outputIndex,
  }) {
    final stableId = _normalizeText(callId) ??
        _normalizeText(itemId) ??
        outputIndex?.toString() ??
        'tool';
    return '$currentMessageId:item:$stableId';
  }
}
