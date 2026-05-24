import 'package:ai_chat/models/llm/adapters/anthropic_messages_adapter.dart';
import 'package:ai_chat/models/llm/adapters/responses_adapter.dart';
import 'package:ai_chat/models/llm/adapters/sdk_chat_completions_adapter.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ApiStyleAdapter contract', () {
    test('chat completions contract declares planner streaming support', () {
      const adapter = SdkChatCompletionsAdapter();

      expect(adapter.capabilities.supportsPlannerStreaming, isTrue);
      expect(adapter.capabilities.supportsParallelToolCalls, isTrue);
    });

    test('responses contract exposes parseDecision entrypoint', () {
      const adapter = ResponsesAdapter();

      expect(
        adapter.parseDecision({'output': const []}),
        isNull,
      );
    });

    test('anthropic contract exposes parseDecision entrypoint', () {
      const adapter = AnthropicMessagesAdapter();

      expect(
        adapter.parseDecision({'content': const []}),
        isNull,
      );
    });
  });
}
