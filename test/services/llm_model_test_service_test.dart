import 'dart:convert';

import 'package:ai_chat/models/llm/llm_provider_config.dart';
import 'package:ai_chat/models/llm/llm_provider_model.dart';
import 'package:ai_chat/services/llm_model_test_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

void main() {
  group('LlmModelTestService', () {
    test('returns assistant text for a successful responses request', () async {
      final service = LlmModelTestService(
        httpClient: _FakeHttpClient(
          handler: (request) async {
            expect(request.url.toString(), 'https://api.example.com/responses');
            expect(request.headers['Authorization'], 'Bearer test-key');
            final payload =
                jsonDecode((request as http.Request).body) as Map<String, dynamic>;
            expect(payload['model'], 'gpt-5.4');
            return http.Response(
              jsonEncode({
                'output': [
                  {
                    'type': 'message',
                    'content': [
                      {
                        'type': 'output_text',
                        'text': 'pong',
                      },
                    ],
                  },
                ],
              }),
              200,
              headers: {'content-type': 'application/json'},
            );
          },
        ),
      );

      final result = await service.testModel(
        provider: const LlmProviderConfig(
          id: 'provider',
          name: 'Provider',
          apiKey: 'test-key',
          baseUrl: 'https://api.example.com',
          models: [
            LlmProviderModel(id: 'gpt-5.4', name: 'GPT-5.4'),
          ],
        ),
        model: const LlmProviderModel(id: 'gpt-5.4', name: 'GPT-5.4'),
      );

      expect(result, 'pong');
    });

    test('throws readable error for failed requests', () async {
      final service = LlmModelTestService(
        httpClient: _FakeHttpClient(
          handler: (request) async => http.Response(
            '{"error":{"message":"model not allowed"}}',
            400,
            headers: {'content-type': 'application/json'},
          ),
        ),
      );

      expect(
        () => service.testModel(
          provider: const LlmProviderConfig(
            id: 'provider',
            name: 'Provider',
            apiKey: 'test-key',
            baseUrl: 'https://api.example.com',
            models: [
              LlmProviderModel(id: 'gpt-5.4', name: 'GPT-5.4'),
            ],
          ),
          model: const LlmProviderModel(id: 'gpt-5.4', name: 'GPT-5.4'),
        ),
        throwsA(
          isA<Exception>().having(
            (error) => error.toString(),
            'message',
            contains('model not allowed'),
          ),
        ),
      );
    });

    test('validates base url before requesting', () async {
      final service = LlmModelTestService(
        httpClient: _FakeHttpClient(
          handler: (request) async => http.Response('{}', 200),
        ),
      );

      expect(
        () => service.testModel(
          provider: const LlmProviderConfig(
            id: 'provider',
            name: 'Provider',
            apiKey: 'test-key',
            baseUrl: 'not-a-url',
            models: [
              LlmProviderModel(id: 'gpt-5.4', name: 'GPT-5.4'),
            ],
          ),
          model: const LlmProviderModel(id: 'gpt-5.4', name: 'GPT-5.4'),
        ),
        throwsA(
          isA<Exception>().having(
            (error) => error.toString(),
            'message',
            contains('Base URL'),
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
