import 'dart:convert';

import 'package:ai_chat/models/llm/api_protocol_resolver.dart';
import 'package:ai_chat/models/llm/llm_config.dart';
import 'package:ai_chat/services/model_capability_sources/anthropic_model_capability_source.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

void main() {
  test('maps anthropic model metadata into resolved capability', () async {
    final source = AnthropicModelCapabilitySource(
      httpClient: _StaticJsonClient({
        'data': [
          {
            'id': 'claude-sonnet-4-5',
            'context_window': 200000,
            'max_output_tokens': 32000,
          },
        ],
      }),
    );

    final capability = await source.fetch(
      const LLMConfig(
        apiKey: 'k',
        apiUrl: 'https://api.anthropic.com/v1/messages',
        model: 'claude-sonnet-4-5',
        apiStyle: ApiStyle.anthropicMessages,
        additionalConfig: {
          'llm.selected_provider_id': 'anthropic',
          'llm.selected_base_url': 'https://api.anthropic.com/v1/messages',
          'llm.selected_api_style': 'anthropicMessages',
        },
      ),
    );

    expect(capability?.contextWindowTotal, 200000);
    expect(capability?.maxOutputTokens, 32000);
  });
}

class _StaticJsonClient extends http.BaseClient {
  _StaticJsonClient(this.payload);

  final Map<String, dynamic> payload;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final body = utf8.encode(jsonEncode(payload));
    return http.StreamedResponse(
      Stream<List<int>>.fromIterable([body]),
      200,
      headers: {'content-type': 'application/json'},
    );
  }
}
