import 'package:flutter/material.dart';

import '../models/llm/llm_provider_config.dart';
import '../models/llm/llm_provider_model.dart';
import '../theme/app_spacing.dart';

class ProviderFormPage extends StatefulWidget {
  final LlmProviderConfig? initialProvider;

  const ProviderFormPage({
    super.key,
    this.initialProvider,
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
        [_EditableModelRow.empty()];
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

  void _addModelRow() {
    setState(() {
      _models = [..._models, _EditableModelRow.empty()];
    });
  }

  void _removeModelRow(int index) {
    if (_models.length == 1) {
      return;
    }
    final row = _models[index];
    row.dispose();
    setState(() {
      _models = [..._models]..removeAt(index);
    });
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

  void _save() {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    final models = _models
        .map(
          (row) => LlmProviderModel(
            id: row.idController.text.trim(),
            name: row.nameController.text.trim(),
          ),
        )
        .where((item) => item.id.isNotEmpty)
        .toList(growable: false);

    final provider = LlmProviderConfig(
      id: widget.initialProvider?.id ?? DateTime.now().millisecondsSinceEpoch.toString(),
      name: _nameController.text.trim(),
      apiKey: _apiKeyController.text.trim(),
      baseUrl: _baseUrlController.text.trim(),
      models: models,
    );
    Navigator.of(context).pop(provider);
  }

  @override
  Widget build(BuildContext context) {
    final spacing = Theme.of(context).extension<AppSpacing>()!;

    return Scaffold(
      appBar: AppBar(
        title: Text(_isEdit ? '编辑提供方' : '新增提供方'),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: EdgeInsets.all(spacing.lg),
          children: [
            TextFormField(
              controller: _nameController,
              decoration: const InputDecoration(
                labelText: '提供方名称',
                hintText: 'AIGoCode / OpenAI Proxy',
              ),
              validator: (value) =>
                  (value?.trim().isEmpty ?? true) ? '请输入提供方名称' : null,
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
                  child: Text(
                    '模型列表',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                TextButton.icon(
                  onPressed: _addModelRow,
                  icon: const Icon(Icons.add),
                  label: const Text('新增模型'),
                ),
              ],
            ),
            SizedBox(height: spacing.sm),
            ..._models.asMap().entries.map((entry) {
              final index = entry.key;
              final row = entry.value;
              return Padding(
                padding: EdgeInsets.only(bottom: spacing.md),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextFormField(
                      controller: row.nameController,
                      decoration: InputDecoration(
                        labelText: '模型名称 ${index + 1}',
                        hintText: 'GPT-5.4',
                      ),
                    ),
                    SizedBox(height: spacing.sm),
                    Row(
                      children: [
                        Expanded(
                          child: TextFormField(
                            controller: row.idController,
                            decoration: const InputDecoration(
                              labelText: '模型 ID',
                              hintText: 'gpt-5.4',
                            ),
                            validator: (value) => (value?.trim().isEmpty ?? true)
                                ? '请输入模型 ID'
                                : null,
                          ),
                        ),
                        SizedBox(width: spacing.sm),
                        IconButton(
                          tooltip: '删除模型',
                          onPressed: () => _removeModelRow(index),
                          icon: const Icon(Icons.remove_circle_outline),
                        ),
                      ],
                    ),
                  ],
                ),
              );
            }),
            SizedBox(height: spacing.lg),
            FilledButton(
              onPressed: _save,
              child: Text(_isEdit ? '保存提供方' : '创建提供方'),
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
