import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

import '../models/llm/llm_provider_config.dart';
import '../models/speech/speech_input_config.dart';

class LlmLocalDefaults {
  /// Default provider selected during the first local seed.
  final String? defaultProviderId;

  /// Default model selected during the first local seed.
  final String? defaultModelId;

  /// Provider directory imported into shared preferences on first launch.
  final List<LlmProviderConfig> providers;

  /// Extra runtime config shared with non-LLM integrations such as tools.
  final Map<String, dynamic> additionalConfig;

  /// Optional speech input config injected for development and test instances.
  final SpeechInputConfig? speechInput;

  const LlmLocalDefaults({
    this.defaultProviderId,
    this.defaultModelId,
    this.providers = const [],
    this.additionalConfig = const {},
    this.speechInput,
  });

  factory LlmLocalDefaults.fromJson(Map<String, dynamic> json) {
    String? normalize(dynamic value) {
      if (value is! String) {
        return null;
      }
      final trimmed = value.trim();
      return trimmed.isEmpty ? null : trimmed;
    }

    final rawProviders = json['providers'];
    final providers = rawProviders is List
        ? rawProviders
            .whereType<Map>()
            .map((item) =>
                LlmProviderConfig.fromJson(Map<String, dynamic>.from(item)))
            .where(
              (item) =>
                  item.id.isNotEmpty &&
                  item.name.isNotEmpty &&
                  item.baseUrl.isNotEmpty &&
                  item.models.isNotEmpty,
            )
            .toList(growable: false)
        : const <LlmProviderConfig>[];

    return LlmLocalDefaults(
      defaultProviderId: normalize(json['default_provider_id']),
      defaultModelId: normalize(json['default_model_id']),
      providers: providers,
      additionalConfig: _readAdditionalConfig(json),
      speechInput: _readSpeechInput(json),
    );
  }

  bool get isEmpty =>
      providers.isEmpty && additionalConfig.isEmpty && speechInput == null;

  static Map<String, dynamic> _readAdditionalConfig(Map<String, dynamic> json) {
    final webSearch = json['web_search'];
    final imageGeneration = json['image_generation'];

    String? normalize(dynamic value) {
      if (value is! String) {
        return null;
      }
      final trimmed = value.trim();
      return trimmed.isEmpty ? null : trimmed;
    }

    final provider = webSearch is Map ? normalize(webSearch['provider']) : null;
    final tavilyApiKey =
        webSearch is Map ? normalize(webSearch['tavily_api_key']) : null;
    final tavilyBaseUrl =
        webSearch is Map ? normalize(webSearch['tavily_base_url']) : null;
    final imageDefaultProviderId = imageGeneration is Map
        ? normalize(imageGeneration['default_provider_id'])
        : null;
    final imageDefaultModelId = imageGeneration is Map
        ? normalize(imageGeneration['default_model_id'])
        : null;
    final imageQualityDefault = imageGeneration is Map
        ? normalize(imageGeneration['quality_default'])
        : null;

    return {
      if (provider != null) 'web_search.provider': provider,
      if (tavilyApiKey != null) 'web_search.tavily_api_key': tavilyApiKey,
      if (tavilyBaseUrl != null) 'web_search.tavily_base_url': tavilyBaseUrl,
      if (imageDefaultProviderId != null)
        'image_generation.default_provider_id': imageDefaultProviderId,
      if (imageDefaultModelId != null)
        'image_generation.default_model_id': imageDefaultModelId,
      if (imageQualityDefault != null)
        'image_generation.quality_default': imageQualityDefault,
    };
  }

  static SpeechInputConfig? _readSpeechInput(Map<String, dynamic> json) {
    final speechInput = json['speechInput'];
    if (speechInput is! Map) {
      return null;
    }
    return SpeechInputConfig.fromJson(
      Map<String, dynamic>.from(speechInput),
    );
  }
}

class AssetLlmLocalDefaultsLoader {
  static const String assetPath = 'config/local_defaults.json';
  static const List<String> _webFallbackPaths = [
    'config/local_defaults.json',
    'assets/config/local_defaults.json',
  ];

  const AssetLlmLocalDefaultsLoader();

  Future<LlmLocalDefaults?> load() async {
    try {
      final defaults = await _loadFromBundle();
      if (defaults != null) {
        return defaults;
      }
    } catch (_) {}

    if (kIsWeb) {
      for (final path in _webFallbackPaths) {
        final defaults = await _loadFromWebPath(path);
        if (defaults != null) {
          return defaults;
        }
      }
    }

    return null;
  }

  Future<LlmLocalDefaults?> _loadFromBundle() async {
    final rawJson = await rootBundle.loadString(assetPath);
    return _parseDefaults(rawJson);
  }

  Future<LlmLocalDefaults?> _loadFromWebPath(String path) async {
    try {
      final response = await http.get(Uri.base.resolve(path));
      if (response.statusCode != 200 || response.body.trim().isEmpty) {
        return null;
      }
      return _parseDefaults(response.body);
    } catch (_) {
      return null;
    }
  }

  LlmLocalDefaults? _parseDefaults(String rawJson) {
    final decoded = jsonDecode(rawJson);
    if (decoded is! Map<String, dynamic>) {
      return null;
    }

    final defaults = LlmLocalDefaults.fromJson(decoded);
    return defaults.isEmpty ? null : defaults;
  }
}
