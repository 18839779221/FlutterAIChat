import 'package:ai_chat/models/chat_message.dart';
import 'package:ai_chat/models/chat/send_message_request.dart';
import 'package:ai_chat/models/interaction/ask_user_question_item.dart';
import 'package:ai_chat/models/interaction/ask_user_question_response.dart';
import 'package:ai_chat/providers/chat_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('submitQuestionAnswers builds response from draft and delegates to send coordinator',
      () async {
    final sendCoordinator = _RecordingChatSendCoordinator();
    final container = ProviderContainer(
      overrides: [
        chatSendCoordinatorProvider.overrideWithValue(sendCoordinator),
      ],
    );
    addTearDown(container.dispose);

    const messageId = 77;
    container.read(questionCardDraftsProvider.notifier).selectOption(
          messageId: messageId,
          questionId: 'storage_layer',
          label: 'SQLite',
          multiSelect: false,
        );

    final coordinator = container.read(chatInteractionCoordinatorProvider);
    final message = ChatMessage(
      id: messageId,
      text: 'Which storage layer should we use?',
      role: MessageRole.assistant,
      status: MessageStatus.completed,
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
    );

    await coordinator.submitQuestionAnswers(message);

    expect(sendCoordinator.submittedMessage, same(message));
    expect(
      sendCoordinator.submittedResponse?.answersByQuestionId,
      containsPair('storage_layer', 'SQLite'),
    );
  });

  test('cancelQuestionPrompt clears local draft state', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    const messageId = 78;
    container.read(questionCardDraftsProvider.notifier).setOtherText(
          messageId: messageId,
          questionId: 'storage_layer',
          value: 'Custom value',
        );

    final coordinator = container.read(chatInteractionCoordinatorProvider);
    await coordinator.cancelQuestionPrompt(
      ChatMessage(
        id: messageId,
        text: 'Question',
        role: MessageRole.assistant,
      ),
    );

    expect(container.read(questionCardDraftsProvider)[messageId], isNull);
  });

  test('skipCurrentQuestion records empty-string answer semantics', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    const messageId = 79;
    final coordinator = container.read(chatInteractionCoordinatorProvider);

    await coordinator.skipCurrentQuestion(
      ChatMessage(
        id: messageId,
        text: 'Need more info',
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
    );

    final draft = container.read(questionCardDraftsProvider)[messageId];
    expect(draft?.selectedOptionLabelsByQuestionId, containsPair('storage_layer', <String>[]));
    expect(
      resolveAnswerText(
        draft: draft!,
        question: const AskUserQuestionItem(
          id: 'storage_layer',
          header: 'Storage',
          question: 'Which storage layer should we use?',
          multiSelect: false,
          options: [],
        ),
      ),
      '',
    );
  });
}

class _RecordingChatSendCoordinator implements ChatSendCoordinator {
  ChatMessage? submittedMessage;
  AskUserQuestionResponse? submittedResponse;

  @override
  Future<void> cancelToolInvocation(ChatMessage message) async {}

  @override
  Future<void> confirmToolInvocation(
    ChatMessage message, {
    bool trustTool = false,
  }) async {}

  @override
  Future<void> sendMessage(
    String text, {
    required void Function() scheduleAutoSummary,
    required void Function() cancelActiveStream,
  }) async {}

  @override
  Future<void> sendMessageRequest(
    SendMessageRequest request, {
    required void Function() scheduleAutoSummary,
    required void Function() cancelActiveStream,
  }) async {}

  @override
  Future<void> submitQuestionAnswers(
    ChatMessage message, {
    required AskUserQuestionResponse response,
  }) async {
    submittedMessage = message;
    submittedResponse = response;
  }
}
