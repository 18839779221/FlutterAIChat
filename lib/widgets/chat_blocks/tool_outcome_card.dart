import 'package:ai_chat/models/chat/tool_card_presentation_model.dart';
import 'package:ai_chat/theme/app_theme_spec.dart';
import 'package:ai_chat/theme/app_radius.dart';
import 'package:ai_chat/theme/app_spacing.dart';
import 'package:flutter/material.dart';

/// Explicit card used for user-visible tool outcomes and stage outputs.
class ToolOutcomeCard extends StatelessWidget {
  final ToolCardPresentationModel model;

  const ToolOutcomeCard({
    super.key,
    required this.model,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppThemeSpec>()!;
    final spacing = Theme.of(context).extension<AppSpacing>()!;
    final radius = Theme.of(context).extension<AppRadius>()!;

    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(spacing.md + spacing.xxs),
      decoration: BoxDecoration(
        color: colors.toolOutcomeSurface,
        borderRadius: BorderRadius.circular(radius.md + 2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  model.title,
                  style: TextStyle(
                    color: colors.primaryText,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    height: 1.24,
                  ),
                ),
              ),
              if ((model.statusLabel ?? '').isNotEmpty)
                Container(
                  padding: EdgeInsets.symmetric(
                    horizontal: spacing.xs,
                    vertical: spacing.xxs,
                  ),
                  decoration: BoxDecoration(
                    color: colors.workflowSuccess.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(radius.pill),
                  ),
                  child: Text(
                    model.statusLabel!,
                    style: TextStyle(
                      color: colors.workflowSuccess,
                      fontSize: 9.5,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
            ],
          ),
          SizedBox(height: spacing.xs),
          Text(
            model.summary,
            style: TextStyle(
              color: colors.secondaryText,
              fontSize: 12.5,
              height: 1.46,
            ),
          ),
          if (model.primaryFields.isNotEmpty) ...[
            SizedBox(height: spacing.sm),
            ...model.primaryFields.entries.map(
              (entry) => Padding(
                padding: EdgeInsets.only(bottom: spacing.xxs),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 64,
                      child: Text(
                        entry.key,
                        style: TextStyle(
                          color: colors.secondaryText,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    Expanded(
                      child: Text(
                        entry.value,
                        style: TextStyle(
                          color: colors.primaryText,
                          fontSize: 12,
                          height: 1.45,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
