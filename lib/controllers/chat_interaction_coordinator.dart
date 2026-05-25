import 'package:ai_chat/controllers/chat_send_coordinator.dart';
import 'package:ai_chat/models/chat_message.dart';
import 'package:ai_chat/models/interaction/ask_user_question_request.dart';
import 'package:ai_chat/models/interaction/ask_user_question_response.dart';
import 'package:ai_chat/providers/chat_interaction_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

abstract class ChatInteractionCoordinator {
  Future<void> submitQuestionAnswers(ChatMessage message);

  Future<void> skipCurrentQuestion(ChatMessage message);

  Future<void> cancelQuestionPrompt(ChatMessage message);
}

class DefaultChatInteractionCoordinator implements ChatInteractionCoordinator {
  final Ref _ref;
  final ChatSendCoordinator _sendCoordinator;

  DefaultChatInteractionCoordinator(
    this._ref, {
    required ChatSendCoordinator sendCoordinator,
  }) : _sendCoordinator = sendCoordinator;

  @override
  Future<void> submitQuestionAnswers(ChatMessage message) async {
    final messageId = message.id;
    final payload = message.payloadJson;
    if (messageId == null || payload == null) {
      return;
    }
    final request = AskUserQuestionRequest.fromJson(payload);
    final draft = _ref.read(questionCardDraftsProvider)[messageId] ??
        const QuestionCardDraft();
    final answersByQuestionId = <String, String>{};
    final selectedByQuestionId = <String, List<String>>{};
    final freeTextByQuestionId = <String, String>{};
    for (final question in request.questions) {
      final hasDraftEntry =
          draft.selectedOptionLabelsByQuestionId.containsKey(question.id);
      final selected = List<String>.from(
        draft.selectedOptionLabelsByQuestionId[question.id] ?? const [],
      );
      if (!hasDraftEntry) {
        continue;
      }
      selectedByQuestionId[question.id] = selected;
      final answer = resolveAnswerText(draft: draft, question: question);
      answersByQuestionId[question.id] = answer;
      final otherText = draft.otherTextByQuestionId[question.id]?.trim() ?? '';
      if (otherText.isNotEmpty) {
        freeTextByQuestionId[question.id] = otherText;
      }
    }

    await _sendCoordinator.submitQuestionAnswers(
      message,
      response: AskUserQuestionResponse(
        answersByQuestionId: answersByQuestionId,
        selectedOptionLabelsByQuestionId: selectedByQuestionId,
        freeTextAnswersByQuestionId: freeTextByQuestionId,
      ),
    );
    _ref.read(questionCardDraftsProvider.notifier).clearDraft(messageId);
  }

  @override
  Future<void> skipCurrentQuestion(ChatMessage message) async {
    final messageId = message.id;
    final payload = message.payloadJson;
    if (messageId == null || payload == null) {
      return;
    }

    final request = AskUserQuestionRequest.fromJson(payload);
    final draft = _ref.read(questionCardDraftsProvider)[messageId] ??
        const QuestionCardDraft();
    final questionIndex = draft.currentQuestionIndex.clamp(
      0,
      request.questions.length - 1,
    );
    final question = request.questions[questionIndex];
    final nextIndex = questionIndex >= request.questions.length - 1
        ? questionIndex
        : questionIndex + 1;

    final notifier = _ref.read(questionCardDraftsProvider.notifier);
    notifier.setSkipped(
      messageId: messageId,
      questionId: question.id,
    );
    notifier.setCurrentQuestionIndex(
      messageId: messageId,
      index: nextIndex,
    );
  }

  @override
  Future<void> cancelQuestionPrompt(ChatMessage message) async {
    final messageId = message.id;
    if (messageId == null) {
      return;
    }
    _ref.read(questionCardDraftsProvider.notifier).clearDraft(messageId);
  }
}
