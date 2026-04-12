import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/tool/tool_policy.dart';
import '../providers/chat_providers.dart';
import '../theme/app_colors.dart';
import '../theme/app_radius.dart';
import '../theme/app_spacing.dart';
import '../widgets/settings/settings_group_section.dart';
import '../widgets/settings/settings_row.dart';
import '../widgets/settings/settings_segmented_control.dart';

class SettingsPage extends ConsumerStatefulWidget {
  const SettingsPage({super.key});

  @override
  ConsumerState<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends ConsumerState<SettingsPage> {
  final _formKey = GlobalKey<FormState>();
  final _apiKeyController = TextEditingController();
  final _modelController = TextEditingController();
  final _baseUrlController = TextEditingController();

  bool _isDarkMode = false;
  bool _autoShowKeyboard = true;
  bool _isLoading = true;
  bool _isSaving = false;
  bool _obscureApiKey = true;
  ToolExecutionMode _toolExecutionMode = ToolExecutionMode.balanced;
  List<String> _trustedToolNames = const [];

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  @override
  void dispose() {
    _apiKeyController.dispose();
    _modelController.dispose();
    _baseUrlController.dispose();
    super.dispose();
  }

  Future<void> _loadSettings() async {
    final repository = ref.read(appSettingsRepositoryProvider);
    final apiKey = await repository.getApiKey();
    final model = await repository.getModel();
    final baseUrl = await repository.getBaseUrl();
    final toolExecutionModeName = await repository.getToolExecutionModeName();
    final trustedToolNames = await repository.getTrustedToolNames();

    if (!mounted) {
      return;
    }

    _apiKeyController.text = apiKey;
    _modelController.text = model;
    _baseUrlController.text = baseUrl;

    setState(() {
      _toolExecutionMode = _parseToolExecutionMode(toolExecutionModeName);
      _trustedToolNames = trustedToolNames.toList()..sort();
      _isLoading = false;
    });
  }

  Future<void> _saveSettings() async {
    final formState = _formKey.currentState;
    if (formState == null || !formState.validate()) {
      return;
    }

    setState(() {
      _isSaving = true;
    });

    try {
      await ref.read(appSettingsRepositoryProvider).saveLlmConfig(
        apiKey: _apiKeyController.text,
        model: _modelController.text,
        baseUrl: _baseUrlController.text,
      );

      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('API 配置已保存')),
      );
    } catch (e) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('保存失败: $e')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
    }
  }

  String? _validateBaseUrl(String? value) {
    final input = value?.trim() ?? '';
    if (input.isEmpty) {
      return '请输入 Base URL';
    }

    final uri = Uri.tryParse(input);
    if (uri == null || !uri.hasScheme || !uri.hasAuthority) {
      return '请输入有效的 URL';
    }

    return null;
  }

  String? _validateModel(String? value) {
    if ((value?.trim() ?? '').isEmpty) {
      return '请输入模型名';
    }

    return null;
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

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppColors>()!;
    final spacing = Theme.of(context).extension<AppSpacing>()!;
    final radius = Theme.of(context).extension<AppRadius>()!;

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
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '保存后，新请求会直接读取最新的 API Key、Model 与 Base URL。',
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: colors.secondaryText,
                                height: 1.4,
                              ),
                        ),
                        SizedBox(height: spacing.md),
                        TextFormField(
                          controller: _apiKeyController,
                          obscureText: _obscureApiKey,
                          decoration: InputDecoration(
                            labelText: 'API Key',
                            hintText: 'sk-...',
                            suffixIcon: IconButton(
                              onPressed: () {
                                setState(() {
                                  _obscureApiKey = !_obscureApiKey;
                                });
                              },
                              icon: Icon(
                                _obscureApiKey
                                    ? Icons.visibility_outlined
                                    : Icons.visibility_off_outlined,
                              ),
                            ),
                          ),
                        ),
                        SizedBox(height: spacing.md),
                        TextFormField(
                          controller: _modelController,
                          validator: _validateModel,
                          decoration: const InputDecoration(
                            labelText: 'Model',
                            hintText: 'gpt-5.4 / claude-sonnet / qwen-plus',
                          ),
                        ),
                        SizedBox(height: spacing.md),
                        TextFormField(
                          controller: _baseUrlController,
                          validator: _validateBaseUrl,
                          decoration: const InputDecoration(
                            labelText: 'Base URL',
                            hintText: 'https://api.example.com/v1/responses',
                          ),
                        ),
                        SizedBox(height: spacing.md),
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton(
                            onPressed: _isSaving ? null : _saveSettings,
                            child: _isSaving
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(strokeWidth: 2),
                                  )
                                : const Text('保存配置'),
                          ),
                        ),
                      ],
                    ),
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
