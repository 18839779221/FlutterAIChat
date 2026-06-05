import 'package:ai_chat/theme/app_theme_spec.dart';
import 'package:flutter/material.dart';

class ContextBoundaryDivider extends StatelessWidget {
  const ContextBoundaryDivider({
    super.key,
    required this.text,
  });

  final String text;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppThemeSpec>()!;

    return Padding(
      key: const ValueKey('context-boundary-divider'),
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        children: [
          Expanded(
            child: Container(
              height: 1,
              color: colors.divider.withValues(alpha: 0.55),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Text(
              text,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: colors.secondaryText,
                  ),
            ),
          ),
          Expanded(
            child: Container(
              height: 1,
              color: colors.divider.withValues(alpha: 0.55),
            ),
          ),
        ],
      ),
    );
  }
}
