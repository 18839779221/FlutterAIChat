import 'package:flutter/material.dart';

import '../../models/session/context_window_segment.dart';
import '../../models/session/context_window_snapshot.dart';
import '../../theme/app_theme_spec.dart';
import '../../theme/app_radius.dart';
import '../../theme/app_spacing.dart';

class ContextWindowBottomSheet extends StatelessWidget {
  const ContextWindowBottomSheet({
    super.key,
    required this.snapshot,
  });

  final ContextWindowSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppThemeSpec>()!;
    final spacing = Theme.of(context).extension<AppSpacing>()!;
    final radius = Theme.of(context).extension<AppRadius>()!;
    final plannerVisibleSegments = snapshot.segments
        .where((segment) => segment.isPlannerVisible)
        .toList(growable: false);
    final reserveSegments = snapshot.segments
        .where((segment) => !segment.isPlannerVisible)
        .toList(growable: false);

    return SafeArea(
      child: Container(
        key: const ValueKey('context-window-bottom-sheet'),
        decoration: BoxDecoration(
          color: colors.chatBackground,
          borderRadius: BorderRadius.vertical(top: Radius.circular(radius.lg)),
        ),
        child: ListView(
          shrinkWrap: true,
          padding: EdgeInsets.fromLTRB(
            spacing.lg,
            spacing.md,
            spacing.lg,
            spacing.lg,
          ),
          children: [
            Center(
              child: Container(
                width: 42,
                height: 4,
                decoration: BoxDecoration(
                  color: colors.secondaryText.withValues(alpha: 0.28),
                  borderRadius: BorderRadius.circular(radius.pill),
                ),
              ),
            ),
            SizedBox(height: spacing.md),
            Text(
              snapshot.modelName,
              style: TextStyle(
                color: colors.primaryText,
                fontSize: 20,
                fontWeight: FontWeight.w700,
              ),
            ),
            SizedBox(height: spacing.xs),
            _SummaryCard(snapshot: snapshot),
            SizedBox(height: spacing.md),
            _SectionCard(
              title: 'Planner Context',
              children: plannerVisibleSegments
                  .map((segment) => _SegmentRow(segment: segment))
                  .toList(growable: false),
            ),
            SizedBox(height: spacing.md),
            _SectionCard(
              title: 'Reserves',
              children: reserveSegments
                  .map((segment) => _SegmentRow(segment: segment))
                  .toList(growable: false),
            ),
            SizedBox(height: spacing.md),
            _SectionCard(
              title: 'Compaction',
              children: [
                _DetailLine(
                  label: '已压缩历史',
                  value: snapshot.didCompactHistory ? '是' : '否',
                ),
                _DetailLine(
                  label: 'snapshot 覆盖至 turn',
                  value: '${snapshot.snapshotCoveredUntilTurnId ?? '-'}',
                ),
                _DetailLine(
                  label: 'recent completed turns',
                  value: '${snapshot.recentCompletedTurnCount}',
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.snapshot});

  final ContextWindowSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppThemeSpec>()!;
    final spacing = Theme.of(context).extension<AppSpacing>()!;
    final radius = Theme.of(context).extension<AppRadius>()!;

    return Container(
      padding: EdgeInsets.all(spacing.md),
      decoration: BoxDecoration(
        color: colors.assistantSurface.withValues(alpha: 0.96),
        borderRadius: BorderRadius.circular(radius.md),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _DetailLine(
            label: '总窗口',
            value:
                '${(snapshot.totalWindowUsageRatio * 100).toStringAsFixed(1)}%',
          ),
          _DetailLine(
            label: '可用输入预算',
            value:
                '${(snapshot.usableInputUsageRatio * 100).toStringAsFixed(1)}%',
          ),
          _DetailLine(
            label: '估算输入 tokens',
            value: '${snapshot.totalEstimatedInputTokens}',
          ),
          _DetailLine(
            label: 'max context',
            value: '${snapshot.maxContextTokens}',
          ),
          _DetailLine(
            label: 'usable input budget',
            value: '${snapshot.usableInputBudget}',
          ),
        ],
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.title,
    required this.children,
  });

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppThemeSpec>()!;
    final spacing = Theme.of(context).extension<AppSpacing>()!;
    final radius = Theme.of(context).extension<AppRadius>()!;

    return Container(
      padding: EdgeInsets.all(spacing.md),
      decoration: BoxDecoration(
        color: colors.assistantSurface.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(radius.md),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              color: colors.primaryText,
              fontSize: 15,
              fontWeight: FontWeight.w700,
            ),
          ),
          SizedBox(height: spacing.xs),
          ...children,
        ],
      ),
    );
  }
}

class _SegmentRow extends StatelessWidget {
  const _SegmentRow({required this.segment});

  final ContextWindowSegment segment;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppThemeSpec>()!;
    final spacing = Theme.of(context).extension<AppSpacing>()!;

    return Padding(
      padding: EdgeInsets.only(bottom: spacing.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Text(
              segment.label,
              style: TextStyle(
                color: colors.primaryText,
                fontSize: 13.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          SizedBox(width: spacing.sm),
          Text(
            '${(segment.shareOfTotalWindow * 100).toStringAsFixed(1)}% / '
            '${(segment.shareOfUsableInput * 100).toStringAsFixed(1)}%',
            style: TextStyle(
              color: colors.secondaryText,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}

class _DetailLine extends StatelessWidget {
  const _DetailLine({
    required this.label,
    required this.value,
  });

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppThemeSpec>()!;
    final spacing = Theme.of(context).extension<AppSpacing>()!;

    return Padding(
      padding: EdgeInsets.only(bottom: spacing.xs),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                color: colors.secondaryText,
                fontSize: 12.5,
              ),
            ),
          ),
          SizedBox(width: spacing.sm),
          Text(
            value,
            style: TextStyle(
              color: colors.primaryText,
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
