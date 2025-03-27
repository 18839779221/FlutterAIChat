import 'dart:convert';
import 'package:http/http.dart' as http;

class ChatService {
  static const String _apiUrl = 'https://api.deepseek.com/v1/chat/completions';  // 替换为实际的DeepSeek API地址
  static const String _apiKey = 'sk-a2a16fa6b87b40bd8f6a88e253790474';  // 替换为你的API密钥

  Stream<String> sendMessageStream(String message) async* {
    try {
      final request = http.Request('POST', Uri.parse(_apiUrl));
      request.headers.addAll({
        'Content-Type': 'application/json; charset=utf-8',
        'Authorization': 'Bearer $_apiKey',
      });
      
      request.body = jsonEncode({
        'model': 'deepseek-chat',
        'messages': [
          {'role': 'user', 'content': message}
        ],
        'stream': true, // 启用流式输出
      });

      final response = await http.Client().send(request);

      if (response.statusCode == 200) {
        await for (final chunk in response.stream.transform(utf8.decoder)) {
          // DeepSeek的流式响应格式为: data: {...}\n\n
          final lines = chunk.split('\n');
          for (final line in lines) {
            if (line.startsWith('data: ')) {
              if (line.contains('[DONE]')) continue;
              
              final jsonStr = line.substring(6); // 移除 'data: ' 前缀
              try {
                final data = jsonDecode(jsonStr);
                final content = data['choices'][0]['delta']['content'];
                if (content != null) {
                  yield content;
                }
              } catch (e) {
                print('JSON解析错误: $e');
              }
            }
          }
        }
      } else {
        throw Exception('API请求失败: ${response.statusCode}');
      }
    } catch (e) {
      throw Exception('发送消息失败: $e');
    }
  }
}