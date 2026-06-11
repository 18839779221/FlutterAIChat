import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/llm/api_protocol_resolver.dart';
import '../models/llm/llm_provider_config.dart';
import '../models/llm/llm_provider_model.dart';

/// Lightweight probe types used for provider connectivity and latency checks.
enum LlmModelProbeType {
  ping,
  pong,
}

extension LlmModelProbeTypeExpectation on LlmModelProbeType {
  String get expectedResponse {
    switch (this) {
      case LlmModelProbeType.ping:
        return 'ping';
      case LlmModelProbeType.pong:
        return 'pong';
    }
  }

  String get requestPrompt {
    return 'Reply with exactly: $expectedResponse';
  }

  String get displayName {
    switch (this) {
      case LlmModelProbeType.ping:
        return 'Ping';
      case LlmModelProbeType.pong:
        return 'Pong';
    }
  }
}

/// Result of a single probe request against one configured model.
class LlmModelProbeResult {
  final LlmModelProbeType probeType;
  final String modelId;
  final String responseText;
  final Duration latency;

  const LlmModelProbeResult({
    required this.probeType,
    required this.modelId,
    required this.responseText,
    required this.latency,
  });
}

/// Combined latency measurement for the default speed-test flow.
class LlmModelSpeedTestResult {
  final LlmModelProbeResult ping;
  final LlmModelProbeResult pong;

  const LlmModelSpeedTestResult({
    required this.ping,
    required this.pong,
  });
}

/// Result of a real image generation probe against one configured model.
class LlmImageGenerationProbeResult {
  final String modelId;
  final Duration latency;

  const LlmImageGenerationProbeResult({
    required this.modelId,
    required this.latency,
  });
}

class LlmModelTestService {
  final http.Client _httpClient;
  final ApiProtocolResolver _protocolResolver;

  LlmModelTestService({
    http.Client? httpClient,
    ApiProtocolResolver? protocolResolver,
  })  : _httpClient = httpClient ?? http.Client(),
        _protocolResolver = protocolResolver ?? const ApiProtocolResolver();

  Future<String> testModel({
    required LlmProviderConfig provider,
    required LlmProviderModel model,
  }) async {
    final result = await probeModel(
      provider: provider,
      model: model,
      probeType: LlmModelProbeType.pong,
    );
    return result.responseText;
  }

  Future<LlmModelProbeResult> probeModel({
    required LlmProviderConfig provider,
    required LlmProviderModel model,
    required LlmModelProbeType probeType,
  }) async {
    _validate(provider: provider, model: model);

    final apiStyle = _protocolResolver.resolveStyle(provider.baseUrl);
    final stopwatch = Stopwatch()..start();
    final response = await _httpClient.post(
      _protocolResolver.buildRequestUri(provider.baseUrl, apiStyle),
      headers: _buildHeaders(provider, apiStyle),
      body: jsonEncode(_buildPayload(model.id, apiStyle, probeType)),
    );
    stopwatch.stop();

    if (response.statusCode != 200) {
      final body = response.body.trim();
      throw Exception(
        '模型测试失败: ${response.statusCode} ${response.reasonPhrase ?? ''} $body',
      );
    }

    final responseText = _extractText(response.body, apiStyle).trim();
    if (responseText.isEmpty) {
      throw Exception('模型测试失败: 返回内容为空');
    }
    if (responseText.toLowerCase() != probeType.expectedResponse) {
      throw Exception(
        '模型测试失败: 期望返回 "${probeType.expectedResponse}"，实际返回 "$responseText"',
      );
    }
    return LlmModelProbeResult(
      probeType: probeType,
      modelId: model.id,
      responseText: responseText,
      latency: stopwatch.elapsed,
    );
  }

  Future<LlmModelSpeedTestResult> speedTestModel({
    required LlmProviderConfig provider,
    required LlmProviderModel model,
  }) async {
    final ping = await probeModel(
      provider: provider,
      model: model,
      probeType: LlmModelProbeType.ping,
    );
    final pong = await probeModel(
      provider: provider,
      model: model,
      probeType: LlmModelProbeType.pong,
    );
    return LlmModelSpeedTestResult(ping: ping, pong: pong);
  }

  Future<LlmImageGenerationProbeResult> testImageGenerationModel({
    required LlmProviderConfig provider,
    required LlmProviderModel model,
  }) async {
    _validate(provider: provider, model: model);

    final stopwatch = Stopwatch()..start();
    final response = await _httpClient.post(
      _buildImageGenerationUri(provider.baseUrl),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer ${provider.apiKey}',
      },
      body: jsonEncode({
        'model': model.id,
        'prompt': 'A tiny blue square icon on a white background.',
        'size': '1024x1024',
        'quality': 'low',
      }),
    );
    stopwatch.stop();

