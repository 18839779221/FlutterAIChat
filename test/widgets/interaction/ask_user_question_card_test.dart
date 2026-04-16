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
    expect(find.text('继续当前回合所需信息'), findsOneWidget);
    expect(find.text('问题 1 / 1'), findsOneWidget);
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

  testWidgets('multi-question card shows progress and next action', (
    tester,
  ) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: Scaffold(
            body: AskUserQuestionCard(
              message: ChatMessage(
                id: 43,
                text: 'Need two answers',
                role: MessageRole.assistant,
                payloadJson: const {
                  'questions': [
                    {
                      'id': 'storage_layer',
                      'header': 'Storage',
                      'question': 'Which storage layer should we use?',
                      'multiSelect': false,
                      'options': [
                        {'label': 'SQLite', 'description': 'Local relational store'},
                      ],
                    },
                    {
                      'id': 'offline_mode',
                      'header': 'Offline',
                      'question': 'Do we need offline mode?',
                      'multiSelect': false,
                      'options': [
                        {'label': 'Yes', 'description': 'Support offline'},
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

    expect(find.text('问题 1 / 2'), findsOneWidget);
    expect(find.text('下一题'), findsOneWidget);
    expect(find.text('提交并继续'), findsOneWidget);
  });
}
