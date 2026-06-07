import 'dart:async';

import 'package:ai_chat/models/chat/active_turn_status_presentation.dart';
import 'package:ai_chat/models/chat/tool_workflow_step.dart';
import 'package:ai_chat/theme/app_radius.dart';
import 'package:ai_chat/theme/app_spacing.dart';
import 'package:ai_chat/theme/app_theme_spec.dart';
import 'package:ai_chat/widgets/chat_blocks/artifact_preview_surface.dart';
import 'package:ai_chat/widgets/chat_blocks/tool_workflow_card.dart';
import 'package:ai_chat/widgets/chat_blocks/unified_turn_status_bar.dart';
import 'package:ai_chat/widgets/tool_renderers/research_tool_card_shell.dart';
import 'package:flutter/material.dart';

/// Lightweight debug lab for the running-state components touched in this task.
class ComponentMotionDebugPage extends StatefulWidget {
  const ComponentMotionDebugPage({super.key});

  @override
  State<ComponentMotionDebugPage> createState() =>
      _ComponentMotionDebugPageState();
}

enum _StatusScene {
  planning('正在规划下一步', '正在分析工具返回结果并组织最终回复'),
  executingTool('正在执行网页搜索', '正在等待工具执行完成并同步最新结构化结果'),
  streamingResponse('正在生成回复', '正在综合已确认信息并生成最终自然语言回复');

  const _StatusScene(this.shortText, this.longText);

  final String shortText;
  final String longText;
}

enum _WorkflowState {
  running('执行中'),
  completed('已完成'),
  awaitingConfirmation('待确认');

  const _WorkflowState(this.label);

  final String label;
}

enum _ArtifactScenario {
  waiting('等待中'),
  refreshing('刷新中');

  const _ArtifactScenario(this.label);

  final String label;
}

class _ComponentMotionDebugPageState extends State<ComponentMotionDebugPage> {
  bool _statusRunning = true;
  bool _useLongStatusText = false;
  _StatusScene _statusScene = _StatusScene.planning;
  double _statusSweepDurationMs = 2500;

  _WorkflowState _workflowState = _WorkflowState.running;
  bool _workflowExpanded = false;

  _ArtifactScenario _artifactScenario = _ArtifactScenario.waiting;
  int _artifactReplayTick = 0;
  String? _artifactSource;
  Timer? _artifactRefreshTimer;

  @override
  void initState() {
    super.initState();
    _applyArtifactScenario();
  }

