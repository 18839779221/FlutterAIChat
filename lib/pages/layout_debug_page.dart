import 'package:ai_chat/debug/layout_debug_cases.dart';
import 'package:ai_chat/models/debug/layout_debug_block.dart';
import 'package:ai_chat/models/debug/layout_debug_case.dart';
import 'package:ai_chat/theme/app_radius.dart';
import 'package:ai_chat/theme/app_spacing.dart';
import 'package:ai_chat/theme/app_theme_spec.dart';
import 'package:ai_chat/widgets/chat_blocks/assistant_doc_block.dart';
import 'package:flutter/material.dart';

/// Stable page for debugging document-style assistant layout cases.
class LayoutDebugPage extends StatefulWidget {
  const LayoutDebugPage({super.key});

  @override
  State<LayoutDebugPage> createState() => _LayoutDebugPageState();
}

class _LayoutDebugPageState extends State<LayoutDebugPage> {
  late LayoutDebugCase _selectedCase;

  @override
  void initState() {
    super.initState();
    _selectedCase = kLayoutDebugCases.first;
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppThemeSpec>()!;
    final spacing = Theme.of(context).extension<AppSpacing>()!;
    final radius = Theme.of(context).extension<AppRadius>()!;

    return Scaffold(
      appBar: AppBar(
        title: const Text('文档排版调试'),
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final isWide = constraints.maxWidth >= 920;
          if (isWide) {
            return Row(
              children: [
                SizedBox(
                  width: 280,
                  child: _buildSidebar(colors, spacing, radius),
                ),
                VerticalDivider(
                  width: 1,
                  thickness: 1,
                  color: colors.divider,
                ),
                Expanded(
                  child: _buildPreviewSurface(colors, spacing, radius),
                ),
              ],
            );
          }
          return Column(
            children: [
              _buildTopPicker(colors, spacing, radius),
              Expanded(
                child: _buildPreviewSurface(colors, spacing, radius),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildSidebar(
    AppThemeSpec colors,
    AppSpacing spacing,
    AppRadius radius,
  ) {
    return Container(
      color: colors.settingsPanelBackground,
      padding: EdgeInsets.all(spacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '固定案例',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
          ),
          SizedBox(height: spacing.xs),
          Text(
            '选择一组内置样例，直接观察真实回复块的文档排版表现。',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: colors.secondaryText,
                ),
          ),
          SizedBox(height: spacing.lg),
          Expanded(
            child: ListView.separated(
              itemCount: kLayoutDebugCases.length,
              separatorBuilder: (context, index) =>
                  SizedBox(height: spacing.xs),
              itemBuilder: (context, index) {
                final item = kLayoutDebugCases[index];
                final isSelected = item.id == _selectedCase.id;
                return Material(
                  color: isSelected
                      ? colors.toolWorkflowSurface
                      : colors.assistantSurface,
                  borderRadius: BorderRadius.circular(radius.md),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(radius.md),
                    onTap: () => _selectCase(item),
                    child: Padding(
                      padding: EdgeInsets.all(spacing.md),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            item.title,
                            style:
                                Theme.of(context).textTheme.titleSmall?.copyWith(
                                      fontWeight: FontWeight.w700,
                                    ),
                          ),
                          SizedBox(height: spacing.xxs),
                          Text(
                            item.description,
                            style:
                                Theme.of(context).textTheme.bodySmall?.copyWith(
                                      color: colors.secondaryText,
                                      height: 1.35,
                                    ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTopPicker(
    AppThemeSpec colors,
    AppSpacing spacing,
    AppRadius radius,
  ) {
    return Container(
      padding: EdgeInsets.fromLTRB(
        spacing.lg,
        spacing.md,
        spacing.lg,
        spacing.sm,
      ),
      decoration: BoxDecoration(
        color: colors.settingsPanelBackground,
        border: Border(
          bottom: BorderSide(color: colors.divider),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '固定案例',
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
          ),
          SizedBox(height: spacing.xs),
          DropdownButtonFormField<String>(
            initialValue: _selectedCase.id,
            decoration: InputDecoration(
              filled: true,
              fillColor: colors.assistantSurface,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(radius.md),
              ),
            ),
            items: [
              for (final item in kLayoutDebugCases)
                DropdownMenuItem<String>(
                  value: item.id,
                  child: Text(item.title),
                ),
            ],
            onChanged: (value) {
              if (value == null) {
                return;
              }
              final nextCase = kLayoutDebugCases.firstWhere(
                (item) => item.id == value,
              );
              _selectCase(nextCase);
            },
          ),
          SizedBox(height: spacing.sm),
          Text(
            _selectedCase.description,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: colors.secondaryText,
                ),
          ),
        ],
      ),
    );
  }

  Widget _buildPreviewSurface(
    AppThemeSpec colors,
    AppSpacing spacing,
    AppRadius radius,
  ) {
    return Container(
      color: colors.chatBackground,
      child: SafeArea(
        top: false,
          child: SingleChildScrollView(
            padding: EdgeInsets.all(spacing.lg),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 840),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final entry
                        in _selectedCase.blocks.asMap().entries) ...[
                      _buildBlock(entry.value, entry.key),
                      SizedBox(height: spacing.lg),
                    ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBlock(LayoutDebugBlock block, int index) {
    switch (block.type) {
      case LayoutDebugBlockType.assistantDoc:
        return AssistantDocBlock(
          text: block.markdownText,
          label: block.label,
          reasoningText: block.reasoningText,
          markdownCacheKey:
              block.markdownCacheKey ?? '${_selectedCase.id}:doc:$index',
        );
    }
  }

  void _selectCase(LayoutDebugCase nextCase) {
    if (nextCase.id == _selectedCase.id) {
      return;
    }
    setState(() {
      _selectedCase = nextCase;
    });
  }
}
