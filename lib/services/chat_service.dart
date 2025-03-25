import 'dart:convert';
import 'package:http/http.dart' as http;

class ChatService {
  static const String _apiUrl = 'https://api.deepseek.com/v1/chat/completions';  // 替换为实际的DeepSeek API地址
  static const String _apiKey = 'sk-a2a16fa6b87b40bd8f6a88e253790474';  // 替换为你的API密钥

  Future<String> sendMessage(String message) async {
    try {
      final response = await http.post(
        Uri.parse(_apiUrl),
        headers: {
          'Content-Type': 'application/json; charset=utf-8',
          'Authorization': 'Bearer $_apiKey',
        },
        body: utf8.encode(jsonEncode({
          'model': 'deepseek-chat',
          'messages': [
            {'role': 'user', 'content': message}
          ],
        })),
      );
      print('responseBody: ${response}');
      if (response.statusCode == 200) {
        final String decodedResponse = utf8.decode(response.bodyBytes);
        final data = jsonDecode(decodedResponse);
        return data['choices'][0]['message']['content'];
      } else {
        throw Exception('API请求失败: ${response.statusCode}');
      }
    } catch (e) {
      print('Error details: $e');
      throw Exception('发送消息失败: $e');
    }
  }
}