import 'package:ai_chat/models/chat_message.dart';
import 'package:ai_chat/models/llm/base_llm.dart';
import 'package:ai_chat/models/tool/tool_definition.dart';
import 'package:ai_chat/services/chat_service.dart';
import 'package:ai_chat/services/tool_decision_service.dart';
import 'package:ai_chat/services/tool_registry.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ToolDecisionService', () {
    test('returns a known tool for valid decision json', () async {
      final service = ToolDecisionService(
        llm: _FakeBaseLLM(
          decisionResponse:
              '{"toolName":"fetch_webpage","arguments":{"url":"https://example.com"}}',
        ),
        toolRegistry: ToolRegistry(),
      );

      final result = await service.decideTool(
        userMessage: '读取这个网页',
        history: const [],
      );

      expect(result, isNotNull);
      expect(result!.toolName, 'fetch_webpage');
      expect(result.arguments, containsPair('url', 'https://example.com'));
    });

    test('returns null when model decides none', () async {
      final service = ToolDecisionService(
        llm: _FakeBaseLLM(decisionResponse: '{"toolName":"none"}'),
        toolRegistry: ToolRegistry(),
      );

      final result = await service.decideTool(
        userMessage: '直接回答',
        history: const [],
      );

      expect(result, isNull);
    });

    test('rejects unknown tool names', () async {
      final service = ToolDecisionService(
        llm: _FakeBaseLLM(
          decisionResponse:
              '{"toolName":"unknown_tool","arguments":{"value":"x"}}',
        ),
        toolRegistry: ToolRegistry(),
      );

      final result = await service.decideTool(
        userMessage: '做点什么',
        history: const [],
      );

      expect(result, isNull);
    });

    test('rejects malformed json', () async {
      final service = ToolDecisionService(
        llm: _FakeBaseLLM(decisionResponse: 'not-json'),
        toolRegistry: ToolRegistry(),
      );

      final result = await service.decideTool(
        userMessage: '做点什么',
        history: const [],
      );

      expect(result, isNull);
    });

    test('rejects non-map arguments', () async {
      final service = ToolDecisionService(
        llm: _FakeBaseLLM(
          decisionResponse:
              '{"toolName":"fetch_webpage","arguments":"https://example.com"}',
        ),
        toolRegistry: ToolRegistry(),
      );

      final result = await service.decideTool(
        userMessage: '读取网页',
        history: const [],
      );

      expect(result, isNull);
    });
  });
}

class _FakeBaseLLM implements BaseLLM {
  final String decisionResponse;

  _FakeBaseLLM({required this.decisionResponse});

  @override
  Map<String, dynamic> get config => const {};

  @override
  Stream<String> chatStream(List<ChatMessage> messages, ChatConfig config) async* {}

  @override
  Future<String> decideToolCall({
    required String userMessage,
    required List<ChatMessage> history,
    required List<ToolDefinition> tools,
  }) async {
    return decisionResponse;
  }

  @override
  String getModelName(ChatConfig config) => 'fake-model';

  @override
  Future<String> structureSummaryCard(String sourceText) {
    throw UnimplementedError();
  }

  @override
  Future<String> summarizeConversation(List<ChatMessage> messages) async => 'summary';

  @override
  Future<bool> validateApiKey(ChatConfig config) async => true;
}
