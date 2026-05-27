import 'package:ai_chat/models/chat_message.dart';
import 'package:ai_chat/models/interaction/ask_user_question_request.dart';
import 'package:ai_chat/providers/chat_providers.dart';
import 'package:ai_chat/theme/app_theme_spec.dart';
import 'package:ai_chat/theme/app_radius.dart';
import 'package:ai_chat/theme/app_spacing.dart';
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
    final isSkipped = draft.selectedOptionLabelsByQuestionId.containsKey(question.id) &&
        selected.isEmpty;
    final isCurrentQuestionAnswered = isQuestionAnswered(
      draft: draft,
      question: question,
    );
    final hasOther = selected.contains('Other');
    final colors = Theme.of(context).extension<AppThemeSpec>() ?? AppThemeSpec.light();
    final spacing = Theme.of(context).extension<AppSpacing>() ?? AppSpacing.base();
    final radius = Theme.of(context).extension<AppRadius>() ?? AppRadius.base();
    final canSubmit = request.questions.every(
      (item) => isQuestionAnswered(
        draft: draft,
        question: item,
      ),
    );
    return Container(
      margin: EdgeInsets.symmetric(vertical: spacing.xs - 2),
      padding: EdgeInsets.all(spacing.lg),
      decoration: BoxDecoration(
        color: colors.structuredSurface.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(radius.md + 2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '继续当前回合所需信息',
            style: TextStyle(
              color: colors.secondaryText,
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.4,
            ),
          ),
          SizedBox(height: spacing.xs),
          Row(
            children: [
              Expanded(
                child: Text(
                  question.header.isEmpty ? 'Question' : question.header,
                  style: TextStyle(
                    color: colors.primaryText,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    height: 1.24,
                  ),
                ),
              ),
              Container(
                padding: EdgeInsets.symmetric(
                  horizontal: spacing.xs,
                  vertical: spacing.xxs,
                ),
                decoration: BoxDecoration(
                  color: colors.workflowRunning.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(radius.pill),
                ),
                child: Text(
                  '问题 ${questionIndex + 1} / ${request.questions.length}',
                  style: TextStyle(
                    color: colors.workflowRunning,
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          SizedBox(height: spacing.sm),
          Text(
            question.question,
            style: TextStyle(
              color: colors.primaryText,
              fontSize: 14,
              height: 1.45,
            ),
          ),
          SizedBox(height: spacing.sm),
          if (isSkipped) ...[
            Container(
              width: double.infinity,
              margin: EdgeInsets.only(bottom: spacing.sm),
              padding: EdgeInsets.symmetric(
                horizontal: spacing.sm,
                vertical: spacing.xs,
              ),
              decoration: BoxDecoration(
                color: colors.chatBackground.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(radius.md),
              ),
              child: Text(
                '此题将以空答案跳过，提交后会继续当前回合。',
                style: TextStyle(
                  color: colors.secondaryText,
                  fontSize: 12,
                  height: 1.4,
                ),
              ),
            ),
          ],
          ...question.options.map(
            (option) => _QuestionOptionTile(
              label: option.label,
              description: option.description,
              selected: selected.contains(option.label),
              isRecommended: option.isRecommended,
              onTap: () {
                ref.read(questionCardDraftsProvider.notifier).selectOption(
                      messageId: messageId,
                      questionId: question.id,
                      label: option.label,
                      multiSelect: question.multiSelect,
                    );
              },
            ),
          ),
          _QuestionOptionTile(
            label: 'Other',
            description: '',
            selected: hasOther,
            isRecommended: false,
            onTap: () {
              ref.read(questionCardDraftsProvider.notifier).selectOption(
                    messageId: messageId,
                    questionId: question.id,
                    label: 'Other',
                    multiSelect: question.multiSelect,
                  );
            },
          ),
          if (hasOther) ...[
            SizedBox(height: spacing.xs),
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
          ],
          SizedBox(height: spacing.md),
          Text(
            '提交后将继续当前回合，而不是开启新对话。',
            style: TextStyle(
              color: colors.secondaryText,
              fontSize: 11.5,
              height: 1.4,
            ),
          ),
          SizedBox(height: spacing.sm),
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
                  child: const Text('上一题'),
                ),
              TextButton(
                onPressed: () => ref
                    .read(chatInteractionCoordinatorProvider)
                    .skipCurrentQuestion(message),
                child: const Text('跳过'),
              ),
              const Spacer(),
              FilledButton(
                onPressed: _resolvePrimaryAction(
                  ref: ref,
                  message: message,
                  messageId: messageId,
                  questionIndex: questionIndex,
                  totalQuestions: request.questions.length,
                  isCurrentQuestionAnswered: isCurrentQuestionAnswered,
                  canSubmit: canSubmit,
                ),
                child: Text(
                  questionIndex >= request.questions.length - 1
                      ? '提交并继续'
                      : '下一题',
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  VoidCallback? _resolvePrimaryAction({
    required WidgetRef ref,
    required ChatMessage message,
    required int messageId,
    required int questionIndex,
    required int totalQuestions,
    required bool isCurrentQuestionAnswered,
    required bool canSubmit,
  }) {
    if (questionIndex < totalQuestions - 1) {
      if (!isCurrentQuestionAnswered) {
        return null;
      }
      return () => ref.read(questionCardDraftsProvider.notifier).setCurrentQuestionIndex(
            messageId: messageId,
            index: questionIndex + 1,
          );
    }
    if (!canSubmit) {
      return null;
    }
    return () => ref
        .read(chatInteractionCoordinatorProvider)
        .submitQuestionAnswers(message);
  }
}

class _QuestionOptionTile extends StatelessWidget {
  final String label;
  final String description;
  final bool selected;
  final bool isRecommended;
  final VoidCallback onTap;

  const _QuestionOptionTile({
    required this.label,
    required this.description,
    required this.selected,
    required this.isRecommended,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppThemeSpec>() ?? AppThemeSpec.light();
    final spacing = Theme.of(context).extension<AppSpacing>() ?? AppSpacing.base();
    final radius = Theme.of(context).extension<AppRadius>() ?? AppRadius.base();

    return Padding(
      padding: EdgeInsets.only(bottom: spacing.xs),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(radius.md),
        child: Ink(
          padding: EdgeInsets.all(spacing.sm),
          decoration: BoxDecoration(
            color: selected
                ? colors.assistantSurface.withValues(alpha: 0.92)
                : colors.chatBackground.withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(radius.md),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 18,
                height: 18,
                margin: EdgeInsets.only(top: 1, right: spacing.sm),
                decoration: BoxDecoration(
                  color: selected
                      ? colors.workflowRunning
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(
                    color: selected
                        ? colors.workflowRunning
                        : colors.divider.withValues(alpha: 0.9),
                  ),
                ),
                child: selected
                    ? const Icon(Icons.check, size: 12, color: Colors.white)
                    : null,
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            label,
                            style: TextStyle(
                              color: colors.primaryText,
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        if (isRecommended) ...[
                          SizedBox(width: spacing.xs),
                          Container(
                            padding: EdgeInsets.symmetric(
                              horizontal: spacing.xs,
                              vertical: spacing.xxs,
                            ),
                            decoration: BoxDecoration(
                              color: colors.workflowSuccess.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(radius.pill),
                            ),
                            child: Text(
                              'Recommended',
                              style: TextStyle(
                                color: colors.workflowSuccess,
                                fontSize: 9.5,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    if (description.isNotEmpty) ...[
                      SizedBox(height: spacing.xxs),
                      Text(
                        description,
                        style: TextStyle(
                          color: colors.secondaryText,
                          fontSize: 11.5,
                          height: 1.38,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
