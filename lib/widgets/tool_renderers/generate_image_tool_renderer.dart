import 'package:flutter/material.dart';

import '../../models/chat/tool_phase_visibility.dart';
import '../../models/chat/tool_presentation_event.dart';
import '../../models/chat/tool_workflow_step.dart';
import '../../models/chat_message.dart';
import '../../models/tool/tool_result.dart';
import '../../services/tool_ui_renderer_registry.dart';
import '../../theme/app_spacing.dart';
import '../shared/app_bottom_sheet.dart';
import 'research_tool_card_shell.dart';

class GenerateImageToolWorkflowCard extends StatelessWidget {
  const GenerateImageToolWorkflowCard({
    super.key,
    required this.steps,
    required this.isExpanded,
    this.onTap,
  });

  final List<ToolWorkflowStep> steps;
  final bool isExpanded;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final step = steps.isEmpty ? null : steps.last;
    final details = step?.details ?? const <String, dynamic>{};
    final prompt = _readString(details['prompt']);
    final modelLine = _buildModelLine(details);

    return ResearchToolCardShell(
      actionLabel: '生成图片',
      primaryText: '生成图片',
      statusLabel: workflowStatusLabel(step),
      statusColor: workflowStatusColor(context, step),
      isRunning: step?.status == ToolWorkflowStepStatus.running,
      expanded: isExpanded,
      onTap: onTap,
      footerHint: '查看参数',
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (prompt.isNotEmpty)
            Text(
              prompt,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    height: 1.4,
                  ),
            ),
          if (modelLine.isNotEmpty) ...[
            if (prompt.isNotEmpty)
              SizedBox(height: Theme.of(context).extension<AppSpacing>()!.xs),
            Text(
              modelLine,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.color
                        ?.withValues(alpha: 0.72),
                    height: 1.35,
                  ),
            ),
          ],
        ],
      ),
      expandedChild: GenerateImageParameterDetails(
        data: details,
        emptyPromptFallback: '未提供 prompt',
      ),
    );
  }
}

class GenerateImageToolResultCard extends StatefulWidget {
  const GenerateImageToolResultCard({
    super.key,
    required this.result,
  });

  final ToolResult result;

  @override
  State<GenerateImageToolResultCard> createState() =>
      _GenerateImageToolResultCardState();
}

class _GenerateImageToolResultCardState extends State<GenerateImageToolResultCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final data = widget.result.data;
    final prompt = _readString(data['prompt']);
    final modelLine = _buildModelLine(data);
    final imageCount = _normalizeGeneratedImages(data['generatedImages']).length;
    final previewLine = widget.result.status == ToolExecutionStatus.success
        ? (imageCount > 0 ? '共生成 $imageCount 张图片' : widget.result.summary)
        : widget.result.summary;

    return ResearchToolCardShell(
      actionLabel: '生成图片',
      primaryText: widget.result.status == ToolExecutionStatus.success
          ? '已生成图片'
          : '生成图片失败',
      statusLabel: widget.result.statusLabel,
      statusColor: resultStatusColor(context, widget.result),
      expanded: _expanded,
      onTap: () {
        setState(() {
          _expanded = !_expanded;
        });
      },
      footerHint: _expanded ? '收起参数' : '查看本次参数',
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (prompt.isNotEmpty)
            Text(
              prompt,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    height: 1.4,
                  ),
            ),
          if (previewLine.isNotEmpty) ...[
            if (prompt.isNotEmpty)
              SizedBox(height: Theme.of(context).extension<AppSpacing>()!.xs),
            Text(
              previewLine,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    height: 1.4,
                  ),
            ),
          ],
          if (modelLine.isNotEmpty) ...[
            if (prompt.isNotEmpty || previewLine.isNotEmpty)
              SizedBox(height: Theme.of(context).extension<AppSpacing>()!.xs),
            Text(
              modelLine,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.color
                        ?.withValues(alpha: 0.72),
                    height: 1.35,
                  ),
            ),
          ],
        ],
      ),
      expandedChild: GenerateImageParameterDetails(
        data: data,
        emptyPromptFallback: '未记录 prompt',
      ),
    );
  }
}

class GenerateImageParameterDetails extends StatelessWidget {
  const GenerateImageParameterDetails({
    super.key,
    required this.data,
    required this.emptyPromptFallback,
  });

  final Map<String, dynamic> data;
  final String emptyPromptFallback;

  @override
  Widget build(BuildContext context) {
    final sections = _buildParameterEntries(data);
    final spacing = Theme.of(context).extension<AppSpacing>()!;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _ParameterSection(
          title: 'Prompt',
          child: Text(
            _readString(data['prompt']).isEmpty
                ? emptyPromptFallback
                : _readString(data['prompt']),
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  height: 1.45,
                ),
          ),
        ),
        if (sections.isNotEmpty) ...[
          SizedBox(height: spacing.sm),
          _ParameterSection(
            title: '输入参数',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: sections
                  .map(
                    (entry) => Padding(
                      padding: EdgeInsets.only(bottom: spacing.xs),
                      child: _ParameterLine(
                        label: entry.label,
                        value: entry.value,
                      ),
                    ),
                  )
                  .toList(growable: false),
            ),
          ),
        ],
      ],
    );
  }
}

