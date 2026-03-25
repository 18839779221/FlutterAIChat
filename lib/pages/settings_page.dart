import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/chat_providers.dart';

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

    if (!mounted) {
      return;
    }

    _apiKeyController.text = apiKey;
    _modelController.text = model;
    _baseUrlController.text = baseUrl;

    setState(() {
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('设置'),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Form(
                      key: _formKey,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '模型配置',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            '保存后新请求会直接读取最新的 API Key 和 Base URL。',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                          const SizedBox(height: 16),
                          TextFormField(
                            controller: _apiKeyController,
                            obscureText: _obscureApiKey,
                            decoration: InputDecoration(
                              labelText: 'API Key',
                              border: const OutlineInputBorder(),
                              suffixIcon: IconButton(
                                onPressed: () {
                                  setState(() {
                                    _obscureApiKey = !_obscureApiKey;
                                  });
                                },
                                icon: Icon(
                                  _obscureApiKey
                                      ? Icons.visibility
                                      : Icons.visibility_off,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),
                          TextFormField(
                            controller: _modelController,
                            validator: _validateModel,
                            decoration: const InputDecoration(
                              labelText: 'Model',
                              hintText: 'deepseek-chat / gpt-5.4 / qwen-plus',
                              border: OutlineInputBorder(),
                            ),
                          ),
                          const SizedBox(height: 16),
                          TextFormField(
                            controller: _baseUrlController,
                            validator: _validateBaseUrl,
                            decoration: const InputDecoration(
                              labelText: 'Base URL',
                              hintText: 'https://api.deepseek.com/v1/chat/completions',
                              border: OutlineInputBorder(),
                            ),
                          ),
                          const SizedBox(height: 16),
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
                ),
                const SizedBox(height: 16),
                SwitchListTile(
                  title: const Text('深色模式'),
                  subtitle: const Text('切换应用主题'),
                  value: _isDarkMode,
                  onChanged: (bool value) {
                    setState(() {
                      _isDarkMode = value;
                    });
                  },
                ),
                SwitchListTile(
                  title: const Text('自动显示键盘'),
                  subtitle: const Text('打开聊天页面时自动显示键盘'),
                  value: _autoShowKeyboard,
                  onChanged: (bool value) {
                    setState(() {
                      _autoShowKeyboard = value;
                    });
                  },
                ),
                ListTile(
                  title: const Text('清除缓存'),
                  subtitle: const Text('清除应用缓存数据'),
                  trailing: const Icon(Icons.arrow_forward_ios),
                  onTap: () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('清除缓存功能待补充')),
                    );
                  },
                ),
              ],
            ),
    );
  }
}
