import 'package:http/http.dart' as http;

import '../../models/llm/llm_config.dart';
import '../../models/llm/model_capability_source_kind.dart';
import '../../models/llm/resolved_model_capability.dart';
import 'provider_model_capability_source.dart';

class CatalogModelCapabilitySource implements ModelCapabilitySource {
  CatalogModelCapabilitySource({
    http.Client? httpClient,
    Uri? catalogUri,
  })  : _httpClient = httpClient ?? http.Client(),
        _catalogUri =
            catalogUri ?? Uri.parse('https://models.dev/catalog.json');

  final http.Client _httpClient;
  final Uri _catalogUri;

  @override
  Future<ResolvedModelCapability?> fetch(LLMConfig config) async {
    final response = await _httpClient.get(_catalogUri);
    if (response.statusCode != 200) {
      return null;
    }

    final decoded = decodeJsonMap(response);
    final models = decoded?['models'];
    if (models is! Map) {
      return null;
    }
    final modelsMap = Map<String, dynamic>.from(models);
    final entry = _findModelEntry(modelsMap, config);
    if (entry == null) {
      return null;
    }
    final limit = entry['limit'] is Map
        ? Map<String, dynamic>.from(entry['limit'] as Map)
        : const <String, dynamic>{};
    final contextWindowTotal = readIntValue(
      limit['context'] ??
          entry['context_window'] ??
          entry['contextWindowTotal'],
    );
    final maxOutputTokens = readIntValue(
      limit['output'] ?? entry['max_output_tokens'] ?? entry['maxOutputTokens'],
    );
    final maxInputTokens = readIntValue(
          limit['input'] ??
              entry['max_input_tokens'] ??
              entry['maxInputTokens'],
        ) ??
        contextWindowTotal;

    return buildResolvedCapability(
      config: config,
      source: ModelCapabilitySourceKind.catalog,
      contextWindowTotal: contextWindowTotal,
      maxInputTokens: maxInputTokens,
      maxOutputTokens: maxOutputTokens,
    );
  }

  Map<String, dynamic>? _findModelEntry(
    Map<String, dynamic> models,
    LLMConfig config,
  ) {
    for (final key in _candidateKeys(config)) {
      final entry = models[key];
      if (entry is Map) {
        return Map<String, dynamic>.from(entry);
      }
    }

    final modelId = readSelectedModelId(config);
    final matches = <Map<String, dynamic>>[];
    for (final rawEntry in models.values) {
      if (rawEntry is! Map) {
        continue;
      }
      final entry = Map<String, dynamic>.from(rawEntry);
      final entryId = (entry['id'] as String? ?? '').trim();
      if (entryId == modelId || entryId.endsWith('/$modelId')) {
        matches.add(entry);
      }
    }
    if (matches.length == 1) {
      return matches.single;
    }
    return null;
  }

  List<String> _candidateKeys(LLMConfig config) {
    final providerId = readSelectedProviderId(config);
    final modelId = readSelectedModelId(config);
    final keys = <String>[];
    if (modelId.contains('/')) {
      keys.add(modelId);
    }
    if (providerId != null && providerId.isNotEmpty) {
      keys.add('${providerId.trim()}/$modelId');
    }
    return keys;
  }
}
