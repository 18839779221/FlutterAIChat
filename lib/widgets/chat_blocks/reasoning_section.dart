import 'package:ai_chat/theme/app_theme_spec.dart';
import 'package:ai_chat/theme/app_spacing.dart';
import 'package:ai_chat/theme/app_typography.dart';
import 'package:flutter/material.dart';

enum ReasoningSectionVariant {
  toolUseInline,
  finalAnswerCollapsible,
}

/// Secondary section for provider-returned visible reasoning.
class ReasoningSection extends StatefulWidget {
  final String text;
  final ReasoningSectionVariant variant;
  final bool initiallyExpanded;
  final ValueChanged<bool>? onExpansionChanged;

  const ReasoningSection({
    super.key,
    required this.text,
    this.variant = ReasoningSectionVariant.toolUseInline,
    this.initiallyExpanded = true,
    this.onExpansionChanged,
  });

  @override
  State<ReasoningSection> createState() => _ReasoningSectionState();
}

class _ReasoningSectionState extends State<ReasoningSection> {
  late bool _isExpanded = widget.initiallyExpanded;

  @override
  void didUpdateWidget(covariant ReasoningSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initiallyExpanded != widget.initiallyExpanded &&
        oldWidget.variant != widget.variant) {
      _isExpanded = widget.initiallyExpanded;
    }
  }

  @override
  Widget build(BuildContext context) {
    final normalized = widget.text.trim();
    if (normalized.isEmpty) {
      return const SizedBox.shrink();
    }
    final colors = Theme.of(context).extension<AppThemeSpec>()!;
    final spacing = Theme.of(context).extension<AppSpacing>()!;

    return Padding(
      padding: EdgeInsets.only(bottom: spacing.sm),
      child: widget.variant == ReasoningSectionVariant.finalAnswerCollapsible
          ? _buildFinalAnswerCollapsedShell(
              context: context,
              colors: colors,
              spacing: spacing,
              normalized: normalized,
            )
          : DecoratedBox(
              decoration: BoxDecoration(
                color: _backgroundColor(colors),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                  spacing.sm,
                  spacing.xs,
                  spacing.sm,
                  spacing.xs,
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 2,
                      margin: EdgeInsets.only(top: 2, right: spacing.sm),
                      decoration: BoxDecoration(
                        color: _railColor(colors),
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                    Expanded(
                      child: _buildExpandedContent(
                        colors: colors,
                        spacing: spacing,
                        normalized: normalized,
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildFinalAnswerCollapsedShell({
    required BuildContext context,
    required AppThemeSpec colors,
    required AppSpacing spacing,
    required String normalized,
  }) {
    return Padding(
      padding: EdgeInsets.only(
        top: spacing.xxs,
        bottom: spacing.xs - 1,
      ),
      child: _buildCollapsibleContent(
        context: context,
        colors: colors,
        spacing: spacing,
        normalized: normalized,
      ),
    );
  }

  Widget _buildCollapsibleContent({
    required BuildContext context,
    required AppThemeSpec colors,
    required AppSpacing spacing,
    required String normalized,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          borderRadius: BorderRadius.circular(6),
          onTap: () {
            setState(() => _isExpanded = !_isExpanded);
            final onExpansionChanged = widget.onExpansionChanged;
            if (onExpansionChanged != null) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (!mounted) {
                  return;
                }
                onExpansionChanged(_isExpanded);
              });
            }
          },
          child: Padding(
            padding: EdgeInsets.symmetric(vertical: spacing.xxs),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    '思考过程',
                    style: AppTypography.uiStyle(
                      color: colors.secondaryText.withValues(alpha: 0.68),
                      fontSize: 10.8,
                      fontWeight: FontWeight.w500,
                      height: 1.2,
                    ),
                  ),
                ),
                Icon(
                  _isExpanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
                  size: 14,
                  color: colors.secondaryText.withValues(alpha: 0.52),
                ),
              ],
            ),
          ),
        ),
        if (_isExpanded) ...[
          SizedBox(height: spacing.xxs),
          SelectableText(
            normalized,
            style: AppTypography.documentStyle(
              color: colors.secondaryText.withValues(alpha: 0.86),
              fontSize: 12.2,
              height: 1.42,
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildExpandedContent({
    required AppThemeSpec colors,
    required AppSpacing spacing,
    required String normalized,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '思考过程',
          style: AppTypography.uiStyle(
            color: colors.secondaryText.withValues(alpha: 0.82),
            fontSize: 10.8,
            fontWeight: FontWeight.w600,
            height: 1.15,
          ),
        ),
        SizedBox(height: spacing.xxs),
        SelectableText(
          normalized,
          style: AppTypography.documentStyle(
            color: colors.secondaryText.withValues(alpha: 0.82),
            fontSize: 12.0,
            height: 1.42,
          ),
        ),
      ],
    );
  }

  Color _backgroundColor(AppThemeSpec colors) {
    switch (widget.variant) {
      case ReasoningSectionVariant.toolUseInline:
        return colors.assistantSurface.withValues(alpha: 0.22);
      case ReasoningSectionVariant.finalAnswerCollapsible:
        return Colors.transparent;
    }
  }

  Color _railColor(AppThemeSpec colors) {
    switch (widget.variant) {
      case ReasoningSectionVariant.toolUseInline:
        return colors.secondaryText.withValues(alpha: 0.28);
      case ReasoningSectionVariant.finalAnswerCollapsible:
        return colors.secondaryText.withValues(alpha: 0.42);
    }
  }
}
