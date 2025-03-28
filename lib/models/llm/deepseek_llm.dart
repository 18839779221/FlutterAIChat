import 'dart:convert';
import 'package:http/http.dart' as http;
import '../../utils/logger.dart';
import '../chat_message.dart';
import 'base_llm.dart';
import 'llm_config.dart';

class DeepSeekLLM implements BaseLLM {
  static const String _tag = 'DeepSeekLLM';
  final LLMConfig _config = const LLMConfig(
    apiKey: 'sk-a2a16fa6b87b40bd8f6a88e253790474',
    apiUrl: 'https://api.deepseek.com/v1/chat/completions',
  );

  @override
  String get modelName => 'deepseek-chat';

  @override
  Map<String, dynamic> get config => {
    'apiKey': _config.apiKey,
    'apiUrl': _config.apiUrl,
    ..._config.additionalConfig,
  };

  @override
  Stream<String> chatStream(List<ChatMessage> messages) async* {
    try {
      Logger.i(_tag, '准备发送消息，消息数量: ${messages.length}');

      final request = http.Request('POST', Uri.parse(_config.apiUrl));
      request.headers.addAll({
        'Content-Type': 'application/json; charset=utf-8',
        'Authorization': 'Bearer ${_config.apiKey}',
      });
      
      request.body = jsonEncode({
        'model': modelName,
        'messages': messages.map((msg) => {
          'role': msg.role.toString().split('.').last,
          'content': msg.text,
        }).toList(),
        'stream': true,
      });

      Logger.i(_tag, '请求体: ${request.body}');

      final response = await http.Client().send(request);

      if (response.statusCode == 200) {
        Logger.i(_tag, '开始接收流式响应');
        await for (final chunk in response.stream.transform(utf8.decoder)) {
          final lines = chunk.split('\n');
          for (final line in lines) {
            if (line.startsWith('data: ')) {
              if (line.contains('[DONE]')) {
                Logger.i(_tag, '流式响应完成');
                continue;
              }
              
              final jsonStr = line.substring(6);
              try {
                final data = jsonDecode(jsonStr);
                final content = data['choices'][0]['delta']['content'];
                if (content != null) {
                  Logger.d(_tag, '收到内容片段: $content');
                  yield content;
                }
              } catch (e) {
                Logger.e(_tag, 'JSON解析错误: $e');
              }
            }
          }
        }
      } else {
        throw Exception('API请求失败: ${response.statusCode}');
      }
    } catch (e, stackTrace) {
      Logger.e(_tag, '发送消息失败', e);
      Logger.e(_tag, '堆栈跟踪', stackTrace);
      throw Exception('发送消息失败: $e');
    }
  }

  @override
  Future<bool> validateApiKey() async {
    try {
      final response = await http.post(
        Uri.parse(_config.apiUrl),
        headers: {
          'Authorization': 'Bearer ${_config.apiKey}',
        },
        body: jsonEncode({
          'model': modelName,
          'messages': [{'role': 'user', 'content': 'test'}],
          'max_tokens': 1,
        }),
      );
      return response.statusCode == 200;
    } catch (e) {
      return false;
    }
  }
} 