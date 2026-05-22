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
import 'model_management_page.dart';
import '../theme/app_theme_controller.dart';

class SettingsPage extends ConsumerStatefulWidget {
  const SettingsPage({super.key});

  @override
  ConsumerState<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends ConsumerState<SettingsPage> {
  bool _autoShowKeyboard = true;
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
  List<LlmProviderConfig> _providers = const [];
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
      _providers = providers;
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
    final result = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor:
          Theme.of(context).extension<AppThemeSpec>()!.chatBackground,
      builder: (_) => SkillInstallSheet(initialUrl: _latestSkillInstallUrl),
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

  Future<void> _selectProvider(LlmProviderConfig provider) async {
    final nextModel = provider.models.isEmpty ? null : provider.models.first;
    if (nextModel == null) {
      return;
    }
    await ref.read(appSettingsRepositoryProvider).selectProviderAndModel(
          providerId: provider.id,
          modelId: nextModel.id,
        );
    await _loadSettings();
  }

  Future<void> _selectModel(LlmProviderModel model) async {
    final provider = _currentProvider;
    if (provider == null) {
      return;
    }
    await ref.read(appSettingsRepositoryProvider).selectProviderAndModel(
          providerId: provider.id,
          modelId: model.id,
        );
    await _loadSettings();
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

  Future<void> _openProviderPicker() async {
    if (_providers.isEmpty) {
      return;
    }
    final selected = await showModalBottomSheet<LlmProviderConfig>(
      context: context,
      isScrollControlled: true,
      builder: (context) => _SelectionSheet<LlmProviderConfig>(
        title: '选择提供方',
        items: _providers,
        isSelected: (item) => item.id == _currentProvider?.id,
        labelBuilder: (item) => item.name,
      ),
    );
    if (selected == null) {
      return;
    }
    await _selectProvider(selected);
  }

  Future<void> _openModelPicker() async {
    final provider = _currentProvider;
    if (provider == null || provider.models.isEmpty) {
      return;
    }
    final selected = await showModalBottomSheet<LlmProviderModel>(
      context: context,
      isScrollControlled: true,
      builder: (context) => _SelectionSheet<LlmProviderModel>(
        title: '选择模型',
        items: provider.models,
        isSelected: (item) => item.id == _currentModel?.id,
        labelBuilder: (item) => item.displayName,
      ),
    );
    if (selected == null) {
      return;
    }
    await _selectModel(selected);
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppThemeSpec>()!;
    final spacing = Theme.of(context).extension<AppSpacing>()!;
    final radius = Theme.of(context).extension<AppRadius>()!;
    final provider = _currentProvider;
    final model = _currentModel;
    final activeTheme = ref.watch(appThemeControllerProvider);
    final currentGroup = ref.watch(currentGroupProvider);
    final isProviderLocked = currentGroup?.lockedProviderStyle != null;
    return Scaffold(
      appBar: AppBar(
        title: const Text('设置'),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: EdgeInsets.all(spacing.lg),
              children: [
                Container(
                  padding: EdgeInsets.all(spacing.lg),
                  decoration: BoxDecoration(
                    color: colors.assistantSurface,
                    borderRadius: BorderRadius.circular(radius.lg),
                    border: Border.all(color: colors.divider),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Precision Settings',
                        style:
                            Theme.of(context).textTheme.headlineSmall?.copyWith(
                                  fontWeight: FontWeight.w700,
                                  color: colors.primaryText,
                                ),
                      ),
                      SizedBox(height: spacing.xs),
                      Text(
                        '高对比、低噪声的控制台配置页。模型接入、工具自动化与界面偏好都在这里统一收口。',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: colors.secondaryText,
                              height: 1.45,
                            ),
                      ),
                    ],
                  ),
                ),
                SizedBox(height: spacing.lg),
                SettingsGroupSection(
                  title: '模型接入',
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '当前运行时配置来自所选提供方与模型，管理入口会统一维护 provider 与 model 目录。',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: colors.secondaryText,
                              height: 1.4,
                            ),
                      ),
                      SizedBox(height: spacing.md),
                      SettingsRow(
                        title: '当前提供方',
                        subtitle: isProviderLocked
                            ? '当前会话已锁定 provider，新建会话方可切换'
                            : provider?.name ?? '暂无提供方',
                        trailing: Tooltip(
                          message:
                              isProviderLocked ? '当前会话已锁定 provider' : '选择提供方',
                          child: OutlinedButton.icon(
                            key: const Key('provider-switcher'),
                            onPressed: isProviderLocked || _providers.isEmpty
                                ? null
                                : _openProviderPicker,
                            icon: const Icon(Icons.unfold_more),
                            label: const Text('选择'),
                          ),
                        ),
                      ),
                      Divider(color: colors.divider, height: spacing.md * 2),
                      SettingsRow(
                        title: '当前模型',
                        subtitle: model?.displayName ?? '暂无模型',
                        trailing: Tooltip(
                          message: '选择模型',
                          child: OutlinedButton.icon(
                            onPressed:
                                provider == null || provider.models.isEmpty
                                    ? null
                                    : _openModelPicker,
                            icon: const Icon(Icons.unfold_more),
                            label: const Text('选择'),
                          ),
                        ),
                      ),
                      Divider(color: colors.divider, height: spacing.md * 2),
                      SettingsRow(
                        title: 'Base URL',
                        subtitle: provider?.baseUrl ?? '未配置',
                        trailing: const SizedBox.shrink(),
                      ),
                      SizedBox(height: spacing.md),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: _openModelManagement,
                              child: const Text('管理模型'),
                            ),
                          ),
                          SizedBox(width: spacing.md),
                          Expanded(
                            child: FilledButton(
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
                      Text(
                        '主题作为一等公民管理。当前提供 Claude 与 Olive Paper 两套主题，后续可以继续扩展。',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: colors.secondaryText,
                              height: 1.4,
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
                      Divider(color: colors.divider, height: spacing.md * 2),
                      SettingsRow(
                        title: '自动显示键盘',
                        subtitle: '打开聊天页时自动聚焦输入区域。',
                        trailing: Switch(
                          value: _autoShowKeyboard,
                          onChanged: (bool value) {
                            setState(() {
                              _autoShowKeyboard = value;
                            });
                          },
                        ),
                      ),
                      Divider(color: colors.divider, height: spacing.md * 2),
                      SettingsRow(
                        title: '清除缓存',
                        subtitle: '清除本地缓存与临时状态。',
                        trailing: OutlinedButton(
                          onPressed: () {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('清除缓存功能待补充')),
                            );
                          },
                          child: const Text('执行'),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }
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

class _SelectionSheet<T> extends StatelessWidget {
  final String title;
  final List<T> items;
  final bool Function(T item) isSelected;
  final String Function(T item) labelBuilder;

  const _SelectionSheet({
    required this.title,
    required this.items,
    required this.isSelected,
    required this.labelBuilder,
  });

  @override
  Widget build(BuildContext context) {
    final spacing = Theme.of(context).extension<AppSpacing>()!;
    final colors = Theme.of(context).extension<AppThemeSpec>()!;
    final maxHeight = MediaQuery.of(context).size.height * 0.7;

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.all(spacing.lg),
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: maxHeight),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: colors.primaryText,
                    ),
              ),
              SizedBox(height: spacing.md),
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: items.length,
                  itemBuilder: (context, index) {
                    final item = items[index];
                    final selected = isSelected(item);
                    return ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: selected
                          ? Container(
                              width: 8,
                              height: 8,
                              decoration: BoxDecoration(
                                color: colors.workflowRunning,
                                shape: BoxShape.circle,
                              ),
                            )
                          : const SizedBox(width: 8, height: 8),
                      title: Text(labelBuilder(item)),
                      onTap: () => Navigator.of(context).pop(item),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
