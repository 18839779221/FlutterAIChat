import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../utils/logger.dart';
import 'api_protocol_resolver.dart';

class ApiStreamParser {
  static const String _tag = 'ApiStreamParser';

  const ApiStreamParser();

  Stream<String> parse(http.StreamedResponse response, ApiStyle style) {
    switch (style) {
      case ApiStyle.responses:
        return _parseResponsesStream(response);
      case ApiStyle.chatCompletions:
        return _parseChatCompletionsStream(response);
      case ApiStyle.anthropicMessages:
        return _parseAnthropicMessagesStream(response);
    }
  }

  Stream<String> _parseChatCompletionsStream(
      http.StreamedResponse response) async* {
    final splitter = _InlineThinkStreamSplitter();
    await for (final line in response.stream
        .transform(utf8.decoder)
        .transform(const LineSplitter())) {
      if (!line.startsWith('data: ')) {
        continue;
      }

      if (line.contains('[DONE]')) {
        for (final chunk in splitter.close()) {
          yield jsonEncode(chunk.toJson());
        }
        Logger.i(_tag, '流式响应完成');
        continue;
      }

      try {
        final data = jsonDecode(line.substring(6));
        final content = data['choices']?[0]?['delta']?['content'];
        final reasoning = data['choices']?[0]?['delta']?['reasoning_content'];

        if (reasoning is String && reasoning.isNotEmpty) {
          yield jsonEncode({'type': 'reasoning', 'content': reasoning});
        }

        if (content is String && content.isNotEmpty) {
          for (final chunk in splitter.consume(content)) {
            yield jsonEncode(chunk.toJson());
          }
        }
      } catch (e) {
        Logger.e(_tag, 'JSON解析错误: $e');
      }
    }
  }

  Stream<String> _parseResponsesStream(http.StreamedResponse response) async* {
    final emittedReasoningChunks = <String>{};

    await for (final line in response.stream
        .transform(utf8.decoder)
        .transform(const LineSplitter())) {
      if (!line.startsWith('data: ')) {
        continue;
      }

      try {
        final data = jsonDecode(line.substring(6));
        final type = data['type'];
        final delta = data['delta'];

        if (type == 'response.output_text.delta' &&
            delta is String &&
            delta.isNotEmpty) {
          yield jsonEncode({'type': 'content', 'content': delta});
          continue;
        }

        if ((type == 'response.reasoning.delta' ||
                type == 'response.reasoning_summary_text.delta') &&
            delta is String &&
            delta.isNotEmpty) {
          yield jsonEncode({'type': 'reasoning', 'content': delta});
          continue;
        }

        if (type == 'response.output_item.added' ||
            type == 'response.output_item.done') {
          final item = data['item'];
          if (item is Map<String, dynamic>) {
            final reasoningChunks = _extractReasoningSummaries(item);
            for (final chunk in reasoningChunks) {
              final dedupeKey = '${item['id'] ?? ''}:$chunk';
              if (emittedReasoningChunks.add(dedupeKey)) {
                yield jsonEncode({'type': 'reasoning', 'content': chunk});
              }
            }
          }
        }
      } catch (e) {
        Logger.e(_tag, 'Responses JSON解析错误: $e');
      }
    }
  }

  Stream<String> _parseAnthropicMessagesStream(
    http.StreamedResponse response,
  ) async* {
    await for (final line in response.stream
        .transform(utf8.decoder)
        .transform(const LineSplitter())) {
      if (!line.startsWith('data: ')) {
        continue;
      }
      if (line.contains('[DONE]')) {
        Logger.i(_tag, 'Anthropic 流式响应完成');
        continue;
      }

      try {
        final data = jsonDecode(line.substring(6));
        if (data is! Map<String, dynamic>) {
          continue;
        }
        final type = data['type'];
        if (type == 'content_block_delta') {
          final delta = data['delta'];
          if (delta is! Map<String, dynamic>) {
            continue;
          }
          final deltaType = delta['type'];
          final text = _extractAnthropicTextDelta(delta);
          if (text != null) {
            if (deltaType == 'text_delta') {
              yield jsonEncode({'type': 'content', 'content': text});
            } else {
              yield jsonEncode({'type': 'reasoning', 'content': text});
            }
          }
          continue;
        }

        if (type == 'message_delta') {
          final delta = data['delta'];
          if (delta is! Map<String, dynamic>) {
            continue;
          }
          final thinking = _extractAnthropicTextDelta(delta);
          if (thinking != null) {
            yield jsonEncode({'type': 'reasoning', 'content': thinking});
          }
        }
      } catch (e) {
        Logger.e(_tag, 'Anthropic JSON解析错误: $e');
      }
    }
  }

