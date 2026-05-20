import 'package:ai_chat/theme/app_theme_spec.dart';
import 'package:ai_chat/theme/app_spacing.dart';
import 'package:flutter/material.dart';

/// Structured output block for parsed key-value style assistant content.
class StructuredOutputBlock extends StatelessWidget {
  final String title;
  final Map<String, String> fields;

  const StructuredOutputBlock({
    super.key,
    required this.title,
    required this.fields,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppThemeSpec>()!;
    final spacing = Theme.of(context).extension<AppSpacing>()!;

    return Padding(
      padding: EdgeInsets.fromLTRB(
        spacing.xs,
        spacing.xxs,
        spacing.xs,
        spacing.xxs + 1,
      ),
      child: SizedBox(
        width: double.infinity,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: TextStyle(
                color: colors.primaryText,
                fontSize: 15,
                fontWeight: FontWeight.w700,
                height: 1.24,
              ),
            ),
            SizedBox(height: spacing.xs + 2),
            ...fields.entries.map(
              (entry) => Padding(
                padding: EdgeInsets.only(bottom: spacing.xs),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 76,
                      child: Text(
                        entry.key,
                        style: TextStyle(
                          color: colors.secondaryText,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          height: 1.42,
                        ),
                      ),
                    ),
                    SizedBox(width: spacing.xs + 2),
                    Expanded(
                      child: Text(
                        entry.value,
                        style: TextStyle(
                          color: colors.primaryText,
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          height: 1.46,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
