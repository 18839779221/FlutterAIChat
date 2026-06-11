import 'package:flutter/material.dart';

import '../../models/session/context_usage_category.dart';
import '../../models/session/context_usage_top_item.dart';
import '../../models/session/context_window_segment.dart';
import '../../models/session/context_window_snapshot.dart';
import '../../theme/app_radius.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_theme_spec.dart';
import '../../theme/app_typography.dart';

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
    final maxSheetHeight = MediaQuery.sizeOf(context).height * 0.78;

    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: maxSheetHeight,
        ),
        child: Container(
          key: const ValueKey('context-window-bottom-sheet'),
          decoration: BoxDecoration(
            color: colors.chatBackground,
            borderRadius:
                BorderRadius.vertical(top: Radius.circular(radius.lg)),
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
                style: AppTypography.uiStyle(
                  color: colors.secondaryText,
                  fontSize: 12.5,
                  height: 1.2,
                  fontWeight: FontWeight.w600,
                ),
              ),
              SizedBox(height: spacing.xs),
              _OverviewCard(snapshot: snapshot),
              SizedBox(height: spacing.md),
              _CardSection(
                title: '分类占用',
                child: Column(
                  children: snapshot.categories
                      .map((category) => _CategoryRow(category: category))
                      .toList(growable: false),
                ),
              ),
              SizedBox(height: spacing.md),
              if (snapshot.topItems.isNotEmpty)
                _CardSection(
                  title: 'Top 5',
                  child: Column(
                    children: snapshot.topItems
                        .map((item) => _TopItemRow(item: item))
                        .toList(growable: false),
                  ),
                ),
              SizedBox(height: spacing.md),
              _TechnicalDetailsCard(snapshot: snapshot),
            ],
          ),
        ),
      ),
    );
  }
}

class _OverviewCard extends StatelessWidget {
  const _OverviewCard({required this.snapshot});

  final ContextWindowSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppThemeSpec>()!;
    final spacing = Theme.of(context).extension<AppSpacing>()!;
    final radius = Theme.of(context).extension<AppRadius>()!;
    final percent = (snapshot.totalWindowUsageRatio * 100).round();
    final remainingTokens =
        (snapshot.maxContextTokens - snapshot.totalEstimatedInputTokens)
            .clamp(0, snapshot.maxContextTokens);

    return Container(
      padding: EdgeInsets.all(spacing.md),
      decoration: BoxDecoration(
        color: colors.assistantSurface.withValues(alpha: 0.96),
        borderRadius: BorderRadius.circular(radius.md),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 5,
                child: _UsageGridHost(snapshot: snapshot),
              ),
              SizedBox(width: spacing.md),
              Expanded(
                flex: 4,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      '$percent%',
                      style: AppTypography.uiStyle(
                        color: colors.primaryText,
                        fontSize: 34,
                        fontWeight: FontWeight.w700,
                        height: 0.95,
                      ),
                    ),
                    SizedBox(height: spacing.xs),
                    Text(
                      '${_formatCompactTokens(snapshot.totalEstimatedInputTokens)} / '
                      '${_formatCompactTokens(snapshot.maxContextTokens)}',
                      style: AppTypography.uiStyle(
                        color: colors.secondaryText,
                        fontSize: 13,
                        height: 1.2,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    SizedBox(height: spacing.sm),
                    _InlineMetric(
                      label: '剩余',
                      value: _formatCompactTokens(remainingTokens),
                    ),
                  ],
                ),
              ),
            ],
          ),
          SizedBox(height: spacing.sm),
          _UsageLegend(snapshot: snapshot),
        ],
      ),
    );
  }
}

class _UsageGridHost extends StatelessWidget {
  const _UsageGridHost({required this.snapshot});

  final ContextWindowSnapshot snapshot;
  static const int _totalCells = 100;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppThemeSpec>()!;
    final radius = Theme.of(context).extension<AppRadius>()!;
    final slices = _buildGridSlices(snapshot, colors);
    final cells = _buildGridCells(
      slices,
      totalCells: _totalCells,
      triggerStartCell:
          _resolveTriggerStartCell(snapshot, totalCells: _totalCells),
    );

