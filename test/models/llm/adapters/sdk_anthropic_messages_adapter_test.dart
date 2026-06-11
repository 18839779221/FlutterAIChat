import 'package:ai_chat/models/chat_message.dart';
import 'package:ai_chat/models/llm/adapters/sdk_anthropic_messages_adapter.dart';
import 'package:ai_chat/models/llm/llm_request_options.dart';
import 'package:ai_chat/services/chat_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('uses requestOptions maxOutputTokens for anthropic sdk payload', () {
    const adapter = SdkAnthropicMessagesAdapter();
    final payload = adapter.buildChatPayload(
      messages: [ChatMessage(text: 'hi', role: MessageRole.user)],
      config: ChatConfig(systemPrompt: ''),
      modelName: 'claude',
      stream: false,
      requestOptions: const LlmRequestOptions(maxOutputTokens: 12000),
    );

    expect(payload['max_tokens'], 12000);
  });
}
