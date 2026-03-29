import 'package:ai_chat/providers/chat_providers.dart';
import 'package:ai_chat/theme/app_theme.dart';
import 'package:ai_chat/widgets/chat_input.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('chat input shows compact status row and send label when idle', (
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

    expect(find.text('发送'), findsOneWidget);
    expect(find.text('Balanced · 可追溯输出'), findsOneWidget);
  });

  testWidgets('chat input shows pending label while awaiting confirmation', (
    tester,
  ) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    container.read(sendPhaseProvider.notifier).state =
        ChatSendPhase.awaitingConfirmation;

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: AppTheme.light(),
          home: const Scaffold(body: ChatInput()),
        ),
      ),
    );

    expect(find.text('等待工具确认'), findsOneWidget);
  });
}
