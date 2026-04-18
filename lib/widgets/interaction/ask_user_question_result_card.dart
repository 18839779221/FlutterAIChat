import 'package:ai_chat/models/chat_message.dart';
import 'package:ai_chat/models/interaction/ask_user_question_response.dart';
import 'package:ai_chat/theme/app_colors.dart';
import 'package:ai_chat/theme/app_radius.dart';
import 'package:ai_chat/theme/app_spacing.dart';
import 'package:flutter/material.dart';

/// Compact timeline card for submitted ask-user-question answers.
class AskUserQuestionResultCard extends StatelessWidget {
  final ChatMessage message;

  const AskUserQuestionResultCard({
    super.key,
    required this.message,
  });

  @override
  Widget build(BuildContext context) {
    final payload = message.payloadJson;
    if (payload == null) {
      return const SizedBox.shrink();
    }

    final submittedAnswers = payload['submittedAnswers'];
    final answers = submittedAnswers is Map<String, dynamic>
        ? AskUserQuestionResponse.fromJson(submittedAnswers).answersByQuestionId
        : const <String, String>{};

    final colors = Theme.of(context).extension<AppColors>() ?? AppColors.light();
    final spacing = Theme.of(context).extension<AppSpacing>() ?? AppSpacing.base();
    final radius = Theme.of(context).extension<AppRadius>() ?? AppRadius.base();

    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(spacing.md),
      decoration: BoxDecoration(
        color: colors.assistantSurface.withValues(alpha: 0.82),
        borderRadius: BorderRadius.circular(radius.md + 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '已补充本回合信息',
            style: TextStyle(
              color: colors.secondaryText,
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.3,
            ),
          ),
          SizedBox(height: spacing.xs),
          if (answers.isEmpty)
            Text(
              message.text.trim().isEmpty ? '已提交答案' : message.text,
              style: TextStyle(
                color: colors.primaryText,
                fontSize: 13,
                fontWeight: FontWeight.w500,
                height: 1.4,
              ),
            )
          else
            ...answers.entries.map(
              (entry) => Padding(
                padding: EdgeInsets.only(bottom: spacing.xs),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 88,
                      child: Text(
                        entry.key,
                        style: TextStyle(
                          color: colors.secondaryText,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          height: 1.4,
                        ),
                      ),
                    ),
                    SizedBox(width: spacing.xs),
                    Expanded(
                      child: Text(
                        entry.value,
                        style: TextStyle(
                          color: colors.primaryText,
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                          height: 1.4,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
