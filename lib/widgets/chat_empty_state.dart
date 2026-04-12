import 'package:ai_chat/theme/app_colors.dart';
import 'package:ai_chat/theme/app_radius.dart';
import 'package:ai_chat/theme/app_spacing.dart';
import 'package:flutter/material.dart';

/// Calm empty state shown before the conversation begins.
class ChatEmptyState extends StatelessWidget {
  const ChatEmptyState({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppColors>()!;
    final spacing = Theme.of(context).extension<AppSpacing>()!;
    final radius = Theme.of(context).extension<AppRadius>()!;

    final suggestions = <String>[
      '帮我梳理一个复杂问题',
      '继续推进我当前的任务',
      '把想法整理成可执行步骤',
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final bottomInset =
            constraints.maxHeight > 720 ? spacing.xl * 2.4 : spacing.xl;

        return Align(
          alignment: const Alignment(0, 0.06),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                spacing.xl,
                spacing.lg,
                spacing.xl,
                bottomInset,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '开始一段新的对话',
                    style: TextStyle(
                      color: colors.primaryText,
                      fontSize: 24,
                      fontWeight: FontWeight.w700,
                      height: 1.12,
                    ),
                  ),
                  SizedBox(height: spacing.sm),
                  Text(
                    '从一个问题开始，或让助手帮你推进下一步。',
                    style: TextStyle(
                      color: colors.secondaryText,
                      fontSize: 14,
                      height: 1.5,
                    ),
                  ),
                  SizedBox(height: spacing.lg + spacing.sm),
                  Wrap(
                    spacing: spacing.xxs + 2,
                    runSpacing: spacing.xxs + 2,
                    children: suggestions
                        .map(
                          (suggestion) => Container(
                            padding: EdgeInsets.symmetric(
                              horizontal: spacing.sm + spacing.xs,
                              vertical: spacing.xxs + 3,
                            ),
                            decoration: BoxDecoration(
                              color: colors.assistantSurface
                                  .withValues(alpha: 0.78),
                              borderRadius: BorderRadius.circular(radius.pill),
                              boxShadow: [
                                BoxShadow(
                                  color: colors.primaryText
                                      .withValues(alpha: 0.04),
                                  blurRadius: 8,
                                  offset: const Offset(0, 3),
                                ),
                              ],
                            ),
                            child: Text(
                              suggestion,
                              style: TextStyle(
                                color: colors.primaryText,
                                fontSize: 11.5,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        )
                        .toList(),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
