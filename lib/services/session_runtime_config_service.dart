import '../models/llm/api_protocol_resolver.dart';
import '../models/llm/llm_provider_config.dart';
import '../models/llm/llm_provider_model.dart';
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

  Future<SessionRuntimeConfig> createDraftRuntime({
    SessionRuntimeConfig? currentRuntime,
  }) async {
    final settingsRepository = _settingsRepository;
    if (settingsRepository == null) {
      throw StateError('app_settings_repository_unavailable');
    }
    final providers = await settingsRepository.getProviders();
    if (providers.isEmpty) {
      throw Exception('请先在设置中新增提供方');
    }
    final inherited = _resolveRuntimeIfValid(
      providers: providers,
      runtime: currentRuntime,
    );
    final selection = await settingsRepository.getSelectionState();
    final selected = _resolveSelectedRuntime(
      providers: providers,
      selectedProviderId: selection.selectedProviderId,
      selectedModelId: selection.selectedModelId,
    );
    final resolved = inherited ?? selected ?? _resolveFirstAvailableRuntime(providers);
    final provider = resolved.$1;
    final model = resolved.$2;
    final sideModel = _resolveExplicitSideModel(provider);
    final apiStyle = provider.apiStyle ??
        const ApiProtocolResolver().resolveStyle(provider.baseUrl);
    return SessionRuntimeConfig(
      groupId: draftGroupId,
      providerId: provider.id,
      modelId: model.id,
      providerStyle: apiStyle.toChatTurnProviderStyle(),
      sideProviderId: sideModel == null ? null : provider.id,
      sideModelId: sideModel?.id,
      sideProviderStyle:
          sideModel == null ? null : apiStyle.toChatTurnProviderStyle(),
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
    final apiStyle = provider.apiStyle ??
        const ApiProtocolResolver().resolveStyle(provider.baseUrl);
    final sideModel = _resolveExplicitSideModel(provider);
    final runtime = SessionRuntimeConfig(
      groupId: groupId,
      providerId: provider.id,
      modelId: model.id,
      providerStyle: apiStyle.toChatTurnProviderStyle(),
      sideProviderId: sideModel == null ? null : provider.id,
      sideModelId: sideModel?.id,
      sideProviderStyle:
          sideModel == null ? null : apiStyle.toChatTurnProviderStyle(),
    );

    if (groupId != draftGroupId) {
      await _runtimeConfigRepository?.upsert(runtime);
    }
    return runtime;
  }

  (LlmProviderConfig, LlmProviderModel)? _resolveRuntimeIfValid({
    required List<LlmProviderConfig> providers,
    required SessionRuntimeConfig? runtime,
  }) {
    if (runtime == null) {
      return null;
    }
    for (final provider in providers) {
      if (provider.id != runtime.providerId) {
        continue;
      }
      for (final model in provider.models) {
        if (model.id == runtime.modelId) {
          return (provider, model);
        }
      }
      return null;
    }
    return null;
  }

  (LlmProviderConfig, LlmProviderModel)? _resolveSelectedRuntime({
    required List<LlmProviderConfig> providers,
    required String? selectedProviderId,
    required String? selectedModelId,
  }) {
    for (final provider in providers) {
      if (provider.id != selectedProviderId) {
        continue;
      }
      if (provider.models.isEmpty) {
        return null;
      }
      for (final model in provider.models) {
        if (model.id == selectedModelId) {
          return (provider, model);
        }
      }
      return (provider, provider.models.first);
    }
    return null;
  }

  (LlmProviderConfig, LlmProviderModel) _resolveFirstAvailableRuntime(
    List<LlmProviderConfig> providers,
  ) {
    final provider = providers.first;
    if (provider.models.isEmpty) {
      throw Exception('请先在设置中为当前提供方配置模型');
    }
    return (provider, provider.models.first);
  }

  LlmProviderModel? _resolveExplicitSideModel(LlmProviderConfig provider) {
    final configuredSideModelId = provider.sideModelId;
    if (configuredSideModelId != null) {
      for (final model in provider.models) {
        if (model.id == configuredSideModelId) {
          return model;
        }
      }
    }
    return null;
  }
}
