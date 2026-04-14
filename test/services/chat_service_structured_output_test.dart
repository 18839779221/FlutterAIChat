import 'package:ai_chat/models/chat_message.dart';
import 'package:ai_chat/models/agent/model_turn_decision.dart';
import 'package:ai_chat/models/agent/planner_tool_choice.dart';
import 'package:ai_chat/models/agent/planner_tool_option.dart';
import 'package:ai_chat/models/chat_turn.dart';
import 'package:ai_chat/models/llm/base_llm.dart';
import 'package:ai_chat/models/response/structured_summary_card.dart';
import 'package:ai_chat/services/chat_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ChatService.streamFinalAnswer', () {
    test('仅透出 content 类型的增量文本', () async {
      final llm = _CapturingBaseLLM();
      final service = ChatService(llm: llm);

      final chunks = await service.streamFinalAnswer(
        messages: [
          ChatMessage(
            text: '系统提示',
            role: MessageRole.system,
            status: MessageStatus.completed,
          ),
          ChatMessage(
            text: '帮我总结',
            role: MessageRole.user,
            status: MessageStatus.completed,
          ),
        ],
        config: ChatConfig(useReasoning: false, systemPrompt: ''),
      ).toList();

      expect(chunks, ['第一段', '第二段']);
      expect(llm.lastMessages, isNotNull);
      expect(
          llm.lastMessages!.map((message) => message.text), ['系统提示', '帮我总结']);
    });

    test('当模型返回原始文本时直接透传非空内容', () async {
      final service = ChatService(llm: _RawTextBaseLLM());

      final chunks = await service.streamFinalAnswer(
        messages: [
          ChatMessage(
            text: '直接回答',
            role: MessageRole.user,
            status: MessageStatus.completed,
          ),
        ],
        config: ChatConfig(useReasoning: false, systemPrompt: ''),
      ).toList();

      expect(chunks, ['纯文本响应']);
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
  Future<String> planNextAction({
    required List<ChatMessage> messages,
    required ChatConfig config,
  }) async =>
      '{"action":"respond","response":"stub"}';

  @override
  Future<PlannerToolChoice?> planNextToolChoice({
    required List<ChatMessage> messages,
    required ChatConfig config,
    required List<PlannerToolOption> availableTools,
  }) async =>
      null;

  @override
  Future<ModelTurnDecision?> planTurnDecision({
    required List<ChatMessage> messages,
    required ChatConfig config,
    required List<PlannerToolOption> availableTools,
    ChatTurnProviderStyle? providerStyle,
    Map<String, dynamic>? providerState,
    List<Map<String, dynamic>> providerContinuationItems = const [],
  }) async =>
      null;

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
  Stream<String> chatStream(
      List<ChatMessage> messages, ChatConfig config) async* {
    lastMessages = List<ChatMessage>.from(messages);
    yield '{"type":"reasoning","content":"先思考"}';
    yield '{"type":"content","content":"第一段"}';
    yield '{"type":"content","content":"第二段"}';
  }

  @override
  Future<String> planNextAction({
    required List<ChatMessage> messages,
    required ChatConfig config,
  }) async =>
      '{"action":"respond","response":"stub"}';

  @override
  Future<PlannerToolChoice?> planNextToolChoice({
    required List<ChatMessage> messages,
    required ChatConfig config,
    required List<PlannerToolOption> availableTools,
  }) async =>
      null;

  @override
  Future<ModelTurnDecision?> planTurnDecision({
    required List<ChatMessage> messages,
    required ChatConfig config,
    required List<PlannerToolOption> availableTools,
    ChatTurnProviderStyle? providerStyle,
    Map<String, dynamic>? providerState,
    List<Map<String, dynamic>> providerContinuationItems = const [],
  }) async =>
      null;

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

class _RawTextBaseLLM implements BaseLLM {
  @override
  Map<String, dynamic> get config => const {};

  @override
  Stream<String> chatStream(
      List<ChatMessage> messages, ChatConfig config) async* {
    yield '纯文本响应';
  }

  @override
  Future<String> planNextAction({
    required List<ChatMessage> messages,
    required ChatConfig config,
  }) async =>
      '{"action":"respond","response":"stub"}';

  @override
  Future<PlannerToolChoice?> planNextToolChoice({
    required List<ChatMessage> messages,
    required ChatConfig config,
    required List<PlannerToolOption> availableTools,
  }) async =>
      null;

  @override
  Future<ModelTurnDecision?> planTurnDecision({
    required List<ChatMessage> messages,
    required ChatConfig config,
    required List<PlannerToolOption> availableTools,
    ChatTurnProviderStyle? providerStyle,
    Map<String, dynamic>? providerState,
    List<Map<String, dynamic>> providerContinuationItems = const [],
  }) async =>
      null;

  @override
  String getModelName(ChatConfig config) => 'raw-text-model';

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
