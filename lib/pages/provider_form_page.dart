import 'package:flutter/material.dart';

import '../models/llm/api_protocol_resolver.dart';
import '../models/llm/llm_provider_config.dart';
import '../models/llm/llm_provider_model.dart';
import '../repositories/app_settings_repository.dart';
import '../services/llm_model_discovery_service.dart';
import '../services/llm_model_test_service.dart';
import '../theme/app_radius.dart';
import '../theme/app_spacing.dart';
import '../theme/app_theme_spec.dart';
import '../widgets/settings/immersive_settings_scaffold.dart';
import '../widgets/settings/settings_group_section.dart';
import '../widgets/settings/settings_row.dart';
import '../widgets/settings/settings_value_badge.dart';
import '../widgets/shared/app_bottom_sheet.dart';

class ProviderFormPage extends StatefulWidget {
  final LlmProviderConfig? initialProvider;
  final AppSettingsRepository repository;
  final LlmModelDiscoveryService discoveryService;
  final LlmModelTestService testService;

  ProviderFormPage({
    super.key,
    this.initialProvider,
    required this.repository,
    required this.discoveryService,
    LlmModelTestService? testService,
  }) : testService = testService ?? LlmModelTestService();

  @override
  State<ProviderFormPage> createState() => _ProviderFormPageState();
}

class _ProviderFormPageState extends State<ProviderFormPage> {
  final _formKey = GlobalKey<FormState>();
  final ApiProtocolResolver _protocolResolver = const ApiProtocolResolver();
  late final TextEditingController _nameController;
  late final TextEditingController _baseUrlController;
  late final TextEditingController _apiKeyController;
  late final FocusNode _apiKeyFocusNode;
  late List<_EditableModelRow> _models;
  late ApiStyle _selectedApiStyle;
  late String _apiKeyValue;
  String? _selectedSideModelId;

  bool _isDiscovering = false;
  bool _isSaving = false;
  bool _isSpeedTesting = false;
  int? _imageGenerationTestingIndex;

  bool get _isEdit => widget.initialProvider != null;

