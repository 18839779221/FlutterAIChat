import 'package:ai_chat/theme/app_colors.dart';
import 'package:ai_chat/theme/app_radius.dart';
import 'package:ai_chat/theme/app_spacing.dart';
import 'package:ai_chat/theme/app_typography.dart';
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

    final isMostlyLatin = RegExp(r'^[\x00-\x7F\s\p{P}]+$', unicode: true)
        .hasMatch(text);

    return Align(
      alignment: Alignment.centerRight,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 468),
        padding: EdgeInsets.symmetric(
          horizontal: spacing.md,
          vertical: spacing.xs + 1,
        ),
        decoration: BoxDecoration(
          color: colors.userBubbleSurface.withValues(alpha: 0.8),
          borderRadius: BorderRadius.only(
            topLeft: Radius.circular(radius.lg),
            topRight: Radius.circular(radius.lg),
            bottomLeft: Radius.circular(radius.lg),
            bottomRight: Radius.circular(radius.sm),
          ),
          boxShadow: [
            BoxShadow(
              color: colors.primaryText.withValues(alpha: 0.036),
              blurRadius: 10,
              offset: const Offset(0, 5),
            ),
          ],
        ),
        child: Text(
          text,
          style: AppTypography.uiStyle(
            color: colors.primaryText,
            fontWeight: FontWeight.w400,
            fontSize: 13.0,
            height: 1.3,
            letterSpacing: isMostlyLatin ? 0.08 : null,
          ),
        ),
      ),
    );
  }
}
