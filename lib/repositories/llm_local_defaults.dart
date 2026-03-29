import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

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