  String? _extractAnthropicTextDelta(Map<String, dynamic> delta) {
    final deltaType = delta['type'];
    if (deltaType == 'text_delta') {
      final text = delta['text'];
      if (text is String && text.isNotEmpty) {
        return text;
      }
    }
    if (deltaType == 'thinking_delta' ||
        deltaType == 'redacted_thinking_delta') {
      final thinking = delta['thinking'] ?? delta['text'];
      if (thinking is String && thinking.isNotEmpty) {
        return thinking;
      }
    }
    return null;
  }

  List<String> _extractReasoningSummaries(Map<String, dynamic> item) {
    if (item['type'] != 'reasoning') {
      return const [];
    }

    final summary = item['summary'];
    if (summary is! List) {
      return const [];
    }

    final chunks = <String>[];
    for (final entry in summary) {
      if (entry is Map<String, dynamic> &&
          entry['type'] == 'summary_text' &&
          entry['text'] is String &&
          (entry['text'] as String).isNotEmpty) {
        chunks.add(entry['text'] as String);
      }
    }
    return chunks;
  }
}

class _InlineThinkStreamSplitter {
  static const String _openTag = '<think>';
  static const String _closeTag = '</think>';

  String _pending = '';
  bool _insideThink = false;

  List<_ParsedStreamChunk> consume(String input) {
    final emitted = <_ParsedStreamChunk>[];
    var remaining = '$_pending$input';
    _pending = '';

    while (remaining.isNotEmpty) {
      final tag = _insideThink ? _closeTag : _openTag;
      final normalized = remaining.toLowerCase();
      final index = normalized.indexOf(tag);
      if (index >= 0) {
        final segment = remaining.substring(0, index);
        _append(emitted, _insideThink, segment);
        remaining = remaining.substring(index + tag.length);
        _insideThink = !_insideThink;
        continue;
      }

      final keep = _longestTrailingTagPrefixLength(normalized, tag);
      final consumableEnd = remaining.length - keep;
      final consumable = remaining.substring(0, consumableEnd);
      _append(emitted, _insideThink, consumable);
      _pending = remaining.substring(consumableEnd);
      break;
    }

    return emitted;
  }

  List<_ParsedStreamChunk> close() {
    if (_pending.isEmpty) {
      return const [];
    }
    final emitted = <_ParsedStreamChunk>[];
    _append(emitted, _insideThink, _pending);
    _pending = '';
    return emitted;
  }

  void _append(List<_ParsedStreamChunk> chunks, bool reasoning, String value) {
    if (value.isEmpty) {
      return;
    }
    chunks.add(
      _ParsedStreamChunk(
        type: reasoning ? 'reasoning' : 'content',
        content: value,
      ),
    );
  }

  int _longestTrailingTagPrefixLength(String value, String tag) {
    final limit = value.length < tag.length ? value.length : tag.length;
    for (var length = limit; length > 0; length--) {
      if (value.endsWith(tag.substring(0, length))) {
        return length;
      }
    }
    return 0;
  }
}

class _ParsedStreamChunk {
  const _ParsedStreamChunk({
    required this.type,
    required this.content,
  });

  final String type;
  final String content;

  Map<String, String> toJson() => {
        'type': type,
        'content': content,
      };
}
