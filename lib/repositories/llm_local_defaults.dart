import 'dart:convert';

import 'package:flutter/services.dart';

class LlmLocalDefaults {
  final String? apiKey;
  final String? baseUrl;
  final String? model;

  const LlmLocalDefaults({
    this.apiKey,
    this.baseUrl,
    this.model,
  });

  factory LlmLocalDefaults.fromJson(Map<String, dynamic> json) {
    String? normalize(dynamic value) {
      if (value is! String) {
        return null;
      }
      final trimmed = value.trim();
      return trimmed.isEmpty ? null : trimmed;
    }

    return LlmLocalDefaults(
      apiKey: normalize(json['api_key']),
      baseUrl: normalize(json['base_url']),
      model: normalize(json['model']),
    );
  }

  bool get isEmpty => apiKey == null && baseUrl == null && model == null;
}

class AssetLlmLocalDefaultsLoader {
  static const String assetPath = 'config/local_defaults.json';

  const AssetLlmLocalDefaultsLoader();

  Future<LlmLocalDefaults?> load() async {
    try {
      final rawJson = await rootBundle.loadString(assetPath);
      final decoded = jsonDecode(rawJson);
      if (decoded is! Map<String, dynamic>) {
        return null;
      }

      final defaults = LlmLocalDefaults.fromJson(decoded);
      return defaults.isEmpty ? null : defaults;
    } catch (_) {
      return null;
    }
  }
}
