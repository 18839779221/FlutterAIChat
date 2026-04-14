import 'package:ai_chat/models/interaction/ask_user_question_item.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class QuestionCardDraft {
  final int currentQuestionIndex;
  final Map<String, List<String>> selectedOptionLabelsByQuestionId;
  final Map<String, String> otherTextByQuestionId;

  const QuestionCardDraft({
    this.currentQuestionIndex = 0,
    this.selectedOptionLabelsByQuestionId = const {},
    this.otherTextByQuestionId = const {},
  });

  QuestionCardDraft copyWith({
    int? currentQuestionIndex,
    Map<String, List<String>>? selectedOptionLabelsByQuestionId,
    Map<String, String>? otherTextByQuestionId,
  }) {
    return QuestionCardDraft(
      currentQuestionIndex: currentQuestionIndex ?? this.currentQuestionIndex,
      selectedOptionLabelsByQuestionId:
          selectedOptionLabelsByQuestionId ?? this.selectedOptionLabelsByQuestionId,
      otherTextByQuestionId: otherTextByQuestionId ?? this.otherTextByQuestionId,
    );
  }
}

class QuestionCardDraftsNotifier extends StateNotifier<Map<int, QuestionCardDraft>> {
  QuestionCardDraftsNotifier() : super(const {});

  void selectOption({
    required int messageId,
    required String questionId,
    required String label,
    required bool multiSelect,
  }) {
    final current = state[messageId] ?? const QuestionCardDraft();
    final currentSelections = List<String>.from(
      current.selectedOptionLabelsByQuestionId[questionId] ?? const [],
    );
    if (multiSelect) {
      if (currentSelections.contains(label)) {
        currentSelections.remove(label);
      } else {
        currentSelections.add(label);
      }
    } else {
      currentSelections
        ..clear()
        ..add(label);
    }
    state = {
      ...state,
      messageId: current.copyWith(
        selectedOptionLabelsByQuestionId: {
          ...current.selectedOptionLabelsByQuestionId,
          questionId: currentSelections,
        },
      ),
    };
  }

  void setOtherText({
    required int messageId,
    required String questionId,
    required String value,
  }) {
    final current = state[messageId] ?? const QuestionCardDraft();
    state = {
      ...state,
      messageId: current.copyWith(
        otherTextByQuestionId: {
          ...current.otherTextByQuestionId,
          questionId: value,
        },
      ),
    };
  }

  void setCurrentQuestionIndex({
    required int messageId,
    required int index,
  }) {
    final current = state[messageId] ?? const QuestionCardDraft();
    state = {
      ...state,
      messageId: current.copyWith(currentQuestionIndex: index),
    };
  }

  void clearDraft(int messageId) {
    if (!state.containsKey(messageId)) {
      return;
    }
    final next = Map<int, QuestionCardDraft>.from(state)..remove(messageId);
    state = next;
  }
}

final questionCardDraftsProvider =
    StateNotifierProvider<QuestionCardDraftsNotifier, Map<int, QuestionCardDraft>>(
  (ref) => QuestionCardDraftsNotifier(),
);

bool isQuestionAnswered({
  required QuestionCardDraft draft,
  required AskUserQuestionItem question,
}) {
  final selected = draft.selectedOptionLabelsByQuestionId[question.id] ?? const [];
  if (selected.isEmpty) {
    return false;
  }
  if (!selected.contains('Other')) {
    return true;
  }
  final otherText = draft.otherTextByQuestionId[question.id]?.trim() ?? '';
  return otherText.isNotEmpty;
}

String resolveAnswerText({
  required QuestionCardDraft draft,
  required AskUserQuestionItem question,
}) {
  final selected = draft.selectedOptionLabelsByQuestionId[question.id] ?? const [];
  if (selected.isEmpty) {
    return '';
  }
  final normalized = selected.map((label) {
    if (label != 'Other') {
      return label;
    }
    return draft.otherTextByQuestionId[question.id]?.trim() ?? '';
  }).where((value) => value.isNotEmpty).toList(growable: false);
  return normalized.join(', ');
}