  @override
  void dispose() {
    _artifactRefreshTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppThemeSpec>()!;
    final spacing = Theme.of(context).extension<AppSpacing>()!;
    final radius = Theme.of(context).extension<AppRadius>()!;

    return Scaffold(
      appBar: AppBar(
        title: const Text('组件与动效调试'),
      ),
      body: SingleChildScrollView(
        padding: EdgeInsets.all(spacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildIntroCard(colors, spacing, radius),
            SizedBox(height: spacing.lg),
            _buildStatusSection(colors, spacing, radius),
            SizedBox(height: spacing.lg),
            _buildWorkflowSection(colors, spacing, radius),
            SizedBox(height: spacing.lg),
            _buildArtifactSection(colors, spacing, radius),
          ],
        ),
      ),
    );
  }

  Widget _buildIntroCard(
    AppThemeSpec colors,
    AppSpacing spacing,
    AppRadius radius,
  ) {
    return Container(
      padding: EdgeInsets.all(spacing.md),
      decoration: BoxDecoration(
        color: colors.assistantSurface,
        borderRadius: BorderRadius.circular(radius.lg),
        border: Border.all(color: colors.divider),
      ),
      child: Text(
        '这个页面只展示本轮涉及的运行态组件，方便直接看状态提示、卡片刀光和 artifact loading。',
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: colors.secondaryText,
              height: 1.45,
            ),
      ),
    );
  }

  Widget _buildStatusSection(
    AppThemeSpec colors,
    AppSpacing spacing,
    AppRadius radius,
  ) {
    final status = ActiveTurnStatusPresentation(
      phase: switch (_statusScene) {
        _StatusScene.planning => ActiveTurnStatusPhase.planning,
        _StatusScene.executingTool => ActiveTurnStatusPhase.executingTool,
        _StatusScene.streamingResponse =>
          ActiveTurnStatusPhase.streamingResponse,
      },
      text: _useLongStatusText ? _statusScene.longText : _statusScene.shortText,
      turnId: 'debug-turn-status',
      sourceKind: ActiveTurnStatusSourceKind.toolEvent,
      allowFloating: true,
    );

    return _DebugSection(
      title: '模型回复状态提示',
      colors: colors,
      spacing: spacing,
      radius: radius,
      controls: [
        _ToggleChip(
          label: _statusRunning ? '运行中' : '静止',
          selected: _statusRunning,
          onSelected: (selected) {
            setState(() {
              _statusRunning = selected;
            });
          },
        ),
        _ChoiceChipGroup<_StatusScene>(
          value: _statusScene,
          options: _StatusScene.values,
          labelBuilder: (value) => switch (value) {
            _StatusScene.planning => '规划',
            _StatusScene.executingTool => '工具执行',
            _StatusScene.streamingResponse => '生成回复',
          },
          onChanged: (value) {
            setState(() {
              _statusScene = value;
            });
          },
        ),
        _ChoiceChipGroup<bool>(
          value: _useLongStatusText,
          options: const [false, true],
          labelBuilder: (value) => value ? '长文案' : '短文案',
          onChanged: (value) {
            setState(() {
              _useLongStatusText = value;
            });
          },
        ),
        SizedBox(
          width: 260,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '文本刀光时长 ${_statusSweepDurationMs.toStringAsFixed(0)}ms',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: colors.secondaryText,
                    ),
              ),
              Slider(
                value: _statusSweepDurationMs,
                min: 1800,
                max: 3200,
                divisions: 28,
                label: '${_statusSweepDurationMs.toStringAsFixed(0)}ms',
                onChanged: (value) {
                  setState(() {
                    _statusSweepDurationMs = value;
                  });
                },
              ),
            ],
          ),
        ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          UnifiedTurnStatusBar(
            status: status,
            isRunning: _statusRunning,
            textSweepDuration: Duration(
              milliseconds: _statusSweepDurationMs.round(),
            ),
          ),
          SizedBox(height: spacing.sm),
          Align(
            alignment: Alignment.centerLeft,
            child: UnifiedTurnStatusBar(
              status: status,
              variant: UnifiedTurnStatusBarVariant.floating,
              isRunning: _statusRunning,
              textSweepDuration: Duration(
                milliseconds: _statusSweepDurationMs.round(),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWorkflowSection(
    AppThemeSpec colors,
    AppSpacing spacing,
    AppRadius radius,
  ) {
    final steps = _buildWorkflowSteps();
    final activeStep = steps.first;
    final statusColor = aggregateWorkflowStatusColor(context, steps);

    return _DebugSection(
      title: 'Tool Workflow 运行卡片',
      colors: colors,
      spacing: spacing,
      radius: radius,
      controls: [
        _ChoiceChipGroup<_WorkflowState>(
          value: _workflowState,
          options: _WorkflowState.values,
          labelBuilder: (value) => value.label,
          onChanged: (value) {
            setState(() {
              _workflowState = value;
            });
          },
        ),
        _ToggleChip(
          label: _workflowExpanded ? '已展开' : '已收起',
          selected: _workflowExpanded,
          onSelected: (_) {
            setState(() {
              _workflowExpanded = !_workflowExpanded;
            });
          },
        ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ToolWorkflowCard(
            title: 'Tool Workflow',
            steps: steps,
            expandedStepId: _workflowExpanded ? activeStep.stepId : null,
          ),
          SizedBox(height: spacing.md),
          ResearchToolCardShell(
            actionLabel: 'web_search',
            primaryText: '调研 shimmer / 刀光在 Flutter 里的可用方案',
            statusLabel: workflowStatusLabel(activeStep),
            statusColor: statusColor,
            isRunning: activeStep.status == ToolWorkflowStepStatus.running,
            expanded: _workflowExpanded,
            body: Text(
              '优先找维护活跃、接入简单、不会破坏当前低噪声运行态设计的实现路径。',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: colors.secondaryText,
                    height: 1.4,
                  ),
            ),
            expandedChild: const ResearchWorkflowItem(
              title: '汇总候选库与现有自定义 sweep 原语',
              statusLabel: '完成',
              statusColor: Colors.green,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildArtifactSection(
    AppThemeSpec colors,
    AppSpacing spacing,
    AppRadius radius,
  ) {
    return _DebugSection(
      title: 'Artifact Preview',
      colors: colors,
      spacing: spacing,
      radius: radius,
      controls: [
        _ChoiceChipGroup<_ArtifactScenario>(
          value: _artifactScenario,
          options: _ArtifactScenario.values,
          labelBuilder: (value) => value.label,
          onChanged: (value) {
            setState(() {
              _artifactScenario = value;
            });
            _applyArtifactScenario();
          },
        ),
        TextButton(
          key: const ValueKey('component-motion-artifact-replay'),
          onPressed: _replayArtifactScenario,
          child: const Text('重新播放'),
        ),
      ],
      child: ArtifactPreviewSurface(
        key: ValueKey('artifact-debug-preview-$_artifactReplayTick'),
        artifactId: 'debug-artifact-$_artifactReplayTick',
        source: _artifactSource,
        sourcePath: 'debug://artifact/$_artifactReplayTick',
        isRuntimePreview: true,
      ),
    );
  }

  List<ToolWorkflowStep> _buildWorkflowSteps() {
    final status = switch (_workflowState) {
      _WorkflowState.running => ToolWorkflowStepStatus.running,
      _WorkflowState.completed => ToolWorkflowStepStatus.completed,
      _WorkflowState.awaitingConfirmation =>
        ToolWorkflowStepStatus.awaitingConfirmation,
    };
    return [
      ToolWorkflowStep(
        stepId: 'debug-step-1',
        turnId: 'debug-turn',
        toolName: 'web_search',
        title: '检索候选方案',
        summary: status == ToolWorkflowStepStatus.running
            ? '正在抓取候选库并比对维护状态'
            : status == ToolWorkflowStepStatus.awaitingConfirmation
                ? '已整理候选项，等待是否继续展开验证'
                : '已完成候选库整理与适配性判断',
        status: status,
        requiresConfirmation:
            status == ToolWorkflowStepStatus.awaitingConfirmation,
      ),
    ];
  }

  void _replayArtifactScenario() {
    setState(() {
      _artifactReplayTick += 1;
    });
    _applyArtifactScenario();
  }

  void _applyArtifactScenario() {
    _artifactRefreshTimer?.cancel();
    if (_artifactScenario == _ArtifactScenario.waiting) {
      setState(() {
        _artifactSource = null;
      });
      return;
    }

    setState(() {
      _artifactSource = _artifactRefreshingBaseHtml;
    });

    _artifactRefreshTimer = Timer(const Duration(milliseconds: 900), () {
      if (!mounted || _artifactScenario != _ArtifactScenario.refreshing) {
        return;
      }
      setState(() {
        _artifactSource = _artifactRefreshingUpdatedHtml;
      });
    });
  }
}

class _DebugSection extends StatelessWidget {
  const _DebugSection({
    required this.title,
    required this.colors,
    required this.spacing,
    required this.radius,
    required this.controls,
    required this.child,
  });

  final String title;
  final AppThemeSpec colors;
  final AppSpacing spacing;
  final AppRadius radius;
  final List<Widget> controls;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.all(spacing.md),
      decoration: BoxDecoration(
        color: colors.assistantSurface,
        borderRadius: BorderRadius.circular(radius.lg),
        border: Border.all(color: colors.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: colors.primaryText,
                ),
          ),
          SizedBox(height: spacing.sm),
          Wrap(
            spacing: spacing.xs,
            runSpacing: spacing.xs,
            children: controls,
          ),
          SizedBox(height: spacing.md),
          child,
        ],
      ),
    );
  }
}

class _ToggleChip extends StatelessWidget {
  const _ToggleChip({
    required this.label,
    required this.selected,
    required this.onSelected,
  });

  final String label;
  final bool selected;
  final ValueChanged<bool> onSelected;

  @override
  Widget build(BuildContext context) {
    return FilterChip(
      label: Text(label),
      selected: selected,
      onSelected: onSelected,
    );
  }
}

class _ChoiceChipGroup<T> extends StatelessWidget {
  const _ChoiceChipGroup({
    required this.value,
    required this.options,
    required this.labelBuilder,
    required this.onChanged,
  });

  final T value;
  final List<T> options;
  final String Function(T value) labelBuilder;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final option in options)
          ChoiceChip(
            label: Text(labelBuilder(option)),
            selected: option == value,
            onSelected: (_) => onChanged(option),
          ),
      ],
    );
  }
}

const String _artifactRefreshingBaseHtml = '''
<div style="padding:16px;font-family:Arial,sans-serif;">
  <h2 style="margin:0 0 12px;">研究记录</h2>
  <p style="margin:0 0 10px;">正在整理候选 shimmer / sweep 方案。</p>
</div>
''';

const String _artifactRefreshingUpdatedHtml = '''
<div style="padding:16px;font-family:Arial,sans-serif;">
  <h2 style="margin:0 0 12px;">研究记录</h2>
  <p style="margin:0 0 10px;">正在整理候选 shimmer / sweep 方案。</p>
  <ul style="margin:0;padding-left:20px;">
    <li>现有 sweep surface 可继续复用</li>
    <li>状态文本建议接入字面刀光</li>
    <li>无需引入新的第三方 shimmer 库</li>
  </ul>
</div>
''';
