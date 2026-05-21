import 'base_llm.dart';
import 'configurable_http_llm.dart';
import '../../repositories/app_settings_repository.dart';

enum LLMType {
  configurable,
  chatGPT,
}

class LLMFactory {
  static BaseLLM createLLM(
    LLMType type, {
    required AppSettingsRepository settingsRepository,
    String chatCompletionsAdapterType = 'sdk',
  }) {
    switch (type) {
      case LLMType.configurable:
        final llm = ConfigurableHttpLLM(settingsRepository: settingsRepository);
        if (chatCompletionsAdapterType != 'sdk') {
          llm.setChatCompletionsAdapter(chatCompletionsAdapterType);
        }
        return llm;
      case LLMType.chatGPT:
        throw UnimplementedError('ChatGPT模型尚未实现');
    }
  }
}
