import '../models/chat_turn.dart';
import '../models/llm/api_protocol_resolver.dart';
import '../models/session/session_runtime_config.dart';
import '../repositories/app_settings_repository.dart';
import '../repositories/session_runtime_config_repository.dart';

class SessionRuntimeConfigService {
  static const int draftGroupId = -1;

  SessionRuntimeConfigService({
    required AppSettingsRepository? settingsRepository,
    required SessionRuntimeConfigRepository? runtimeConfigRepository,
  })  : _settingsRepository = settingsRepository,
        _runtimeConfigRepository = runtimeConfigRepository;

  final AppSettingsRepository? _settingsRepository;
  final SessionRuntimeConfigRepository? _runtimeConfigRepository;

  Future<SessionRuntimeConfig> createDraftRuntime() async {
    final settingsRepository = _settingsRepository;
    if (settingsRepository == null) {
      throw StateError('app_settings_repository_unavailable');
    }
    final providers = await settingsRepository.getProviders();
    final selection = await settingsRepository.getSelectionState();
    final provider = providers.firstWhere(
      (item) => item.id == selection.defaultProviderId,
      orElse: () => providers.first,
    );
    final modelId = selection.defaultModelId ??
        (provider.models.isEmpty ? '' : provider.models.first.id);
    final apiStyle =
        provider.apiStyle ?? ApiProtocolResolver().resolveStyle(provider.baseUrl);
    return SessionRuntimeConfig(
      groupId: draftGroupId,
      providerId: provider.id,
      modelId: modelId,
      providerStyle: apiStyle.toChatTurnProviderStyle(),
    );
  }

  Future<SessionRuntimeConfig?> loadPersisted(int groupId) async {
    return _runtimeConfigRepository?.getByGroup(groupId);
  }

  Future<SessionRuntimeConfig> updateRuntime({
    required int groupId,
    required String providerId,
    required String modelId,
  }) async {
    final settingsRepository = _settingsRepository;
    if (settingsRepository == null) {
      throw StateError('app_settings_repository_unavailable');
    }

    final providers = await settingsRepository.getProviders();
    final provider = providers.firstWhere(
      (item) => item.id == providerId,
      orElse: () => throw StateError('provider_not_found:$providerId'),
    );
    final model = provider.models.firstWhere(
      (item) => item.id == modelId,
      orElse: () => throw StateError('model_not_found:$modelId'),
    );
    final apiStyle =
        provider.apiStyle ?? ApiProtocolResolver().resolveStyle(provider.baseUrl);
    final runtime = SessionRuntimeConfig(
      groupId: groupId,
      providerId: provider.id,
      modelId: model.id,
      providerStyle: apiStyle.toChatTurnProviderStyle(),
    );

    if (groupId != draftGroupId) {
      await _runtimeConfigRepository?.upsert(runtime);
    }
    return runtime;
  }
}
