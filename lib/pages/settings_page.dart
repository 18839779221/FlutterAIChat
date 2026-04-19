import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/llm/llm_provider_config.dart';
import '../models/llm/llm_provider_model.dart';
import '../models/tool/tool_policy.dart';
import '../providers/chat_providers.dart';
import '../services/llm_model_test_service.dart';
import '../theme/app_colors.dart';
import '../theme/app_radius.dart';
import '../theme/app_spacing.dart';
import '../widgets/settings/settings_group_section.dart';
import '../widgets/settings/settings_row.dart';
import '../widgets/settings/settings_segmented_control.dart';
import 'model_management_page.dart';

class SettingsPage extends ConsumerStatefulWidget {
  const SettingsPage({super.key});

  @override
  ConsumerState<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends ConsumerState<SettingsPage> {
  bool _isDarkMode = false;
  bool _autoShowKeyboard = true;
  bool _isLoading = true;
  bool _isTestingModel = false;
  ToolExecutionMode _toolExecutionMode = ToolExecutionMode.balanced;
  List<String> _trustedToolNames = const [];
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
    final trustedToolNames = await repository.getTrustedToolNames();

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

    setState(() {
      _providers = providers;
      _currentProvider = currentProvider;
      _currentModel = currentModel;
      _toolExecutionMode = _parseToolExecutionMode(toolExecutionModeName);
      _trustedToolNames = trustedToolNames.toList()..sort();
      _isLoading = false;
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
    await ref.read(appSettingsRepositoryProvider).removeTrustedToolName(toolName);
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
    final colors = Theme.of(context).extension<AppColors>()!;
    final spacing = Theme.of(context).extension<AppSpacing>()!;
    final radius = Theme.of(context).extension<AppRadius>()!;
    final provider = _currentProvider;
    final model = _currentModel;
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
                        style: Theme.of(context).textTheme.headlineSmall?.copyWith(
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
                        subtitle: provider?.name ?? '暂无提供方',
                        trailing: Tooltip(
                          message: '选择提供方',
                          child: OutlinedButton.icon(
                            onPressed: _providers.isEmpty ? null : _openProviderPicker,
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
                            onPressed: provider == null || provider.models.isEmpty
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
                              onPressed: _isTestingModel ? null : _testCurrentModel,
                              child: _isTestingModel
                                  ? const SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(strokeWidth: 2),
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
                  title: '工具自动化',
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SettingsRow(
                        title: '默认执行模式',
                        subtitle: _toolExecutionModeDescription(_toolExecutionMode),
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
                              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                                    color: colors.primaryText,
                                    fontWeight: FontWeight.w700,
                                  ),
                            ),
                            SizedBox(height: spacing.xxs),
                            Text(
                              '将可信指令直接放行，降低重复确认。',
                              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                    color: colors.secondaryText,
                                  ),
                            ),
                            SizedBox(height: spacing.sm),
                            if (_trustedToolNames.isEmpty)
                              Text(
                                '当前没有已信任工具。',
                                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                      color: colors.secondaryText,
                                    ),
                              )
                            else
                              ..._trustedToolNames.map(
                                (toolName) => SettingsRow(
                                  padding: EdgeInsets.symmetric(vertical: spacing.xxs),
                                  title: toolName,
                                  subtitle: '已加入免确认白名单',
                                  trailing: IconButton(
                                    tooltip: '移除 $toolName',
                                    icon: const Icon(Icons.remove_circle_outline),
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
                    children: [
                      SettingsRow(
                        title: '深色模式',
                        subtitle: '后续将接入完整浅色 / 深色主题切换。',
                        trailing: Switch(
                          value: _isDarkMode,
                          onChanged: (bool value) {
                            setState(() {
                              _isDarkMode = value;
                            });
                          },
                        ),
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
    final colors = Theme.of(context).extension<AppColors>()!;
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
