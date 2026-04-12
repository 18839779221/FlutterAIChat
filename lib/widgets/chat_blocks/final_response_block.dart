import 'package:ai_chat/theme/app_spacing.dart';
import 'package:ai_chat/widgets/markdown/flutter_markdown_impl.dart';
import 'package:flutter/material.dart';

/// High-priority final answer block shown after intermediate analysis.
class FinalResponseBlock extends StatelessWidget {
  final String title;
  final String text;

  const FinalResponseBlock({
    super.key,
    required this.title,
    required this.text,
  });

  @override
  Widget build(BuildContext context) {
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
            if (title.trim().isNotEmpty && title != '最终回答') ...[
              Text(
                title,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      height: 1.2,
                    ),
              ),
              SizedBox(height: spacing.xxs + 2),
            ],
            FlutterMarkdownImpl(data: text),
          ],
        ),
      ),
    );
  }
}