    return Container(
      key: const ValueKey('context-usage-grid'),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: colors.structuredSurface.withValues(alpha: 0.78),
        borderRadius: BorderRadius.circular(radius.md),
        border: Border.all(
          color: colors.divider.withValues(alpha: 0.9),
        ),
        boxShadow: [
          BoxShadow(
            color: colors.semantic.chart.highlight.withValues(alpha: 0.04),
            blurRadius: 12,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: AspectRatio(
        aspectRatio: 1,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final cellSize = (constraints.maxWidth - (9 * 3)) / 10;
            return Wrap(
              spacing: 3,
              runSpacing: 3,
              children: cells
                  .map(
                    (cell) => SizedBox(
                      width: cellSize,
                      height: cellSize,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: cell.color,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: cell.showTriggerMark
                            ? CustomPaint(
                                painter: _GridTriggerMarkPainter(
                                  color: colors.primaryText
                                      .withValues(alpha: 0.24),
                                ),
                              )
                            : null,
                      ),
                    ),
                  )
                  .toList(growable: false),
            );
          },
        ),
      ),
    );
  }
}

class _GridTriggerMarkPainter extends CustomPainter {
  const _GridTriggerMarkPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = size.shortestSide * 0.12
      ..strokeCap = StrokeCap.round;
    final inset = size.shortestSide * 0.24;
    canvas.drawLine(
      Offset(inset, inset),
      Offset(size.width - inset, size.height - inset),
      paint,
    );
    canvas.drawLine(
      Offset(size.width - inset, inset),
      Offset(inset, size.height - inset),
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant _GridTriggerMarkPainter oldDelegate) {
    return oldDelegate.color != color;
  }
}

class _UsageLegend extends StatelessWidget {
  const _UsageLegend({required this.snapshot});

  final ContextWindowSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppThemeSpec>()!;
    final spacing = Theme.of(context).extension<AppSpacing>()!;
    final entries = _buildGridSlices(snapshot, colors)
        .where((slice) => slice.tokens > 0)
        .toList(growable: false);
    final triggerRatio = _resolveTriggerRatio(snapshot);
    final reserveZoneRatio = (1 - triggerRatio).clamp(0.0, 1.0);

