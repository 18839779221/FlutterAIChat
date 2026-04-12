import 'package:ai_chat/models/chat_message.dart';
import 'package:ai_chat/models/llm/base_llm.dart';
import 'package:ai_chat/models/response/structured_summary_card.dart';
import 'package:ai_chat/models/trace/chat_trace_event.dart';
import 'package:ai_chat/models/tool/tool_definition.dart';
import 'package:ai_chat/services/chat_service.dart';
import 'package:ai_chat/services/chat_trace_recorder.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ChatService.sendMessageStream', () {
    test('保留最近的系统工具上下文，即使它本身超过上下文预算', () async {
      final llm = _CapturingBaseLLM();
      final service = ChatService(
        llm: llm,
        maxTokens: 40,
      );
      final longToolContext = List.filled(80, 'OpenAI 最新消息摘要').join(' ');

      await service
          .sendMessageStream(
            '帮我总结',
            [
              ChatMessage(
                text: longToolContext,
                role: MessageRole.system,
                status: MessageStatus.completed,
              ),
            ],
            ChatConfig(useReasoning: false, systemPrompt: ''),
          )
          .drain<void>();

      expect(llm.lastMessages, isNotNull);
      expect(llm.lastMessages!, hasLength(2));
      expect(llm.lastMessages!.first.role, MessageRole.system);
      expect(llm.lastMessages!.first.text, contains('OpenAI 最新消息摘要'));
      expect(
        llm.lastMessages!.first.text.length,
        lessThan(longToolContext.length),
      );
      expect(llm.lastMessages!.last.text, '帮我总结');
    });

    test('records context and llm lifecycle trace events', () async {
      final traceRecorder = ChatTraceRecorder();
      final llm = _CapturingBaseLLM();
      final service = ChatService(
        llm: llm,
        traceRecorder: traceRecorder,
      );
      const turnId = 'turn-chat-1';

      await service
          .sendMessageStream(
            '帮我总结',
            [
              ChatMessage(
                text: '这是工具上下文',
                role: MessageRole.system,
                status: MessageStatus.completed,
              ),
            ],
            ChatConfig(useReasoning: false, systemPrompt: ''),
            turnId: turnId,
          )
          .drain<void>();

      final stages = traceRecorder
          .eventsForTurn(turnId)
          .map((event) => event.stage)
          .toList();

      expect(
        stages,
        containsAllInOrder([
          ChatTraceStage.contextSelected,
          ChatTraceStage.llmRequestStart,
          ChatTraceStage.llmFirstToken,
          ChatTraceStage.llmDone,
        ]),
      );
    });
  });

  group('ChatService.structureMessageForDebug', () {
    test('成功时返回已解析的结构化卡片结果而不是原始 json', () async {
      final service = ChatService(
        llm: _FakeBaseLLM(
          structuredResponse:
              '{"title":"Weekly Summary","summary":"A short summary","keyPoints":["A"],"actionItems":["B"],"risks":["C"]}',
        ),
      );

      final result = await service.structureMessageForDebug('source text');

      expect(result.isStructuredCard, isTrue);
      expect(
        result.card,
        isA<StructuredSummaryCard>()
            .having((card) => card.title, 'title', 'Weekly Summary'),
      );
      expect(result.fallbackText, isNull);
    });

    test('请求失败时返回与解析失败相同的固定普通文本回退结果', () async {
      final service = ChatService(
        llm: _FakeBaseLLM(
          structuredError: Exception('network failed'),
        ),
      );

      final result = await service.structureMessageForDebug('source text');

      expect(result.isStructuredCard, isFalse);
      expect(result.card, isNull);
      expect(result.fallbackText, '结构化整理失败，请重试。');
    });

    test('debug 标记命中时返回本地结构化卡片且不请求 llm', () async {
      final llm = _FakeBaseLLM(
        structuredError: Exception('should not be called'),
      );
      final service = ChatService(llm: llm);

      final result = await service.structureMessageForDebug(
        '${ChatService.debugStructuredSuccessMarker} source text',
      );

      expect(result.isStructuredCard, isTrue);
      expect(result.card?.title, 'Debug Structured Summary');
      expect(llm.structureSummaryCardCallCount, 0);
    });
  });
}

class _FakeBaseLLM implements BaseLLM {
  final String? structuredResponse;
  final Exception? structuredError;
  int structureSummaryCardCallCount = 0;

  _FakeBaseLLM({
    this.structuredResponse,
    this.structuredError,
  });

  @override
  Map<String, dynamic> get config => const {};

  @override
  Stream<String> chatStream(
      List<ChatMessage> messages, ChatConfig config) async* {}

  @override
  Future<String> decideToolCall({
    required String userMessage,
    required List<ChatMessage> history,
    required List<ToolDefinition> tools,
  }) {
    throw UnimplementedError();
  }

  @override
  String getModelName(ChatConfig config) => 'fake-model';

  @override
  Future<String> structureSummaryCard(String sourceText) async {
    structureSummaryCardCallCount++;
    if (structuredError != null) {
      throw structuredError!;
    }
    return structuredResponse!;
  }

  @override
  Future<String> summarizeConversation(List<ChatMessage> messages) async =>
      'summary';

  @override
  Future<bool> validateApiKey(ChatConfig config) async => true;
}

class _CapturingBaseLLM implements BaseLLM {
  List<ChatMessage>? lastMessages;

  @override
  Map<String, dynamic> get config => const {};

  @override
  Stream<String> chatStream(List<ChatMessage> messages, ChatConfig config) async* {
    lastMessages = List<ChatMessage>.from(messages);
    yield '{"type":"content","content":"ok"}';
  }

  @override
  Future<String> decideToolCall({
    required String userMessage,
    required List<ChatMessage> history,
    required List<ToolDefinition> tools,
  }) {
    throw UnimplementedError();
  }

  @override
  String getModelName(ChatConfig config) => 'capture-model';

  @override
  Future<String> structureSummaryCard(String sourceText) {
    throw UnimplementedError();
  }

  @override
  Future<String> summarizeConversation(List<ChatMessage> messages) async =>
      'summary';

  @override
  Future<bool> validateApiKey(ChatConfig config) async => true;
}
