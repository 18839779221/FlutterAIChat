import 'dart:convert';

import 'package:ai_chat/models/llm/llm_provider_config.dart';
import 'package:ai_chat/services/llm_model_discovery_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

void main() {
  group('LlmModelDiscoveryService', () {
    test('discovers models from OpenAI-compatible models endpoint', () async {
      final service = LlmModelDiscoveryService(
        httpClient: _FakeHttpClient(
          handler: (request) async {
            expect(request.url.toString(), 'https://api.example.com/v1/models');
            expect(request.headers['Authorization'], 'Bearer test-key');
            return http.Response(
              jsonEncode({
                'data': [
                  {'id': 'gpt-4o-mini'},
                  {'id': 'gpt-4.1'},
                ],
              }),
              200,
              headers: {'content-type': 'application/json'},
            );
          },
        ),
      );

      final models = await service.discoverModels(
        provider: const LlmProviderConfig(
          id: 'provider',
          name: 'Provider',
          apiKey: 'test-key',
          baseUrl: 'https://api.example.com/v1',
          models: [],
        ),
      );

      expect(models.map((item) => item.id), ['gpt-4o-mini', 'gpt-4.1']);
      expect(models.map((item) => item.name), ['', '']);
    });

    test('normalizes explicit endpoint urls back to the shared models endpoint',
        () async {
      final service = LlmModelDiscoveryService(
        httpClient: _FakeHttpClient(
          handler: (request) async {
            expect(request.url.toString(), 'https://api.example.com/v1/models');
            return http.Response(
              jsonEncode({
                'data': [
                  {'id': 'gpt-4o-mini'},
                ],
              }),
              200,
              headers: {'content-type': 'application/json'},
            );
          },
        ),
      );

      final models = await service.discoverModels(
        provider: const LlmProviderConfig(
          id: 'provider',
          name: 'Provider',
          apiKey: 'test-key',
          baseUrl: 'https://api.example.com/v1/chat/completions',
          models: [],
        ),
      );

      expect(models.map((item) => item.id), ['gpt-4o-mini']);
    });

    test('throws readable error when discovery request fails', () async {
      final service = LlmModelDiscoveryService(
        httpClient: _FakeHttpClient(
          handler: (request) async => http.Response(
            '{"error":{"message":"unauthorized"}}',
            401,
            headers: {'content-type': 'application/json'},
          ),
        ),
      );

      expect(
        () => service.discoverModels(
          provider: const LlmProviderConfig(
            id: 'provider',
            name: 'Provider',
            apiKey: 'test-key',
            baseUrl: 'https://api.example.com/v1',
            models: [],
          ),
        ),
        throwsA(
          isA<Exception>().having(
            (error) => error.toString(),
            'message',
            contains('unauthorized'),
          ),
        ),
      );
    });

    test('throws readable error when endpoint returns no models', () async {
      final service = LlmModelDiscoveryService(
        httpClient: _FakeHttpClient(
          handler: (request) async => http.Response(
            jsonEncode({'data': []}),
            200,
            headers: {'content-type': 'application/json'},
          ),
        ),
      );

      expect(
        () => service.discoverModels(
          provider: const LlmProviderConfig(
            id: 'provider',
            name: 'Provider',
            apiKey: 'test-key',
            baseUrl: 'https://api.example.com/v1',
            models: [],
          ),
        ),
        throwsA(
          isA<Exception>().having(
            (error) => error.toString(),
            'message',
            contains('未返回可用模型'),
          ),
        ),
      );
    });
  });
}

class _FakeHttpClient extends http.BaseClient {
  _FakeHttpClient({required this.handler});

  final Future<http.Response> Function(http.BaseRequest request) handler;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final response = await handler(request);
    return http.StreamedResponse(
      Stream.value(response.bodyBytes),
      response.statusCode,
      headers: response.headers,
      reasonPhrase: response.reasonPhrase,
    );
  }
}
