import 'package:ai_chat/models/chat_turn.dart';
import 'package:ai_chat/models/llm/llm_provider_config.dart';
import 'package:ai_chat/models/llm/llm_provider_model.dart';
import 'package:ai_chat/models/session/session_runtime_config.dart';
import 'package:ai_chat/repositories/app_settings_repository.dart';
import 'package:ai_chat/repositories/llm_local_defaults.dart';
import 'package:ai_chat/repositories/session_runtime_config_repository.dart';
import 'package:ai_chat/services/session_runtime_config_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('SessionRuntimeConfigService', () {
    test('initializes draft runtime from global defaults', () async {
      SharedPreferences.setMockInitialValues({});
      final preferences = await SharedPreferences.getInstance();
      final settingsRepository = AppSettingsRepository(
        preferences,
        localDefaultsLoader: () async => const LlmLocalDefaults(
          defaultProviderId: 'openai',
          defaultModelId: 'gpt-5.4',
          providers: [
            LlmProviderConfig(
              id: 'openai',
              name: 'OpenAI',
              apiKey: 'key',
              baseUrl: 'https://api.openai.com/v1/responses',
              models: [
                LlmProviderModel(id: 'gpt-5.4', name: 'GPT-5.4'),
              ],
            ),
          ],
        ),
      );
      final service = SessionRuntimeConfigService(
        settingsRepository: settingsRepository,
        runtimeConfigRepository: null,
      );

      final draft = await service.createDraftRuntime();

      expect(draft.providerId, 'openai');
      expect(draft.modelId, 'gpt-5.4');
      expect(draft.providerStyle, ChatTurnProviderStyle.openaiResponses);
      expect(draft.sideProviderId, isNull);
      expect(draft.sideModelId, isNull);
      expect(draft.sideProviderStyle, isNull);
      expect(draft.groupId, SessionRuntimeConfigService.draftGroupId);
    });

    test('loads persisted runtime when a group config exists', () async {
      SharedPreferences.setMockInitialValues({});
      final preferences = await SharedPreferences.getInstance();
      final settingsRepository = AppSettingsRepository(
        preferences,
        localDefaultsLoader: () async => const LlmLocalDefaults(
          defaultProviderId: 'openai',
          defaultModelId: 'gpt-5.4',
          providers: [
            LlmProviderConfig(
              id: 'openai',
              name: 'OpenAI',
              apiKey: 'key',
              baseUrl: 'https://api.openai.com/v1/responses',
              models: [
                LlmProviderModel(id: 'gpt-5.4', name: 'GPT-5.4'),
              ],
            ),
          ],
        ),
      );
      final repository = _FakeSessionRuntimeConfigRepository(
        stored: SessionRuntimeConfig(
          id: 7,
          groupId: 42,
          providerId: 'anthropic',
          modelId: 'claude-sonnet-4-5',
          providerStyle: ChatTurnProviderStyle.anthropicMessages,
        ),
      );
      final service = SessionRuntimeConfigService(
        settingsRepository: settingsRepository,
        runtimeConfigRepository: repository,
      );

      final restored = await service.loadPersisted(42);

      expect(restored, isNotNull);
      expect(restored!.providerId, 'anthropic');
      expect(restored.modelId, 'claude-sonnet-4-5');
      expect(restored.providerStyle, ChatTurnProviderStyle.anthropicMessages);
    });

    test('keeps side slot unset by default when updating primary runtime', () async {
      SharedPreferences.setMockInitialValues({});
      final preferences = await SharedPreferences.getInstance();
      final settingsRepository = AppSettingsRepository(
        preferences,
        localDefaultsLoader: () async => const LlmLocalDefaults(
          defaultProviderId: 'openai',
          defaultModelId: 'gpt-5.4',
          providers: [
            LlmProviderConfig(
              id: 'openai',
              name: 'OpenAI',
              apiKey: 'key',
              baseUrl: 'https://api.openai.com/v1/responses',
              models: [
                LlmProviderModel(id: 'gpt-5.4', name: 'GPT-5.4'),
              ],
            ),
            LlmProviderConfig(
              id: 'anthropic',
              name: 'Anthropic',
              apiKey: 'key',
              baseUrl: 'https://api.anthropic.com/v1/messages',
              models: [
                LlmProviderModel(id: 'claude-sonnet-4-5', name: 'Claude'),
              ],
            ),
          ],
        ),
      );
      final repository = _FakeSessionRuntimeConfigRepository();
      final service = SessionRuntimeConfigService(
        settingsRepository: settingsRepository,
        runtimeConfigRepository: repository,
      );

      final updated = await service.updateRuntime(
        groupId: 42,
        providerId: 'anthropic',
        modelId: 'claude-sonnet-4-5',
      );

      expect(updated.providerId, 'anthropic');
      expect(updated.modelId, 'claude-sonnet-4-5');
      expect(updated.sideProviderId, isNull);
      expect(updated.sideModelId, isNull);
      expect(updated.sideProviderStyle, isNull);
    });

    test('updates draft runtime without persisting to repository', () async {
      SharedPreferences.setMockInitialValues({});
      final preferences = await SharedPreferences.getInstance();
      final settingsRepository = AppSettingsRepository(
        preferences,
        localDefaultsLoader: () async => const LlmLocalDefaults(
          defaultProviderId: 'openai',
          defaultModelId: 'gpt-5.4',
          providers: [
            LlmProviderConfig(
              id: 'openai',
              name: 'OpenAI',
              apiKey: 'key',
              baseUrl: 'https://api.openai.com/v1/responses',
              models: [
                LlmProviderModel(id: 'gpt-5.4', name: 'GPT-5.4'),
              ],
            ),
            LlmProviderConfig(
              id: 'anthropic',
              name: 'Anthropic',
              apiKey: 'key',
              baseUrl: 'https://api.anthropic.com/v1/messages',
              models: [
                LlmProviderModel(id: 'claude-sonnet-4-5', name: 'Claude'),
              ],
            ),
          ],
        ),
      );
      final repository = _FakeSessionRuntimeConfigRepository();
      final service = SessionRuntimeConfigService(
        settingsRepository: settingsRepository,
        runtimeConfigRepository: repository,
      );

      final updated = await service.updateRuntime(
        groupId: SessionRuntimeConfigService.draftGroupId,
        providerId: 'anthropic',
        modelId: 'claude-sonnet-4-5',
      );

      expect(updated.groupId, SessionRuntimeConfigService.draftGroupId);
      expect(updated.providerId, 'anthropic');
      expect(updated.modelId, 'claude-sonnet-4-5');
      expect(updated.providerStyle, ChatTurnProviderStyle.anthropicMessages);
      expect(updated.sideProviderId, isNull);
      expect(updated.sideModelId, isNull);
      expect(updated.sideProviderStyle, isNull);
      expect(repository.stored, isNull);
    });
  });
}

class _FakeSessionRuntimeConfigRepository
    implements SessionRuntimeConfigRepository {
  _FakeSessionRuntimeConfigRepository({this.stored});

  SessionRuntimeConfig? stored;

  @override
  Future<SessionRuntimeConfig?> getByGroup(int groupId) async {
    final current = stored;
    if (current?.groupId != groupId) {
      return null;
    }
    return current;
  }

  @override
  Future<int> upsert(SessionRuntimeConfig config) async {
    stored = config.copyWith(id: stored?.id ?? 1);
    return stored!.id!;
  }
}
