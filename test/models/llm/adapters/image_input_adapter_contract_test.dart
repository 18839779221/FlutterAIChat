import 'package:ai_chat/models/llm/adapters/sdk_anthropic_messages_adapter.dart';
import 'package:ai_chat/models/llm/adapters/sdk_chat_completions_adapter.dart';
import 'package:ai_chat/models/llm/adapters/sdk_responses_adapter.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('responses and anthropic adapters advertise image input support', () {
    expect(const SdkResponsesAdapter().capabilities.supportsImageInput, isTrue);
    expect(
      const SdkAnthropicMessagesAdapter().capabilities.supportsImageInput,
      isTrue,
    );
    expect(
      const SdkChatCompletionsAdapter().capabilities.supportsImageInput,
      isTrue,
    );
  });
}