  @override
  void initState() {
    super.initState();
    final provider = widget.initialProvider;
    _nameController = TextEditingController(text: provider?.name ?? '');
    _baseUrlController = TextEditingController(text: provider?.baseUrl ?? '');
    _apiKeyValue = provider?.apiKey ?? '';
    _apiKeyController =
        TextEditingController(text: _maskedApiKey(_apiKeyValue));
    _apiKeyFocusNode = FocusNode()..addListener(_handleApiKeyFocusChange);
    _selectedApiStyle = _resolvedApiStyleForInput(provider?.baseUrl ?? '');
    _selectedSideModelId = provider?.sideModelId;
    _baseUrlController.addListener(_syncApiStyleFromBaseUrlInput);
    _models = provider?.models
            .map(
              (item) => _EditableModelRow.synced(
                idController: TextEditingController(text: item.id),
                nameController: TextEditingController(
                  text: item.name.isEmpty ? item.id : item.name,
                ),
                syncNameWithId: item.name.isEmpty || item.name == item.id,
                supportsImageGeneration: item.supportsImageGeneration,
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
    _apiKeyFocusNode.dispose();
    for (final row in _models) {
      row.dispose();
    }
    super.dispose();
  }

  String _maskedApiKey(String rawValue) {
    final value = rawValue.trim();
    if (value.length <= 8) {
      return value;
    }
    return '${value.substring(0, 4)}*****${value.substring(value.length - 4)}';
  }

  void _handleApiKeyFocusChange() {
    if (_apiKeyFocusNode.hasFocus) {
      final rawValue = _apiKeyValue.trim();
      _apiKeyController.value = _apiKeyController.value.copyWith(
        text: rawValue,
        selection: TextSelection.collapsed(offset: rawValue.length),
        composing: TextRange.empty,
      );
      return;
    }
    _apiKeyValue = _apiKeyController.text.trim();
    final maskedValue = _maskedApiKey(_apiKeyValue);
    _apiKeyController.value = _apiKeyController.value.copyWith(
      text: maskedValue,
      selection: TextSelection.collapsed(offset: maskedValue.length),
      composing: TextRange.empty,
    );
  }

  String _currentApiKeyValue() {
    return _apiKeyFocusNode.hasFocus
        ? _apiKeyController.text.trim()
        : _apiKeyValue.trim();
  }

  ApiStyle _resolvedApiStyleForInput(String rawUrl) {
    final trimmed = rawUrl.trim();
    if (trimmed.isEmpty) {
      return ApiStyle.responses;
    }
    final explicit = _tryDetectExplicitStyle(trimmed);
    if (explicit != null) {
      return explicit;
    }
    return _protocolResolver.resolveStyle(trimmed);
  }

  ApiStyle? _tryDetectExplicitStyle(String rawUrl) {
    final trimmed = rawUrl.trim();
    if (trimmed.isEmpty) {
      return null;
    }
    final uri = Uri.tryParse(trimmed);
    if (uri == null || !uri.hasScheme || !uri.hasAuthority) {
      return null;
    }
    return _protocolResolver.detectExplicitStyle(trimmed);
  }

  void _syncApiStyleFromBaseUrlInput() {
    final detectedStyle = _tryDetectExplicitStyle(_baseUrlController.text);
    if (detectedStyle == null ||
        detectedStyle == _selectedApiStyle ||
        !mounted) {
      return;
    }
    setState(() {
      _selectedApiStyle = detectedStyle;
    });
  }

  String _normalizedBaseUrlForSelectedStyle() {
    final input = _baseUrlController.text.trim();
    final uri = Uri.tryParse(input);
    if (uri == null || !uri.hasScheme || !uri.hasAuthority) {
      return input;
    }
    return _protocolResolver
        .buildRequestUri(input, _selectedApiStyle)
        .toString();
  }

  Future<void> _selectApiStyle() async {
    final spacing = Theme.of(context).extension<AppSpacing>()!;
    final selected = await showAppBottomSheet<ApiStyle>(
      context: context,
      mode: AppBottomSheetMode.adaptive,
      title: '选择 API Style',
      subtitle: '最终会根据你选择的风格，把 Base URL 规范成对应的 endpoint。',
      bodyPadding: EdgeInsets.fromLTRB(
        spacing.lg,
        spacing.sm,
        spacing.lg,
        spacing.lg,
      ),
      body: _ApiStyleSelectionSheet(
        selectedStyle: _selectedApiStyle,
      ),
    );
    if (selected == null || selected == _selectedApiStyle) {
      return;
    }
    final normalizedUrl = _normalizedBaseUrlFor(selected);
    setState(() {
      _selectedApiStyle = selected;
      if (normalizedUrl != null) {
        _baseUrlController.value = _baseUrlController.value.copyWith(
          text: normalizedUrl,
          selection: TextSelection.collapsed(offset: normalizedUrl.length),
          composing: TextRange.empty,
        );
      }
    });
  }

  String? _normalizedBaseUrlFor(ApiStyle style) {
    final input = _baseUrlController.text.trim();
    final uri = Uri.tryParse(input);
    if (uri == null || !uri.hasScheme || !uri.hasAuthority) {
      return null;
    }
    return _protocolResolver.buildRequestUri(input, style).toString();
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
            supportsImageGeneration: row.supportsImageGeneration,
          ),
        )
        .where((item) => item.id.isNotEmpty)
        .toList(growable: false);

    return LlmProviderConfig(
      id: widget.initialProvider?.id ??
          DateTime.now().millisecondsSinceEpoch.toString(),
      name: _nameController.text.trim(),
      apiKey: _currentApiKeyValue(),
      baseUrl: _normalizedBaseUrlForSelectedStyle(),
      apiStyle: _selectedApiStyle,
      models: models,
      sideModelId: _resolveValidSideModelId(models),
    );
  }

  String? _resolveValidSideModelId(List<LlmProviderModel> models) {
    final candidate = _selectedSideModelId?.trim();
    if (candidate == null || candidate.isEmpty) {
      return null;
    }
    for (final model in models) {
      if (model.id == candidate) {
        return candidate;
      }
    }
    return null;
  }

