import 'package:flutter/material.dart';

import '../models/llm/llm_provider_config.dart';
import '../models/llm/llm_provider_model.dart';
import '../repositories/app_settings_repository.dart';
import '../services/llm_model_discovery_service.dart';
import '../theme/app_radius.dart';
import '../theme/app_spacing.dart';
import '../theme/app_theme_spec.dart';

class ProviderFormPage extends StatefulWidget {
  final LlmProviderConfig? initialProvider;
  final AppSettingsRepository repository;
  final LlmModelDiscoveryService discoveryService;

  const ProviderFormPage({
    super.key,
    this.initialProvider,
    required this.repository,
    required this.discoveryService,
  });

  @override
  State<ProviderFormPage> createState() => _ProviderFormPageState();
}

class _ProviderFormPageState extends State<ProviderFormPage> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _baseUrlController;
  late final TextEditingController _apiKeyController;
  late List<_EditableModelRow> _models;

  bool _isDiscovering = false;
  bool _isSaving = false;

  bool get _isEdit => widget.initialProvider != null;

  @override
  void initState() {
    super.initState();
    final provider = widget.initialProvider;
    _nameController = TextEditingController(text: provider?.name ?? '');
    _baseUrlController = TextEditingController(text: provider?.baseUrl ?? '');
    _apiKeyController = TextEditingController(text: provider?.apiKey ?? '');
    _models = provider?.models
            .map(
              (item) => _EditableModelRow(
                idController: TextEditingController(text: item.id),
                nameController: TextEditingController(text: item.name),
              ),
            )
            .toList(growable: true) ??
        <_EditableModelRow>[];
  }

  @override
  void dispose() {
    _nameController.dispose();
    _baseUrlController.dispose();
    _apiKeyController.dispose();
    for (final row in _models) {
      row.dispose();
    }
    super.dispose();
  }

  String? _validateBaseUrl(String? value) {
    final input = value?.trim() ?? '';
    final uri = Uri.tryParse(input);
    if (input.isEmpty) {
      return '请输入 Base URL';
    }
    if (uri == null || !uri.hasScheme || !uri.hasAuthority) {
      return '请输入有效的 URL';
    }
    return null;
  }

  LlmProviderConfig _buildProvider() {
    final models = _models
        .map(
          (row) => LlmProviderModel(
            id: row.idController.text.trim(),
            name: row.nameController.text.trim(),
          ),
        )
        .where((item) => item.id.isNotEmpty)
        .toList(growable: false);

    return LlmProviderConfig(
      id: widget.initialProvider?.id ??
          DateTime.now().millisecondsSinceEpoch.toString(),
      name: _nameController.text.trim(),
      apiKey: _apiKeyController.text.trim(),
      baseUrl: _baseUrlController.text.trim(),
      models: models,
    );
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() {
      _isSaving = true;
    });

    try {
      final provider = _buildProvider();
      await widget.repository.saveProvider(provider);
      if (!mounted) {
        return;
      }
      Navigator.of(context).pop(provider);
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
    }
  }

  Future<void> _discoverModels() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() {
      _isDiscovering = true;
    });

    try {
      final models = await widget.discoveryService.discoverModels(
        provider: _buildProvider(),
      );
      for (final row in _models) {
        row.dispose();
      }
      if (!mounted) {
        return;
      }
      setState(() {
        _models = models
            .map(
              (item) => _EditableModelRow(
                idController: TextEditingController(text: item.id),
                nameController: TextEditingController(text: item.name),
              ),
            )
            .toList(growable: true);
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('模型探测失败: $error')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isDiscovering = false;
        });
      }
    }
  }

  Future<void> _setDefaultModel(_EditableModelRow row) async {
    final provider = _buildProvider();
    final modelId = row.idController.text.trim();
    if (modelId.isEmpty) {
      return;
    }
    await widget.repository.saveProvider(provider);
    await widget.repository.setDefaultProviderAndModel(
      providerId: provider.id,
      modelId: modelId,
    );
    await widget.repository.selectProviderAndModel(
      providerId: provider.id,
      modelId: modelId,
    );
    if (!mounted) {
      return;
    }
    Navigator.of(context).pop(provider);
  }

  void _addModelRow() {
    setState(() {
      _models = [..._models, _EditableModelRow.empty()];
    });
  }

  void _removeModelRow(int index) {
    final row = _models[index];
    row.dispose();
    setState(() {
      _models = [..._models]..removeAt(index);
    });
  }

  @override
  Widget build(BuildContext context) {
    final spacing = Theme.of(context).extension<AppSpacing>()!;
    final hasModels = _models.isNotEmpty;

    return Scaffold(
      appBar: _buildTintedHeader(context, _isEdit ? '编辑 Provider' : '新增 Provider'),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: EdgeInsets.all(spacing.lg),
          children: [
            _ProviderHeroCard(
              isEdit: _isEdit,
              providerName: _nameController.text.trim(),
              modelCount: _models.length,
            ),
            SizedBox(height: spacing.lg),
            _SectionCard(
              title: '连接配置',
              subtitle: '先保存 Provider 名称、Base URL 和 API Key，再执行模型探测。',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextFormField(
                    controller: _nameController,
                    decoration: const InputDecoration(
                      labelText: 'Provider 名称',
                      hintText: 'OpenAI / AIGoCode',
                    ),
                    validator: (value) =>
                        (value?.trim().isEmpty ?? true) ? '请输入 Provider 名称' : null,
                    onChanged: (_) => setState(() {}),
                  ),
                  SizedBox(height: spacing.md),
                  TextFormField(
                    controller: _baseUrlController,
                    decoration: const InputDecoration(
                      labelText: 'Base URL',
                      hintText: 'https://api.example.com/v1',
                    ),
                    validator: _validateBaseUrl,
                  ),
                  SizedBox(height: spacing.md),
                  TextFormField(
                    controller: _apiKeyController,
                    decoration: const InputDecoration(
                      labelText: 'API Key',
                      hintText: 'sk-...',
                    ),
                  ),
                  SizedBox(height: spacing.lg),
                  Row(
                    children: [
                      Expanded(
                        child: FilledButton(
                          onPressed: _isSaving ? null : _save,
                          child: _isSaving
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Text('保存'),
                        ),
                      ),
                      SizedBox(width: spacing.sm),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _isDiscovering ? null : _discoverModels,
                          icon: const Icon(Icons.travel_explore_outlined),
                          label: _isDiscovering
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Text('探测模型'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            SizedBox(height: spacing.lg),
            _SectionCard(
              title: '模型列表',
              subtitle: hasModels ? '可直接设为默认，或按需手动补充。' : '可先探测模型，再按需手动新增。',
              trailing: hasModels
                  ? TextButton(
                      onPressed: _addModelRow,
                      child: const Text('手动新增模型'),
                    )
                  : null,
              child: hasModels
                  ? Column(
                      children: _models.asMap().entries.map((entry) {
                        final index = entry.key;
                        final row = entry.value;
                        return Padding(
                          padding: EdgeInsets.only(
                            bottom:
                                index == _models.length - 1 ? 0 : spacing.md,
                          ),
                          child: _ModelEditorCard(
                            index: index,
                            row: row,
                            onSetDefault: () => _setDefaultModel(row),
                            onDelete: () => _removeModelRow(index),
                          ),
                        );
                      }).toList(growable: false),
                    )
                  : _EmptyModelState(onAddModel: _addModelRow),
            ),
          ],
        ),
      ),
    );
  }
}

class _ProviderHeroCard extends StatelessWidget {
  const _ProviderHeroCard({
    required this.isEdit,
    required this.providerName,
    required this.modelCount,
  });

  final bool isEdit;
  final String providerName;
  final int modelCount;

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
            colors.assistantSurface.withValues(alpha: 0.98),
            colors.settingsPanelBackground.withValues(alpha: 0.98),
          ],
        ),
        border: Border.all(color: colors.divider),
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
                isEdit ? 'Provider 详情' : '新增 Provider',
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: colors.workflowRunning,
                      fontWeight: FontWeight.w700,
                    ),
              ),
            ),
            SizedBox(height: spacing.md),
            Text(
              providerName.isEmpty ? '配置新的模型连接' : providerName,
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    height: 1.15,
                  ),
            ),
            SizedBox(height: spacing.xs),
            Text(
              '每个 Provider 独立管理连接信息与模型列表。默认建议先探测模型，再手动兜底编辑。',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: colors.secondaryText,
                    height: 1.5,
                  ),
            ),
            SizedBox(height: spacing.md),
            Wrap(
              spacing: spacing.sm,
              runSpacing: spacing.sm,
              children: [
                _InfoChip(
                  icon: Icons.layers_outlined,
                  label: modelCount == 0 ? '待探测模型' : '$modelCount 个模型',
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

class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.title,
    required this.subtitle,
    required this.child,
    this.trailing,
  });

  final String title;
  final String subtitle;
  final Widget child;
  final Widget? trailing;

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
        padding: EdgeInsets.all(spacing.lg),
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
                      Text(
                        title,
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                      ),
                      SizedBox(height: spacing.xxs),
                      Text(
                        subtitle,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: colors.secondaryText,
                              height: 1.45,
                            ),
                      ),
                    ],
                  ),
                ),
                if (trailing != null) ...[
                  SizedBox(width: spacing.sm),
                  trailing!,
                ],
              ],
            ),
            SizedBox(height: spacing.md),
            child,
          ],
        ),
      ),
    );
  }
}

