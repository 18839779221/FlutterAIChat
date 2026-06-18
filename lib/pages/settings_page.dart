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
  String? _imageGenerationProviderId;
  String? _imageGenerationModelId;
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
    final additionalConfig = await repository.getAdditionalConfig();
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
      _imageGenerationProviderId =
          additionalConfig['image_generation.default_provider_id']?.toString();
      _imageGenerationModelId =
          additionalConfig['image_generation.default_model_id']?.toString();
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

  Future<void> _openThemePicker() async {
    final activeTheme = ref.read(appThemeControllerProvider);
    final selected = await showAppBottomSheet<String>(
      context: context,
      mode: AppBottomSheetMode.adaptive,
      title: '选择主题',
      subtitle: '主题切换会立即作用到整个应用。',
      bodyPadding: const EdgeInsets.fromLTRB(0, 8, 0, 16),
      body: _SelectionListSheet<String>(
        sheetKey: const ValueKey('theme-picker-sheet'),
        items: AppThemeSpec.builtInThemes().map((theme) {
          return _SelectionListItem<String>(
            value: theme.id,
            title: theme.displayName,
            subtitle: theme.id == activeTheme.id ? '当前主题' : '点击切换',
          );
        }).toList(growable: false),
        selectedValue: activeTheme.id,
      ),
    );
    if (selected == null) {
      return;
    }
    await ref.read(appThemeControllerProvider.notifier).setTheme(selected);
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

  Future<void> _openDuplicateInvocationModePicker() async {
    final selected = await showAppBottomSheet<DuplicateSkillInvocationMode>(
      context: context,
      mode: AppBottomSheetMode.adaptive,
      title: '重复调用策略',
      subtitle: '简单切换即可，复杂技能管理仍留在扩展能力分组。',
      bodyPadding: const EdgeInsets.fromLTRB(0, 8, 0, 16),
      body: _SelectionListSheet<DuplicateSkillInvocationMode>(
        items: DuplicateSkillInvocationMode.values
            .map(
              (mode) => _SelectionListItem<DuplicateSkillInvocationMode>(
                value: mode,
                title: mode == DuplicateSkillInvocationMode.reload
                    ? '重复调用时重载'
                    : '重复调用时复用',
                subtitle: mode == DuplicateSkillInvocationMode.reload
                    ? '重复调用会重新读取并加载一次 skill 内容。'
                    : '重复调用直接复用已加载结果。',
              ),
            )
            .toList(growable: false),
        selectedValue: _duplicateSkillInvocationMode,
      ),
    );
    if (selected == null) {
      return;
    }
    await _saveDuplicateSkillInvocationMode(selected);
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

    if (isBootstrapReady && !_didScheduleBootstrapReadyLoad) {
      _didScheduleBootstrapReadyLoad = true;
      Future<void>.microtask(_loadSettings);
    }

    return Scaffold(
      appBar: _buildTintedHeader(context, '设置'),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: EdgeInsets.all(spacing.lg),
              children: [
                SettingsSummaryGroup(
                  title: '模型与运行时',
                  summary: model == null ? '尚未完成模型接入' : '当前模型可用',
                  actionLabel: '进入管理',
                  onActionPressed: _openModelManagement,
                  children: [
                    SettingsRow(
                      title: '当前 Provider',
                      subtitle: provider?.baseUrl ?? '未配置连接地址',
                      trailing: SettingsValueBadge(
                        label: provider?.name ?? '未配置',
                        tone: provider == null
                            ? SettingsValueBadgeTone.warning
                            : SettingsValueBadgeTone.neutral,
                      ),
                    ),
                    SettingsRow(
                      title: '当前 Model',
                      subtitle: '用于主对话的默认模型',
                      trailing: SettingsValueBadge(
                        label: model?.displayName ?? '未配置',
                        tone: model == null
                            ? SettingsValueBadgeTone.warning
                            : SettingsValueBadgeTone.active,
                      ),
                    ),
                    SettingsRow(
                      title: '当前 Side Model',
                      subtitle: '默认 side task 模型',
                      trailing: SettingsValueBadge(
                        label: provider?.sideModelId?.trim().isNotEmpty == true
                            ? provider!.sideModelId!.trim()
                            : '跟随主模型',
                      ),
                    ),
                    SettingsRow(
                      title: '当前生图模型',
                      subtitle: _imageGenerationProviderId?.trim().isNotEmpty ==
                              true
                          ? _imageGenerationProviderId!.trim()
                          : '未配置生图 Provider',
                      trailing: SettingsValueBadge(
                        label: _imageGenerationModelId?.trim().isNotEmpty ==
                                true
                            ? _imageGenerationModelId!.trim()
                            : '未配置',
                        tone: _imageGenerationModelId?.trim().isNotEmpty == true
                            ? SettingsValueBadgeTone.neutral
                            : SettingsValueBadgeTone.warning,
                      ),
                    ),
                    SettingsRow(
                      title: '连通状态',
                      subtitle: '对当前模型执行快速连通验证',
                      trailing: _QuickActionButton(
                        label: _isTestingModel ? '测试中...' : '测试当前模型',
                        onPressed: _isTestingModel ? null : _testCurrentModel,
                      ),
                    ),
                  ],
                ),
                SizedBox(height: spacing.lg),
                SettingsSummaryGroup(
                  title: '工具与安全',
                  summary: _toolExecutionModeDescription(_toolExecutionMode),
                  actionLabel: '进入管理',
                  onActionPressed: _openToolExecutionModePicker,
                  children: [
                    SettingsRow(
                      title: '执行模式',
                      subtitle: '当前自动化策略',
                      onTap: _openToolExecutionModePicker,
                      trailing: SettingsValueBadge(
                        label: _toolExecutionModeTitle(_toolExecutionMode),
                        tone: _toolExecutionMode == ToolExecutionMode.aggressive
                            ? SettingsValueBadgeTone.warning
                            : SettingsValueBadgeTone.active,
                      ),
                    ),
                    SettingsRow(
                      title: '已信任工具',
                      subtitle: _trustedToolNames.isEmpty
                          ? '当前没有直接放行项'
                          : _trustedToolNames.take(2).join(' · '),
                      trailing: SettingsValueBadge(
                        label: '${_trustedToolNames.length} 项',
                      ),
                    ),
                    SettingsRow(
                      title: '已阻止工具',
                      subtitle: _blockedToolNames.isEmpty
                          ? '当前没有明确拦截项'
                          : _blockedToolNames.take(2).join(' · '),
                      trailing: SettingsValueBadge(
                        label: '${_blockedToolNames.length} 项',
                        tone: _blockedToolNames.isEmpty
                            ? SettingsValueBadgeTone.neutral
                            : SettingsValueBadgeTone.warning,
                      ),
                    ),
                    SettingsRow(
                      title: '执行模式',
                      subtitle: '轻量切换当前策略',
                      trailing: _QuickActionButton(
                        label: '切换',
                        onPressed: _openToolExecutionModePicker,
                      ),
                    ),
                  ],
                ),
                SizedBox(height: spacing.lg),
                SettingsSummaryGroup(
                  title: '扩展能力',
                  summary: _isLoadingSkills
                      ? '正在读取 skills 状态'
                      : _skills.isEmpty
                          ? '当前没有已安装 skills'
                          : '已安装 ${_skills.length} 项，启用 ${_skills.where((skill) => skill.isEnabled).length} 项',
                  actionLabel: '进入管理',
                  onActionPressed: _openSkillManagement,
                  children: [
                    SettingsRow(
                      title: '已安装 Skills',
                      subtitle: '当前可参与运行时匹配的技能目录',
                      trailing: SettingsValueBadge(label: '${_skills.length} 项'),
                    ),
                    SettingsRow(
                      title: '启用状态',
                      subtitle: _skills.isEmpty
                          ? '暂无可用技能'
                          : '禁用 ${_skills.where((skill) => !skill.isEnabled).length} 项',
                      trailing: SettingsValueBadge(
                        label:
                            '${_skills.where((skill) => skill.isEnabled).length} 项启用',
                        tone: SettingsValueBadgeTone.active,
                      ),
                    ),
                    SettingsRow(
                      title: '最近安装来源',
                      subtitle: _latestSkillInstallUrl ?? '尚未记录安装来源',
                      trailing: SettingsValueBadge(
                        label: _latestSkillInstallUrl == null ? '无' : '已记录',
                      ),
                    ),
                    SettingsRow(
                      title: '重复调用策略',
                      subtitle:
                          _duplicateSkillInvocationMode ==
                                  DuplicateSkillInvocationMode.reload
                              ? '重复调用会重新读取 skill 内容'
                              : '重复调用直接复用已加载结果',
                      trailing: _QuickActionButton(
                        label: _duplicateSkillInvocationMode ==
                                DuplicateSkillInvocationMode.reload
                            ? '重载'
                            : '复用',
                        onPressed: _openDuplicateInvocationModePicker,
                      ),
                    ),
                  ],
                ),
                SizedBox(height: spacing.lg),
                SettingsSummaryGroup(
                  title: '外观与兼容',
                  summary: '共享首页语法，兼容项作为高阶配置收口。',
                  actionLabel: '进入管理',
                  onActionPressed: _openThemePicker,
                  children: [
                    SettingsRow(
                      title: '当前主题',
                      subtitle: '轻量切换整个应用主题',
                      onTap: _openThemePicker,
                      trailing: _QuickActionButton(
                        label: activeTheme.displayName,
                        onPressed: _openThemePicker,
                      ),
                    ),
                    SettingsRow(
                      title: '兼容适配器',
                      subtitle: '用于 Chat Completions 的运行兼容策略',
                      trailing: SettingsValueBadge(
                        label:
                            (_chatCompletionsAdapterType ?? 'sdk').toUpperCase(),
                        tone: (_chatCompletionsAdapterType ?? 'sdk') == 'sdk'
                            ? SettingsValueBadgeTone.neutral
                            : SettingsValueBadgeTone.warning,
                      ),
                    ),
                  ],
                ),
              ],
            ),
    );
  }
}

