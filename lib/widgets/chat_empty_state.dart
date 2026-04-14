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
    label: '单题问答',
    prompt:
        '帮我设计一个本地 AI 聊天 App 的存储方案，但我现在还没决定用哪种数据库。请先向我提一个关键澄清问题，再继续给方案。',
  ),
  ChatEmptySuggestion(
    label: 'Other 自定义',
    prompt:
        '帮我规划一个 Flutter 聊天应用的本地持久化架构，但不要自己替我决定数据库类型。请先问我该选什么存储方案。',
  ),
  ChatEmptySuggestion(
    label: '多题澄清',
    prompt:
        '我要做一个新的 AI Chat 产品方案，但我还没决定目标平台、数据存储、以及是否支持离线模式。不要自己猜，请把这些关键问题一次性问我，然后再给最终建议。',
  ),
  ChatEmptySuggestion(
    label: '多选优先级',
    prompt:
        '我要做一个聊天应用的 MVP，但还没确定第一版必须支持哪些能力。请先问我希望首发包含哪些功能，允许多选，然后再帮我排优先级。',
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