  void _replaceModelRows(List<LlmProviderModel> models) {
    for (final row in _models) {
      row.dispose();
    }
    _models = models
        .map(
          (item) => _EditableModelRow.synced(
            idController: TextEditingController(text: item.id),
            nameController: TextEditingController(
              text: item.name.isEmpty ? item.id : item.name,
            ),
            syncNameWithId: item.name.isEmpty || item.name == item.id,
            supportsImageGeneration: item.supportsImageGeneration,
          ),
        )
        .toList(growable: true);
  }

  String _formatActionError(String prefix, Object error) {
    final message = error.toString();
    if (message.startsWith('Exception: ')) {
      return '$prefix: ${message.substring('Exception: '.length)}';
    }
    return '$prefix: $message';
  }

  LlmProviderModel? _firstModel() {
    final provider = _buildProvider();
    return provider.models.isEmpty ? null : provider.models.first;
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    final normalizedBaseUrl = _normalizedBaseUrlForSelectedStyle();
    if (normalizedBaseUrl != _baseUrlController.text.trim()) {
      _baseUrlController.value = _baseUrlController.value.copyWith(
        text: normalizedBaseUrl,
        selection: TextSelection.collapsed(offset: normalizedBaseUrl.length),
        composing: TextRange.empty,
      );
    }

    setState(() {
      _isSaving = true;
    });

    try {
      var provider = _buildProvider();
      final shouldAutoDiscover = provider.models.isEmpty;
      if (shouldAutoDiscover) {
        final models = await widget.discoveryService.discoverModels(
          provider: provider,
        );
        if (models.isNotEmpty) {
          if (!mounted) {
            return;
          }
          setState(() {
            _replaceModelRows(models);
          });
          provider = _buildProvider();
        }
      }
      await widget.repository.saveProvider(provider);
      if (shouldAutoDiscover && provider.models.isNotEmpty) {
        await widget.testService.speedTestModel(
          provider: provider,
          model: provider.models.first,
        );
      }
      if (!mounted) {
        return;
      }
      Navigator.of(context).pop(provider);
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_formatActionError('保存失败', error))),
      );
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
      if (!mounted) {
        return;
      }
      setState(() {
        _replaceModelRows(models);
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_formatActionError('模型探测失败', error))),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isDiscovering = false;
        });
      }
    }
  }

  Future<void> _useModelNow(_EditableModelRow row) async {
    final provider = _buildProvider();
    final modelId = row.idController.text.trim();
    if (modelId.isEmpty) {
      return;
    }
    await widget.repository.saveProvider(provider);
    await widget.repository.selectProviderAndModel(
      providerId: provider.id,
      modelId: modelId,
    );
    if (!mounted) {
      return;
    }
    Navigator.of(context).pop(provider);
  }

  Future<void> _speedTest() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }
    final model = _firstModel();
    if (model == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请先探测模型或手动新增模型')),
      );
      return;
    }

    setState(() {
      _isSpeedTesting = true;
    });

    try {
      final result = await widget.testService.speedTestModel(
        provider: _buildProvider(),
        model: model,
      );
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '测速完成，连接正常：首次响应 ${result.ping.latency.inMilliseconds}ms · 再次响应 ${result.pong.latency.inMilliseconds}ms',
          ),
        ),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_formatActionError('测速失败', error))),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isSpeedTesting = false;
        });
      }
    }
  }

  void _addModelRow() {
    setState(() {
      _models = [..._models, _EditableModelRow.emptySynced()];
    });
  }

  void _removeModelRow(int index) {
    final row = _models[index];
    row.dispose();
    setState(() {
      _models = [..._models]..removeAt(index);
    });
  }

  Future<void> _testImageGenerationModel(
    int index,
    _EditableModelRow row,
  ) async {
    if (_imageGenerationTestingIndex != null) {
      return;
    }
    if (!_formKey.currentState!.validate()) {
      return;
    }
    final modelId = row.idController.text.trim();
    if (modelId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请先填写模型 ID')),
      );
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('确认测试生图'),
        content: const Text('生图测试会调用真实生图接口，可能较慢且产生费用。确认继续测试？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('确认测试'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) {
      return;
    }

    setState(() {
      _imageGenerationTestingIndex = index;
    });

    try {
      final result = await widget.testService.testImageGenerationModel(
        provider: _buildProvider(),
        model: LlmProviderModel(
          id: modelId,
          name: row.nameController.text.trim(),
          supportsImageGeneration: row.supportsImageGeneration,
        ),
      );
      if (!mounted) {
        return;
      }
      setState(() {
        row.supportsImageGeneration = true;
      });
      final provider = _buildProvider();
      await widget.repository.saveProvider(provider);
      final additionalConfig = await widget.repository.getAdditionalConfig();
      final hasExplicitImageGenerationDefault =
          (additionalConfig['image_generation.default_provider_id'] as String?)
                  ?.trim()
                  .isNotEmpty ==
              true &&
          (additionalConfig['image_generation.default_model_id'] as String?)
                  ?.trim()
                  .isNotEmpty ==
              true;
      if (!hasExplicitImageGenerationDefault) {
        await widget.repository.saveImageGenerationSelection(
          providerId: provider.id,
          modelId: modelId,
        );
      }
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            hasExplicitImageGenerationDefault
                ? '生图测试完成：${result.latency.inMilliseconds}ms，已勾选支持生图'
                : '生图测试完成：${result.latency.inMilliseconds}ms，已勾选支持生图并设为全局生图模型',
          ),
        ),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_formatActionError('生图测试失败', error))),
      );
    } finally {
      if (mounted) {
        setState(() {
          _imageGenerationTestingIndex = null;
        });
      }
    }
  }

  Future<void> _setAsGlobalImageGenerationModel(_EditableModelRow row) async {
    final modelId = row.idController.text.trim();
    if (modelId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请先填写模型 ID')),
      );
      return;
    }

    row.supportsImageGeneration = true;
    final provider = _buildProvider();
    await widget.repository.saveProvider(provider);
    await widget.repository.saveImageGenerationSelection(
      providerId: provider.id,
      modelId: modelId,
    );
    if (!mounted) {
      return;
    }
    setState(() {});
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('已设为全局生图模型')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final spacing = Theme.of(context).extension<AppSpacing>()!;
    final hasModels = _models.isNotEmpty;

    return ImmersiveSettingsScaffold(
      title: _isEdit ? '编辑 Provider' : '新增 Provider',
      headerStyle: SettingsHeaderStyle.editor,
      bodyPadding: EdgeInsets.zero,
      body: Form(
        key: _formKey,
        child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(
            spacing.lg,
            ImmersiveSettingsScaffold.contentStartPadding(
              context,
              headerStyle: SettingsHeaderStyle.editor,
            ),
            spacing.lg,
            spacing.lg,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SettingsGroupSection(
              title: '连接与鉴权',
              summary: '这里只编辑单个 Provider 对象。先完成连接信息，再决定是否探测模型。',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SettingsRow(
                    title: '编辑对象',
                    subtitle: _isEdit ? '当前正在修改已有 Provider' : '当前正在创建新的 Provider',
                    trailing: SettingsValueBadge(
                      label: _isEdit ? '编辑中' : '新对象',
                      tone: SettingsValueBadgeTone.active,
                    ),
                  ),
                  SizedBox(height: spacing.md),
                  TextFormField(
                    controller: _nameController,
                    decoration: const InputDecoration(
                      labelText: 'Provider 名称',
                      hintText: '用于展示（例如：OpenAI）',
                    ),
                    validator: (value) => (value?.trim().isEmpty ?? true)
                        ? '请输入 Provider 名称'
                        : null,
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
                  SizedBox(height: spacing.sm),
                  _ApiStyleRow(
                    selectedStyle: _selectedApiStyle,
                    onPressed: _selectApiStyle,
                  ),
                  SizedBox(height: spacing.md),
                  TextFormField(
                    controller: _apiKeyController,
                    focusNode: _apiKeyFocusNode,
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
                          onPressed: _isSpeedTesting ? null : _speedTest,
                          icon: const Icon(Icons.bolt_rounded),
                          label: _isSpeedTesting
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Text('测速'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
              SizedBox(height: spacing.lg),
              SettingsGroupSection(
              title: '模型目录',
              summary: hasModels
                  ? '优先通过探测更新模型目录，也可按需手动补充。测速会基于当前第一个模型执行。'
                  : '可先探测模型，再按需手动新增；测速会基于当前第一个模型执行。',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: spacing.xs,
                    runSpacing: spacing.xs,
                    children: [
                      TextButton(
                        onPressed: _isDiscovering ? null : _discoverModels,
                        child: _isDiscovering
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Text('探测模型'),
                      ),
                      if (hasModels)
                        TextButton(
                          onPressed: _addModelRow,
                          child: const Text('手动新增模型'),
                        ),
                    ],
                  ),
                  SizedBox(height: spacing.md),
                  if (hasModels)
                    Column(
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
                            onUseModelNow: () => _useModelNow(row),
                            onDelete: () => _removeModelRow(index),
                            onSetAsGlobalImageGenerationModel: () =>
                                _setAsGlobalImageGenerationModel(row),
                            onImageGenerationChanged: (value) {
                              setState(() {
                                row.supportsImageGeneration = value;
                              });
                            },
                            onTestImageGeneration: () =>
                                _testImageGenerationModel(index, row),
                            isImageGenerationTesting:
                                _imageGenerationTestingIndex == index,
                            isAnyImageGenerationTesting:
                                _imageGenerationTestingIndex != null,
                          ),
                        );
                      }).toList(growable: false),
                    )
                  else
                    _EmptyModelState(onAddModel: _addModelRow),
                ],
              ),
            ),
              if (hasModels) ...[
                SizedBox(height: spacing.lg),
                SettingsGroupSection(
                title: '高级运行时',
                summary: '仅在需要主模型之外的辅助模型时单独指定。默认留空，随主模型变化。',
                child: DropdownButtonFormField<String>(
                  initialValue:
                      _resolveValidSideModelId(_buildProvider().models) ?? '',
                  decoration: const InputDecoration(
                    labelText: '当前 Provider 的 Side Model',
                  ),
                  items: [
                    const DropdownMenuItem<String>(
                      value: '',
                      child: Text('与主模型一致'),
                    ),
                    ..._buildProvider().models.map(
                      (model) => DropdownMenuItem<String>(
                        value: model.id,
                        child: Text(model.displayName),
                      ),
                    ),
                  ],
                  onChanged: (value) {
                    setState(() {
                      final trimmed = value?.trim();
                      _selectedSideModelId =
                          (trimmed == null || trimmed.isEmpty) ? null : trimmed;
                    });
                  },
                ),
                ),
              ],
            ],
          ),
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
    required this.onUseModelNow,
    required this.onDelete,
    required this.onSetAsGlobalImageGenerationModel,
    required this.onImageGenerationChanged,
    required this.onTestImageGeneration,
    required this.isImageGenerationTesting,
    required this.isAnyImageGenerationTesting,
  });

  final int index;
  final _EditableModelRow row;
  final VoidCallback onUseModelNow;
  final VoidCallback onDelete;
  final VoidCallback onSetAsGlobalImageGenerationModel;
  final ValueChanged<bool> onImageGenerationChanged;
  final VoidCallback onTestImageGeneration;
  final bool isImageGenerationTesting;
  final bool isAnyImageGenerationTesting;

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
                  onPressed: onUseModelNow,
                  child: const Text('用于当前会话'),
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
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              value: row.supportsImageGeneration,
              onChanged: (value) => onImageGenerationChanged(value ?? false),
              title: const Text('支持生图'),
              subtitle: Text(
                '勾选后该模型可作为 generate_image 的运行模型。',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: colors.secondaryText,
                    ),
              ),
            ),
            SizedBox(height: spacing.sm),
            Align(
              alignment: Alignment.centerRight,
              child: Wrap(
                spacing: spacing.sm,
                alignment: WrapAlignment.end,
                children: [
                  TextButton(
                    onPressed: onSetAsGlobalImageGenerationModel,
                    child: const Text('设为全局生图模型'),
                  ),
                  OutlinedButton.icon(
                    onPressed: isAnyImageGenerationTesting
                        ? null
                        : onTestImageGeneration,
                    icon: isImageGenerationTesting
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.image_search_outlined),
                    label: Text(isImageGenerationTesting ? '测试中' : '测试生图'),
                  ),
                  TextButton(
                    onPressed: onDelete,
                    child: const Text('删除'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

extension on ApiStyle {
  String get displayTitle {
    switch (this) {
      case ApiStyle.responses:
        return 'OpenAI Responses';
      case ApiStyle.chatCompletions:
        return 'OpenAI Chat Completions';
      case ApiStyle.anthropicMessages:
        return 'Anthropic Messages';
    }
  }

  String get protocolStyle {
    switch (this) {
      case ApiStyle.responses:
        return 'responses';
      case ApiStyle.chatCompletions:
        return 'chat_completions';
      case ApiStyle.anthropicMessages:
        return 'anthropic_messages';
    }
  }
}

class _ApiStyleRow extends StatelessWidget {
  const _ApiStyleRow({
    required this.selectedStyle,
    required this.onPressed,
  });

  final ApiStyle selectedStyle;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final spacing = Theme.of(context).extension<AppSpacing>()!;
    final radius = Theme.of(context).extension<AppRadius>()!;
    final colors = Theme.of(context).extension<AppThemeSpec>()!;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.chatBackground.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(radius.md),
      ),
      child: Padding(
        padding: EdgeInsets.all(spacing.md),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'API Style',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                ],
              ),
            ),
            SizedBox(width: spacing.sm),
            OutlinedButton.icon(
              onPressed: onPressed,
              icon: const Icon(Icons.alt_route_rounded),
              label: Text(selectedStyle.displayTitle),
            ),
          ],
        ),
      ),
    );
  }
}