PreferredSizeWidget _buildTintedHeader(BuildContext context, String title) {
  final colors = Theme.of(context).extension<AppThemeSpec>()!;

  return AppBar(
    backgroundColor: colors.workflowRunning.withValues(alpha: 0.1),
    surfaceTintColor: Colors.transparent,
    elevation: 0,
    titleSpacing: 12,
    title: Text(
      title,
      style: Theme.of(context).textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w600,
            color: colors.primaryText,
          ),
    ),
  );
}

class _QuickActionButton extends StatefulWidget {
  const _QuickActionButton({
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
            padding: EdgeInsets.symmetric(
              horizontal: spacing.sm,
              vertical: spacing.xs,
            ),
            decoration: BoxDecoration(
              color: colors.assistantSurface.withValues(
                alpha: widget.onPressed == null ? 0.6 : (_pressed ? 0.98 : 0.9),
              ),
              borderRadius: BorderRadius.circular(radius.pill),
            ),
            child: Text(
              widget.label,
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: widget.onPressed == null
                        ? colors.secondaryText
                        : colors.primaryText,
                    fontWeight: FontWeight.w700,
                  ),
            ),
          ),
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
  final Future<void> Function(SkillDescriptor skill, bool enabled) onSkillToggled;

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
              label: isInstalling ? '安装中' : (latestInstallUrl == null ? '无' : '已记录'),
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
