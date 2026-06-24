import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/llm/llm_provider_config.dart';
import '../models/llm/llm_provider_model.dart';
import '../models/skill/duplicate_skill_invocation_mode.dart';
import '../models/skill/skill_descriptor.dart';
import '../models/tool/tool_policy.dart';
import '../providers/chat_providers.dart';
import '../services/llm_model_test_service.dart';
import '../theme/app_motion.dart';
import '../theme/app_radius.dart';
import '../theme/app_spacing.dart';
import '../theme/app_theme_controller.dart';
import '../theme/app_theme_spec.dart';
import '../widgets/settings/settings_row.dart';
import '../widgets/settings/settings_summary_group.dart';
import '../widgets/settings/settings_value_badge.dart';
import '../widgets/shared/app_bottom_sheet.dart';
import 'model_management_page.dart';

class SettingsPage extends ConsumerStatefulWidget {
  const SettingsPage({super.key});

  @override
  ConsumerState<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends ConsumerState<SettingsPage> {
  bool _didScheduleBootstrapReadyLoad = false;
  bool _isLoading = true;
  bool _isTestingModel = false;
  bool _isLoadingSkills = true;
  bool _isInstallingSkill = false;
  ToolExecutionMode _toolExecutionMode = ToolExecutionMode.balanced;
  DuplicateSkillInvocationMode _duplicateSkillInvocationMode =
      DuplicateSkillInvocationMode.reuse;
  List<String> _trustedToolNames = const [];
  List<String> _blockedToolNames = const [];
  List<SkillDescriptor> _skills = const [];
  String? _latestSkillInstallUrl;
  String? _chatCompletionsAdapterType;
  LlmProviderConfig? _currentProvider;
  LlmProviderModel? _currentModel;

  @override
  void initState() {
    super.initState();
  }

  Future<void> _loadSettings() async {
    final repository = ref.read(appSettingsRepositoryProvider);
    final providers = await repository.getProviders();
    final selection = await repository.getSelectionState();
    final toolExecutionModeName = await repository.getToolExecutionModeName();
    final duplicateSkillInvocationMode =
        await repository.getDuplicateSkillInvocationMode();
    final trustedToolNames = await repository.getTrustedToolNames();
    final blockedToolNames = await repository.getBlockedToolNames();
    final latestSkillInstallUrl = await repository.getLatestSkillInstallUrl();
    final chatCompletionsAdapterType =
        await repository.getChatCompletionsAdapterType();

    LlmProviderConfig? currentProvider;
    LlmProviderModel? currentModel;
    for (final provider in providers) {
      if (provider.id == selection.selectedProviderId) {
        currentProvider = provider;
        break;
      }
    }
    currentProvider ??= providers.isEmpty ? null : providers.first;

    if (currentProvider != null) {
      for (final model in currentProvider.models) {
        if (model.id == selection.selectedModelId) {
          currentModel = model;
          break;
        }
      }
      currentModel ??=
          currentProvider.models.isEmpty ? null : currentProvider.models.first;
    }

    if (!mounted) {
      return;
    }

    await _loadSkills();

    if (!mounted) {
      return;
    }

    setState(() {
      _currentProvider = currentProvider;
      _currentModel = currentModel;
      _toolExecutionMode = _parseToolExecutionMode(toolExecutionModeName);
      _duplicateSkillInvocationMode = duplicateSkillInvocationMode;
      _trustedToolNames = trustedToolNames.toList()..sort();
      _blockedToolNames = blockedToolNames.toList()..sort();
      _latestSkillInstallUrl = latestSkillInstallUrl;
      _chatCompletionsAdapterType = chatCompletionsAdapterType;
      _isLoading = false;
    });
  }

  Future<void> _loadSkills() async {
    final skills =
        await ref.read(skillRuntimeServiceProvider).listInstalledSkills();
    if (!mounted) {
      return;
    }
    setState(() {
      _skills = skills;
      _isLoadingSkills = false;
    });
  }

  ToolExecutionMode _parseToolExecutionMode(String? modeName) {
    for (final value in ToolExecutionMode.values) {
      if (value.name == modeName) {
        return value;
      }
    }
    return ToolExecutionMode.balanced;
  }

  String _toolExecutionModeDescription(ToolExecutionMode mode) {
    switch (mode) {
      case ToolExecutionMode.conservative:
        return '只有低风险读取类工具自动执行。';
      case ToolExecutionMode.balanced:
        return '读取类工具自动执行，副作用工具默认先确认。';
      case ToolExecutionMode.aggressive:
        return '尽量自动执行已识别的工具动作。';
    }
  }

  Future<void> _saveToolExecutionMode(ToolExecutionMode mode) async {
    await ref.read(appSettingsRepositoryProvider).saveToolExecutionModeName(
          mode.name,
        );
    if (!mounted) {
      return;
    }
    setState(() {
      _toolExecutionMode = mode;
    });
  }

  Future<void> _removeTrustedTool(String toolName) async {
    await ref
        .read(appSettingsRepositoryProvider)
        .removeTrustedToolName(toolName);
    if (!mounted) {
      return;
    }
    setState(() {
      _trustedToolNames =
          _trustedToolNames.where((item) => item != toolName).toList();
    });
  }

  Future<void> _removeBlockedTool(String toolName) async {
    await ref
        .read(appSettingsRepositoryProvider)
        .removeBlockedToolName(toolName);
    if (!mounted) {
      return;
    }
    setState(() {
      _blockedToolNames =
          _blockedToolNames.where((item) => item != toolName).toList();
    });
  }

  Future<void> _saveDuplicateSkillInvocationMode(
    DuplicateSkillInvocationMode mode,
  ) async {
    await ref
        .read(appSettingsRepositoryProvider)
        .saveDuplicateSkillInvocationMode(mode);
    if (!mounted) {
      return;
    }
    setState(() {
      _duplicateSkillInvocationMode = mode;
    });
  }

  Future<void> _openModelManagement() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ModelManagementPage(
          repository: ref.read(appSettingsRepositoryProvider),
        ),
      ),
    );
    await _loadSettings();
  }

  Future<void> _openSkillManagement() async {
    final result = await showAppBottomSheet<String>(
      context: context,
      mode: AppBottomSheetMode.adaptive,
      title: '安装 Skill',
      subtitle: '输入公开 GitHub 仓库或 tree 子目录 URL。推荐直接填写 skill 子目录地址。',
      bodyPadding: EdgeInsets.fromLTRB(
        Theme.of(context).extension<AppSpacing>()!.lg,
        Theme.of(context).extension<AppSpacing>()!.sm,
        Theme.of(context).extension<AppSpacing>()!.lg,
        Theme.of(context).extension<AppSpacing>()!.lg,
      ),
      body: _SkillQuickManageSheet(
        skills: _skills,
        isLoading: _isLoadingSkills,
        isInstalling: _isInstallingSkill,
        duplicateMode: _duplicateSkillInvocationMode,
        latestInstallUrl: _latestSkillInstallUrl,
        onReloadModeChanged: (reload) {
          _saveDuplicateSkillInvocationMode(
            reload
                ? DuplicateSkillInvocationMode.reload
                : DuplicateSkillInvocationMode.reuse,
          );
        },
        onSkillToggled: _toggleSkill,
      ),
    );
    if (result == null || result.trim().isEmpty) {
      return;
    }
    setState(() {
      _isInstallingSkill = true;
    });
    try {
      await ref
          .read(appSettingsRepositoryProvider)
          .saveLatestSkillInstallUrl(result);
      await ref
          .read(skillInstallerServiceProvider)
          .installFromGitHubUrl(result);
      await _loadSettings();
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Skill 安装成功')),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Skill 安装失败: $error')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isInstallingSkill = false;
        });
      }
    }
  }

  Future<void> _toggleSkill(SkillDescriptor skill, bool enabled) async {
    final repository = ref.read(appSettingsRepositoryProvider);
    if (enabled) {
      await repository.enableSkillId(skill.id);
    } else {
      await repository.disableSkillId(skill.id);
    }
    await _loadSkills();
  }

  Future<void> _testCurrentModel() async {
    final provider = _currentProvider;
    final model = _currentModel;
    if (provider == null || model == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请先新增提供方和模型')),
      );
      return;
    }

    setState(() {
      _isTestingModel = true;
    });

    try {
      final result = await LlmModelTestService().testModel(
        provider: provider,
        model: model,
      );
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('测试成功: $result')),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('测试失败: $error')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isTestingModel = false;
        });
      }
    }
  }

  Future<void> _openToolExecutionModePicker() async {
    final selected = await showAppBottomSheet<ToolExecutionMode>(
      context: context,
      mode: AppBottomSheetMode.adaptive,
      title: '执行模式',
      subtitle: '当前页只做轻量切换，详细说明保留在工具与安全分组中。',
      bodyPadding: const EdgeInsets.fromLTRB(0, 8, 0, 16),
      body: _SelectionListSheet<ToolExecutionMode>(
        sheetKey: const ValueKey('tool-execution-mode-picker-sheet'),
        items: ToolExecutionMode.values
            .map(
              (mode) => _SelectionListItem<ToolExecutionMode>(
                value: mode,
                title: _toolExecutionModeTitle(mode),
                subtitle: _toolExecutionModeDescription(mode),
              ),
            )
            .toList(growable: false),
        selectedValue: _toolExecutionMode,
      ),
    );
    if (selected == null) {
      return;
    }
    await _saveToolExecutionMode(selected);
  }

  String _toolExecutionModeTitle(ToolExecutionMode mode) {
    switch (mode) {
      case ToolExecutionMode.conservative:
        return '保守';
      case ToolExecutionMode.balanced:
        return '平衡';
      case ToolExecutionMode.aggressive:
        return '激进';
    }
  }

  @override
  Widget build(BuildContext context) {
    final bootstrapState = ref.watch(appBootstrapStateProvider);
    final isBootstrapReady = bootstrapState.isReady;
    final spacing = Theme.of(context).extension<AppSpacing>()!;
    final activeTheme = ref.watch(appThemeControllerProvider);
    final provider = _currentProvider;
    final model = _currentModel;
    final enabledSkillCount = _skills.where((skill) => skill.isEnabled).length;
    final showCompatibilityAdapter =
        (_chatCompletionsAdapterType ?? 'sdk').toLowerCase() != 'sdk';

    if (isBootstrapReady && !_didScheduleBootstrapReadyLoad) {
      _didScheduleBootstrapReadyLoad = true;
      Future<void>.microtask(_loadSettings);
    }

    return Scaffold(
      appBar: _buildTintedHeader(context, '设置'),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: EdgeInsets.fromLTRB(
                spacing.lg,
                spacing.lg,
                spacing.lg,
                spacing.xl,
              ),
              children: [
                Align(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 760),
                    child: Column(
                      children: [
                        SettingsSummaryGroup(
                          title: '模型与运行时',
                          children: [
                            SettingsRow(
                              title: '当前 Provider',
                              leading: const Icon(Icons.hub_outlined),
                              trailing: _StaticValuePill(
                                label: provider?.name ?? '未配置',
                                emphasize: provider == null,
                              ),
                            ),
                            SettingsRow(
                              title: '当前 Model',
                              leading:
                                  const Icon(Icons.chat_bubble_outline_rounded),
                              trailing: _StaticValuePill(
                                label: model?.displayName ?? '未配置',
                                emphasize: model == null,
                              ),
                            ),
                            SettingsRow(
                              title: '连通测试',
                              leading: const Icon(Icons.wifi_tethering_rounded),
                              padding: EdgeInsets.symmetric(
                                horizontal: spacing.lg,
                                vertical: spacing.xxs + 2,
                              ),
                              trailing: _QuickActionButton(
                                key: const ValueKey('connectivity-test-button'),
                                label: _isTestingModel ? '测试中' : '测试',
                                onPressed:
                                    _isTestingModel ? null : _testCurrentModel,
                              ),
                            ),
                            SettingsRow(
                              title: '模型管理',
                              leading: const Icon(Icons.tune_rounded),
                              onTap: _openModelManagement,
                              trailing: const SizedBox.shrink(),
                            ),
                          ],
                        ),
                        SizedBox(height: spacing.xl),
                        SettingsSummaryGroup(
                          title: '工具与安全',
                          children: [
                            SettingsRow(
                              title: '执行模式',
                              leading: const Icon(Icons.bolt_outlined),
                              onTap: _openToolExecutionModePicker,
                              trailing: _TrailingTextValue(
                                label: _toolExecutionModeTitle(
                                  _toolExecutionMode,
                                ),
                                emphasize: _toolExecutionMode ==
                                    ToolExecutionMode.aggressive,
                              ),
                            ),
                            _PermissionOverviewBlock(
                              trustedToolNames: _trustedToolNames,
                              blockedToolNames: _blockedToolNames,
                              onRemoveTrusted: _removeTrustedTool,
                              onRemoveBlocked: _removeBlockedTool,
                            ),
                          ],
                        ),
                        SizedBox(height: spacing.xl),
                        SettingsSummaryGroup(
                          title: '扩展能力',
                          children: [
                            SettingsRow(
                              title: '已安装 Skills',
                              leading: const Icon(Icons.extension_outlined),
                              trailing: _TrailingTextValue(
                                label: '$enabledSkillCount/${_skills.length}',
                                emphasize: enabledSkillCount > 0,
                              ),
                            ),
                            SettingsRow(
                              title: '管理 Skills',
                              leading: const Icon(Icons.folder_open_outlined),
                              onTap: _openSkillManagement,
                              trailing: const SizedBox.shrink(),
                            ),
                            SettingsRow(
                              title: '重复调用时重载',
                              leading: const Icon(Icons.refresh_rounded),
                              padding: EdgeInsets.symmetric(
                                horizontal: spacing.lg,
                                vertical: spacing.xs,
                              ),
                              trailing: _CompactSettingsToggle(
                                key: const ValueKey(
                                  'duplicate-invocation-toggle',
                                ),
                                value: _duplicateSkillInvocationMode ==
                                    DuplicateSkillInvocationMode.reload,
                                onChanged: (value) {
                                  _saveDuplicateSkillInvocationMode(
                                    value
                                        ? DuplicateSkillInvocationMode.reload
                                        : DuplicateSkillInvocationMode.reuse,
                                  );
                                },
                              ),
                            ),
                          ],
                        ),
                        SizedBox(height: spacing.xl),
                        SettingsSummaryGroup(
                          title: '外观与兼容',
                          children: [
                            Padding(
                              padding: EdgeInsets.fromLTRB(
                                spacing.md,
                                spacing.md,
                                spacing.md,
                                spacing.xs,
                              ),
                              child: _ThemeSelectorBlock(
                                activeThemeId: activeTheme.id,
                                onThemeSelected: (themeId) => ref
                                    .read(appThemeControllerProvider.notifier)
                                    .setTheme(themeId),
                              ),
                            ),
                            if (showCompatibilityAdapter)
                              SettingsRow(
                                title: '兼容适配器',
                                leading: const Icon(Icons.sync_alt_rounded),
                                trailing: _TrailingTextValue(
                                  label: (_chatCompletionsAdapterType ?? 'sdk')
                                      .toUpperCase(),
                                  emphasize: true,
                                ),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}

PreferredSizeWidget _buildTintedHeader(BuildContext context, String title) {
  final colors = Theme.of(context).extension<AppThemeSpec>()!;

  return AppBar(
    centerTitle: true,
    backgroundColor: colors.chatBackground,
    surfaceTintColor: Colors.transparent,
    elevation: 0,
    scrolledUnderElevation: 0,
    shadowColor: Colors.transparent,
    shape: Border(
      bottom: BorderSide(
        color: colors.divider.withValues(alpha: 0.18),
      ),
    ),
    title: Text(
      title,
      style: Theme.of(context).textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w600,
            color: colors.primaryText,
          ),
    ),
  );
}

class _QuickActionButton extends StatefulWidget {
  const _QuickActionButton({
    super.key,
    required this.label,
    required this.onPressed,
  });

  final String label;
  final VoidCallback? onPressed;

  @override
  State<_QuickActionButton> createState() => _QuickActionButtonState();
}

class _QuickActionButtonState extends State<_QuickActionButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppThemeSpec>()!;
    final motion = Theme.of(context).extension<AppMotion>()!;
    final spacing = Theme.of(context).extension<AppSpacing>()!;
    final radius = Theme.of(context).extension<AppRadius>()!;

    return AnimatedScale(
      scale: _pressed ? 0.985 : 1,
      duration: motion.instant,
      curve: motion.easeOut,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(radius.pill),
          onTap: widget.onPressed,
          onHighlightChanged: (value) {
            if (_pressed != value) {
              setState(() {
                _pressed = value;
              });
            }
          },
          child: AnimatedContainer(
            duration: motion.quick,
            curve: motion.easeOut,
            constraints: const BoxConstraints(minWidth: 52, minHeight: 24),
            padding: EdgeInsets.symmetric(
              horizontal: spacing.xs + 2,
              vertical: spacing.xxs - 1,
            ),
            decoration: BoxDecoration(
              color: colors.assistantSurface.withValues(
                alpha:
                    widget.onPressed == null ? 0.58 : (_pressed ? 0.96 : 0.84),
              ),
              borderRadius: BorderRadius.circular(radius.pill),
            ),
            child: Center(
              child: Text(
                widget.label,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: widget.onPressed == null
                          ? colors.secondaryText
                          : colors.primaryText,
                      fontWeight: FontWeight.w500,
                      fontSize: 12,
                      height: 1,
                    ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _StaticValuePill extends StatelessWidget {
  const _StaticValuePill({
    required this.label,
    this.emphasize = false,
  });

  final String label;
  final bool emphasize;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppThemeSpec>()!;
    return Text(
      label,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      textAlign: TextAlign.right,
      style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: emphasize
                ? colors.workflowWarning.withValues(alpha: 0.9)
                : colors.secondaryText.withValues(alpha: 0.9),
            fontWeight: FontWeight.w400,
            height: 1.15,
          ),
    );
  }
}

class _TrailingTextValue extends StatelessWidget {
  const _TrailingTextValue({
    required this.label,
    this.emphasize = false,
  });

  final String label;
  final bool emphasize;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppThemeSpec>()!;
    return Text(
      label,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      textAlign: TextAlign.right,
      style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: emphasize
                ? colors.workflowWarning.withValues(alpha: 0.9)
                : colors.secondaryText.withValues(alpha: 0.86),
            fontWeight: FontWeight.w600,
            height: 1.15,
          ),
    );
  }
}

class _CompactSettingsToggle extends StatefulWidget {
  const _CompactSettingsToggle({
    super.key,
    required this.value,
    required this.onChanged,
  });

  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  State<_CompactSettingsToggle> createState() => _CompactSettingsToggleState();
}

class _CompactSettingsToggleState extends State<_CompactSettingsToggle> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppThemeSpec>()!;
    final motion = Theme.of(context).extension<AppMotion>()!;
    final radius = Theme.of(context).extension<AppRadius>()!;

    return Semantics(
      button: true,
      toggled: widget.value,
      child: AnimatedScale(
        scale: _pressed ? 0.97 : 1,
        duration: motion.instant,
        curve: motion.easeOut,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () => widget.onChanged(!widget.value),
            borderRadius: BorderRadius.circular(radius.pill),
            onHighlightChanged: (value) {
              if (_pressed != value) {
                setState(() {
                  _pressed = value;
                });
              }
            },
            child: AnimatedContainer(
              duration: motion.quick,
              curve: motion.easeOut,
              width: 34,
              height: 20,
              padding: const EdgeInsets.all(2),
              decoration: BoxDecoration(
                color: widget.value
                    ? colors.workflowRunning.withValues(
                        alpha: _pressed ? 0.8 : 0.92,
                      )
                    : colors.assistantSurface.withValues(
                        alpha: _pressed ? 0.98 : 0.9,
                      ),
                borderRadius: BorderRadius.circular(radius.pill),
                border: Border.all(
                  color: widget.value
                      ? colors.workflowRunning.withValues(alpha: 0.2)
                      : colors.divider.withValues(alpha: 0.5),
                ),
              ),
              child: Align(
                alignment: widget.value
                    ? Alignment.centerRight
                    : Alignment.centerLeft,
                child: Container(
                  width: 14,
                  height: 14,
                  decoration: BoxDecoration(
                    color:
                        widget.value ? Colors.white : colors.secondaryText,
                    borderRadius: BorderRadius.circular(radius.pill),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PermissionOverviewBlock extends StatelessWidget {
  const _PermissionOverviewBlock({
    required this.trustedToolNames,
    required this.blockedToolNames,
    required this.onRemoveTrusted,
    required this.onRemoveBlocked,
  });

  final List<String> trustedToolNames;
  final List<String> blockedToolNames;
  final Future<void> Function(String toolName) onRemoveTrusted;
  final Future<void> Function(String toolName) onRemoveBlocked;

  @override
  Widget build(BuildContext context) {
    final spacing = Theme.of(context).extension<AppSpacing>()!;

    return Padding(
      padding: EdgeInsets.fromLTRB(
        spacing.md,
        spacing.xs,
        spacing.md,
        spacing.sm,
      ),
      child: Column(
        children: [
          _PermissionBucket(
            title: '长期授权工具',
            emptyLabel: '当前没有长期授权项',
            toolNames: trustedToolNames,
            tone: SettingsValueBadgeTone.active,
            removeKeyBuilder: (toolName) =>
                ValueKey('remove-trusted-$toolName'),
            onRemove: onRemoveTrusted,
          ),
          SizedBox(height: spacing.sm),
          _PermissionBucket(
            title: '已阻止工具',
            emptyLabel: '当前没有阻止项',
            toolNames: blockedToolNames,
            tone: SettingsValueBadgeTone.warning,
            removeKeyBuilder: (toolName) =>
                ValueKey('remove-blocked-$toolName'),
            onRemove: onRemoveBlocked,
          ),
        ],
      ),
    );
  }
}

class _PermissionBucket extends StatelessWidget {
  const _PermissionBucket({
    required this.title,
    required this.emptyLabel,
    required this.toolNames,
    required this.tone,
    required this.removeKeyBuilder,
    required this.onRemove,
  });

  final String title;
  final String emptyLabel;
  final List<String> toolNames;
  final SettingsValueBadgeTone tone;
  final Key Function(String toolName) removeKeyBuilder;
  final Future<void> Function(String toolName) onRemove;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppThemeSpec>()!;
    final spacing = Theme.of(context).extension<AppSpacing>()!;
    final radius = Theme.of(context).extension<AppRadius>()!;
    final previewNames = toolNames.take(3).toList(growable: false);

    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.assistantSurface.withValues(alpha: 0.62),
        borderRadius: BorderRadius.circular(radius.md),
      ),
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          spacing.md,
          spacing.sm,
          spacing.md,
          spacing.sm,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: colors.primaryText,
                          fontWeight: FontWeight.w400,
                          fontSize: 14,
                        ),
                  ),
                ),
                _PermissionCountBadge(
                  count: toolNames.length,
                  tone: tone,
                ),
              ],
            ),
            if (previewNames.isNotEmpty) ...[
              SizedBox(height: spacing.sm),
              Wrap(
                spacing: spacing.sm,
                runSpacing: spacing.sm,
                children: previewNames
                    .map(
                      (toolName) => _SettingsToolChip(
                        label: toolName,
                        tone: tone,
                        removeKey: removeKeyBuilder(toolName),
                        onRemove: () => onRemove(toolName),
                      ),
                    )
                    .toList(growable: false),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _PermissionCountBadge extends StatelessWidget {
  const _PermissionCountBadge({
    required this.count,
    required this.tone,
  });

  final int count;
  final SettingsValueBadgeTone tone;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppThemeSpec>()!;
    return Text(
      '$count 项',
      style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: colors.secondaryText.withValues(alpha: 0.86),
            fontWeight: FontWeight.w400,
            height: 1.15,
          ),
    );
  }
}

class _SettingsToolChip extends StatefulWidget {
  const _SettingsToolChip({
    required this.label,
    required this.removeKey,
    required this.onRemove,
    this.tone = SettingsValueBadgeTone.neutral,
  });

  final String label;
  final Key removeKey;
  final VoidCallback onRemove;
  final SettingsValueBadgeTone tone;

  @override
  State<_SettingsToolChip> createState() => _SettingsToolChipState();
}

class _SettingsToolChipState extends State<_SettingsToolChip> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppThemeSpec>()!;
    final motion = Theme.of(context).extension<AppMotion>()!;
    final spacing = Theme.of(context).extension<AppSpacing>()!;
    final radius = Theme.of(context).extension<AppRadius>()!;

    return AnimatedScale(
      scale: _pressed ? 0.985 : 1,
      duration: motion.instant,
      curve: motion.easeOut,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: _backgroundColor(colors),
          borderRadius: BorderRadius.circular(radius.pill),
        ),
        child: Padding(
          padding: EdgeInsets.only(
            left: spacing.sm,
            top: spacing.xxs + 1,
            bottom: spacing.xxs + 1,
            right: spacing.xxs + 1,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                widget.label,
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: _foregroundColor(colors),
                      fontWeight: FontWeight.w700,
                    ),
              ),
              SizedBox(width: spacing.xxs),
              InkWell(
                key: widget.removeKey,
                borderRadius: BorderRadius.circular(radius.pill),
                onTap: widget.onRemove,
                onHighlightChanged: (value) {
                  if (_pressed != value) {
                    setState(() {
                      _pressed = value;
                    });
                  }
                },
                child: Padding(
                  padding: EdgeInsets.all(spacing.xxs + 1),
                  child: Icon(
                    Icons.close_rounded,
                    size: 14,
                    color: _foregroundColor(colors),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Color _backgroundColor(AppThemeSpec colors) {
    switch (widget.tone) {
      case SettingsValueBadgeTone.neutral:
        return colors.assistantSurface.withValues(alpha: 0.92);
      case SettingsValueBadgeTone.active:
        return colors.workflowRunning.withValues(alpha: 0.12);
      case SettingsValueBadgeTone.success:
        return colors.workflowSuccess.withValues(alpha: 0.12);
      case SettingsValueBadgeTone.warning:
        return colors.workflowWarning.withValues(alpha: 0.14);
    }
  }

  Color _foregroundColor(AppThemeSpec colors) {
    switch (widget.tone) {
      case SettingsValueBadgeTone.neutral:
        return colors.primaryText;
      case SettingsValueBadgeTone.active:
        return colors.workflowRunning;
      case SettingsValueBadgeTone.success:
        return colors.workflowSuccess;
      case SettingsValueBadgeTone.warning:
        return colors.workflowWarning;
    }
  }
}

class _ThemeSelectorBlock extends StatelessWidget {
  const _ThemeSelectorBlock({
    required this.activeThemeId,
    required this.onThemeSelected,
  });

  final String activeThemeId;
  final ValueChanged<String> onThemeSelected;

  @override
  Widget build(BuildContext context) {
    final spacing = Theme.of(context).extension<AppSpacing>()!;
    final activeTheme =
        AppThemeSpec.resolveById(activeThemeId) ?? AppThemeSpec.light();
    final themes = AppThemeSpec.builtInThemes();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(0, 0, 0, spacing.sm),
          child: Row(
            children: [
              Text(
                '主题',
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
              ),
              const Spacer(),
              Text(
                activeTheme.displayName,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context)
                          .extension<AppThemeSpec>()!
                          .secondaryText,
                      fontWeight: FontWeight.w600,
                    ),
              ),
            ],
          ),
        ),
        Row(
          children: [
            for (final theme in themes) ...[
              Expanded(
                child: _ThemeOptionCard(
                  themeId: theme.id,
                  title: theme.displayName,
                  previewTheme: theme,
                  selected: theme.id == activeThemeId,
                  onTap: () => onThemeSelected(theme.id),
                ),
              ),
              if (theme != themes.last) SizedBox(width: spacing.sm),
            ],
          ],
        ),
      ],
    );
  }
}

class _ThemeOptionCard extends StatefulWidget {
  const _ThemeOptionCard({
    required this.themeId,
    required this.title,
    required this.previewTheme,
    required this.selected,
    required this.onTap,
  });

  final String themeId;
  final String title;
  final AppThemeSpec previewTheme;
  final bool selected;
  final VoidCallback onTap;

  @override
  State<_ThemeOptionCard> createState() => _ThemeOptionCardState();
}

class _ThemeOptionCardState extends State<_ThemeOptionCard> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppThemeSpec>()!;
    final motion = Theme.of(context).extension<AppMotion>()!;
    final spacing = Theme.of(context).extension<AppSpacing>()!;
    final radius = Theme.of(context).extension<AppRadius>()!;

    return AnimatedScale(
      scale: _pressed ? 0.985 : 1,
      duration: motion.instant,
      curve: motion.easeOut,
      child: InkWell(
        key: ValueKey('theme-option-${widget.themeId}'),
        onTap: widget.onTap,
        borderRadius: BorderRadius.circular(radius.lg),
        onHighlightChanged: (value) {
          if (_pressed != value) {
            setState(() {
              _pressed = value;
            });
          }
        },
        child: AnimatedContainer(
          duration: motion.quick,
          curve: motion.easeOut,
          constraints: const BoxConstraints(minHeight: 124),
          padding: EdgeInsets.fromLTRB(
            spacing.sm,
            spacing.sm,
            spacing.sm,
            spacing.xs,
          ),
          decoration: BoxDecoration(
            color: widget.selected
                ? colors.assistantSurface
                : colors.chatBackground
                    .withValues(alpha: _pressed ? 0.98 : 0.92),
            borderRadius: BorderRadius.circular(radius.lg),
            border: Border.all(
              color: widget.selected
                  ? colors.workflowRunning.withValues(alpha: 0.76)
                  : colors.divider.withValues(alpha: 0.7),
              width: widget.selected ? 1.2 : 1,
            ),
            boxShadow: widget.selected
                ? [
                    BoxShadow(
                      color: colors.core.elevation.shadowColor
                          .withValues(alpha: 0.06),
                      blurRadius: 12,
                      spreadRadius: -8,
                      offset: const Offset(0, 6),
                    ),
                  ]
                : null,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AspectRatio(
                aspectRatio: 1.45,
                child: _ThemePreviewSwatch(
                  selected: widget.selected,
                  previewTheme: widget.previewTheme,
                ),
              ),
              SizedBox(height: spacing.xs),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      widget.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: widget.selected
                                ? colors.workflowRunning
                                : colors.primaryText,
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                  ),
                  if (widget.selected)
                    Icon(
                      Icons.check_rounded,
                      size: 14,
                      color: colors.workflowRunning,
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ThemePreviewSwatch extends StatelessWidget {
  const _ThemePreviewSwatch({
    required this.selected,
    required this.previewTheme,
  });

  final bool selected;
  final AppThemeSpec previewTheme;

  @override
  Widget build(BuildContext context) {
    final colors = previewTheme;
    final spacing = Theme.of(context).extension<AppSpacing>()!;
    final radius = Theme.of(context).extension<AppRadius>()!;
    final isOlivePaper = previewTheme.id == 'olive-paper';

    return DecoratedBox(
      decoration: BoxDecoration(
        color: selected
            ? colors.chatBackground.withValues(alpha: 0.98)
            : colors.assistantSurface.withValues(alpha: 0.88),
        borderRadius: BorderRadius.circular(radius.md),
        border: Border.all(
          color: colors.divider.withValues(alpha: 0.46),
        ),
      ),
      child: Padding(
        padding: EdgeInsets.all(spacing.xs + 1),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: isOlivePaper ? 24 : 28,
                        height: 4,
                        decoration: BoxDecoration(
                          color: colors.secondaryText.withValues(
                            alpha: isOlivePaper ? 0.55 : 0.72,
                          ),
                          borderRadius: BorderRadius.circular(999),
                        ),
                      ),
                      SizedBox(height: spacing.xxs + 2),
                      Container(
                        width: isOlivePaper ? 30 : 22,
                        height: 4,
                        decoration: BoxDecoration(
                          color: colors.secondaryText.withValues(
                            alpha: isOlivePaper ? 0.32 : 0.45,
                          ),
                          borderRadius: BorderRadius.circular(999),
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    color: isOlivePaper
                        ? colors.workflowRunning.withValues(alpha: 0.82)
                        : colors.workflowWarning.withValues(alpha: 0.86),
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
              ],
            ),
            SizedBox(height: spacing.xs),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Container(
                    height: 22,
                    decoration: BoxDecoration(
                      color: (isOlivePaper
                              ? colors.toolWorkflowSurface
                              : colors.structuredSurface)
                          .withValues(alpha: isOlivePaper ? 0.78 : 0.72),
                      borderRadius: BorderRadius.circular(radius.sm),
                    ),
                  ),
                ),
                SizedBox(width: spacing.xxs + 2),
                Container(
                  width: 24,
                  height: 22,
                  decoration: BoxDecoration(
                    color: (isOlivePaper
                            ? colors.structuredSurface
                            : colors.toolWorkflowSurface)
                        .withValues(alpha: isOlivePaper ? 0.72 : 0.8),
                    borderRadius: BorderRadius.circular(radius.sm),
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

class _SelectionListItem<T> {
  const _SelectionListItem({
    required this.value,
    required this.title,
    required this.subtitle,
  });

  final T value;
  final String title;
  final String subtitle;
}

class _SelectionListSheet<T> extends StatelessWidget {
  const _SelectionListSheet({
    required this.items,
    required this.selectedValue,
    this.sheetKey,
  });

  final List<_SelectionListItem<T>> items;
  final T selectedValue;
  final Key? sheetKey;

  @override
  Widget build(BuildContext context) {
    final spacing = Theme.of(context).extension<AppSpacing>()!;

    return ListView.separated(
      key: sheetKey,
      shrinkWrap: true,
      itemCount: items.length,
      padding: EdgeInsets.symmetric(horizontal: spacing.lg),
      itemBuilder: (context, index) {
        final item = items[index];
        final selected = item.value == selectedValue;
        return ListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(item.title),
          subtitle: Text(item.subtitle),
          trailing: selected
              ? const Icon(Icons.check_rounded)
              : const SizedBox(width: 20),
          onTap: () => Navigator.of(context).pop(item.value),
        );
      },
      separatorBuilder: (_, __) => SizedBox(height: spacing.xs),
    );
  }
}

class _SkillQuickManageSheet extends StatelessWidget {
  const _SkillQuickManageSheet({
    required this.skills,
    required this.isLoading,
    required this.isInstalling,
    required this.duplicateMode,
    required this.latestInstallUrl,
    required this.onReloadModeChanged,
    required this.onSkillToggled,
  });

  final List<SkillDescriptor> skills;
  final bool isLoading;
  final bool isInstalling;
  final DuplicateSkillInvocationMode duplicateMode;
  final String? latestInstallUrl;
  final ValueChanged<bool> onReloadModeChanged;
  final Future<void> Function(SkillDescriptor skill, bool enabled)
      onSkillToggled;

  @override
  Widget build(BuildContext context) {
    final spacing = Theme.of(context).extension<AppSpacing>()!;
    final colors = Theme.of(context).extension<AppThemeSpec>()!;

    return ListView(
      shrinkWrap: true,
      children: [
        Padding(
          padding: EdgeInsets.symmetric(horizontal: spacing.lg),
          child: SettingsRow(
            title: '最近安装来源',
            subtitle: latestInstallUrl ?? '尚未记录安装来源',
            trailing: SettingsValueBadge(
              label: isInstalling
                  ? '安装中'
                  : (latestInstallUrl == null ? '无' : '已记录'),
            ),
          ),
        ),
        Padding(
          padding: EdgeInsets.symmetric(horizontal: spacing.lg),
          child: SettingsRow(
            title: '重复调用时重载 Skill',
            subtitle: duplicateMode == DuplicateSkillInvocationMode.reload
                ? '重复调用会重新读取并加载 skill 内容。'
                : '重复调用直接复用已加载结果。',
            trailing: Switch(
              value: duplicateMode == DuplicateSkillInvocationMode.reload,
              onChanged: onReloadModeChanged,
            ),
          ),
        ),
        SizedBox(height: spacing.sm),
        if (isLoading)
          const Center(child: CircularProgressIndicator())
        else if (skills.isEmpty)
          Padding(
            padding: EdgeInsets.symmetric(horizontal: spacing.lg),
            child: Text(
              '当前没有已安装 skills。',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: colors.secondaryText,
                  ),
            ),
          )
        else
          ...skills.map(
            (skill) => Padding(
              padding: EdgeInsets.fromLTRB(
                spacing.lg,
                0,
                spacing.lg,
                spacing.sm,
              ),
              child: SettingsRow(
                title: skill.name,
                subtitle: skill.description,
                trailing: Switch(
                  value: skill.isEnabled,
                  onChanged: (value) => onSkillToggled(skill, value),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
