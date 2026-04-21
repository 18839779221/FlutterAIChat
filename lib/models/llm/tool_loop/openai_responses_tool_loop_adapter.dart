import 'dart:convert';

import '../../agent/model_tool_call.dart';
import '../../agent/model_turn_decision.dart';

class OpenAIResponsesToolLoopAdapter {
  const OpenAIResponsesToolLoopAdapter();

  ModelTurnDecision? parseDecision(Map<String, dynamic> payload) {
    final canReuseResponseState = _canReuseResponseState(payload);
    final providerState = <String, dynamic>{
      if (canReuseResponseState &&
          payload['id'] is String &&
          (payload['id'] as String).trim().isNotEmpty)
        'response_id': payload['id'],
    };

    final output = payload['output'];
    if (output is List) {
      final toolCalls = _parseToolCalls(output);
      final assistantMessage = _extractAssistantMessage(output);
      if (toolCalls.isNotEmpty || assistantMessage != null) {
        return ModelTurnDecision(
          toolCalls: toolCalls,
          assistantMessage: assistantMessage,
          providerState: providerState,
          isTerminal: toolCalls.isEmpty,
        );
      }
    }

    final outputText = _normalizeText(payload['output_text']);
    if (outputText != null) {
      return ModelTurnDecision(
        toolCalls: const [],
        assistantMessage: outputText,
        providerState: providerState,
        isTerminal: true,
      );
    }

    return null;
  }

  bool _canReuseResponseState(Map<String, dynamic> payload) {
    final store = payload['store'];
    if (store is bool) {
      return store;
    }
    return true;
  }

  List<ModelToolCall> _parseToolCalls(List<dynamic> output) {
    final parsed = <ModelToolCall>[];
    for (var i = 0; i < output.length; i++) {
      final item = output[i];
      if (item is! Map) {
        continue;
      }
      final normalizedItem = item.cast<String, dynamic>();
      if (normalizedItem['type'] != 'function_call') {
        continue;
      }
      final toolName = _normalizeText(normalizedItem['name']);
      final arguments = _decodeArguments(normalizedItem['arguments']);
      final providerCallId = _normalizeText(
        normalizedItem['call_id'] ?? normalizedItem['id'],
      );
      if (toolName == null || arguments == null) {
        continue;
      }
      parsed.add(
        ModelToolCall(
          providerCallId: providerCallId,
          toolName: toolName,
          arguments: arguments,
          sequence: i,
        ),
      );
    }
    return parsed;
  }

  String? _extractAssistantMessage(List<dynamic> output) {
    final buffer = StringBuffer();
    for (final item in output) {
      if (item is! Map) {
        continue;
      }
      final normalizedItem = item.cast<String, dynamic>();
      if (normalizedItem['type'] != 'message') {
        continue;
      }
      final content = normalizedItem['content'];
      if (content is! List) {
        continue;
      }
      for (final part in content) {
        if (part is! Map) {
          continue;
        }
        final normalizedPart = part.cast<String, dynamic>();
        if (normalizedPart['type'] != 'output_text') {
          continue;
        }
        final text = _normalizeText(normalizedPart['text']);
        if (text != null) {
          buffer.write(text);
        }
      }
    }
    final aggregated = buffer.toString().trim();
    if (aggregated.isEmpty) {
      return null;
    }
    return aggregated;
  }

  Map<String, dynamic>? _decodeArguments(dynamic rawArguments) {
    if (rawArguments is Map) {
      return rawArguments.cast<String, dynamic>();
    }
    final encoded = _normalizeText(rawArguments);
    if (encoded == null) {
      return null;
    }
    final decoded = jsonDecode(encoded);
    if (decoded is Map) {
      return decoded.cast<String, dynamic>();
    }
    return null;
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
