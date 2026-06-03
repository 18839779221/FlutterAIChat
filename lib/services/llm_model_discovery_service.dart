import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/llm/api_protocol_resolver.dart';
import '../models/llm/llm_provider_config.dart';
import '../models/llm/llm_provider_model.dart';

class LlmModelDiscoveryService {
  LlmModelDiscoveryService({
    http.Client? httpClient,
    ApiProtocolResolver? protocolResolver,
  })  : _httpClient = httpClient ?? http.Client(),
        _protocolResolver = protocolResolver ?? const ApiProtocolResolver();

  final http.Client _httpClient;
  final ApiProtocolResolver _protocolResolver;

  Future<List<LlmProviderModel>> discoverModels({
    required LlmProviderConfig provider,
  }) async {
    _validateProvider(provider);

    final response = await _httpClient.get(
      _buildModelsUri(provider.baseUrl),
      headers: _buildHeaders(provider),
    );

    if (response.statusCode != 200) {
      final body = response.body.trim();
      throw Exception(
        '模型探测失败: ${response.statusCode} ${response.reasonPhrase ?? ''} $body',
      );
    }

    final models = _extractModels(response.body);
    if (models.isEmpty) {
      throw Exception('模型探测失败: 未返回可用模型');
    }
    return models;
  }

  void _validateProvider(LlmProviderConfig provider) {
    if (provider.apiKey.trim().isEmpty) {
      throw Exception('请先填写 API Key');
    }
    final baseUrl = provider.baseUrl.trim();
    final uri = Uri.tryParse(baseUrl);
    if (uri == null || !uri.hasScheme || !uri.hasAuthority) {
      throw Exception('请先填写有效的 Base URL');
    }
  }

  Uri _buildModelsUri(String baseUrl) {
    return _protocolResolver.buildModelsUri(baseUrl);
  }

  Map<String, String> _buildHeaders(LlmProviderConfig provider) {
    return {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer ${provider.apiKey}',
    };
  }

  List<LlmProviderModel> _extractModels(String body) {
    final decoded = jsonDecode(body);
    if (decoded is! Map<String, dynamic>) {
      return const <LlmProviderModel>[];
    }
    final data = decoded['data'];
    if (data is! List) {
      return const <LlmProviderModel>[];
    }

    return data
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .map(
          (item) => LlmProviderModel(
            id: (item['id'] as String? ?? '').trim(),
            name: '',
          ),
        )
        .where((item) => item.id.isNotEmpty)
        .toList(growable: false);
  }
}
