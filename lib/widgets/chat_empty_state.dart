import 'package:ai_chat/theme/app_colors.dart';
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

const defaultChatEmptySuggestions = <ChatEmptySuggestion>[
  ChatEmptySuggestion(
    label: '确认链路',
    prompt: 'remind me tomorrow at 9am to attend meeting',
  ),
  ChatEmptySuggestion(
    label: '多轮 Tool Call',
    prompt:
        '先搜索当前聊天记录里和 agent loop 相关的内容；如果只命中我这条提问，继续读取 turn harness 或 planner 相关代码文件确认实现，再给出简短结论。不要在信息不足时直接结束。',
  ),
  ChatEmptySuggestion(
    label: '单轮多工具',
    prompt:
        '先搜索当前聊天记录里和 agent loop 相关的内容，再读取相关代码文件，最后把发现整理成简短结论。能在一轮里规划多个工具就直接规划。',
  ),
  ChatEmptySuggestion(
    label: '工具失败回退',
    prompt:
        '请帮我创建一个明天上午九点的提醒，标题是“After meeting”，如果工具不可用，就给我一个清晰的回退说明。',
  ),
];

/// Calm empty state shown before the conversation begins.
class ChatEmptyState extends StatelessWidget {
  final ValueChanged<String>? onSuggestionSelected;
  final List<ChatEmptySuggestion> suggestions;

  const ChatEmptyState({
    super.key,
    this.onSuggestionSelected,
    this.suggestions = defaultChatEmptySuggestions,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppColors>()!;
    final spacing = Theme.of(context).extension<AppSpacing>()!;
    final radius = Theme.of(context).extension<AppRadius>()!;

    return LayoutBuilder(
      builder: (context, constraints) {
        final bottomInset =
            constraints.maxHeight > 720 ? spacing.xl * 2.4 : spacing.xl;

        return Align(
          alignment: const Alignment(0, 0.18),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                spacing.xl,
                spacing.xl,
                spacing.xl,
                bottomInset,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '开始一段新的对话',
                    style: TextStyle(
                      color: colors.primaryText,
                      fontSize: 24,
                      fontWeight: FontWeight.w700,
                      height: 1.12,
                    ),
                  ),
                  SizedBox(height: spacing.sm),
                  Text(
                    '从一个问题开始，或让助手帮你推进下一步。',
                    style: TextStyle(
                      color: colors.secondaryText,
                      fontSize: 14,
                      height: 1.5,
                    ),
                  ),
                  SizedBox(height: spacing.lg + spacing.sm),
                  Wrap(
                    spacing: spacing.xxs + 2,
                    runSpacing: spacing.xxs + 2,
                    children: suggestions
                        .map(
                          (suggestion) => Container(
                            decoration: BoxDecoration(
                              color: colors.assistantSurface
                                  .withValues(alpha: 0.78),
                              borderRadius: BorderRadius.circular(radius.pill),
                              boxShadow: [
                                BoxShadow(
                                  color: colors.primaryText
                                      .withValues(alpha: 0.04),
                                  blurRadius: 8,
                                  offset: const Offset(0, 3),
                                ),
                              ],
                            ),
                            child: Material(
                              color: Colors.transparent,
                              child: InkWell(
                                borderRadius: BorderRadius.circular(radius.pill),
                                onTap: () =>
                                    onSuggestionSelected?.call(suggestion.prompt),
                                child: Padding(
                                  padding: EdgeInsets.symmetric(
                                    horizontal: spacing.sm + spacing.xs,
                                    vertical: spacing.xxs + 3,
                                  ),
                                  child: Text(
                                    suggestion.label,
                                    style: TextStyle(
                                      color: colors.primaryText,
                                      fontSize: 11.5,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        )
                        .toList(),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
