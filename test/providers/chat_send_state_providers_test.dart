import 'package:ai_chat/providers/chat_send_state_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('chatSendStateProvider', () {
    test('默认处于 idle 且未生成', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      expect(container.read(sendPhaseProvider), ChatSendPhase.idle);
      expect(container.read(isGeneratingProvider), isFalse);
    });

    test('更新统一状态后派生 provider 同步变化', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      container.read(chatSendStateProvider.notifier).update(
            phase: ChatSendPhase.streamingResponse,
            isGenerating: true,
          );

      expect(
          container.read(sendPhaseProvider), ChatSendPhase.streamingResponse);
      expect(container.read(isGeneratingProvider), isTrue);
    });

    test('进入流式回复阶段会清理 transient 重试文案', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final notifier = container.read(chatSendStateProvider.notifier);
      notifier.update(
        phase: ChatSendPhase.preparing,
        isGenerating: false,
        statusText: '请求失败，正在重试 1/5',
      );

      notifier.update(
        phase: ChatSendPhase.streamingResponse,
        isGenerating: true,
      );

      final state = container.read(chatSendStateProvider);
      expect(state.phase, ChatSendPhase.streamingResponse);
      expect(state.isGenerating, isTrue);
      expect(state.statusText, isNull);
    });
  });
}
