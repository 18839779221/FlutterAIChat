import 'package:ai_chat/models/agent/agent_action.dart';
import 'package:ai_chat/models/agent/agent_loop_limits.dart';
import 'package:ai_chat/models/chat_event.dart';
import 'package:ai_chat/models/chat_turn.dart';
import 'package:ai_chat/models/chat_message.dart';
import 'package:ai_chat/models/llm/base_llm.dart';
import 'package:ai_chat/services/agent_planner_service.dart';
import 'package:ai_chat/services/chat_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AgentPlannerService', () {
    test('parses respond action from valid json', () async {
      final service = AgentPlannerService(
        llm: _FakePlannerLLM(
          plannerResponse: '{"action":"respond","response":"这是最终回答"}',
        ),
      );

      final result = await service.planNextAction(
        turn: _turn(),
        transcript: [_userEvent()],
        config: ChatConfig(useReasoning: false, systemPrompt: ''),
        limits: const AgentLoopLimits(),
      );

      expect(result.type, AgentActionType.respond);
      expect(result.response, '这是最终回答');
      expect(result.toolCall, isNull);
    });

    test('parses callTool action from valid json', () async {
      final service = AgentPlannerService(
        llm: _FakePlannerLLM(
          plannerResponse:
              '{"action":"call_tool","toolName":"search_chat_history","arguments":{"query":"数据库","maxResults":3}}',
        ),
      );

      final result = await service.planNextAction(
        turn: _turn(),
        transcript: [_userEvent()],
        config: ChatConfig(useReasoning: false, systemPrompt: ''),
        limits: const AgentLoopLimits(),
      );

      expect(result.type, AgentActionType.callTool);
      expect(result.toolCall, isNotNull);
      expect(result.toolCall!.toolName, 'search_chat_history');
      expect(result.toolCall!.arguments, containsPair('query', '数据库'));
    });

    test('trims planner action and tool name before matching runtime tools', () async {
      final service = AgentPlannerService(
        llm: _FakePlannerLLM(
          plannerResponse:
              '{\n  "action":" call_tool\\n",\n  "toolName":" web_search\\t",\n  "arguments":{"query":"OpenAI 最新新闻"}\n}',
        ),
      );

      final result = await service.planNextAction(
        turn: _turn(),
        transcript: [_userEvent()],
        config: ChatConfig(useReasoning: false, systemPrompt: ''),
        limits: const AgentLoopLimits(),
      );

      expect(result.type, AgentActionType.callTool);
      expect(result.toolCall, isNotNull);
      expect(result.toolCall!.toolName, 'web_search');
      expect(result.toolCall!.arguments, containsPair('query', 'OpenAI 最新新闻'));
    });

    test('falls back to respond when planner output is malformed', () async {
      final service = AgentPlannerService(
        llm: _FakePlannerLLM(plannerResponse: 'not-json'),
      );

      final result = await service.planNextAction(
        turn: _turn(),
        transcript: [_userEvent()],
        config: ChatConfig(useReasoning: false, systemPrompt: ''),
        limits: const AgentLoopLimits(),
      );

      expect(result.type, AgentActionType.respond);
      expect(result.response, contains('抱歉'));
    });

    test('planner prompt exposes allowed runtime tool names', () async {
      final llm = _FakePlannerLLM(
        plannerResponse: '{"action":"respond","response":"ok"}',
      );
      final service = AgentPlannerService(llm: llm);

      await service.planNextAction(
        turn: _turn(),
        transcript: [_userEvent()],
        config: ChatConfig(useReasoning: false, systemPrompt: ''),
        limits: const AgentLoopLimits(),
      );

      expect(
        llm.lastMessages.first.text,
        contains('只能调用这些工具名'),
      );
      expect(
        llm.lastMessages.first.text,
        contains('web_search'),
      );
      expect(
        llm.lastMessages.first.text,
        contains('fetch_webpage'),
      );
    });

    test('falls back to respond when planner emits an unknown tool name', () async {
      final service = AgentPlannerService(
        llm: _FakePlannerLLM(
          plannerResponse:
              '{"action":"call_tool","toolName":"search_news","arguments":{"query":"OpenAI 最新新闻"}}',
        ),
      );

      final result = await service.planNextAction(
        turn: _turn(),
        transcript: [_userEvent()],
        config: ChatConfig(useReasoning: false, systemPrompt: ''),
        limits: const AgentLoopLimits(),
      );

      expect(result.type, AgentActionType.respond);
      expect(result.response, contains('暂时无法规划'));
      expect(result.toolCall, isNull);
    });
  });
}

ChatTurn _turn() => ChatTurn(
      id: 1,
      groupId: 1,
      status: ChatTurnStatus.running,
      userInput: '帮我回忆刚才聊到的数据库版本',
    );

ChatEvent _userEvent() => ChatEvent(
      turnId: 1,
      groupId: 1,
      sequence: 1,
      eventType: ChatEventType.userMessage,
      role: MessageRole.user,
      content: '帮我回忆刚才聊到的数据库版本',
    );

class _FakePlannerLLM implements BaseLLM {
  final String plannerResponse;
  List<ChatMessage> lastMessages = const [];

  _FakePlannerLLM({required this.plannerResponse});

  @override
  Map<String, dynamic> get config => const {};
  @override
  String getModelName(ChatConfig config) => 'fake-planner';

  @override
  Future<String> planNextAction({
    required List<ChatMessage> messages,
    required ChatConfig config,
  }) async {
    lastMessages = List<ChatMessage>.from(messages);
    return plannerResponse;
  }

  @override
  Stream<String> chatStream(List<ChatMessage> messages, ChatConfig config) async* {}

  @override
  Future<String> structureSummaryCard(String sourceText) async => '{}';

  @override
  Future<String> summarizeConversation(List<ChatMessage> messages) async => 'summary';

  @override
  Future<bool> validateApiKey(ChatConfig config) async => true;
}
