import 'package:ai_chat/models/debug/debug_test_case.dart';
import 'package:ai_chat/theme/app_theme_spec.dart';
import 'package:ai_chat/theme/app_radius.dart';
import 'package:ai_chat/theme/app_spacing.dart';
import 'package:flutter/material.dart';

class ChatEmptySuggestion {
  final String label;
  final String prompt;

  const ChatEmptySuggestion({
    required this.label,
    required this.prompt,
  });
}

List<ChatEmptySuggestion> buildChatEmptySuggestionsFromCases(
  List<DebugTestCase> cases, {
  int maxItems = 4,
}) {
  return cases
      .where((item) => item.enabled && item.featured)
      .take(maxItems)
      .map(
        (item) => ChatEmptySuggestion(
          label: item.title,
          prompt: item.prompt,
        ),
      )
      .toList(growable: false);
}

/// Calm empty state shown before the conversation begins.
class ChatEmptyState extends StatelessWidget {
  final ValueChanged<String>? onSuggestionSelected;
  final List<ChatEmptySuggestion> suggestions;
  final bool showModelSetupCallout;
  final VoidCallback? onConfigureModel;

  const ChatEmptyState({
    super.key,
    this.onSuggestionSelected,
    this.suggestions = const <ChatEmptySuggestion>[],
    this.showModelSetupCallout = false,
    this.onConfigureModel,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppThemeSpec>()!;
    final spacing = Theme.of(context).extension<AppSpacing>()!;
    final radius = Theme.of(context).extension<AppRadius>()!;

    return LayoutBuilder(
      builder: (context, constraints) {
        final bottomInset =
            constraints.maxHeight > 720 ? spacing.xl * 2.4 : spacing.xl;

        return Align(
          alignment: const Alignment(0, 0.06),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                spacing.xl,
                spacing.lg,
                spacing.xl,
                bottomInset,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (showModelSetupCallout)
                    DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            colors.assistantSurface.withValues(alpha: 0.96),
                            colors.settingsPanelBackground.withValues(alpha: 0.98),
                          ],
                        ),
                        borderRadius: BorderRadius.circular(radius.lg),
                        border: Border.all(color: colors.divider),
                        boxShadow: [
                          BoxShadow(
                            color: colors.primaryText.withValues(alpha: 0.05),
                            blurRadius: 24,
                            offset: const Offset(0, 12),
                          ),
                        ],
                      ),
                      child: Padding(
                        padding: EdgeInsets.all(spacing.xl),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              padding: EdgeInsets.symmetric(
                                horizontal: spacing.sm,
                                vertical: spacing.xxs + 2,
                              ),
                              decoration: BoxDecoration(
                                color: colors.workflowRunning
                                    .withValues(alpha: 0.12),
                                borderRadius:
                                    BorderRadius.circular(radius.pill),
                              ),
                              child: Text(
                                '开始前需要完成接入',
                                style: Theme.of(context)
                                    .textTheme
                                    .labelMedium
                                    ?.copyWith(
                                      color: colors.workflowRunning,
                                      fontWeight: FontWeight.w700,
                                    ),
                              ),
                            ),
                            SizedBox(height: spacing.md),
                            Text(
                              '先配置 API Key 与模型',
                              style: Theme.of(context)
                                  .textTheme
                                  .headlineSmall
                                  ?.copyWith(
                                    color: colors.primaryText,
                                    fontWeight: FontWeight.w700,
                                    height: 1.12,
                                  ),
                            ),
                            SizedBox(height: spacing.sm),
                            Text(
                              '当前首页推荐案例已被配置提醒替代。完成 Provider 和模型配置后，才能开始新的对话。',
                              style: Theme.of(context)
                                  .textTheme
                                  .bodyMedium
                                  ?.copyWith(
                                    color: colors.secondaryText,
                                    height: 1.55,
                                  ),
                            ),
                            SizedBox(height: spacing.lg),
                            Row(
                              children: [
                                Expanded(
                                  child: FilledButton(
                                    onPressed: onConfigureModel,
                                    child: const Text('去配置模型'),
                                  ),
                                ),
                              ],
                            ),
                            SizedBox(height: spacing.sm),
                            Wrap(
                              spacing: spacing.sm,
                              runSpacing: spacing.sm,
                              children: const [
                                _SetupHintChip(
                                  label: '统一在模型配置页完成设置',
                                ),
                                _SetupHintChip(
                                  label: '优先使用模型探测',
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    )
                  else ...[
                    Text(
                      '开始一段新的对话',
                      style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                            color: colors.primaryText,
                            fontWeight: FontWeight.w700,
                            height: 1.12,
                          ),
                    ),
                    SizedBox(height: spacing.sm),
                    Text(
                      '从一个问题开始，或让助手帮你推进下一步。',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: colors.secondaryText,
                            height: 1.5,
                          ),
                    ),
                    SizedBox(height: spacing.lg + spacing.sm),
                    Wrap(
                      spacing: spacing.sm,
                      runSpacing: spacing.sm,
                      children: suggestions
                          .map(
                            (suggestion) => _SuggestionChip(
                              suggestion: suggestion,
                              onTap: () =>
                                  onSuggestionSelected?.call(suggestion.prompt),
                            ),
                          )
                          .toList(),
                    ),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _SetupHintChip extends StatelessWidget {
  const _SetupHintChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppThemeSpec>()!;
    final radius = Theme.of(context).extension<AppRadius>()!;
    final spacing = Theme.of(context).extension<AppSpacing>()!;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.chatBackground.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(radius.pill),
      ),
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: spacing.sm,
          vertical: spacing.xxs + 2,
        ),
        child: Text(
          label,
          style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: colors.primaryText,
                fontWeight: FontWeight.w600,
              ),
        ),
      ),
    );
  }
}

class _SuggestionChip extends StatelessWidget {
  const _SuggestionChip({
    required this.suggestion,
    required this.onTap,
  });

  final ChatEmptySuggestion suggestion;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppThemeSpec>()!;
    final radius = Theme.of(context).extension<AppRadius>()!;
    final spacing = Theme.of(context).extension<AppSpacing>()!;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.assistantSurface.withValues(alpha: 0.82),
        borderRadius: BorderRadius.circular(radius.lg),
        boxShadow: [
          BoxShadow(
            color: colors.primaryText.withValues(alpha: 0.035),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(radius.lg),
          onTap: onTap,
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: spacing.md,
              vertical: spacing.sm,
            ),
            child: Text(
              suggestion.label,
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: colors.primaryText,
                    fontWeight: FontWeight.w600,
                  ),
            ),
          ),
        ),
      ),
    );
  }
}
