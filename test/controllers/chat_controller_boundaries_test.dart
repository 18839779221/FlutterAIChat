import 'package:ai_chat/controllers/chat_controller.dart';
import 'package:ai_chat/controllers/chat_send_coordinator.dart';
import 'package:ai_chat/controllers/chat_session_coordinator.dart';
import 'package:ai_chat/providers/chat_providers.dart'
    show
        chatControllerProvider,
        chatSendCoordinatorProvider,
        chatSessionCoordinatorProvider;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('chat providers expose dedicated controller and coordinator types', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    expect(container.read(chatControllerProvider), isA<ChatController>());
    expect(container.read(chatSendCoordinatorProvider), isA<ChatSendCoordinator>());
    expect(
      container.read(chatSessionCoordinatorProvider),
      isA<ChatSessionCoordinator>(),
    );
  });
}