class _EmptyModelState extends StatelessWidget {
  const _EmptyModelState({required this.onAddModel});

  final VoidCallback onAddModel;

  @override
  Widget build(BuildContext context) {
    final spacing = Theme.of(context).extension<AppSpacing>()!;
    final radius = Theme.of(context).extension<AppRadius>()!;
    final colors = Theme.of(context).extension<AppThemeSpec>()!;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.chatBackground.withValues(alpha: 0.88),
        borderRadius: BorderRadius.circular(radius.lg),
      ),
      child: Padding(
        padding: EdgeInsets.all(spacing.lg),
        child: Column(
          children: [
            Icon(Icons.travel_explore_outlined, color: colors.secondaryText),
            SizedBox(height: spacing.sm),
            Text(
              '还没有模型列表',
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
            ),
            SizedBox(height: spacing.xs),
            Text(
              '推荐先点击上方“探测模型”。如果上游接口不支持模型列表，再手动新增。',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: colors.secondaryText,
                    height: 1.5,
                  ),
            ),
            SizedBox(height: spacing.md),
            OutlinedButton(
              onPressed: onAddModel,
              child: const Text('手动新增模型'),
            ),
          ],
        ),
      ),
    );
  }
}

class _ModelEditorCard extends StatelessWidget {
  const _ModelEditorCard({
    required this.index,
    required this.row,
    required this.onSetDefault,
    required this.onDelete,
  });

