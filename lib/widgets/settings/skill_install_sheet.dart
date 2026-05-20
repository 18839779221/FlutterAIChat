import 'package:ai_chat/theme/app_theme_spec.dart';
import 'package:ai_chat/theme/app_spacing.dart';
import 'package:flutter/material.dart';

class SkillInstallSheet extends StatefulWidget {
  const SkillInstallSheet({
    super.key,
    this.initialUrl,
  });

  final String? initialUrl;

  @override
  State<SkillInstallSheet> createState() => _SkillInstallSheetState();
}

class _SkillInstallSheetState extends State<SkillInstallSheet> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialUrl ?? '');
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final spacing = Theme.of(context).extension<AppSpacing>()!;
    final colors = Theme.of(context).extension<AppThemeSpec>()!;
    final viewInsets = MediaQuery.of(context).viewInsets;

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          spacing.lg,
          spacing.lg,
          spacing.lg,
          spacing.lg + viewInsets.bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '安装 Skill',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: colors.primaryText,
                    fontWeight: FontWeight.w700,
                  ),
            ),
            SizedBox(height: spacing.xs),
            Text(
              '输入公开 GitHub 仓库或 tree 子目录 URL。推荐直接填写 skill 子目录地址。',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: colors.secondaryText,
                    height: 1.4,
                  ),
            ),
            SizedBox(height: spacing.md),
            TextField(
              controller: _controller,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'GitHub URL',
                hintText: 'https://github.com/android/skills/tree/main/edge-to-edge',
              ),
              minLines: 1,
              maxLines: 3,
            ),
            SizedBox(height: spacing.md),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('取消'),
                  ),
                ),
                SizedBox(width: spacing.md),
                Expanded(
                  child: FilledButton(
                    onPressed: () =>
                        Navigator.of(context).pop(_controller.text.trim()),
                    child: const Text('继续'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
