import 'package:ai_chat/models/llm/base_llm.dart';
import 'package:ai_chat/models/chat_message.dart';
import 'package:ai_chat/providers/chat_dependency_providers.dart';
import 'package:ai_chat/services/chat_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('chatServiceProvider delegates to chatServiceFactoryProvider override',
      () {
    final expected = ChatService(llm: _NoopBaseLLM());
    final container = ProviderContainer(
      overrides: [
        chatServiceFactoryProvider.overrideWith((ref) => expected),
      ],
    );
    addTearDown(container.dispose);

    expect(identical(container.read(chatServiceProvider), expected), isTrue);
  });
}

class _NoopBaseLLM extends BaseLLM {
  @override
  Map<String, dynamic> get config => const {};

  @override
  String getModelName(ChatConfig config) => 'noop';

  @override
  Stream<String> chatStream(List<ChatMessage> messages, ChatConfig config) async* {}

  @override
  Future<bool> validateApiKey(ChatConfig config) async => true;

  @override
  Future<String> summarizeConversation(List<ChatMessage> messages) async => '';

  @override
  Future<String> structureSummaryCard(String sourceText) async => '';
}
