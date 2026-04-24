import '../../agent/model_tool_call.dart';
import '../../agent/model_turn_decision.dart';

class AnthropicMessagesToolLoopAdapter {
  const AnthropicMessagesToolLoopAdapter();

  ModelTurnDecision? parseDecision(Map<String, dynamic> payload) {
    final content = payload['content'];
    final providerState = <String, dynamic>{
      if (payload['id'] is String && (payload['id'] as String).trim().isNotEmpty)
        'message_id': payload['id'],
      if (content is List)
        'content_blocks': content
            .whereType<Map>()
            .map((item) => Map<String, dynamic>.from(item))
            .toList(growable: false),
    };
    if (content is! List) {
      return null;
    }

    final toolCalls = <ModelToolCall>[];
    final textBuffer = StringBuffer();
    for (var i = 0; i < content.length; i++) {
      final item = content[i];
      if (item is! Map) {
        continue;
      }
      final normalizedItem = item.cast<String, dynamic>();
      if (normalizedItem['type'] == 'tool_use') {
        final toolName = _normalizeText(normalizedItem['name']);
        final input = normalizedItem['input'];
        if (toolName == null || input is! Map) {
          continue;
        }
        toolCalls.add(
          ModelToolCall(
            providerCallId: _normalizeText(normalizedItem['id']),
            toolName: toolName,
            arguments: input.cast<String, dynamic>(),
            sequence: i,
          ),
        );
        continue;
      }

      final text = _extractText(normalizedItem);
      if (text != null) {
        textBuffer.write(text);
      }
    }

    if (toolCalls.isNotEmpty) {
      return ModelTurnDecision(
        toolCalls: toolCalls,
        assistantMessage: null,
        providerState: providerState,
        isTerminal: false,
      );
    }

    final assistantMessage = textBuffer.toString().trim();
    if (assistantMessage.isEmpty) {
      return null;
    }
    return ModelTurnDecision(
      toolCalls: const [],
      assistantMessage: assistantMessage,
      providerState: providerState,
      isTerminal: true,
    );
  }

  String? _extractText(Map<String, dynamic> item) {
    final type = item['type'];
    if (type != 'text' && type != 'thinking' && type != 'redacted_thinking') {
      return null;
    }
    return _normalizeText(item['text'] ?? item['thinking']);
  }

  String? _normalizeText(dynamic value) {
    if (value is! String) {
      return null;
    }
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      return null;
    }
    return trimmed;
  }
}
