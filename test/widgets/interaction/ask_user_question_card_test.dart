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

  testWidgets('long option list can scroll to reveal items beyond first screen',
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
            body: SizedBox(
              height: 420,
              child: AskUserQuestionCard(
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
            ),
          ),
        ),
      ),
    );

    final lastOption = find.text('Option 18');
    final viewportBottom = tester.getRect(find.byType(Scaffold)).bottom;
    expect(lastOption, findsNothing);

    await tester.scrollUntilVisible(
      lastOption,
      200,
      scrollable: find.descendant(
        of: find.byKey(const ValueKey('ask-user-question-scroll')),
        matching: find.byType(Scrollable),
      ),
    );
    await tester.pumpAndSettle();

    expect(lastOption, findsOneWidget);
    expect(tester.getRect(lastOption).bottom, lessThanOrEqualTo(viewportBottom));
  });

  testWidgets('inner list view is non-primary for nested chat timeline usage',
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

    final scrollView = tester.widget<ListView>(find.byType(ListView));
    expect(scrollView.primary, isFalse);
  });

  testWidgets('dragging on option tile still scrolls long question content',
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
            body: SizedBox(
              height: 420,
              child: AskUserQuestionCard(
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
            ),
          ),
        ),
      ),
    );

    final lastOption = find.text('Option 18');
    final viewportBottom = tester.getRect(find.byType(Scaffold)).bottom;
    final scrollable = find.descendant(
      of: find.byKey(const ValueKey('ask-user-question-scroll')),
      matching: find.byType(Scrollable),
    );
    expect(lastOption, findsNothing);

    await tester.drag(find.text('Option 3'), const Offset(0, -800));
    await tester.pumpAndSettle();

    final position =
        tester.state<ScrollableState>(scrollable).position.pixels;
    expect(position, greaterThan(0));
    await tester.scrollUntilVisible(lastOption, 200, scrollable: scrollable);
    await tester.pumpAndSettle();
    expect(lastOption, findsOneWidget);
    expect(tester.getRect(lastOption).bottom, lessThanOrEqualTo(viewportBottom));
  });
}
