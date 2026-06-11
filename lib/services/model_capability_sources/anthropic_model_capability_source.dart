import 'package:http/http.dart' as http;

import '../../models/llm/llm_config.dart';
import '../../models/llm/model_capability_source_kind.dart';
import '../../models/llm/resolved_model_capability.dart';
import 'provider_model_capability_source.dart';

class AnthropicModelCapabilitySource implements ProviderModelCapabilitySource {
  AnthropicModelCapabilitySource({
    http.Client? httpClient,
  }) : _httpClient = httpClient ?? http.Client();

  final http.Client _httpClient;

  @override
  bool supports(LLMConfig config) {
    final providerId = readSelectedProviderId(config);
    return providerId == 'anthropic';
  }

  @override
  Future<ResolvedModelCapability?> fetch(LLMConfig config) async {
    if (!supports(config)) {
      return null;
    }
    final baseUrl = readSelectedBaseUrl(config);
    final modelId = readSelectedModelId(config);
    if (baseUrl == null || modelId.isEmpty || config.apiKey.trim().isEmpty) {
      return null;
    }
    final baseUri = Uri.tryParse(baseUrl);
    if (baseUri == null || !baseUri.hasScheme || !baseUri.hasAuthority) {
      return null;
    }

    final response = await _httpClient.get(
      baseUri.replace(path: '/v1/models', queryParameters: null),
      headers: {
        'content-type': 'application/json',
        'x-api-key': config.apiKey,
        'anthropic-version': '2023-06-01',
      },
    );
    if (response.statusCode != 200) {
      return null;
    }

    final decoded = decodeJsonMap(response);
    final data = decoded?['data'];
    if (data is! List) {
      return null;
    }
    Map<String, dynamic>? match;
    for (final rawEntry in data) {
      if (rawEntry is! Map) {
        continue;
      }
      final entry = Map<String, dynamic>.from(rawEntry);
      final entryId = (entry['id'] as String? ?? '').trim();
      if (entryId == modelId) {
        match = entry;
        break;
      }
    }
    if (match == null) {
      return null;
    }

    final maxInputTokens = readIntValue(
      match['max_input_tokens'] ?? match['input_token_limit'],
    );
    final maxOutputTokens = readIntValue(
      match['max_output_tokens'] ?? match['max_tokens'],
    );
    final contextWindowTotal = readIntValue(match['context_window']) ??
        _inferContextWindowTotal(
          maxInputTokens: maxInputTokens,
          maxOutputTokens: maxOutputTokens,
        );

    return buildResolvedCapability(
      config: config,
      source: ModelCapabilitySourceKind.providerMetadata,
      contextWindowTotal: contextWindowTotal,
      maxInputTokens: maxInputTokens,
      maxOutputTokens: maxOutputTokens,
    );
  }

  int? _inferContextWindowTotal({
    required int? maxInputTokens,
    required int? maxOutputTokens,
  }) {
    if (maxInputTokens == null) {
      return null;
    }
    return maxOutputTokens == null
        ? maxInputTokens
        : maxInputTokens + maxOutputTokens;
  }
}
