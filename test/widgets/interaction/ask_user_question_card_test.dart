import 'package:ai_chat/models/chat_message.dart';
import 'package:ai_chat/providers/chat_interaction_providers.dart';
import 'package:ai_chat/widgets/interaction/ask_user_question_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('single-select question renders options and submits selected answer',
      (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: Scaffold(
            body: AskUserQuestionCard(
              message: ChatMessage(
                id: 41,
                text: 'Which storage layer should we use?',
                role: MessageRole.assistant,
                payloadJson: const {
                  'questions': [
                    {
                      'id': 'storage_layer',
                      'header': 'Storage',
                      'question': 'Which storage layer should we use?',
                      'multiSelect': false,
                      'options': [
                        {
                          'label': 'SQLite',
                          'description': 'Local relational store',
                        },
                      ],
                    },
                  ],
                  'agentTurnId': 42,
                },
              ),
            ),
          ),
        ),
      ),
    );

    expect(find.text('Which storage layer should we use?'), findsOneWidget);
    await tester.tap(find.text('SQLite'));
    await tester.pump();

    final draft = container.read(questionCardDraftsProvider)[41];
    expect(draft?.selectedOptionLabelsByQuestionId['storage_layer'], ['SQLite']);
  });

  testWidgets('selecting Other reveals input field', (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: Scaffold(
            body: AskUserQuestionCard(
              message: ChatMessage(
                id: 42,
                text: 'Which storage layer should we use?',
                role: MessageRole.assistant,
                payloadJson: const {
                  'questions': [
                    {
                      'id': 'storage_layer',
                      'header': 'Storage',
                      'question': 'Which storage layer should we use?',
                      'multiSelect': false,
                      'options': [],
                    },
                  ],
                  'agentTurnId': 42,
                },
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Other'));
    await tester.pump();

    expect(find.byType(TextField), findsOneWidget);
  });
}
