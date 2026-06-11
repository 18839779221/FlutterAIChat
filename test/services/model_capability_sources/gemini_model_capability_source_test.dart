import 'dart:convert';

import 'package:ai_chat/models/llm/api_protocol_resolver.dart';
import 'package:ai_chat/models/llm/llm_config.dart';
import 'package:ai_chat/services/model_capability_sources/gemini_model_capability_source.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

void main() {
  test('maps gemini getModel response into resolved capability', () async {
    final source = GeminiModelCapabilitySource(
      httpClient: _StaticJsonClient({
        'name': 'models/gemini-2.5-pro',
        'inputTokenLimit': 1048576,
        'outputTokenLimit': 65536,
      }),
    );

    final capability = await source.fetch(
      const LLMConfig(
        apiKey: 'k',
        apiUrl: 'https://generativelanguage.googleapis.com',
        model: 'gemini-2.5-pro',
        apiStyle: ApiStyle.responses,
        additionalConfig: {
          'llm.selected_provider_id': 'gemini',
          'llm.selected_base_url': 'https://generativelanguage.googleapis.com',
          'llm.selected_api_style': 'responses',
        },
      ),
    );

    expect(capability?.maxInputTokens, 1048576);
    expect(capability?.maxOutputTokens, 65536);
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
