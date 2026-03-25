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
    }
  }

  Stream<String> _parseChatCompletionsStream(http.StreamedResponse response) async* {
    await for (final line in response.stream.transform(utf8.decoder).transform(const LineSplitter())) {
      if (!line.startsWith('data: ')) {
        continue;
      }

      if (line.contains('[DONE]')) {
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
          Logger.d(_tag, '收到内容片段: $content');
          yield jsonEncode({'type': 'content', 'content': content});
        }
      } catch (e) {
        Logger.e(_tag, 'JSON解析错误: $e');
      }
    }
  }

  Stream<String> _parseResponsesStream(http.StreamedResponse response) async* {
    await for (final line in response.stream.transform(utf8.decoder).transform(const LineSplitter())) {
      if (!line.startsWith('data: ')) {
        continue;
      }

      try {
        final data = jsonDecode(line.substring(6));
        final type = data['type'];
        final delta = data['delta'];

        if (type == 'response.output_text.delta' && delta is String && delta.isNotEmpty) {
          Logger.d(_tag, '收到 Responses 内容片段: $delta');
          yield jsonEncode({'type': 'content', 'content': delta});
          continue;
        }

        if ((type == 'response.reasoning.delta' || type == 'response.reasoning_summary_text.delta') &&
            delta is String &&
            delta.isNotEmpty) {
          yield jsonEncode({'type': 'reasoning', 'content': delta});
        }
      } catch (e) {
        Logger.e(_tag, 'Responses JSON解析错误: $e');
      }
    }
  }
}
