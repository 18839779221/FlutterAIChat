import 'package:ai_chat/providers/chat_providers.dart';
import 'package:ai_chat/theme/app_theme.dart';
import 'package:ai_chat/widgets/chat_input.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('chat input shows compact reply tray when idle', (
    tester,
  ) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: AppTheme.light(),
          home: const Scaffold(body: ChatInput()),
        ),
      ),
    );

    expect(find.byKey(const ValueKey('chat-input-dock')), findsOneWidget);
    expect(find.byKey(const ValueKey('chat-input-panel')), findsOneWidget);
    expect(find.text('Balanced · 可追溯输出'), findsNothing);
    expect(find.text('深度'), findsNothing);
    expect(find.text('简洁'), findsNothing);
    expect(find.byKey(const ValueKey('chat-input-idle-note')), findsNothing);
    expect(find.byIcon(Icons.arrow_upward_rounded), findsOneWidget);

    final textField = tester
        .widget<TextField>(find.byKey(const ValueKey('chat-input-field')));
    expect(textField.minLines, 1);
    expect(textField.maxLines, 4);
  });

  testWidgets('chat input does not show pending label while awaiting confirmation', (
    tester,
  ) async {
    final container = ProviderContainer(
      overrides: [
        chatSendStateProvider.overrideWith(
          (ref) => ChatSendStateNotifier()
            ..update(
              phase: ChatSendPhase.awaitingConfirmation,
              isGenerating: false,
            ),
        ),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: AppTheme.light(),
          home: const Scaffold(body: ChatInput()),
        ),
      ),
    );

    expect(find.text('等待工具确认'), findsNothing);
  });

  testWidgets('chat input does not show planner hint while preparing', (tester) async {
    final container = ProviderContainer(
      overrides: [
        chatSendStateProvider.overrideWith(
          (ref) => ChatSendStateNotifier()
            ..update(
              phase: ChatSendPhase.preparing,
              isGenerating: false,
            ),
        ),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: AppTheme.light(),
          home: const Scaffold(body: ChatInput()),
        ),
      ),
    );

    expect(find.text('正在规划下一步'), findsNothing);
  });

  testWidgets('chat input does not show tool running helper text', (tester) async {
    final container = ProviderContainer(
      overrides: [
        chatSendStateProvider.overrideWith(
          (ref) => ChatSendStateNotifier()
            ..update(
              phase: ChatSendPhase.executingTool,
              isGenerating: false,
            ),
        ),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: AppTheme.light(),
          home: const Scaffold(body: ChatInput()),
        ),
      ),
    );

    expect(find.text('工具执行中'), findsNothing);
  });

  testWidgets('chat input shows stop icon instead of spinner while streaming', (
    tester,
  ) async {
    final container = ProviderContainer(
      overrides: [
        chatSendStateProvider.overrideWith(
          (ref) => ChatSendStateNotifier()
            ..update(
              phase: ChatSendPhase.streamingResponse,
              isGenerating: true,
            ),
        ),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: AppTheme.light(),
          home: const Scaffold(body: ChatInput()),
        ),
      ),
    );

    expect(find.byIcon(Icons.stop_rounded), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });
}
