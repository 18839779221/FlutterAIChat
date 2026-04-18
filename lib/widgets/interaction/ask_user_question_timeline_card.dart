import 'package:ai_chat/models/chat_message.dart';
import 'package:ai_chat/models/interaction/ask_user_question_request.dart';
import 'package:ai_chat/theme/app_colors.dart';
import 'package:ai_chat/theme/app_radius.dart';
import 'package:ai_chat/theme/app_spacing.dart';
import 'package:flutter/material.dart';

/// Compact timeline placeholder for active ask-user-question checkpoints.
class AskUserQuestionTimelineCard extends StatelessWidget {
  final ChatMessage message;

  const AskUserQuestionTimelineCard({
    super.key,
    required this.message,
  });

  @override
  Widget build(BuildContext context) {
    final payload = message.payloadJson;
    if (payload == null) {
      return const SizedBox.shrink();
    }
    final request = AskUserQuestionRequest.fromJson(payload);
    final colors = Theme.of(context).extension<AppColors>() ?? AppColors.light();
    final spacing = Theme.of(context).extension<AppSpacing>() ?? AppSpacing.base();
    final radius = Theme.of(context).extension<AppRadius>() ?? AppRadius.base();
    final firstQuestion = request.questions.first;
    final remainingCount = request.questions.length - 1;

    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(spacing.md),
      decoration: BoxDecoration(
        color: colors.structuredSurface.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(radius.md + 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '等待你补充信息',
            style: TextStyle(
              color: colors.secondaryText,
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.3,
            ),
          ),
          SizedBox(height: spacing.xs),
          Text(
            firstQuestion.header.isEmpty ? '继续当前回合' : firstQuestion.header,
            style: TextStyle(
              color: colors.primaryText,
              fontSize: 15,
              fontWeight: FontWeight.w700,
            ),
          ),
          SizedBox(height: spacing.xxs),
          Text(
            firstQuestion.question,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: colors.secondaryText,
              fontSize: 12.5,
              height: 1.35,
            ),
          ),
          SizedBox(height: spacing.sm),
          Wrap(
            spacing: spacing.xs,
            runSpacing: spacing.xs,
            children: [
              _Badge(
                label: '共 ${request.questions.length} 题',
                backgroundColor: colors.workflowRunning.withValues(alpha: 0.12),
                foregroundColor: colors.workflowRunning,
              ),
              if (remainingCount > 0)
                _Badge(
                  label: '还有 $remainingCount 题待完成',
                  backgroundColor:
                      colors.assistantSurface.withValues(alpha: 0.9),
                  foregroundColor: colors.primaryText,
                ),
              _Badge(
                label: '请在底部交互区继续',
                backgroundColor: colors.chatBackground.withValues(alpha: 0.55),
                foregroundColor: colors.secondaryText,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  final String label;
  final Color backgroundColor;
  final Color foregroundColor;

  const _Badge({
    required this.label,
    required this.backgroundColor,
    required this.foregroundColor,
  });

  @override
  Widget build(BuildContext context) {
    final spacing = Theme.of(context).extension<AppSpacing>() ?? AppSpacing.base();
    final radius = Theme.of(context).extension<AppRadius>() ?? AppRadius.base();
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: spacing.xs,
        vertical: spacing.xxs,
      ),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(radius.pill),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: foregroundColor,
          fontSize: 10.5,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