class _ApiStyleSelectionSheet extends StatelessWidget {
  const _ApiStyleSelectionSheet({required this.selectedStyle});

  final ApiStyle selectedStyle;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppThemeSpec>()!;
    const styles = <ApiStyle>[
      ApiStyle.responses,
      ApiStyle.chatCompletions,
      ApiStyle.anthropicMessages,
    ];

    return ListView.builder(
      shrinkWrap: true,
      itemCount: styles.length,
      itemBuilder: (context, index) {
        final style = styles[index];
        final selected = style == selectedStyle;
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
          title: Text(style.displayTitle),
          subtitle: Text(style.protocolStyle),
          onTap: () => Navigator.of(context).pop(style),
        );
      },
    );
  }
}

class _EditableModelRow {
  final TextEditingController idController;
  final TextEditingController nameController;
  bool supportsImageGeneration;
  bool _syncNameWithId;
  bool _isUpdatingNameFromId = false;
  late final VoidCallback _idListener;
  late final VoidCallback _nameListener;

  _EditableModelRow.synced({
    required this.idController,
    required this.nameController,
    required bool syncNameWithId,
    this.supportsImageGeneration = false,
  }) : _syncNameWithId = syncNameWithId {
    _idListener = () {
      if (!_syncNameWithId) {
        return;
      }
      final nextValue = idController.text;
      if (nameController.text == nextValue) {
        return;
      }
      _isUpdatingNameFromId = true;
      nameController.value = nameController.value.copyWith(
        text: nextValue,
        selection: TextSelection.collapsed(offset: nextValue.length),
        composing: TextRange.empty,
      );
      _isUpdatingNameFromId = false;
    };
    _nameListener = () {
      if (_isUpdatingNameFromId) {
        return;
      }
      final currentName = nameController.text;
      final currentId = idController.text;
      _syncNameWithId = currentName.isEmpty || currentName == currentId;
    };
    idController.addListener(_idListener);
    nameController.addListener(_nameListener);
  }

  factory _EditableModelRow.emptySynced() {
    return _EditableModelRow.synced(
      idController: TextEditingController(),
      nameController: TextEditingController(),
      syncNameWithId: true,
      supportsImageGeneration: false,
    );
  }

  void dispose() {
    idController.removeListener(_idListener);
    nameController.removeListener(_nameListener);
    idController.dispose();
    nameController.dispose();
  }
}
