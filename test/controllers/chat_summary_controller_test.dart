import 'package:ai_chat/controllers/chat_summary_controller.dart';
import 'package:ai_chat/models/agent/model_turn_decision.dart';
import 'package:ai_chat/models/agent/planner_tool_option.dart';
import 'package:ai_chat/models/chat_group.dart';
import 'package:ai_chat/models/chat_message.dart';
import 'package:ai_chat/models/chat_turn.dart';
import 'package:ai_chat/models/context/planner_context_carrier.dart';
import 'package:ai_chat/models/llm/api_protocol_resolver.dart';
import 'package:ai_chat/models/llm/base_llm.dart';
import 'package:ai_chat/models/llm/llm_config.dart';
import 'package:ai_chat/models/llm/llm_provider_config.dart';
import 'package:ai_chat/models/llm/llm_provider_model.dart';
import 'package:ai_chat/models/session/session_runtime_config.dart';
import 'package:ai_chat/providers/chat_collection_providers.dart';
import 'package:ai_chat/providers/chat_dependency_providers.dart';
import 'package:ai_chat/providers/chat_providers.dart';
import 'package:ai_chat/repositories/app_settings_repository.dart';
import 'package:ai_chat/repositories/llm_local_defaults.dart';
import 'package:ai_chat/services/chat_service.dart';
import 'package:ai_chat/storage/chat_storage.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('DefaultChatSummaryController.isDefaultTitle', () {
    test('matches auto-generated defaults: 新对话 <digits>', () {
      expect(DefaultChatSummaryController.isDefaultTitle('新对话 1'), isTrue);
      expect(DefaultChatSummaryController.isDefaultTitle('新对话 42'), isTrue);
      expect(DefaultChatSummaryController.isDefaultTitle('新对话 9999'), isTrue);
    });

    test('matches legacy defaults: AI Chat / 默认对话', () {
      expect(DefaultChatSummaryController.isDefaultTitle('AI Chat'), isTrue);
      expect(DefaultChatSummaryController.isDefaultTitle('默认对话'), isTrue);
    });

    test('rejects user-customized titles starting with 新对话', () {
      expect(DefaultChatSummaryController.isDefaultTitle('新对话的想法'), isFalse);
      expect(DefaultChatSummaryController.isDefaultTitle('新对话'), isFalse);
      expect(DefaultChatSummaryController.isDefaultTitle('新对话abc'), isFalse);
      expect(DefaultChatSummaryController.isDefaultTitle('新对话1'), isFalse);
      expect(DefaultChatSummaryController.isDefaultTitle('新对话 1 备注'), isFalse);
    });

    test('rejects unrelated titles', () {
      expect(DefaultChatSummaryController.isDefaultTitle(''), isFalse);
      expect(DefaultChatSummaryController.isDefaultTitle('今天的工作'), isFalse);
      expect(DefaultChatSummaryController.isDefaultTitle('ai chat'), isFalse);
      expect(DefaultChatSummaryController.isDefaultTitle('默认对话 1'), isFalse);
    });
  });

  test('summarizeAndUpdateTitle uses current session runtime override',
      () async {
    SharedPreferences.setMockInitialValues({});
    final repository = AppSettingsRepository(
      await SharedPreferences.getInstance(),
      localDefaultsLoader: () async => const LlmLocalDefaults(
        defaultProviderId: 'global-provider',
        defaultModelId: 'global-model',
        providers: [
          LlmProviderConfig(
            id: 'global-provider',
            name: 'Global',
            apiKey: 'global-key',
            baseUrl: 'https://global.example/v1/chat/completions',
            apiStyle: ApiStyle.chatCompletions,
            models: [
              LlmProviderModel(id: 'global-model', name: 'global-model'),
            ],
          ),
          LlmProviderConfig(
            id: 'session-provider',
            name: 'Session',
            apiKey: 'session-key',
            baseUrl: 'https://session.example/v1/chat/completions',
            apiStyle: ApiStyle.chatCompletions,
            models: [
              LlmProviderModel(id: 'session-model', name: 'session-model'),
            ],
          ),
          LlmProviderConfig(
            id: 'side-provider',
            name: 'Side',
            apiKey: 'side-key',
            baseUrl: 'https://side.example/v1/messages',
            apiStyle: ApiStyle.anthropicMessages,
            models: [
              LlmProviderModel(id: 'side-model', name: 'side-model'),
            ],
          ),
        ],
      ),
    );
    final llm = _CapturingSummaryBaseLlm();
    final storage = _SummaryTestChatStorage();
    final container = ProviderContainer(
      overrides: [
        databaseProvider.overrideWithValue(storage),
        appSettingsRepositoryProvider.overrideWithValue(repository),
        chatServiceProvider.overrideWithValue(ChatService(llm: llm)),
      ],
    );
    addTearDown(container.dispose);

    final groupId = await storage.insertGroupTitle('新对话 1');
    container.read(currentGroupProvider.notifier).state =
        storage.currentGroup(groupId);
    container.read(messagesProvider.notifier).setMessages([
      for (var i = 0; i < 6; i += 1)
        ChatMessage(
          text: 'message-$i',
          role: i.isEven ? MessageRole.user : MessageRole.assistant,
          status: MessageStatus.completed,
        ),
    ]);
    container.read(currentSessionRuntimeConfigProvider.notifier).state =
        SessionRuntimeConfig(
      groupId: groupId,
      providerId: 'session-provider',
      modelId: 'session-model',
      providerStyle: ChatTurnProviderStyle.openaiChatCompletions,
      sideProviderId: 'side-provider',
      sideModelId: 'side-model',
      sideProviderStyle: ChatTurnProviderStyle.anthropicMessages,
    );

    final summary = await container
        .read(chatSummaryControllerProvider)
        .summarizeAndUpdateTitle();

    expect(summary, 'session-summary');
    expect(llm.capturedConfig, isNotNull);
    expect(
      llm.capturedConfig!.sideRuntimeConfigOverride?.apiUrl,
      'https://side.example/v1/messages',
    );
    expect(
      llm.capturedConfig!.sideRuntimeConfigOverride?.model,
      'side-model',
    );
  });
}

