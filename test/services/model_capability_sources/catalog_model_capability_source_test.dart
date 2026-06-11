import 'dart:convert';

import 'package:ai_chat/models/llm/api_protocol_resolver.dart';
import 'package:ai_chat/models/llm/llm_config.dart';
import 'package:ai_chat/services/model_capability_sources/catalog_model_capability_source.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

void main() {
  test('maps models.dev catalog entry into resolved capability', () async {
    final source = CatalogModelCapabilitySource(
      httpClient: _StaticJsonClient({
        'models': {
          'openai/gpt-5': {
            'id': 'openai/gpt-5',
            'limit': {
              'context': 1000000,
              'output': 32000,
            },
          },
        },
      }),
    );

    final capability = await source.fetch(
      const LLMConfig(
        apiKey: 'k',
        apiUrl: 'https://api.openai.com/v1',
        model: 'gpt-5',
        apiStyle: ApiStyle.responses,
        additionalConfig: {
          'llm.selected_provider_id': 'openai',
          'llm.selected_base_url': 'https://api.openai.com/v1',
          'llm.selected_api_style': 'responses',
        },
      ),
    );

    expect(capability?.contextWindowTotal, 1000000);
    expect(capability?.maxOutputTokens, 32000);
    expect(capability?.modelId, 'gpt-5');
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
