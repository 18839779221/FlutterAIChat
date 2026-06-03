import 'package:flutter/material.dart';

import '../models/llm/llm_provider_config.dart';
import '../models/llm/llm_provider_model.dart';
import '../models/llm/llm_selection_state.dart';
import '../repositories/app_settings_repository.dart';
import '../services/llm_model_discovery_service.dart';
import '../services/llm_model_test_service.dart';
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
    _discoveryService =
        widget.discoveryService ?? LlmModelDiscoveryService();
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
        ),
      ),
    );
    if (result == null) {
      return;
    }
    await widget.repository.saveProvider(result);
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

  LlmProviderConfig? get _defaultProvider {
    for (final provider in _providers) {
      if (provider.id == _selection.defaultProviderId) {
        return provider;
      }
    }
    return _providers.isEmpty ? null : _providers.first;
  }

  LlmProviderModel? get _defaultModel {
    final provider = _defaultProvider;
    if (provider == null) {
      return null;
    }
    for (final model in provider.models) {
      if (model.id == _selection.defaultModelId) {
        return model;
      }
    }
    return provider.models.isEmpty ? null : provider.models.first;
  }

  Future<void> _testCurrentModel() async {
    final provider = _defaultProvider;
    final model = _defaultModel;
    if (provider == null || model == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请先完成 Provider 与默认模型配置')),
      );
      return;
    }

    setState(() {
      _isTestingCurrentModel = true;
    });

    try {
      final result = await _testService.testModel(provider: provider, model: model);
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
    final colors = Theme.of(context).extension<AppThemeSpec>()!;
    final defaultProvider = _defaultProvider;
    final defaultModel = _defaultModel;

    return Scaffold(
      appBar: AppBar(title: const Text('模型配置')),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: EdgeInsets.all(spacing.lg),
              children: [
                _ManagementOverviewCard(
                  defaultProvider: defaultProvider,
                  defaultModel: defaultModel,
                  providerCount: _providers.length,
                  onCreateProvider: _openProviderForm,
                  isTestingCurrentModel: _isTestingCurrentModel,
                  onTestCurrentModel: _testCurrentModel,
                ),
                SizedBox(height: spacing.lg),
                if (_providers.isEmpty)
                  _EmptyProviderState(onCreateProvider: _openProviderForm),
                if (_providers.isNotEmpty) ...[
                  Padding(
                    padding: EdgeInsets.only(bottom: spacing.md),
                    child: Text(
                      '按 Provider 管理连接与模型。优先在每个 Provider 内执行模型探测，再按需手动补充。',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: colors.secondaryText,
                            height: 1.5,
                          ),
                    ),
                  ),
                  ..._providers.map(
                    (provider) => Padding(
                      padding: EdgeInsets.only(bottom: spacing.md),
                      child: _ProviderListTile(
                        provider: provider,
                        isDefault: provider.id == _selection.defaultProviderId,
                        onEdit: () => _openProviderForm(provider),
                        onDelete: () => _deleteProvider(provider),
                      ),
                    ),
                  ),
                ],
              ],
            ),
    );
  }
}

class _ManagementOverviewCard extends StatelessWidget {
  const _ManagementOverviewCard({
    required this.defaultProvider,
    required this.defaultModel,
    required this.providerCount,
    required this.onCreateProvider,
    required this.isTestingCurrentModel,
    required this.onTestCurrentModel,
  });

  final LlmProviderConfig? defaultProvider;
  final LlmProviderModel? defaultModel;
  final int providerCount;
  final VoidCallback onCreateProvider;
  final bool isTestingCurrentModel;
  final VoidCallback onTestCurrentModel;

  @override
  Widget build(BuildContext context) {
    final spacing = Theme.of(context).extension<AppSpacing>()!;
    final radius = Theme.of(context).extension<AppRadius>()!;
    final colors = Theme.of(context).extension<AppThemeSpec>()!;

    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius.lg),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            colors.assistantSurface.withValues(alpha: 0.96),
            colors.settingsPanelBackground.withValues(alpha: 0.98),
          ],
        ),
        border: Border.all(color: colors.divider),
        boxShadow: [
          BoxShadow(
            color: colors.primaryText.withValues(alpha: 0.05),
            blurRadius: 24,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Padding(
        padding: EdgeInsets.all(spacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: EdgeInsets.symmetric(
                horizontal: spacing.sm,
                vertical: spacing.xxs + 2,
              ),
              decoration: BoxDecoration(
                color: colors.workflowRunning.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(radius.pill),
              ),
              child: Text(
                providerCount == 0 ? '准备接入' : '默认对话模型',
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: colors.workflowRunning,
                      fontWeight: FontWeight.w700,
                    ),
              ),
            ),
            SizedBox(height: spacing.md),
            Text(
              '当前默认模型',
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: colors.secondaryText,
                  ),
            ),
            SizedBox(height: spacing.xs),
            Text(
              defaultModel?.displayName ?? '尚未完成模型接入',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    height: 1.15,
                  ),
            ),
            SizedBox(height: spacing.xs),
            Text(
              defaultProvider?.name ?? '请先新增 Provider 并选择默认模型',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: colors.secondaryText,
                    height: 1.45,
                  ),
            ),
            SizedBox(height: spacing.md),
            Wrap(
              spacing: spacing.sm,
              runSpacing: spacing.sm,
              children: [
                _SummaryPill(
                  icon: Icons.hub_outlined,
                  label: '$providerCount 个 Provider',
                ),
                _SummaryPill(
                  icon: Icons.travel_explore_outlined,
                  label: '优先使用模型探测',
                ),
              ],
            ),
            SizedBox(height: spacing.lg),
            Row(
              children: [
                Expanded(
                  child: FilledButton(
                    onPressed: onCreateProvider,
                    child: const Text('新增 Provider'),
                  ),
                ),
                SizedBox(width: spacing.sm),
                Expanded(
                  child: OutlinedButton(
                    onPressed:
                        isTestingCurrentModel ? null : onTestCurrentModel,
                    child: isTestingCurrentModel
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
    );
  }
}

class _SummaryPill extends StatelessWidget {
  const _SummaryPill({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final spacing = Theme.of(context).extension<AppSpacing>()!;
    final radius = Theme.of(context).extension<AppRadius>()!;
    final colors = Theme.of(context).extension<AppThemeSpec>()!;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.chatBackground.withValues(alpha: 0.9),
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
        color: colors.settingsPanelBackground,
        borderRadius: BorderRadius.circular(radius.lg),
        border: Border.all(color: colors.divider),
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
        border: Border.all(
          color: isDefault
              ? colors.workflowRunning.withValues(alpha: 0.28)
              : colors.divider,
        ),
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
                                borderRadius: BorderRadius.circular(radius.pill),
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
                    color: colors.assistantSurface.withValues(alpha: 0.9),
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
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: colors.secondaryText,
                              ),
                        ),
                        Text(
                          '${provider.models.length} 个模型',
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: colors.secondaryText.withValues(alpha: 0.0),
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
                  label: provider.apiKey.trim().isEmpty ? '未填写 API Key' : '已填写 API Key',
                ),
                _MetaTag(
                  icon: Icons.layers_outlined,
                  label: provider.models.isEmpty ? '待探测模型' : '支持模型管理',
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