class _CapturingSummaryBaseLlm implements BaseLLM, RuntimeConfigurableBaseLlm {
  ChatConfig? capturedConfig;

  @override
  Map<String, dynamic> get config => const {};

  @override
  String getModelName(ChatConfig config) => 'summary-test';

  @override
  Future<String> summarizeConversation(List<ChatMessage> messages) async {
    return 'legacy-summary';
  }

  @override
  Future<ModelTurnDecision?> planTurnDecision({
    required List<PlannerContextCarrier> carriers,
    required ChatTurnProviderStyle activeApiStyle,
    required bool currentTurnRunning,
    required ChatConfig config,
    required List<PlannerToolOption> availableTools,
    void Function(LlmRetryProgress progress)? onRetryScheduled,
  }) async =>
      null;

  @override
  Future<String> processWebpageContent({
    required String webpageContent,
    required String prompt,
  }) async =>
      '';

  @override
  Future<String> processWebpageContentWithConfig({
    required String webpageContent,
    required String prompt,
    required ChatConfig config,
  }) async =>
      '';

  @override
  Future<String> summarizeConversationWithConfig(
    List<ChatMessage> messages, {
      required ChatConfig config,
  }) async {
    capturedConfig = config;
    return 'session-summary';
  }

  @override
  Future<String> runSideTextTaskWithConfig(
    List<ChatMessage> messages, {
    required ChatConfig config,
    required String requestLabel,
    Duration? timeout,
  }) async {
    return 'side-task';
  }
}

class _SummaryTestChatStorage extends Fake implements ChatStorage {
  int _nextGroupId = 1;
  final Map<int, ChatGroup> _groups = {};

  Future<int> insertGroupTitle(String title) async {
    final groupId = _nextGroupId++;
    _groups[groupId] = ChatGroup(id: groupId, title: title);
    return groupId;
  }

  ChatGroup currentGroup(int groupId) => _groups[groupId]!;

  @override
  Future<void> updateGroupTitle(int groupId, String title,
      {bool isSummarized = false}) async {
    final current = _groups[groupId]!;
    _groups[groupId] = current.copyWith(
      title: title,
      isSummarized: isSummarized,
    );
  }

  @override
  Future<ChatGroup?> getGroupById(int id) async => _groups[id];
}
