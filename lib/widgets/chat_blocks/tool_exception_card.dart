import 'package:ai_chat/models/chat/tool_card_presentation_model.dart';
import 'package:ai_chat/theme/app_colors.dart';
import 'package:ai_chat/theme/app_radius.dart';
import 'package:ai_chat/theme/app_spacing.dart';
import 'package:flutter/material.dart';

/// Expanded card for actionable or user-visible tool failures.
class ToolExceptionCard extends StatelessWidget {
  final ToolCardPresentationModel model;

  const ToolExceptionCard({
    super.key,
    required this.model,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppColors>()!;
    final spacing = Theme.of(context).extension<AppSpacing>()!;
    final radius = Theme.of(context).extension<AppRadius>()!;
    final nextStep = model.primaryFields['nextStep'];

    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(spacing.md + spacing.xxs),
      decoration: BoxDecoration(
        color: colors.toolExceptionSurface,
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
                    color: colors.workflowWarning.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(radius.pill),
                  ),
                  child: Text(
                    model.statusLabel!,
                    style: TextStyle(
                      color: colors.workflowWarning,
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
            ...model.primaryFields.entries
                .where((entry) => entry.key != 'nextStep')
                .map(
                  (entry) => Padding(
                    padding: EdgeInsets.only(bottom: spacing.xxs),
                    child: Text(
                      '${entry.key}: ${entry.value}',
                      style: TextStyle(
                        color: colors.primaryText,
                        fontSize: 11.5,
                        height: 1.42,
                      ),
                    ),
                  ),
                ),
          ],
          if (nextStep != null && nextStep.isNotEmpty) ...[
            SizedBox(height: spacing.xs),
            Text(
              nextStep,
              style: TextStyle(
                color: colors.primaryText,
                fontSize: 12,
                fontWeight: FontWeight.w600,
                height: 1.42,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
