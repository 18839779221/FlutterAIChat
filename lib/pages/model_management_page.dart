import 'package:flutter/material.dart';

import '../models/llm/llm_provider_config.dart';
import '../models/llm/llm_provider_model.dart';
import '../models/llm/llm_selection_state.dart';
import '../repositories/app_settings_repository.dart';
import '../services/llm_model_test_service.dart';
import '../theme/app_spacing.dart';
import 'provider_form_page.dart';

class ModelManagementPage extends StatefulWidget {
  final AppSettingsRepository repository;
  final LlmModelTestService? testService;

  const ModelManagementPage({
    super.key,
    required this.repository,
    this.testService,
  });

  @override
  State<ModelManagementPage> createState() => _ModelManagementPageState();
}

class _ModelManagementPageState extends State<ModelManagementPage> {
  late final LlmModelTestService _testService;

  bool _isLoading = true;
  List<LlmProviderConfig> _providers = const [];
  LlmSelectionState _selection = const LlmSelectionState();

  @override
  void initState() {
    super.initState();
    _testService = widget.testService ?? LlmModelTestService();
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
        builder: (_) => ProviderFormPage(initialProvider: provider),
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
            title: const Text('删除提供方'),
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

  Future<void> _selectModel(
    LlmProviderConfig provider,
    LlmProviderModel model,
  ) async {
    await widget.repository.selectProviderAndModel(
      providerId: provider.id,
      modelId: model.id,
    );
    await _load();
  }

  Future<void> _setDefaultModel(
    LlmProviderConfig provider,
    LlmProviderModel model,
  ) async {
    await widget.repository.setDefaultProviderAndModel(
      providerId: provider.id,
      modelId: model.id,
    );
    await _load();
  }

  Future<void> _testModel(
    LlmProviderConfig provider,
    LlmProviderModel model,
  ) async {
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
    }
  }

  bool _isCurrent(LlmProviderConfig provider, LlmProviderModel model) {
    return _selection.selectedProviderId == provider.id &&
        _selection.selectedModelId == model.id;
  }

  bool _isDefault(LlmProviderConfig provider, LlmProviderModel model) {
    return _selection.defaultProviderId == provider.id &&
        _selection.defaultModelId == model.id;
  }

  @override
  Widget build(BuildContext context) {
    final spacing = Theme.of(context).extension<AppSpacing>()!;

    return Scaffold(
      appBar: AppBar(
        title: const Text('模型管理'),
      ),
      floatingActionButton: FloatingActionButton(
        tooltip: '新增提供方',
        onPressed: () => _openProviderForm(),
        child: const Icon(Icons.add),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _providers.isEmpty
              ? Center(
                  child: Text(
                    '暂无提供方，请先新增',
                    style: Theme.of(context).textTheme.bodyLarge,
                  ),
                )
              : ListView.separated(
                  padding: EdgeInsets.all(spacing.lg),
                  itemCount: _providers.length,
                  separatorBuilder: (_, __) => SizedBox(height: spacing.md),
                  itemBuilder: (context, index) {
                    final provider = _providers[index];
                    return Card(
                      child: Padding(
                        padding: EdgeInsets.all(spacing.md),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        provider.name,
                                        style: Theme.of(context).textTheme.titleMedium,
                                      ),
                                      SizedBox(height: spacing.xxs),
                                      Text(provider.baseUrl),
                                    ],
                                  ),
                                ),
                                IconButton(
                                  tooltip: '编辑提供方',
                                  onPressed: () => _openProviderForm(provider),
                                  icon: const Icon(Icons.edit_outlined),
                                ),
                                IconButton(
                                  tooltip: '删除提供方',
                                  onPressed: () => _deleteProvider(provider),
                                  icon: const Icon(Icons.delete_outline),
                                ),
                              ],
                            ),
                            SizedBox(height: spacing.md),
                            ...provider.models.map((model) {
                              final isCurrent = _isCurrent(provider, model);
                              final isDefault = _isDefault(provider, model);
                              return Padding(
                                padding: EdgeInsets.only(bottom: spacing.md),
                                child: Container(
                                  width: double.infinity,
                                  padding: EdgeInsets.all(spacing.md),
                                  decoration: BoxDecoration(
                                    border: Border.all(color: Theme.of(context).dividerColor),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Text(model.displayName),
                                                SizedBox(height: spacing.xxs),
                                                Text(model.id),
                                              ],
                                            ),
                                          ),
                                          if (isCurrent)
                                            const Chip(label: Text('当前使用')),
                                          if (isDefault)
                                            const Chip(label: Text('默认')),
                                        ],
                                      ),
                                      SizedBox(height: spacing.sm),
                                      Wrap(
                                        spacing: spacing.sm,
                                        runSpacing: spacing.sm,
                                        children: [
                                          FilledButton(
                                            onPressed: isCurrent
                                                ? null
                                                : () => _selectModel(provider, model),
                                            child: const Text('使用此模型'),
                                          ),
                                          OutlinedButton(
                                            onPressed: isDefault
                                                ? null
                                                : () => _setDefaultModel(provider, model),
                                            child: const Text('设为默认'),
                                          ),
                                          OutlinedButton(
                                            onPressed: () => _testModel(provider, model),
                                            child: const Text('测试模型'),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            }),
                          ],
                        ),
                      ),
                    );
                  },
                ),
    );
  }
}
