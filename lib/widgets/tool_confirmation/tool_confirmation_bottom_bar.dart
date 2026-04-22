import 'package:flutter/material.dart';

import '../../models/chat_message.dart';
import '../../models/tool/tool_invocation.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_radius.dart';
import '../../theme/app_spacing.dart';
import '../../tools/core/tool_display_names.dart';

/// Shared bottom bar for tool confirmations. It keeps authorization controls
/// out of the tool-specific timeline cards.
class ToolConfirmationBottomBar extends StatelessWidget {
  const ToolConfirmationBottomBar({
    super.key,
    required this.message,
    required this.invocation,
    this.onContinue,
    this.onCancel,
    this.onContinueAndTrust,
  });

  final ChatMessage message;
  final ToolInvocation invocation;
  final VoidCallback? onContinue;
  final VoidCallback? onCancel;
  final VoidCallback? onContinueAndTrust;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppColors>()!;
    final spacing = Theme.of(context).extension<AppSpacing>()!;
    final radius = Theme.of(context).extension<AppRadius>()!;
    final title = resolveToolDisplayName(invocation.toolName);
    final summary = invocation.summary.trim().isEmpty
        ? message.text.trim()
        : invocation.summary.trim();

    return Padding(
      padding: EdgeInsets.fromLTRB(
        spacing.md,
        spacing.xs,
        spacing.md,
        spacing.xs,
      ),
      child: Container(
        width: double.infinity,
        padding: EdgeInsets.all(spacing.md),
        decoration: BoxDecoration(
          color: colors.assistantSurface.withValues(alpha: 0.96),
          borderRadius: BorderRadius.circular(radius.lg + 4),
          boxShadow: [
            BoxShadow(
              color: colors.primaryText.withValues(alpha: 0.06),
              blurRadius: 18,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '待确认操作',
              style: TextStyle(
                color: colors.secondaryText,
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.3,
              ),
            ),
            SizedBox(height: spacing.xs),
            Text(
              title,
              style: TextStyle(
                color: colors.primaryText,
                fontSize: 15,
                fontWeight: FontWeight.w700,
                height: 1.24,
              ),
            ),
            if (summary.isNotEmpty) ...[
              SizedBox(height: spacing.xs),
              Text(
                summary,
                style: TextStyle(
                  color: colors.secondaryText,
                  fontSize: 12.5,
                  height: 1.42,
                ),
              ),
            ],
            SizedBox(height: spacing.sm),
            Wrap(
              spacing: spacing.xs,
              runSpacing: spacing.xs,
              children: [
                FilledButton(
                  onPressed: onContinue,
                  child: const Text('继续'),
                ),
                OutlinedButton(
                  onPressed: onCancel,
                  child: const Text('取消'),
                ),
                OutlinedButton(
                  onPressed: onContinueAndTrust,
                  child: const Text('继续，以后不再确认'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
