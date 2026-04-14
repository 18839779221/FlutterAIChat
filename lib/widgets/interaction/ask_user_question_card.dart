import 'package:ai_chat/models/chat_message.dart';
import 'package:ai_chat/models/interaction/ask_user_question_request.dart';
import 'package:ai_chat/providers/chat_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class AskUserQuestionCard extends ConsumerWidget {
  final ChatMessage message;

  const AskUserQuestionCard({
    super.key,
    required this.message,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final payload = message.payloadJson;
    final messageId = message.id;
    if (payload == null || messageId == null) {
      return const SizedBox.shrink();
    }
    final request = AskUserQuestionRequest.fromJson(payload);
    final draft = ref.watch(questionCardDraftsProvider)[messageId] ??
        const QuestionCardDraft();
    final questionIndex = draft.currentQuestionIndex.clamp(
      0,
      request.questions.length - 1,
    );
    final question = request.questions[questionIndex];
    final selected = draft.selectedOptionLabelsByQuestionId[question.id] ?? const [];
    final hasOther = selected.contains('Other');
    final canSubmit = request.questions.every(
      (item) => isQuestionAnswered(
        draft: draft,
        question: item,
      ),
    );

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              question.header.isEmpty ? 'Question' : question.header,
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 8),
            Text(
              question.question,
              style: Theme.of(context).textTheme.bodyLarge,
            ),
            const SizedBox(height: 12),
            ...question.options.map(
              (option) => CheckboxListTile(
                value: selected.contains(option.label),
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                title: Text(option.label),
                subtitle:
                    option.description.isEmpty ? null : Text(option.description),
                onChanged: (_) {
                  ref.read(questionCardDraftsProvider.notifier).selectOption(
                        messageId: messageId,
                        questionId: question.id,
                        label: option.label,
                        multiSelect: question.multiSelect,
                      );
                },
              ),
            ),
            CheckboxListTile(
              value: hasOther,
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              title: const Text('Other'),
              onChanged: (_) {
                ref.read(questionCardDraftsProvider.notifier).selectOption(
                      messageId: messageId,
                      questionId: question.id,
                      label: 'Other',
                      multiSelect: question.multiSelect,
                    );
              },
            ),
            if (hasOther)
              TextField(
                onChanged: (value) {
                  ref.read(questionCardDraftsProvider.notifier).setOtherText(
                        messageId: messageId,
                        questionId: question.id,
                        value: value,
                      );
                },
                decoration: const InputDecoration(
                  hintText: 'Tell us more',
                ),
              ),
            const SizedBox(height: 12),
            Row(
              children: [
                if (request.questions.length > 1)
                  TextButton(
                    onPressed: questionIndex == 0
                        ? null
                        : () => ref
                            .read(questionCardDraftsProvider.notifier)
                            .setCurrentQuestionIndex(
                              messageId: messageId,
                              index: questionIndex - 1,
                            ),
                    child: const Text('Previous'),
                  ),
                if (request.questions.length > 1)
                  TextButton(
                    onPressed: questionIndex >= request.questions.length - 1
                        ? null
                        : () => ref
                            .read(questionCardDraftsProvider.notifier)
                            .setCurrentQuestionIndex(
                              messageId: messageId,
                              index: questionIndex + 1,
                            ),
                    child: const Text('Next'),
                  ),
                const Spacer(),
                FilledButton(
                  onPressed: canSubmit
                      ? () => ref
                          .read(chatInteractionCoordinatorProvider)
                          .submitQuestionAnswers(message)
                      : null,
                  child: const Text('Submit'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
