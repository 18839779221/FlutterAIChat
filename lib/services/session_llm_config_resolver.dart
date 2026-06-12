import '../models/llm/api_protocol_resolver.dart';
import '../models/llm/llm_config.dart';
import '../models/llm/llm_provider_config.dart';
import '../models/llm/llm_provider_model.dart';
import '../models/session/session_runtime_config.dart';
import '../repositories/app_settings_repository.dart';

class SessionLlmConfigResolver {
  SessionLlmConfigResolver(this._settingsRepository);

  final AppSettingsRepository _settingsRepository;

  Future<LLMConfig> resolve(
    SessionRuntimeConfig runtimeConfig, {
    SessionRuntimeSlot slot = SessionRuntimeSlot.primary,
  }) async {
    final providers = await _settingsRepository.getProviders();
    final providerId = runtimeConfig.providerIdForSlot(slot);
    final provider = providers.firstWhere(
      (item) => item.id == providerId,
      orElse: () => throw StateError(
        'provider_not_found:$providerId',
      ),
    );
    final modelId = runtimeConfig.modelIdForSlot(slot);
    final model = _resolveModel(provider, modelId);
    if (model == null) {
      throw StateError('model_not_found:$modelId');
    }
    final apiStyle = provider.apiStyle ??
        const ApiProtocolResolver().resolveStyle(provider.baseUrl);

    return LLMConfig(
      apiKey: provider.apiKey,
      apiUrl: provider.baseUrl,
      model: model.id,
      apiStyle: apiStyle,
      additionalConfig: {
        'llm.selected_provider_id': provider.id,
        'llm.selected_model_id': model.id,
        'llm.selected_api_style': apiStyle.name,
        'llm.selected_base_url': provider.baseUrl,
        'llm.runtime_slot': slot.name,
        'llm.selected_model_supports_image_input': model.supportsImageInput,
        'llm.runtime_selected_model_supports_image_input':
            await _settingsRepository.getRuntimeImageInputSupport(
          providerId: provider.id,
          modelId: model.id,
        ),
      },
    );
  }

  LlmProviderModel? _resolveModel(
    LlmProviderConfig provider,
    String modelId,
  ) {
    for (final model in provider.models) {
      if (model.id == modelId) {
        return model;
      }
    }
    return null;
  }
}
