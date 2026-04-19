import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/llm/api_protocol_resolver.dart';
import '../models/llm/llm_provider_config.dart';
import '../models/llm/llm_provider_model.dart';

class LlmModelTestService {
  final http.Client _httpClient;
  final ApiProtocolResolver _protocolResolver;

  LlmModelTestService({
    http.Client? httpClient,
    ApiProtocolResolver? protocolResolver,
  })  : _httpClient = httpClient ?? http.Client(),
        _protocolResolver = protocolResolver ?? const ApiProtocolResolver();

  Future<String> testModel({
    required LlmProviderConfig provider,
    required LlmProviderModel model,
  }) async {
    _validate(provider: provider, model: model);

    final apiStyle = _protocolResolver.resolveStyle(provider.baseUrl);
    final response = await _httpClient.post(
      _protocolResolver.buildRequestUri(provider.baseUrl, apiStyle),
      headers: _buildHeaders(provider, apiStyle),
      body: jsonEncode(_buildPayload(model.id, apiStyle)),
    );

    if (response.statusCode != 200) {
      final body = response.body.trim();
      throw Exception(
        '模型测试失败: ${response.statusCode} ${response.reasonPhrase ?? ''} $body',
      );
    }

    final responseText = _extractText(response.body, apiStyle).trim();
    if (responseText.isEmpty) {
      throw Exception('模型测试失败: 返回内容为空');
    }
    return responseText;
  }

  void _validate({
    required LlmProviderConfig provider,
    required LlmProviderModel model,
  }) {
    if (provider.apiKey.trim().isEmpty) {
      throw Exception('请先填写 API Key');
    }
    final baseUrl = provider.baseUrl.trim();
    final uri = Uri.tryParse(baseUrl);
    if (uri == null || !uri.hasScheme || !uri.hasAuthority) {
      throw Exception('请先填写有效的 Base URL');
    }
    if (model.id.trim().isEmpty) {
      throw Exception('请先填写有效的模型 ID');
    }
  }

  Map<String, String> _buildHeaders(
    LlmProviderConfig provider,
    ApiStyle style,
  ) {
    if (style == ApiStyle.anthropicMessages) {
      return {
        'Content-Type': 'application/json',
        'x-api-key': provider.apiKey,
        'anthropic-version': '2023-06-01',
      };
    }
    return {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer ${provider.apiKey}',
    };
  }

  Map<String, dynamic> _buildPayload(String modelId, ApiStyle style) {
    switch (style) {
      case ApiStyle.chatCompletions:
        return {
          'model': modelId,
          'messages': const [
            {'role': 'user', 'content': 'Reply with exactly: pong'},
          ],
          'stream': false,
          'max_tokens': 20,
        };
      case ApiStyle.anthropicMessages:
        return {
          'model': modelId,
          'messages': const [
            {'role': 'user', 'content': 'Reply with exactly: pong'},
          ],
          'max_tokens': 20,
          'stream': false,
        };
      case ApiStyle.responses:
        return {
          'model': modelId,
          'input': 'Reply with exactly: pong',
          'stream': false,
          'max_output_tokens': 20,
        };
    }
  }

  String _extractText(String body, ApiStyle style) {
    final decoded = jsonDecode(body);
    if (decoded is! Map<String, dynamic>) {
      return '';
    }

    switch (style) {
      case ApiStyle.chatCompletions:
        final choices = decoded['choices'];
        if (choices is! List || choices.isEmpty) {
          return '';
        }
        final first = choices.first;
        if (first is! Map) {
          return '';
        }
        final message = first['message'];
        if (message is! Map) {
          return '';
        }
        return (message['content'] as String? ?? '').trim();
      case ApiStyle.anthropicMessages:
        final content = decoded['content'];
        if (content is! List) {
          return '';
        }
        for (final item in content) {
          if (item is Map && item['type'] == 'text') {
            return (item['text'] as String? ?? '').trim();
          }
        }
        return '';
      case ApiStyle.responses:
        final output = decoded['output'];
        if (output is! List) {
          return '';
        }
        for (final item in output) {
          if (item is! Map) {
            continue;
          }
          final content = item['content'];
          if (content is! List) {
            continue;
          }
          for (final part in content) {
            if (part is Map && part['type'] == 'output_text') {
              return (part['text'] as String? ?? '').trim();
            }
          }
        }
        return '';
    }
  }
}