    if (response.statusCode != 200) {
      final body = response.body.trim();
      throw Exception(
        '生图测试失败: ${response.statusCode} ${response.reasonPhrase ?? ''} $body',
      );
    }
    if (!_hasDecodableB64Image(response.body)) {
      throw Exception('生图测试失败: 未返回可用图片');
    }
    return LlmImageGenerationProbeResult(
      modelId: model.id,
      latency: stopwatch.elapsed,
    );
  }

  void _validate({
    required LlmProviderConfig provider,
    required LlmProviderModel model,
  }) {
    if (provider.apiKey.trim().isEmpty) {
      throw Exception('请先填写 API Key');
    }
    final baseUrl = provider.baseUrl.trim();
    final uri = Uri.tryParse(baseUrl);
    if (uri == null || !uri.hasScheme || !uri.hasAuthority) {
      throw Exception('请先填写有效的 Base URL');
    }
    if (model.id.trim().isEmpty) {
      throw Exception('请先填写有效的模型 ID');
    }
  }

  Map<String, String> _buildHeaders(
    LlmProviderConfig provider,
    ApiStyle style,
  ) {
    if (style == ApiStyle.anthropicMessages) {
      return {
        'Content-Type': 'application/json',
        'x-api-key': provider.apiKey,
        'anthropic-version': '2023-06-01',
      };
    }
    return {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer ${provider.apiKey}',
    };
  }

  Uri _buildImageGenerationUri(String baseUrl) {
    final uri = Uri.parse(baseUrl.trim());
    final segments = uri.pathSegments.toList(growable: true);
    if (segments.length >= 2 &&
        segments[segments.length - 2] == 'chat' &&
        segments.last == 'completions') {
      segments.removeRange(segments.length - 2, segments.length);
    } else if (segments.isNotEmpty && segments.last == 'responses') {
      segments.removeLast();
    } else if (segments.isNotEmpty && segments.last == 'completions') {
      segments.removeLast();
    }
    if (segments.isEmpty || segments.last != 'v1') {
      segments.add('v1');
    }
    return uri.replace(
      pathSegments: [...segments, 'images', 'generations'],
    );
  }

  bool _hasDecodableB64Image(String body) {
    final decoded = jsonDecode(body);
    if (decoded is! Map<String, dynamic>) {
      return false;
    }
    final data = decoded['data'];
    if (data is! List) {
      return false;
    }
    for (final item in data) {
      if (item is! Map) {
        continue;
      }
      final b64 = item['b64_json'];
      if (b64 is! String || b64.trim().isEmpty) {
        continue;
      }
      try {
        base64Decode(b64.trim());
        return true;
      } catch (_) {
        continue;
      }
    }
    return false;
  }

  Map<String, dynamic> _buildPayload(
    String modelId,
    ApiStyle style,
    LlmModelProbeType probeType,
  ) {
    final prompt = probeType.requestPrompt;
    switch (style) {
      case ApiStyle.chatCompletions:
        return {
          'model': modelId,
          'messages': [
            {'role': 'user', 'content': prompt},
          ],
          'stream': false,
          'max_tokens': 20,
        };
      case ApiStyle.anthropicMessages:
        return {
          'model': modelId,
          'messages': [
            {'role': 'user', 'content': prompt},
          ],
          'max_tokens': 20,
          'stream': false,
        };
      case ApiStyle.responses:
        return {
          'model': modelId,
          'input': prompt,
          'stream': false,
          'max_output_tokens': 20,
        };
    }
  }

  String _extractText(String body, ApiStyle style) {
    final decoded = jsonDecode(body);
    if (decoded is! Map<String, dynamic>) {
      return '';
    }

    switch (style) {
      case ApiStyle.chatCompletions:
        final choices = decoded['choices'];
        if (choices is! List || choices.isEmpty) {
          return '';
        }
        final first = choices.first;
        if (first is! Map) {
          return '';
        }
        final message = first['message'];
        if (message is! Map) {
          return '';
        }
        return (message['content'] as String? ?? '').trim();
      case ApiStyle.anthropicMessages:
        final content = decoded['content'];
        if (content is! List) {
          return '';
        }
        for (final item in content) {
          if (item is Map && item['type'] == 'text') {
            return (item['text'] as String? ?? '').trim();
          }
        }
        return '';
      case ApiStyle.responses:
        final output = decoded['output'];
        if (output is! List) {
          return '';
        }
        for (final item in output) {
          if (item is! Map) {
            continue;
          }
          final content = item['content'];
          if (content is! List) {
            continue;
          }
          for (final part in content) {
            if (part is Map && part['type'] == 'output_text') {
              return (part['text'] as String? ?? '').trim();
            }
          }
        }
        return '';
    }
  }
}
