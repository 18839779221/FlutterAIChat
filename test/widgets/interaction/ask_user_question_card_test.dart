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
    expect(find.text('提交并继续'), findsNothing);
    expect(find.text('跳过'), findsOneWidget);
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNull,
    );
    expect(
      tester.widget<TextButton>(find.widgetWithText(TextButton, '跳过')).onPressed,
      isNotNull,
    );
  });

  testWidgets('selecting an option enables next question action', (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: Scaffold(
            body: AskUserQuestionCard(
              message: ChatMessage(
                id: 430,
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

    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNull,
    );

    await tester.tap(find.text('SQLite'));
    await tester.pump();

    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNotNull,
    );
  });

  testWidgets('last question shows submit action instead of next action', (
    tester,
  ) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    container.read(questionCardDraftsProvider.notifier).setCurrentQuestionIndex(
          messageId: 47,
          index: 1,
        );

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: Scaffold(
            body: AskUserQuestionCard(
              message: ChatMessage(
                id: 47,
                text: 'Need two answers',
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
                    {
                      'id': 'offline_mode',
                      'header': 'Offline',
                      'question': 'Do we need offline mode?',
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

    expect(find.text('问题 2 / 2'), findsOneWidget);
    expect(find.text('提交并继续'), findsOneWidget);
    expect(find.text('下一题'), findsNothing);
  });

  testWidgets('skip advances to the next question automatically', (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: Scaffold(
            body: AskUserQuestionCard(
              message: ChatMessage(
                id: 48,
                text: 'Need two answers',
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
                    {
                      'id': 'offline_mode',
                      'header': 'Offline',
                      'question': 'Do we need offline mode?',
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

    await tester.tap(find.text('跳过'));
    await tester.pump();

    expect(find.text('问题 2 / 2'), findsOneWidget);
    expect(find.text('Do we need offline mode?'), findsOneWidget);
  });

  testWidgets(
      'ask user question card expands naturally without inner vertical scroll view',
      (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    final options = List.generate(
      18,
      (index) => {
        'label': 'Option ${index + 1}',
        'description': 'Description ${index + 1}',
      },
    );

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: Scaffold(
            body: ListView(
              children: [
                AskUserQuestionCard(
                  message: ChatMessage(
                    id: 44,
                    text: 'Need one answer',
                    role: MessageRole.assistant,
                    payloadJson: {
                      'questions': [
                        {
                          'id': 'long_list',
                          'header': 'Long List',
                          'question': 'Choose one option',
                          'multiSelect': false,
                          'options': options,
                        },
                      ],
                      'agentTurnId': 42,
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    final lastOption = find.text('Option 18');
    expect(
      find.descendant(
        of: find.byType(AskUserQuestionCard),
        matching: find.byType(Scrollable),
      ),
      findsNothing,
    );
    expect(lastOption, findsOneWidget);
  });

  testWidgets('ask user question card does not render inner vertical scrollables',
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
                id: 45,
                text: 'Need one answer',
                role: MessageRole.assistant,
                payloadJson: const {
                  'questions': [
                    {
                      'id': 'nested_scroll',
                      'header': 'Nested Scroll',
                      'question': 'Choose one option',
                      'multiSelect': false,
                      'options': [
                        {
                          'label': 'Option 1',
                          'description': 'Description 1',
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

    expect(
      find.descendant(
        of: find.byType(AskUserQuestionCard),
        matching: find.byType(Scrollable),
      ),
      findsNothing,
    );
  });

  testWidgets('dragging on option tile keeps question card content visible',
      (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    final options = List.generate(
      18,
      (index) => {
        'label': 'Option ${index + 1}',
        'description': 'Description ${index + 1}',
      },
    );

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: Scaffold(
            body: ListView(
              children: [
                AskUserQuestionCard(
                  message: ChatMessage(
                    id: 46,
                    text: 'Need one answer',
                    role: MessageRole.assistant,
                    payloadJson: {
                      'questions': [
                        {
                          'id': 'long_list_drag_tile',
                          'header': 'Long List',
                          'question': 'Choose one option',
                          'multiSelect': false,
                          'options': options,
                        },
                      ],
                      'agentTurnId': 42,
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    final lastOption = find.text('Option 18');
    final optionTile = find.text('Option 3');
    expect(lastOption, findsOneWidget);

    await tester.drag(optionTile, const Offset(0, -120));
    await tester.pumpAndSettle();

    expect(optionTile, findsOneWidget);
    expect(lastOption, findsOneWidget);
  });
}
