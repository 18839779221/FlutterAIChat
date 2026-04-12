import 'package:ai_chat/providers/chat_ui_providers.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('chat ui providers', () {
    test('默认 UI 状态符合聊天页预期', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      expect(container.read(autoScrollToBottomProvider), isTrue);
      expect(container.read(hasMoreMessagesProvider), isTrue);
      expect(container.read(isLoadingMoreProvider), isFalse);
      expect(container.read(isInitializingProvider), isTrue);
    });

    test('controller providers expose Flutter controllers', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      expect(container.read(scrollControllerProvider), isA<ScrollController>());
      expect(
        container.read(textControllerProvider),
        isA<TextEditingController>(),
      );
      expect(container.read(focusNodeProvider), isA<FocusNode>());
    });
  });
}
