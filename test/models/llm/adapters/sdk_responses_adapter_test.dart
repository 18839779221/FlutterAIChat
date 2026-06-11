import 'package:ai_chat/models/chat_message.dart';
import 'package:ai_chat/models/llm/adapters/sdk_responses_adapter.dart';
import 'package:ai_chat/models/llm/llm_request_options.dart';
import 'package:ai_chat/services/chat_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('writes max_output_tokens into responses payload', () {
    const adapter = SdkResponsesAdapter();
    final payload = adapter.buildChatPayload(
      messages: [ChatMessage(text: '继续', role: MessageRole.user)],
      config: ChatConfig(systemPrompt: ''),
      modelName: 'gpt-5',
      stream: false,
      requestOptions: const LlmRequestOptions(maxOutputTokens: 4096),
    );

    expect(payload['max_output_tokens'], 4096);
  });
}