class GenerateImageToolUiRenderer extends ToolUiRenderer {
  const GenerateImageToolUiRenderer();

  @override
  Widget? buildResult(
    BuildContext context, {
    required ToolResult result,
    required ChatMessage? sourceMessage,
  }) {
    return GenerateImageToolResultCard(result: result);
  }

  @override
  Widget? buildWorkflowStep(
    BuildContext context, {
    required List<ToolWorkflowStep> steps,
    required ChatMessage? sourceMessage,
    required bool isExpanded,
    required VoidCallback? onTap,
  }) {
    return GenerateImageToolWorkflowCard(
      steps: steps,
      isExpanded: isExpanded,
      onTap: onTap,
    );
  }

  @override
  bool supportsResult(String toolName) => toolName.trim() == 'generate_image';

  @override
  bool supportsWorkflowStep(String toolName) =>
      toolName.trim() == 'generate_image';

  @override
  ToolPhaseVisibility visibilityForPhase(
    String toolName,
    ToolPresentationEventPhase phase,
  ) {
    if (toolName.trim() == 'generate_image' &&
        phase == ToolPresentationEventPhase.proposed) {
      return ToolPhaseVisibility.hidden;
    }
    return ToolPhaseVisibility.visible;
  }
}

class _ParameterSection extends StatelessWidget {
  const _ParameterSection({
    required this.title,
    required this.child,
  });

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final spacing = Theme.of(context).extension<AppSpacing>()!;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: Theme.of(context).textTheme.labelMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
        ),
        SizedBox(height: spacing.xs),
        child,
      ],
    );
  }
}

class _ParameterLine extends StatelessWidget {
  const _ParameterLine({
    required this.label,
    required this.value,
  });

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return RichText(
      text: TextSpan(
        style: Theme.of(context).textTheme.bodySmall?.copyWith(height: 1.4),
        children: [
          TextSpan(
            text: '$label：',
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          TextSpan(text: value),
        ],
      ),
    );
  }
}

class _ParameterEntry {
  const _ParameterEntry({
    required this.label,
    required this.value,
  });

  final String label;
  final String value;
}

List<_ParameterEntry> _buildParameterEntries(Map<String, dynamic> data) {
  final entries = <_ParameterEntry>[];
  void add(String label, Object? value) {
    final text = _normalizeParameterValue(value);
    if (text == null) {
      return;
    }
    entries.add(_ParameterEntry(label: label, value: text));
  }

  add('Model', _buildModelLine(data));
  add('Size', data['size']);
  add('Quality', data['quality']);
  add('Background', data['background']);
  add('Output Format', data['outputFormat'] ?? data['output_format']);
  add('Count', data['count'] ?? data['n'] ?? _generatedImageCount(data));
  add('Style', data['style']);
  add('Moderation', data['moderation']);

  final seenKeys = <String>{
    'prompt',
    'model',
    'provider',
    'size',
    'quality',
    'background',
    'outputFormat',
    'output_format',
    'count',
    'n',
    'style',
    'moderation',
    'generatedImages',
  };
  for (final entry in data.entries) {
    if (seenKeys.contains(entry.key)) {
      continue;
    }
    final text = _normalizeParameterValue(entry.value);
    if (text == null) {
      continue;
    }
    entries.add(
      _ParameterEntry(
        label: _humanizeKey(entry.key),
        value: text,
      ),
    );
  }
  return entries;
}

int? _generatedImageCount(Map<String, dynamic> data) {
  final images = _normalizeGeneratedImages(data['generatedImages']);
  return images.isEmpty ? null : images.length;
}

List<Map<String, dynamic>> _normalizeGeneratedImages(Object? value) {
  if (value is! List) {
    return const [];
  }
  return value.whereType<Map>().map(Map<String, dynamic>.from).toList();
}

String _buildModelLine(Map<String, dynamic> data) {
  final model = _readString(data['model']);
  final provider = _readString(data['provider']);
  if (model.isEmpty) {
    return provider.isEmpty ? '' : provider;
  }
  if (provider.isEmpty) {
    return model;
  }
  return '$model ($provider)';
}

String _readString(Object? value) {
  if (value is! String) {
    return '';
  }
  return value.trim();
}

String? _normalizeParameterValue(Object? value) {
  if (value == null) {
    return null;
  }
  if (value is String) {
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }
  if (value is num || value is bool) {
    return '$value';
  }
  return null;
}

String _humanizeKey(String key) {
  final normalized = key.replaceAll('_', ' ');
  if (normalized.isEmpty) {
    return key;
  }
  return normalized
      .split(' ')
      .where((part) => part.isNotEmpty)
      .map((part) => '${part[0].toUpperCase()}${part.substring(1)}')
      .join(' ');
}
