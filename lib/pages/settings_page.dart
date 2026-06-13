import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/llm/llm_provider_config.dart';
import '../models/llm/llm_provider_model.dart';
import '../models/skill/duplicate_skill_invocation_mode.dart';
import '../models/skill/skill_descriptor.dart';
import '../models/tool/tool_policy.dart';
import '../providers/chat_providers.dart';
import '../services/llm_model_test_service.dart';
import '../theme/app_theme_spec.dart';
import '../theme/app_radius.dart';
import '../theme/app_spacing.dart';
import '../widgets/settings/settings_group_section.dart';
import '../widgets/settings/settings_row.dart';
import '../widgets/settings/settings_segmented_control.dart';
import '../widgets/settings/skill_install_sheet.dart';
import '../widgets/shared/app_bottom_sheet.dart';
import 'model_management_page.dart';
import '../theme/app_theme_controller.dart';

class SettingsPage extends ConsumerStatefulWidget {
  const SettingsPage({super.key});

  @override
  ConsumerState<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends ConsumerState<SettingsPage> {
  bool _isLoading = true;
  bool _isTestingModel = false;
  bool _isLoadingSkills = true;
  bool _isInstallingSkill = false;
  ToolExecutionMode _toolExecutionMode = ToolExecutionMode.balanced;
  DuplicateSkillInvocationMode _duplicateSkillInvocationMode =
      DuplicateSkillInvocationMode.reuse;
  List<String> _trustedToolNames = const [];
  List<SkillDescriptor> _skills = const [];
  String? _latestSkillInstallUrl;
  LlmProviderConfig? _currentProvider;
  LlmProviderModel? _currentModel;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final repository = ref.read(appSettingsRepositoryProvider);
    final providers = await repository.getProviders();
    final selection = await repository.getSelectionState();
    final toolExecutionModeName = await repository.getToolExecutionModeName();
    final duplicateSkillInvocationMode =
        await repository.getDuplicateSkillInvocationMode();
    final trustedToolNames = await repository.getTrustedToolNames();
    final latestSkillInstallUrl = await repository.getLatestSkillInstallUrl();

    LlmProviderConfig? currentProvider;
    LlmProviderModel? currentModel;
    for (final provider in providers) {
      if (provider.id == selection.selectedProviderId) {
        currentProvider = provider;
        break;
      }
    }
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
      _latestSkillInstallUrl = latestSkillInstallUrl;
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
    final matched = ToolExecutionMode.values.where(
      (value) => value.name == modeName,
    );
    if (matched.isEmpty) {
      return ToolExecutionMode.balanced;
    }
    return matched.first;
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

  Future<void> _toggleSkill(SkillDescriptor skill, bool enabled) async {
    final repository = ref.read(appSettingsRepositoryProvider);
    if (enabled) {
      await repository.enableSkillId(skill.id);
    } else {
      await repository.disableSkillId(skill.id);
    }
    await _loadSkills();
  }

  Future<void> _saveDuplicateSkillInvocationMode(bool reload) async {
    final mode = reload
        ? DuplicateSkillInvocationMode.reload
        : DuplicateSkillInvocationMode.reuse;
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

  Future<void> _openSkillInstallSheet() async {
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
      body: SkillInstallSheet(initialUrl: _latestSkillInstallUrl),
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

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppThemeSpec>()!;
    final spacing = Theme.of(context).extension<AppSpacing>()!;
    final radius = Theme.of(context).extension<AppRadius>()!;
    final provider = _currentProvider;
    final model = _currentModel;
    final activeTheme = ref.watch(appThemeControllerProvider);
    return Scaffold(
      appBar: _buildTintedHeader(context, '设置'),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: EdgeInsets.all(spacing.lg),
              children: [
                SettingsGroupSection(
                  title: '模型与连接',
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SettingsRow(
                        title: '当前模型',
                        subtitle: model?.displayName ?? '尚未完成模型接入',
                        trailing: const SizedBox.shrink(),
                      ),
                      Divider(color: colors.divider, height: spacing.md * 2),
                      SettingsRow(
                        title: '当前 Provider',
                        subtitle: provider?.name ?? '尚未配置 Provider',
                        trailing: const SizedBox.shrink(),
                      ),
                      Divider(color: colors.divider, height: spacing.md * 2),
                      SettingsRow(
                        title: '连接地址',
                        subtitle: provider?.baseUrl ?? '未配置',
                        trailing: const SizedBox.shrink(),
                      ),
                      SizedBox(height: spacing.md),
                      Row(
                        children: [
                          Expanded(
                            child: FilledButton(
                              onPressed: _openModelManagement,
                              child: const Text('进入模型配置'),
                            ),
                          ),
                          SizedBox(width: spacing.md),
                          Expanded(
                            child: OutlinedButton(
                              onPressed:
                                  _isTestingModel ? null : _testCurrentModel,
                              child: _isTestingModel
                                  ? const SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                          strokeWidth: 2),
                                    )
                                  : const Text('测试当前模型'),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                SizedBox(height: spacing.lg),
                SettingsGroupSection(
                  title: 'Skills',
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '这里可以安装到本地、启用或停用可用 skills。启用后的 skills 会出现在运行时上下文中，并可由 Skill tool 调用。',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: colors.secondaryText,
                              height: 1.4,
                            ),
                      ),
                      SizedBox(height: spacing.md),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: _isInstallingSkill
                                  ? null
                                  : _openSkillInstallSheet,
                              child: _isInstallingSkill
                                  ? const SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                          strokeWidth: 2),
                                    )
                                  : const Text('安装 Skill'),
                            ),
                          ),
                          SizedBox(width: spacing.md),
                          Expanded(
                            child: OutlinedButton(
                              onPressed: _isLoadingSkills ? null : _loadSkills,
                              child: const Text('刷新列表'),
                            ),
                          ),
                        ],
                      ),
                      SizedBox(height: spacing.md),
                      SettingsRow(
                        title: '重复调用时重载 Skill',
                        subtitle: _duplicateSkillInvocationMode ==
                                DuplicateSkillInvocationMode.reload
                            ? '开启时重复调用会重新读取并加载一遍 skill 内容。'
                            : '关闭时重复调用直接复用已加载结果，不再向用户显示失败。',
                        trailing: Switch(
                          value: _duplicateSkillInvocationMode ==
                              DuplicateSkillInvocationMode.reload,
                          onChanged: _saveDuplicateSkillInvocationMode,
                        ),
                      ),
                      SizedBox(height: spacing.md),
                      if (_isLoadingSkills)
                        const Center(child: CircularProgressIndicator())
                      else if (_skills.isEmpty)
                        Text(
                          '当前没有已安装 skills。',
                          style:
                              Theme.of(context).textTheme.bodySmall?.copyWith(
                                    color: colors.secondaryText,
                                  ),
                        )
                      else
                        ..._skills.map(
                          (skill) => Column(
                            children: [
                              SettingsRow(
                                title: skill.name,
                                subtitle: skill.description,
                                trailing: Switch(
                                  value: skill.isEnabled,
                                  onChanged: (value) =>
                                      _toggleSkill(skill, value),
                                ),
                              ),
                              if (skill != _skills.last)
                                Divider(
                                    color: colors.divider,
                                    height: spacing.md * 2),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
                SizedBox(height: spacing.lg),
                SettingsGroupSection(
                  title: '工具自动化',
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SettingsRow(
                        title: '默认执行模式',
                        subtitle:
                            _toolExecutionModeDescription(_toolExecutionMode),
                        trailing: SettingsSegmentedControl<ToolExecutionMode>(
                          value: _toolExecutionMode,
                          options: const {
                            ToolExecutionMode.conservative: '保守',
                            ToolExecutionMode.balanced: '平衡',
                            ToolExecutionMode.aggressive: '激进',
                          },
                          onChanged: _saveToolExecutionMode,
                        ),
                      ),
                      SizedBox(height: spacing.md),
                      Container(
                        width: double.infinity,
                        padding: EdgeInsets.all(spacing.md),
                        decoration: BoxDecoration(
                          color: colors.assistantSurface,
                          borderRadius: BorderRadius.circular(radius.md),
                          border: Border.all(color: colors.divider),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '自动执行白名单',
                              style: Theme.of(context)
                                  .textTheme
                                  .titleSmall
                                  ?.copyWith(
                                    color: colors.primaryText,
                                    fontWeight: FontWeight.w700,
                                  ),
                            ),
                            SizedBox(height: spacing.xxs),
                            Text(
                              '将可信指令直接放行，降低重复确认。',
                              style: Theme.of(context)
                                  .textTheme
                                  .bodySmall
                                  ?.copyWith(
                                    color: colors.secondaryText,
                                  ),
                            ),
                            SizedBox(height: spacing.sm),
                            if (_trustedToolNames.isEmpty)
                              Text(
                                '当前没有已信任工具。',
                                style: Theme.of(context)
                                    .textTheme
                                    .bodySmall
                                    ?.copyWith(
                                      color: colors.secondaryText,
                                    ),
                              )
                            else
                              ..._trustedToolNames.map(
                                (toolName) => SettingsRow(
                                  padding: EdgeInsets.symmetric(
                                      vertical: spacing.xxs),
                                  title: toolName,
                                  subtitle: '已加入免确认白名单',
                                  trailing: IconButton(
                                    tooltip: '移除 $toolName',
                                    icon:
                                        const Icon(Icons.remove_circle_outline),
                                    color: colors.secondaryText,
                                    onPressed: () {
                                      _removeTrustedTool(toolName);
                                    },
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                SizedBox(height: spacing.lg),
                SettingsGroupSection(
                  title: '界面偏好',
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SettingsRow(
                        title: '当前主题',
                        subtitle: activeTheme.displayName,
                        trailing: Container(
                          padding: EdgeInsets.symmetric(
                            horizontal: spacing.sm,
                            vertical: spacing.xs,
                          ),
                          decoration: BoxDecoration(
                            color: colors.workflowRunning,
                            borderRadius: BorderRadius.circular(radius.pill),
                          ),
                          child: const Text(
                            '当前',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                      SizedBox(height: spacing.md),
                      Wrap(
                        spacing: spacing.sm,
                        runSpacing: spacing.sm,
                        children: [
                          for (final theme in AppThemeSpec.builtInThemes())
                            _ThemeCard(
                              title: theme.displayName,
                              selected: theme.id == activeTheme.id,
                              onTap: () => ref
                                  .read(appThemeControllerProvider.notifier)
                                  .setTheme(theme.id),
                            ),
                        ],
                      ),
                    ],
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
    backgroundColor: colors.workflowRunning.withValues(alpha: 0.12),
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

class _ThemeCard extends StatelessWidget {
  const _ThemeCard({
    required this.title,
    required this.selected,
    required this.onTap,
  });

  final String title;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppThemeSpec>()!;
    final spacing = Theme.of(context).extension<AppSpacing>()!;
    final radius = Theme.of(context).extension<AppRadius>()!;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(radius.lg),
      child: Container(
        width: 132,
        padding: EdgeInsets.all(spacing.md),
        decoration: BoxDecoration(
          color: selected ? colors.assistantSurface : colors.chatBackground,
          borderRadius: BorderRadius.circular(radius.lg),
          border: Border.all(
            color: selected ? colors.workflowRunning : colors.divider,
            width: selected ? 1.2 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: TextStyle(
                color: colors.primaryText,
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
            SizedBox(height: spacing.xxs),
            Text(
              selected ? '已启用' : '点击切换',
              style: TextStyle(
                color: colors.secondaryText,
                fontSize: 11,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