    return Wrap(
      spacing: spacing.sm,
      runSpacing: spacing.xs,
      children: [
        ...entries.map(
          (entry) => Container(
            padding: EdgeInsets.symmetric(
              horizontal: spacing.xs + 2,
              vertical: spacing.xxs + 1,
            ),
            decoration: BoxDecoration(
              color: colors.structuredSurface.withValues(alpha: 0.66),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: entry.color,
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
                SizedBox(width: spacing.xs),
                Text(
                  entry.label,
                  style: AppTypography.uiStyle(
                    color: colors.secondaryText,
                    fontSize: 11.5,
                    height: 1.2,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ),
        if (reserveZoneRatio > 0)
          Container(
            padding: EdgeInsets.symmetric(
              horizontal: spacing.xs + 2,
              vertical: spacing.xxs + 1,
            ),
            decoration: BoxDecoration(
              color: colors.structuredSurface.withValues(alpha: 0.72),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: 10,
                  height: 10,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: colors.divider.withValues(alpha: 0.9),
                      borderRadius: BorderRadius.circular(3),
                    ),
                    child: CustomPaint(
                      painter: _GridTriggerMarkPainter(
                        color: colors.primaryText.withValues(alpha: 0.28),
                      ),
                    ),
                  ),
                ),
                SizedBox(width: spacing.xs),
                Text(
                  '压缩预留区 ${_formatPercent(reserveZoneRatio)}',
                  style: AppTypography.uiStyle(
                    color: colors.secondaryText,
                    fontSize: 11.5,
                    height: 1.2,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _InlineMetric extends StatelessWidget {
  const _InlineMetric({
    required this.label,
    required this.value,
  });

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppThemeSpec>()!;
    final spacing = Theme.of(context).extension<AppSpacing>()!;

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: spacing.sm,
        vertical: spacing.xs,
      ),
      decoration: BoxDecoration(
        color: colors.structuredSurface.withValues(alpha: 0.78),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: AppTypography.uiStyle(
              color: colors.secondaryText,
              fontSize: 11.5,
              height: 1.2,
              fontWeight: FontWeight.w600,
            ),
          ),
          SizedBox(width: spacing.xs),
          Text(
            value,
            style: AppTypography.uiStyle(
              color: colors.primaryText,
              fontSize: 11.5,
              height: 1.2,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _MetricBadge extends StatelessWidget {
  const _MetricBadge({
    required this.value,
  });

  final String value;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppThemeSpec>()!;
    final spacing = Theme.of(context).extension<AppSpacing>()!;

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: spacing.sm,
        vertical: spacing.xs,
      ),
      decoration: BoxDecoration(
        color: colors.structuredSurface.withValues(alpha: 0.82),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        value,
        style: AppTypography.uiStyle(
          color: colors.primaryText,
          fontSize: 11.5,
          height: 1.2,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _CardSection extends StatelessWidget {
  const _CardSection({
    required this.title,
    required this.child,
  });

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppThemeSpec>()!;
    final spacing = Theme.of(context).extension<AppSpacing>()!;
    final radius = Theme.of(context).extension<AppRadius>()!;

    return Container(
      padding: EdgeInsets.all(spacing.md),
      decoration: BoxDecoration(
        color: colors.assistantSurface.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(radius.md),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: AppTypography.uiStyle(
              color: colors.primaryText,
              fontSize: 15,
              height: 1.2,
              fontWeight: FontWeight.w700,
            ),
          ),
          SizedBox(height: spacing.sm),
          child,
        ],
      ),
    );
  }
}

class _CategoryRow extends StatelessWidget {
  const _CategoryRow({required this.category});

  final ContextUsageCategory category;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppThemeSpec>()!;
    final spacing = Theme.of(context).extension<AppSpacing>()!;
    final accent = _categoryColor(colors, category.type);

    return Padding(
      padding: EdgeInsets.only(bottom: spacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  category.label,
                  style: AppTypography.uiStyle(
                    color: colors.primaryText,
                    fontSize: 13.5,
                    height: 1.2,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              SizedBox(width: spacing.sm),
              _MetricBadge(
                value: '${_formatCompactTokens(category.estimatedTokens)} '
                    '${_formatPercent(category.shareOfTotalWindow)}',
              ),
            ],
          ),
          SizedBox(height: spacing.xs),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: Container(
              height: 8,
              color: colors.divider.withValues(alpha: 0.65),
              child: FractionallySizedBox(
                alignment: Alignment.centerLeft,
                widthFactor: category.shareOfTotalWindow.clamp(0.0, 1.0),
                child: Container(color: accent),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TopItemRow extends StatelessWidget {
  const _TopItemRow({required this.item});

  final ContextUsageTopItem item;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppThemeSpec>()!;
    final spacing = Theme.of(context).extension<AppSpacing>()!;

    return Padding(
      padding: EdgeInsets.only(bottom: spacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  item.displayLabel,
                  style: AppTypography.uiStyle(
                    color: colors.primaryText,
                    fontSize: 13,
                    height: 1.2,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              SizedBox(width: spacing.sm),
              _MetricBadge(
                value: '${_formatCompactTokens(item.estimatedTokens)} '
                    '${_formatPercent(item.shareOfTotalWindow)}',
              ),
            ],
          ),
          SizedBox(height: spacing.xs),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: Container(
              height: 6,
              color: colors.divider.withValues(alpha: 0.55),
              child: FractionallySizedBox(
                alignment: Alignment.centerLeft,
                widthFactor: item.shareOfTotalWindow.clamp(0.0, 1.0),
                child: Container(
                  color: colors.semantic.chart.series2,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TechnicalDetailsCard extends StatelessWidget {
  const _TechnicalDetailsCard({required this.snapshot});

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

    return Container(
      decoration: BoxDecoration(
        color: colors.assistantSurface.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(radius.md),
      ),
      child: ExpansionTile(
        tilePadding: EdgeInsets.symmetric(
          horizontal: spacing.md,
          vertical: spacing.xs,
        ),
        childrenPadding: EdgeInsets.fromLTRB(
          spacing.md,
          0,
          spacing.md,
          spacing.md,
        ),
        iconColor: colors.secondaryText,
        collapsedIconColor: colors.secondaryText,
        title: Text(
          '技术细节',
          style: AppTypography.uiStyle(
            color: colors.primaryText,
            fontSize: 14,
            height: 1.2,
            fontWeight: FontWeight.w700,
          ),
        ),
        children: [
          _DetailLine(
            label: 'planner 输入占触发阈值',
            value: _formatPercent(snapshot.plannerInputUsageRatio),
          ),
          _DetailLine(
            label: '总窗口占比',
            value: _formatPercent(snapshot.totalWindowUsageRatio),
          ),
          _DetailLine(
            label: 'effective input 占比',
            value: _formatPercent(snapshot.effectiveInputUsageRatio),
          ),
          _DetailLine(
            label: '估算输入 tokens',
            value: _formatCompactTokens(snapshot.totalEstimatedInputTokens),
          ),
          _DetailLine(
            label: '自动压缩阈值',
            value: _formatCompactTokens(snapshot.autoCompactTriggerTokens),
          ),
          _DetailLine(
            label: 'max context',
            value: _formatCompactTokens(snapshot.maxContextTokens),
          ),
          _DetailLine(
            label: 'effective input budget',
            value: _formatCompactTokens(snapshot.effectiveInputBudget),
          ),
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
          if (plannerVisibleSegments.isNotEmpty) ...[
            SizedBox(height: spacing.sm),
            Text(
              'Planner Context',
              style: AppTypography.uiStyle(
                color: colors.secondaryText,
                fontSize: 11.5,
                height: 1.2,
                fontWeight: FontWeight.w700,
              ),
            ),
            SizedBox(height: spacing.xs),
            ...plannerVisibleSegments
                .map((segment) => _SegmentRow(segment: segment)),
          ],
          if (reserveSegments.isNotEmpty) ...[
            SizedBox(height: spacing.sm),
            Text(
              'Reserves',
              style: AppTypography.uiStyle(
                color: colors.secondaryText,
                fontSize: 11.5,
                height: 1.2,
                fontWeight: FontWeight.w700,
              ),
            ),
            SizedBox(height: spacing.xs),
            ...reserveSegments.map((segment) => _SegmentRow(segment: segment)),
          ],
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
              style: AppTypography.uiStyle(
                color: colors.primaryText,
                fontSize: 12.5,
                height: 1.2,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          SizedBox(width: spacing.sm),
          Text(
            '${_formatPercent(segment.shareOfTotalWindow)} / '
            '${_formatPercent(segment.shareOfEffectiveInput)}',
            style: AppTypography.uiStyle(
              color: colors.secondaryText,
              fontSize: 11.5,
              height: 1.2,
              fontWeight: FontWeight.w500,
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
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Text(
              label,
              style: AppTypography.uiStyle(
                color: colors.secondaryText,
                fontSize: 12,
                height: 1.2,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          SizedBox(width: spacing.sm),
          Text(
            value,
            style: AppTypography.uiStyle(
              color: colors.primaryText,
              fontSize: 12,
              height: 1.2,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _GridSlice {
  const _GridSlice({
    required this.label,
    required this.tokens,
    required this.color,
  });

  final String label;
  final int tokens;
  final Color color;
}

class _GridCell {
  const _GridCell({
    required this.color,
    required this.showTriggerMark,
  });

  final Color color;
  final bool showTriggerMark;
}

List<_GridSlice> _buildGridSlices(
  ContextWindowSnapshot snapshot,
  AppThemeSpec colors,
) {
  final slices = snapshot.categories
      .map(
        (category) => _GridSlice(
          label: category.label,
          tokens: category.estimatedTokens,
          color: _categoryColor(colors, category.type),
        ),
      )
      .toList(growable: true);
  final remainingTokens =
      (snapshot.maxContextTokens - snapshot.totalEstimatedInputTokens).clamp(
    0,
    snapshot.maxContextTokens,
  );
  if (remainingTokens > 0) {
    slices.add(
      _GridSlice(
        label: '剩余',
        tokens: remainingTokens,
        color: colors.divider.withValues(alpha: 0.85),
      ),
    );
  }
  return slices;
}

List<_GridCell> _buildGridCells(
  List<_GridSlice> slices, {
  required int totalCells,
  required int triggerStartCell,
}) {
  if (slices.isEmpty || totalCells <= 0) {
    return const [];
  }
  final totalTokens = slices.fold<int>(0, (sum, item) => sum + item.tokens);
  if (totalTokens <= 0) {
    return List<_GridCell>.generate(
      totalCells,
      (index) => _GridCell(
        color: Colors.transparent,
        showTriggerMark: index >= triggerStartCell,
      ),
    );
  }

  final provisional = <int>[];
  final remainders = <double>[];
  var assigned = 0;
  for (final slice in slices) {
    final exact = (slice.tokens / totalTokens) * totalCells;
    final floored = exact.floor();
    provisional.add(floored);
    remainders.add(exact - floored);
    assigned += floored;
  }
  while (assigned < totalCells) {
    var maxIndex = 0;
    for (var i = 1; i < remainders.length; i += 1) {
      if (remainders[i] > remainders[maxIndex]) {
        maxIndex = i;
      }
    }
    provisional[maxIndex] += 1;
    remainders[maxIndex] = 0;
    assigned += 1;
  }

  final cells = <_GridCell>[];
  for (var i = 0; i < slices.length; i += 1) {
    cells.addAll(
      List<_GridCell>.generate(
        provisional[i],
        (_) => _GridCell(
          color: slices[i].color,
          showTriggerMark: false,
        ),
      ),
    );
  }
  final clampedCells = cells.length > totalCells
      ? cells.take(totalCells).toList(growable: false)
      : cells;
  return List<_GridCell>.generate(
    clampedCells.length,
    (index) => _GridCell(
      color: clampedCells[index].color,
      showTriggerMark: index >= triggerStartCell,
    ),
    growable: false,
  );
}

int _resolveTriggerStartCell(
  ContextWindowSnapshot snapshot, {
  required int totalCells,
}) {
  final triggerRatio = _resolveTriggerRatio(snapshot);
  final triggerStartCell = (triggerRatio * totalCells).ceil();
  return triggerStartCell.clamp(0, totalCells);
}

double _resolveTriggerRatio(ContextWindowSnapshot snapshot) {
  if (snapshot.maxContextTokens <= 0) {
    return 1.0;
  }
  final triggerWindowTokens =
      (snapshot.autoCompactTriggerTokens + snapshot.plannerReserveTokens)
          .clamp(0, snapshot.maxContextTokens);
  return (triggerWindowTokens / snapshot.maxContextTokens).clamp(0.0, 1.0);
}

Color _categoryColor(
  AppThemeSpec colors,
  ContextUsageCategoryType type,
) {
  switch (type) {
    case ContextUsageCategoryType.recentConversation:
      return colors.semantic.chart.series1;
    case ContextUsageCategoryType.toolResults:
      return colors.semantic.chart.series2;
    case ContextUsageCategoryType.historySummary:
      return colors.semantic.chart.series3;
    case ContextUsageCategoryType.systemSettings:
      return colors.semantic.chart.series5;
  }
}

String _formatPercent(double ratio) {
  return '${(ratio * 100).toStringAsFixed(1)}%';
}

String _formatCompactTokens(int tokens) {
  if (tokens >= 1000000) {
    final value = tokens / 1000000;
    return value >= 10
        ? '${value.toStringAsFixed(0)}m'
        : '${value.toStringAsFixed(1)}m';
  }
  if (tokens >= 1000) {
    final value = tokens / 1000;
    return value >= 100
        ? '${value.toStringAsFixed(0)}k'
        : '${value.toStringAsFixed(1)}k';
  }
  return '$tokens';
}
