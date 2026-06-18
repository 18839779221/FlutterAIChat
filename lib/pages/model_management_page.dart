import 'package:flutter/material.dart';

import '../models/llm/llm_provider_config.dart';
import '../models/llm/llm_provider_model.dart';
import '../models/llm/llm_selection_state.dart';
import '../repositories/app_settings_repository.dart';
import '../services/llm_model_discovery_service.dart';
import '../services/llm_model_test_service.dart';
import '../widgets/settings/settings_group_section.dart';
import '../widgets/settings/settings_row.dart';
import '../widgets/settings/settings_value_badge.dart';
import '../theme/app_radius.dart';
import '../theme/app_spacing.dart';
import '../theme/app_theme_spec.dart';
import 'provider_form_page.dart';

class ModelManagementPage extends StatefulWidget {
  final AppSettingsRepository repository;
  final LlmModelTestService? testService;
  final LlmModelDiscoveryService? discoveryService;

  const ModelManagementPage({
    super.key,
    required this.repository,
    this.testService,
    this.discoveryService,
  });

  @override
  State<ModelManagementPage> createState() => _ModelManagementPageState();
}

class _ModelManagementPageState extends State<ModelManagementPage> {
  late final LlmModelTestService _testService;
  late final LlmModelDiscoveryService _discoveryService;

  bool _isLoading = true;
  bool _isTestingCurrentModel = false;
  List<LlmProviderConfig> _providers = const [];
  LlmSelectionState _selection = const LlmSelectionState();

  @override
  void initState() {
    super.initState();
    _testService = widget.testService ?? LlmModelTestService();
    _discoveryService = widget.discoveryService ?? LlmModelDiscoveryService();
    _load();
  }

  Future<void> _load() async {
    final providers = await widget.repository.getProviders();
    final selection = await widget.repository.getSelectionState();
    if (!mounted) {
      return;
    }
    setState(() {
      _providers = providers;
      _selection = selection;
      _isLoading = false;
    });
  }

  Future<void> _openProviderForm([LlmProviderConfig? provider]) async {
    final result = await Navigator.of(context).push<LlmProviderConfig>(
      MaterialPageRoute(
        builder: (_) => ProviderFormPage(
          initialProvider: provider,
          repository: widget.repository,
          discoveryService: _discoveryService,
          testService: _testService,
        ),
      ),
    );
    if (result == null) {
      return;
    }
    await _load();
  }

