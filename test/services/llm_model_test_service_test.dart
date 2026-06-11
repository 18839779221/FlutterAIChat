import 'dart:convert';

import 'package:ai_chat/models/llm/llm_provider_config.dart';
import 'package:ai_chat/models/llm/llm_provider_model.dart';
import 'package:ai_chat/services/llm_model_test_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

void main() {
  group('LlmModelTestService', () {
    test('probeModel returns structured pong result with latency', () async {
      final service = LlmModelTestService(
        httpClient: _FakeHttpClient(
          handler: (request) async {
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

      final result = await service.probeModel(
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
        probeType: LlmModelProbeType.pong,
      );

      expect(result.probeType, LlmModelProbeType.pong);
      expect(result.modelId, 'gpt-5.4');
      expect(result.responseText, 'pong');
      expect(result.latency, isNotNull);
      expect(result.latency >= Duration.zero, isTrue);
    });

    test('speedTestModel runs ping and pong probes', () async {
      final requests = <Map<String, dynamic>>[];
      final service = LlmModelTestService(
        httpClient: _FakeHttpClient(
          handler: (request) async {
            final payload = jsonDecode((request as http.Request).body)
                as Map<String, dynamic>;
            requests.add(payload);
            final input = payload['input'] as String?;
            final text =
                input != null && input.contains('ping') ? 'ping' : 'pong';
            return http.Response(
              jsonEncode({
                'output': [
                  {
                    'type': 'message',
                    'content': [
                      {
                        'type': 'output_text',
                        'text': text,
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

      final result = await service.speedTestModel(
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

      expect(requests, hasLength(2));
      expect(result.ping.responseText, 'ping');
      expect(result.pong.responseText, 'pong');
    });

    test('testImageGenerationModel posts low quality image probe', () async {
      http.Request? capturedRequest;
      final service = LlmModelTestService(
        httpClient: _FakeHttpClient(
          handler: (request) async {
            capturedRequest = request as http.Request;
            return http.Response(
              jsonEncode({
                'data': [
                  {
                    'b64_json': base64Encode([0, 1, 2, 3])
                  },
                ],
              }),
              200,
              headers: {'content-type': 'application/json'},
            );
          },
        ),
      );

      final result = await service.testImageGenerationModel(
        provider: const LlmProviderConfig(
          id: 'beehears',
          name: 'Beehears',
          apiKey: 'image-key',
          baseUrl: 'https://ai.beehears.com/v1',
          models: [
            LlmProviderModel(id: 'gpt-image-2', name: 'GPT Image 2'),
          ],
        ),
        model: const LlmProviderModel(id: 'gpt-image-2', name: 'GPT Image 2'),
      );

      expect(result.modelId, 'gpt-image-2');
      expect(result.latency, isNotNull);
      expect(
        capturedRequest?.url.toString(),
        'https://ai.beehears.com/v1/images/generations',
      );
      expect(capturedRequest?.headers['Authorization'], 'Bearer image-key');
      final payload = jsonDecode(capturedRequest!.body) as Map<String, dynamic>;
      expect(payload['model'], 'gpt-image-2');
      expect(payload['quality'], 'low');
      expect(payload['size'], '1024x1024');
    });

    test('testImageGenerationModel rejects responses without b64 image data',
        () async {
      final service = LlmModelTestService(
        httpClient: _FakeHttpClient(
          handler: (request) async => http.Response(
            jsonEncode({
              'data': [
                {'url': 'https://example.com/temp.png'},
              ],
            }),
            200,
            headers: {'content-type': 'application/json'},
          ),
        ),
      );

      expect(
        () => service.testImageGenerationModel(
          provider: const LlmProviderConfig(
            id: 'beehears',
            name: 'Beehears',
            apiKey: 'image-key',
            baseUrl: 'https://ai.beehears.com/v1',
            models: [
              LlmProviderModel(id: 'gpt-image-2', name: 'GPT Image 2'),
            ],
          ),
          model: const LlmProviderModel(id: 'gpt-image-2', name: 'GPT Image 2'),
        ),
        throwsA(
          isA<Exception>().having(
            (error) => error.toString(),
            'message',
            contains('未返回可用图片'),
          ),
        ),
      );
    });

    test('returns assistant text for a successful responses request', () async {
      final service = LlmModelTestService(
        httpClient: _FakeHttpClient(
          handler: (request) async {
            expect(request.url.toString(), 'https://api.example.com/responses');
            expect(request.headers['Authorization'], 'Bearer test-key');
            final payload = jsonDecode((request as http.Request).body)
                as Map<String, dynamic>;
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

    test('throws when probe response does not match expected word', () async {
      final service = LlmModelTestService(
        httpClient: _FakeHttpClient(
          handler: (request) async => http.Response(
            jsonEncode({
              'output': [
                {
                  'type': 'message',
                  'content': [
                    {
                      'type': 'output_text',
                      'text': 'hello',
                    },
                  ],
                },
              ],
            }),
            200,
            headers: {'content-type': 'application/json'},
          ),
        ),
      );

      expect(
        () => service.probeModel(
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
          probeType: LlmModelProbeType.ping,
        ),
        throwsA(
          isA<Exception>().having(
            (error) => error.toString(),
            'message',
            contains('期望返回'),
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
