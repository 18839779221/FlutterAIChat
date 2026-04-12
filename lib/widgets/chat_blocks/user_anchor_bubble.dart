import 'package:ai_chat/theme/app_colors.dart';
import 'package:ai_chat/theme/app_radius.dart';
import 'package:ai_chat/theme/app_spacing.dart';
import 'package:flutter/material.dart';

/// Compact user bubble used as a question anchor in the chat timeline.
class UserAnchorBubble extends StatelessWidget {
  final String text;

  const UserAnchorBubble({
    super.key,
    required this.text,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppColors>()!;
    final spacing = Theme.of(context).extension<AppSpacing>()!;
    final radius = Theme.of(context).extension<AppRadius>()!;

    return Align(
      alignment: Alignment.centerRight,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 420),
        padding: EdgeInsets.symmetric(
          horizontal: spacing.md + spacing.xxs,
          vertical: spacing.sm,
        ),
        decoration: BoxDecoration(
          color: colors.userBubbleSurface.withValues(alpha: 0.96),
          borderRadius: BorderRadius.only(
            topLeft: Radius.circular(radius.lg),
            topRight: Radius.circular(radius.lg),
            bottomLeft: Radius.circular(radius.lg),
            bottomRight: Radius.circular(radius.sm),
          ),
          boxShadow: [
            BoxShadow(
              color: colors.primaryText.withValues(alpha: 0.055),
              blurRadius: 14,
              offset: const Offset(0, 7),
            ),
          ],
        ),
        child: Text(
          text,
          style: TextStyle(
            color: colors.primaryText,
            fontWeight: FontWeight.w600,
            fontSize: 14,
            height: 1.38,
          ),
        ),
      ),
    );
  }
}
