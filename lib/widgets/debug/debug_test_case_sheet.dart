import 'package:ai_chat/models/debug/debug_test_case.dart';
import 'package:ai_chat/theme/app_theme_spec.dart';
import 'package:ai_chat/theme/app_spacing.dart';
import 'package:flutter/material.dart';

class DebugTestCaseSheet extends StatelessWidget {
  final List<DebugTestCase> cases;
  final ValueChanged<DebugTestCase> onSelected;
  final VoidCallback? onShowIdleStatus;
  final VoidCallback? onClearIdleStatus;

  const DebugTestCaseSheet({
    super.key,
    required this.cases,
    required this.onSelected,
    this.onShowIdleStatus,
    this.onClearIdleStatus,
  });

  @override
  Widget build(BuildContext context) {
    final spacing = Theme.of(context).extension<AppSpacing>()!;
    final colors = Theme.of(context).extension<AppThemeSpec>()!;
    final groupedCases = _groupCases(cases);
    final maxHeight = MediaQuery.of(context).size.height * 0.72;

    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxHeight),
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            spacing.lg,
            spacing.md,
            spacing.lg,
            spacing.lg,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '测试案例',
                style: TextStyle(
                  color: colors.primaryText,
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
              SizedBox(height: spacing.xs),
              Text(
                '选择一个案例后会直接填入输入框。',
                style: TextStyle(
                  color: colors.secondaryText,
                  fontSize: 12.5,
                  height: 1.4,
                ),
              ),
              if (onShowIdleStatus != null || onClearIdleStatus != null) ...[
                SizedBox(height: spacing.md),
                Wrap(
                  spacing: spacing.xs,
                  runSpacing: spacing.xs,
                  children: [
                    if (onShowIdleStatus != null)
                      OutlinedButton(
                        key: const ValueKey('debug-idle-status-button'),
                        onPressed: onShowIdleStatus,
                        child: const Text('显示测试状态'),
                      ),
                    if (onClearIdleStatus != null)
                      TextButton(
                        key: const ValueKey('debug-clear-idle-status-button'),
                        onPressed: onClearIdleStatus,
                        child: const Text('清除测试状态'),
                      ),
                  ],
                ),
              ],
              SizedBox(height: spacing.md),
              Expanded(
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: groupedCases.length,
                  separatorBuilder: (_, __) => SizedBox(height: spacing.md),
                  itemBuilder: (context, index) {
                    final entry = groupedCases[index];
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: EdgeInsets.only(
                            left: spacing.xs,
                            bottom: spacing.xs,
                          ),
                          child: Text(
                            _groupTitle(entry.$1),
                            style: TextStyle(
                              color: colors.primaryText,
                              fontSize: 12.5,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        ...entry.$2.map(
                          (item) => Padding(
                            padding: EdgeInsets.only(bottom: spacing.xs),
                            child: Material(
                              color: colors.assistantSurface.withValues(alpha: 0.94),
                              borderRadius: BorderRadius.circular(18),
                              child: InkWell(
                                key: ValueKey('debug-test-case-${item.id}'),
                                borderRadius: BorderRadius.circular(18),
                                onTap: () => onSelected(item),
                                child: Padding(
                                  padding: EdgeInsets.all(spacing.md),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        item.title,
                                        style: TextStyle(
                                          color: colors.primaryText,
                                          fontSize: 14,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                      SizedBox(height: spacing.xxs + 2),
                                      Text(
                                        item.summary,
                                        style: TextStyle(
                                          color: colors.secondaryText,
                                          fontSize: 12.5,
                                          height: 1.35,
                                        ),
                                      ),
                                      SizedBox(height: spacing.xs),
                                      Text(
                                        item.prompt,
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          color: colors.primaryText.withValues(alpha: 0.78),
                                          fontSize: 12.5,
                                          height: 1.35,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<(String, List<DebugTestCase>)> _groupCases(List<DebugTestCase> items) {
    const groupOrder = <String>[
      'ask-user-question',
      'tool-call',
      'confirmation',
      'failure',
    ];

    final buckets = <String, List<DebugTestCase>>{};
    for (final item in items) {
      buckets.putIfAbsent(item.group, () => <DebugTestCase>[]).add(item);
    }

    final orderedGroups = <String>[
      ...groupOrder.where(buckets.containsKey),
      ...buckets.keys.where((key) => !groupOrder.contains(key)),
    ];

    return orderedGroups
        .map((group) => (group, List<DebugTestCase>.unmodifiable(buckets[group]!)))
        .toList(growable: false);
  }

  String _groupTitle(String group) {
    switch (group) {
      case 'ask-user-question':
        return '澄清提问';
      case 'tool-call':
        return '工具调用';
      case 'confirmation':
        return '确认流程';
      case 'failure':
        return '异常与失败';
      default:
        return group;
    }
  }
}
