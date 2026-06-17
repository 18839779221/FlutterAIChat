import 'package:ai_chat/theme/app_radius.dart';
import 'package:ai_chat/theme/app_spacing.dart';
import 'package:ai_chat/theme/app_theme_spec.dart';
import 'package:flutter/material.dart';

class ChatMessageListSkeleton extends StatelessWidget {
  const ChatMessageListSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    final spacing = Theme.of(context).extension<AppSpacing>()!;
    final radius = Theme.of(context).extension<AppRadius>()!;
    final colors = Theme.of(context).extension<AppThemeSpec>()!;
    return ListView(
      physics: const NeverScrollableScrollPhysics(),
      padding: EdgeInsets.fromLTRB(
        spacing.md,
        spacing.lg,
        spacing.md,
        spacing.xl * 2,
      ),
      children: [
        _SkeletonBubble(
          widthFactor: 0.72,
          height: 104,
          color: colors.assistantSurface.withValues(alpha: 0.72),
          radius: radius.lg,
        ),
        SizedBox(height: spacing.md),
        Align(
          alignment: Alignment.centerRight,
          child: _SkeletonBubble(
            widthFactor: 0.52,
            height: 72,
            color: colors.userBubbleSurface.withValues(alpha: 0.7),
            radius: radius.lg,
          ),
        ),
        SizedBox(height: spacing.md),
        _SkeletonBubble(
          widthFactor: 0.86,
          height: 132,
          color: colors.assistantSurface.withValues(alpha: 0.72),
          radius: radius.lg,
        ),
      ],
    );
  }
}

class _SkeletonBubble extends StatelessWidget {
  const _SkeletonBubble({
    required this.widthFactor,
    required this.height,
    required this.color,
    required this.radius,
  });

  final double widthFactor;
  final double height;
  final Color color;
  final double radius;

  @override
  Widget build(BuildContext context) {
    return FractionallySizedBox(
      widthFactor: widthFactor,
      alignment: Alignment.centerLeft,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: Container(
          height: height,
          decoration: BoxDecoration(
            color: color,
          ),
        ),
      ),
    );
  }
}
