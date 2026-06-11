import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../models/llm/api_protocol_resolver.dart';
import '../../models/llm/llm_config.dart';
import '../../models/llm/model_capability_source_kind.dart';
import '../../models/llm/resolved_model_capability.dart';

abstract class ModelCapabilitySource {
  Future<ResolvedModelCapability?> fetch(LLMConfig config);
}

/// Shared contract for provider-specific model capability metadata sources.
abstract class ProviderModelCapabilitySource implements ModelCapabilitySource {
  const ProviderModelCapabilitySource();

  bool supports(LLMConfig config);

  @override
  Future<ResolvedModelCapability?> fetch(LLMConfig config);
}

String? readSelectedProviderId(LLMConfig config) {
  final providerId =
      (config.additionalConfig['llm.selected_provider_id'] as String?)?.trim();
  if (providerId == null || providerId.isEmpty) {
    return null;
  }
  return providerId;
}

ApiStyle readSelectedApiStyle(LLMConfig config) {
  final rawStyle =
      (config.additionalConfig['llm.selected_api_style'] as String?)?.trim();
  if (rawStyle != null && rawStyle.isNotEmpty) {
    for (final style in ApiStyle.values) {
      if (style.name == rawStyle) {
        return style;
      }
    }
  }
  return config.apiStyle ?? ApiStyle.chatCompletions;
}

String? readSelectedBaseUrl(LLMConfig config) {
  final baseUrl =
      (config.additionalConfig['llm.selected_base_url'] as String?)?.trim() ??
          config.apiUrl.trim();
  if (baseUrl.isEmpty) {
    return null;
  }
  return baseUrl;
}

String readSelectedModelId(LLMConfig config) => config.model.trim();

Map<String, dynamic>? decodeJsonMap(http.Response response) {
  final decoded = jsonDecode(utf8.decode(response.bodyBytes));
  if (decoded is! Map<String, dynamic>) {
    return null;
  }
  return decoded;
}

ResolvedModelCapability buildResolvedCapability({
  required LLMConfig config,
  required ModelCapabilitySourceKind source,
  int? contextWindowTotal,
  int? maxInputTokens,
  int? maxOutputTokens,
}) {
  final providerId = readSelectedProviderId(config) ?? 'unknown-provider';
  final baseUrlFingerprint =
      readSelectedBaseUrl(config) ?? config.apiUrl.trim();
  return ResolvedModelCapability(
    providerId: providerId,
    providerStyle: readSelectedApiStyle(config),
    baseUrlFingerprint: baseUrlFingerprint,
    modelId: readSelectedModelId(config),
    contextWindowTotal: contextWindowTotal,
    maxInputTokens: maxInputTokens,
    maxOutputTokens: maxOutputTokens,
    source: source,
  );
}

int? readIntValue(dynamic value) {
  if (value is int) {
    return value;
  }
  if (value is num) {
    return value.toInt();
  }
  if (value is String) {
    return int.tryParse(value.trim());
  }
  return null;
}
