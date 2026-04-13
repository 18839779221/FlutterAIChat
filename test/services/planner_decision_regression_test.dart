import 'package:ai_chat/models/agent/planner_tool_choice.dart';
import 'package:ai_chat/models/agent/model_turn_decision.dart';
import 'package:ai_chat/models/agent/planner_tool_option.dart';
import 'package:ai_chat/models/agent/agent_loop_limits.dart';
import 'package:ai_chat/models/chat_event.dart';
import 'package:ai_chat/models/chat_message.dart';
import 'package:ai_chat/models/chat_turn.dart';
import 'package:ai_chat/models/llm/base_llm.dart';
import 'package:ai_chat/models/tool/tool_argument_property.dart';
import 'package:ai_chat/models/tool/tool_argument_schema.dart';
import 'package:ai_chat/models/tool/tool_definition.dart';
import 'package:ai_chat/services/agent_planner_service.dart';
import 'package:ai_chat/services/chat_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Planner decision regression', () {
    test('URL 场景优先暴露 fetch_webpage', () async {
      final llm = _CapturingStructuredPlannerLLM();
      final service = AgentPlannerService(
        llm: llm,
        availableTools: _allTools,
      );

      await service.planNextAction(
        turn: _turn('请总结这个网页 https://example.com'),
        transcript: [_userEvent('请总结这个网页 https://example.com')],
        config: ChatConfig(useReasoning: false, systemPrompt: ''),
        limits: const AgentLoopLimits(),
      );

      expect(llm.lastToolNames, contains('fetch_webpage'));
      expect(llm.lastToolNames, isNot(contains('share_result')));
    });

    test('实时检索场景暴露 web_search 但隐藏写工具', () async {
      final llm = _CapturingStructuredPlannerLLM();
      final service = AgentPlannerService(
        llm: llm,
        availableTools: _allTools,
      );

      await service.planNextAction(
        turn: _turn('帮我查一下 OpenAI 最近的发布'),
        transcript: [_userEvent('帮我查一下 OpenAI 最近的发布')],
        config: ChatConfig(useReasoning: false, systemPrompt: ''),
        limits: const AgentLoopLimits(),
      );

      expect(llm.lastToolNames, contains('web_search'));
      expect(llm.lastToolNames, isNot(contains('create_reminder')));
      expect(llm.lastToolNames, isNot(contains('share_result')));
    });

    test('提醒场景暴露 create_reminder', () async {
      final llm = _CapturingStructuredPlannerLLM();
      final service = AgentPlannerService(
        llm: llm,
        availableTools: _allTools,
      );

      await service.planNextAction(
        turn: _turn('明天下午三点提醒我开会'),
        transcript: [_userEvent('明天下午三点提醒我开会')],
        config: ChatConfig(useReasoning: false, systemPrompt: ''),
        limits: const AgentLoopLimits(),
      );

      expect(llm.lastToolNames, contains('create_reminder'));
    });

    test('结构化 planner choice 可以直接返回 respond', () async {
      final llm = _CapturingStructuredPlannerLLM(
        choice: const PlannerToolChoice.respond('直接回答'),
      );
      final service = AgentPlannerService(
        llm: llm,
        availableTools: _allTools,
      );

      final result = await service.planNextAction(
        turn: _turn('简单解释一下 Riverpod'),
        transcript: [_userEvent('简单解释一下 Riverpod')],
        config: ChatConfig(useReasoning: false, systemPrompt: ''),
        limits: const AgentLoopLimits(),
      );

      expect(result.response, '直接回答');
      expect(result.toolCall, isNull);
    });
  });
}

const _allTools = [
  ToolDefinition(
    name: 'web_search',
    title: '联网搜索',
    description: '搜索外部网页',
    descriptionForModel: '当用户需要实时外部资料时使用。',
    category: ToolCategory.retrieval,
    argumentSchema: ToolArgumentSchema(
      properties: {
        'query': ToolArgumentProperty.string(description: '搜索词'),
      },
      required: ['query'],
    ),
  ),
  ToolDefinition(
    name: 'fetch_webpage',
    title: '读取网页',
    description: '读取网页',
    descriptionForModel: '当用户已经提供 URL 时使用。',
    category: ToolCategory.retrieval,
    argumentSchema: ToolArgumentSchema(
      properties: {
        'url': ToolArgumentProperty.string(description: '网页链接'),
      },
      required: ['url'],
    ),
  ),
  ToolDefinition(
    name: 'create_reminder',
    title: '创建提醒',
    description: '创建提醒',
    descriptionForModel: '当用户明确要求提醒时使用。',
    category: ToolCategory.productivity,
    argumentSchema: ToolArgumentSchema(
      properties: {
        'title': ToolArgumentProperty.string(description: '标题'),
        'dueAt': ToolArgumentProperty.string(description: '时间'),
      },
      required: ['title', 'dueAt'],
    ),
  ),
  ToolDefinition(
    name: 'share_result',
    title: '分享结果',
    description: '分享结果',
    descriptionForModel: '当用户明确要求分享时使用。',
    category: ToolCategory.outputAction,
    argumentSchema: ToolArgumentSchema(
      properties: {
        'text': ToolArgumentProperty.string(description: '正文'),
      },
      required: ['text'],
    ),
  ),
];

ChatTurn _turn(String input) => ChatTurn(
      id: 1,
      groupId: 1,
      status: ChatTurnStatus.running,
      userInput: input,
    );

ChatEvent _userEvent(String input) => ChatEvent(
      turnId: 1,
      groupId: 1,
      sequence: 1,
      eventType: ChatEventType.userMessage,
      role: MessageRole.user,
      content: input,
    );

class _CapturingStructuredPlannerLLM implements BaseLLM {
  final PlannerToolChoice choice;
  List<String> lastToolNames = const [];

  _CapturingStructuredPlannerLLM({
    this.choice = const PlannerToolChoice.respond('ok'),
  });

  @override
  Map<String, dynamic> get config => const {};

  @override
  String getModelName(ChatConfig config) => 'regression-planner';

  @override
  Future<PlannerToolChoice?> planNextToolChoice({
    required List<ChatMessage> messages,
    required ChatConfig config,
    required List<PlannerToolOption> availableTools,
  }) async {
    lastToolNames =
        availableTools.map((tool) => tool.name).toList(growable: false);
    return choice;
  }

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
  Future<String> planNextAction({
    required List<ChatMessage> messages,
    required ChatConfig config,
  }) async =>
      '{"action":"respond","response":"fallback"}';

  @override
  Stream<String> chatStream(
      List<ChatMessage> messages, ChatConfig config) async* {}

  @override
  Future<String> structureSummaryCard(String sourceText) async => '{}';

  @override
  Future<String> summarizeConversation(List<ChatMessage> messages) async =>
      'summary';

  @override
  Future<bool> validateApiKey(ChatConfig config) async => true;
}
