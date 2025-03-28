import 'base_llm.dart';
import 'deepseek_llm.dart';
import 'llm_config.dart';

enum LLMType {
  deepseek,
  chatGPT,
}

class LLMFactory {
  static BaseLLM createLLM(LLMType type) {
    switch (type) {
      case LLMType.deepseek:
        return DeepSeekLLM();
      case LLMType.chatGPT:
        throw UnimplementedError('ChatGPT模型尚未实现');
    }
  }
} 