  final int index;
  final _EditableModelRow row;
  final VoidCallback onSetDefault;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final spacing = Theme.of(context).extension<AppSpacing>()!;
    final radius = Theme.of(context).extension<AppRadius>()!;
    final colors = Theme.of(context).extension<AppThemeSpec>()!;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.chatBackground,
        borderRadius: BorderRadius.circular(radius.lg),
        border: Border.all(color: colors.divider),
      ),
      child: Padding(
        padding: EdgeInsets.all(spacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  '模型 ${index + 1}',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
                const Spacer(),
                TextButton(
                  onPressed: onSetDefault,
                  child: const Text('设为默认'),
                ),
              ],
            ),
            SizedBox(height: spacing.sm),
            TextFormField(
              controller: row.nameController,
              decoration: InputDecoration(
                labelText: '模型名称 ${index + 1}',
                hintText: 'GPT-4o mini',
              ),
            ),
            SizedBox(height: spacing.sm),
            TextFormField(
              controller: row.idController,
              decoration: const InputDecoration(
                labelText: '模型 ID',
                hintText: 'gpt-4o-mini',
              ),
              validator: (value) =>
                  (value?.trim().isEmpty ?? true) ? '请输入模型 ID' : null,
            ),
            SizedBox(height: spacing.sm),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: onDelete,
                child: const Text('删除'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _InfoChip extends StatelessWidget {
  const _InfoChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final spacing = Theme.of(context).extension<AppSpacing>()!;
    final radius = Theme.of(context).extension<AppRadius>()!;
    final colors = Theme.of(context).extension<AppThemeSpec>()!;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.chatBackground.withValues(alpha: 0.92),
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

class _EditableModelRow {
  final TextEditingController idController;
  final TextEditingController nameController;

  _EditableModelRow({
    required this.idController,
    required this.nameController,
  });

  factory _EditableModelRow.empty() {
    return _EditableModelRow(
      idController: TextEditingController(),
      nameController: TextEditingController(),
    );
  }

  void dispose() {
    idController.dispose();
    nameController.dispose();
  }
}