  Future<void> _deleteProvider(LlmProviderConfig provider) async {
    final shouldDelete = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('删除 Provider'),
            content: Text('确定删除 ${provider.name} 吗？'),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('删除'),
              ),
            ],
          ),
        ) ??
        false;
    if (!shouldDelete) {
      return;
    }
    await widget.repository.deleteProvider(provider.id);
    await _load();
  }

  LlmProviderConfig? get _currentProvider {
    for (final provider in _providers) {
      if (provider.id == _selection.selectedProviderId) {
        return provider;
      }
    }
    return _providers.isEmpty ? null : _providers.first;
  }

  LlmProviderModel? get _currentModel {
    final provider = _currentProvider;
    if (provider == null) {
      return null;
    }
    for (final model in provider.models) {
      if (model.id == _selection.selectedModelId) {
        return model;
      }
    }
    return provider.models.isEmpty ? null : provider.models.first;
  }

  Future<void> _testCurrentModel() async {
    final provider = _currentProvider;
    final model = _currentModel;
    if (provider == null || model == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请先完成 Provider 与模型配置')),
      );
      return;
    }

    setState(() {
      _isTestingCurrentModel = true;
    });

    try {
      final result =
          await _testService.testModel(provider: provider, model: model);
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
          _isTestingCurrentModel = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final spacing = Theme.of(context).extension<AppSpacing>()!;
    final currentProvider = _currentProvider;
    final currentModel = _currentModel;

    return Scaffold(
      appBar: _buildTintedHeader(context, '模型配置'),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: EdgeInsets.all(spacing.lg),
              children: [
                SettingsGroupSection(
                  title: '当前接入',
                  summary: '一级设置页负责总览，这里只保留当前连接状态与管理动作。',
                  child: Column(
                    children: [
                      SettingsRow(
                        title: '当前 Provider',
                        subtitle: '主对话默认使用的连接来源',
                        trailing: SettingsValueBadge(
                          label: currentProvider?.name ?? '未配置',
                          tone: currentProvider == null
                              ? SettingsValueBadgeTone.warning
                              : SettingsValueBadgeTone.active,
                        ),
                      ),
                      SizedBox(height: spacing.xs),
                      SettingsRow(
                        title: '当前 Model',
                        subtitle: '本次会话的默认主模型',
                        trailing: SettingsValueBadge(
                          label: currentModel?.displayName ?? '未配置',
                          tone: currentModel == null
                              ? SettingsValueBadgeTone.warning
                              : SettingsValueBadgeTone.neutral,
                        ),
                      ),
                      SizedBox(height: spacing.sm),
                      Row(
                        children: [
                          Expanded(
                            child: FilledButton(
                              onPressed: _openProviderForm,
                              child: const Text('新增 Provider'),
                            ),
                          ),
                          SizedBox(width: spacing.sm),
                          Expanded(
                            child: OutlinedButton(
                              onPressed: _isTestingCurrentModel
                                  ? null
                                  : _testCurrentModel,
                              child: _isTestingCurrentModel
                                  ? const SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
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
                if (_providers.isEmpty)
                  _EmptyProviderState(onCreateProvider: _openProviderForm),
                if (_providers.isNotEmpty) ...[
                  SettingsGroupSection(
                    title: 'Provider 列表',
                    summary: '按 Provider 管理连接与模型。先维护连接，再在对象内探测或补充模型。',
                    child: Column(
                      children: [
                        for (var index = 0; index < _providers.length; index++)
                          Padding(
                            padding: EdgeInsets.only(
                              bottom:
                                  index == _providers.length - 1 ? 0 : spacing.md,
                            ),
                            child: _ProviderListTile(
                              provider: _providers[index],
                              isDefault: _providers[index].id ==
                                  _selection.selectedProviderId,
                              onEdit: () => _openProviderForm(_providers[index]),
                              onDelete: () =>
                                  _deleteProvider(_providers[index]),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
    );
  }
}

class _EmptyProviderState extends StatelessWidget {
  const _EmptyProviderState({required this.onCreateProvider});

  final VoidCallback onCreateProvider;

  @override
  Widget build(BuildContext context) {
    final spacing = Theme.of(context).extension<AppSpacing>()!;
    final radius = Theme.of(context).extension<AppRadius>()!;
    final colors = Theme.of(context).extension<AppThemeSpec>()!;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.settingsPanelBackground.withValues(alpha: 0.82),
        borderRadius: BorderRadius.circular(radius.lg),
        boxShadow: [
          BoxShadow(
            color: colors.core.elevation.shadowColor.withValues(alpha: 0.05),
            blurRadius: 18,
            spreadRadius: -10,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Padding(
        padding: EdgeInsets.all(spacing.xl),
        child: Column(
          children: [
            Icon(
              Icons.settings_ethernet_rounded,
              size: 28,
              color: colors.secondaryText,
            ),
            SizedBox(height: spacing.md),
            Text(
              '暂无 Provider，请先新增',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
            ),
            SizedBox(height: spacing.xs),
            Text(
              '统一在这里管理 API Key、Base URL 和模型列表。建议先保存连接信息，再执行模型探测。',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: colors.secondaryText,
                    height: 1.5,
                  ),
            ),
            SizedBox(height: spacing.lg),
            FilledButton(
              onPressed: onCreateProvider,
              child: const Text('新增 Provider'),
            ),
          ],
        ),
      ),
    );
  }
}

class _ProviderListTile extends StatelessWidget {
  const _ProviderListTile({
    required this.provider,
    required this.isDefault,
    required this.onEdit,
    required this.onDelete,
  });

  final LlmProviderConfig provider;
  final bool isDefault;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final spacing = Theme.of(context).extension<AppSpacing>()!;
    final radius = Theme.of(context).extension<AppRadius>()!;
    final colors = Theme.of(context).extension<AppThemeSpec>()!;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.chatBackground.withValues(alpha: 0.96),
        borderRadius: BorderRadius.circular(radius.lg),
        boxShadow: [
          BoxShadow(
            color: colors.core.elevation.shadowColor.withValues(alpha: 0.04),
            blurRadius: 14,
            spreadRadius: -8,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Padding(
        padding: EdgeInsets.all(spacing.md + spacing.xxs),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              provider.name,
                              style: Theme.of(context)
                                  .textTheme
                                  .titleMedium
                                  ?.copyWith(fontWeight: FontWeight.w700),
                            ),
                          ),
                          if (isDefault) ...[
                            SizedBox(width: spacing.xs),
                            Container(
                              padding: EdgeInsets.symmetric(
                                horizontal: spacing.xs,
                                vertical: spacing.xxs,
                              ),
                              decoration: BoxDecoration(
                                color: colors.workflowRunning
                                    .withValues(alpha: 0.14),
                                borderRadius:
                                    BorderRadius.circular(radius.pill),
                              ),
                              child: Text(
                                '默认',
                                style: Theme.of(context)
                                    .textTheme
                                    .labelSmall
                                    ?.copyWith(
                                      color: colors.workflowRunning,
                                      fontWeight: FontWeight.w700,
                                    ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      SizedBox(height: spacing.xs),
                      Text(
                        provider.baseUrl,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: colors.secondaryText,
                            ),
                      ),
                    ],
                  ),
                ),
                SizedBox(width: spacing.sm),
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: isDefault
                        ? colors.workflowRunning.withValues(alpha: 0.12)
                        : colors.assistantSurface.withValues(alpha: 0.9),
                    borderRadius: BorderRadius.circular(radius.lg),
                  ),
                  child: Padding(
                    padding: EdgeInsets.symmetric(
                      horizontal: spacing.sm,
                      vertical: spacing.sm,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          '${provider.models.length}',
                          style: Theme.of(context)
                              .textTheme
                              .titleLarge
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                        Text(
                          '个模型',
                          style:
                              Theme.of(context).textTheme.bodySmall?.copyWith(
                                    color: colors.secondaryText,
                                  ),
                        ),
                        Text(
                          '${provider.models.length} 个模型',
                          style: Theme.of(context)
                              .textTheme
                              .bodySmall
                              ?.copyWith(
                                color:
                                    colors.secondaryText.withValues(alpha: 0.0),
                                fontSize: 1,
                                height: 0.1,
                              ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            SizedBox(height: spacing.md),
            Wrap(
              spacing: spacing.sm,
              runSpacing: spacing.sm,
              children: [
                _MetaTag(
                  icon: Icons.key_outlined,
                  label: provider.apiKey.trim().isEmpty
                      ? '未填写 API Key'
                      : '已填写 API Key',
                ),
              ],
            ),
            SizedBox(height: spacing.md),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: onEdit,
                    child: const Text('编辑'),
                  ),
                ),
                SizedBox(width: spacing.sm),
                Expanded(
                  child: TextButton(
                    onPressed: onDelete,
                    child: const Text('删除'),
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

class _MetaTag extends StatelessWidget {
  const _MetaTag({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final spacing = Theme.of(context).extension<AppSpacing>()!;
    final radius = Theme.of(context).extension<AppRadius>()!;
    final colors = Theme.of(context).extension<AppThemeSpec>()!;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.assistantSurface.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(radius.pill),
      ),
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: spacing.sm,
          vertical: spacing.xxs + 2,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: colors.secondaryText),
            SizedBox(width: spacing.xxs + 2),
            Text(
              label,
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: colors.primaryText,
                    fontWeight: FontWeight.w600,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}
