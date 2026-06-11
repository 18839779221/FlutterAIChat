import 'package:http/http.dart' as http;

import '../../models/llm/llm_config.dart';
import '../../models/llm/model_capability_source_kind.dart';
import '../../models/llm/resolved_model_capability.dart';
import 'provider_model_capability_source.dart';

class GeminiModelCapabilitySource implements ProviderModelCapabilitySource {
  GeminiModelCapabilitySource({
    http.Client? httpClient,
  }) : _httpClient = httpClient ?? http.Client();

  final http.Client _httpClient;

  @override
  bool supports(LLMConfig config) {
    final providerId = readSelectedProviderId(config);
    if (providerId == 'gemini') {
      return true;
    }
    final baseUrl = readSelectedBaseUrl(config);
    return baseUrl?.contains('generativelanguage.googleapis.com') == true;
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
      _buildModelUri(baseUri, modelId),
      headers: {
        'content-type': 'application/json',
        'x-goog-api-key': config.apiKey,
      },
    );
    if (response.statusCode != 200) {
      return null;
    }

    final decoded = decodeJsonMap(response);
    if (decoded == null) {
      return null;
    }
    final maxInputTokens = readIntValue(decoded['inputTokenLimit']);
    final maxOutputTokens = readIntValue(decoded['outputTokenLimit']);
    final contextWindowTotal = _inferContextWindowTotal(
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

  Uri _buildModelUri(Uri baseUri, String modelId) {
    final normalizedModelId = modelId.startsWith('models/')
        ? modelId.substring('models/'.length)
        : modelId;
    final versionPrefix = _extractVersionPrefix(baseUri.path);
    return baseUri.replace(
      path: '$versionPrefix/models/$normalizedModelId',
      queryParameters: null,
    );
  }

  String _extractVersionPrefix(String path) {
    final trimmed = path.trim();
    if (trimmed.isEmpty || trimmed == '/') {
      return '/v1beta';
    }
    final segments = Uri.parse('https://placeholder$trimmed').pathSegments;
    if (segments.isEmpty) {
      return '/v1beta';
    }
    final first = segments.first;
    if (first.startsWith('v1')) {
      return '/$first';
    }
    return '/v1beta';
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
