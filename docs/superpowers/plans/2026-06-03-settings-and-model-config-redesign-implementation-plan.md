# 设置页与模型配置重构 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 重构首页、设置页、模型配置页的职责分工与交互路径，让首次模型接入、日常模型切换、provider 维护三条路径更清晰，并显著提升 UI 的专业感与主题一致性。

**Architecture:** 保留现有 provider/model 持久化与选择逻辑作为单一状态源，先补齐“空模型 provider + 模型探测”底层能力，再重构模型配置页为 provider 列表页 + provider 详情页，最后把首页与设置页切换到新的入口结构。首页空态覆盖推荐案例与输入区 model sheet 只做轻量入口，不承担完整管理逻辑。

**Tech Stack:** Flutter, Riverpod, SharedPreferences, http, flutter_test

---

## 文件结构与职责

### 需要新增的文件

- `lib/services/llm_model_discovery_service.dart`
  - 负责基于 provider 配置请求模型列表接口并解析返回结果
- `test/services/llm_model_discovery_service_test.dart`
  - 覆盖模型探测成功、失败、协议兼容等行为

### 需要重点修改的文件

- `lib/repositories/app_settings_repository.dart`
  - 放宽 provider 持久化约束，允许“先保存 provider、后探测 models”
- `lib/pages/model_management_page.dart`
  - 重做为 provider 列表页，承担状态摘要、provider 列表、进入详情页等职责
- `lib/pages/provider_form_page.dart`
  - 重做为 provider 详情/编辑页，承载连接配置、模型探测、默认模型选择、手动增删 model
- `lib/pages/settings_page.dart`
  - 移除顶部展示卡、移除 provider/model 直接切换、清理无效偏好项，只保留模型摘要与入口
- `lib/widgets/chat_input.dart`
  - 新增输入区第二行的 model 胶囊入口与选择 sheet
- `lib/widgets/chat_empty_state.dart`
  - 支持“未配置模型”时覆盖推荐案例的引导卡
- `lib/widgets/chat_message_list.dart`
  - 在空态渲染路径中接入“未配置模型”状态与引导卡

### 需要补充或更新的测试文件

- `test/repositories/app_settings_repository_test.dart`
- `test/services/llm_model_test_service_test.dart`
- `test/pages/model_management_page_test.dart`
- `test/pages/settings_page_tool_settings_test.dart`
- `test/widgets/chat_input_test.dart`
- `test/widgets/chat_message_list_test.dart`
- `test/pages/chat_page_test.dart`

## 实施策略

- 先打通底层：provider 可空模型保存 + 模型探测服务
- 再重做模型配置页：先列表页、后详情页
- 再接首页：空态引导卡 + model 胶囊 + 二级 provider 选择
- 最后收口设置页：迁出运行时切换，删除无效项

---

### Task 1: 底层 provider 约束与模型探测能力

**Files:**
- Create: `lib/services/llm_model_discovery_service.dart`
- Test: `test/services/llm_model_discovery_service_test.dart`
- Modify: `lib/repositories/app_settings_repository.dart`
- Modify: `test/repositories/app_settings_repository_test.dart`

- [ ] **Step 1: 为“空模型 provider 可持久化”写失败测试**

```dart
test('allows saving provider before models are discovered', () async {
  SharedPreferences.setMockInitialValues({});
  final repository = AppSettingsRepository(
    await SharedPreferences.getInstance(),
    localDefaultsLoader: () async => null,
  );

  await repository.saveProvider(
    const LlmProviderConfig(
      id: 'openai',
      name: 'OpenAI',
      apiKey: 'key',
      baseUrl: 'https://api.openai.com/v1',
      models: [],
    ),
  );

  final providers = await repository.getProviders();
  expect(providers.single.id, 'openai');
  expect(providers.single.models, isEmpty);
});
```

- [ ] **Step 2: 运行仓库测试确认当前失败**

Run: `fvm flutter test test/repositories/app_settings_repository_test.dart`
Expected: FAIL，现有过滤逻辑会丢弃 `models.isEmpty` 的 provider

- [ ] **Step 3: 最小化修改 repository 持久化约束**

```dart
return decoded
    .whereType<Map>()
    .map((item) => LlmProviderConfig.fromJson(Map<String, dynamic>.from(item)))
    .where(
      (item) =>
          item.id.isNotEmpty &&
          item.name.isNotEmpty &&
          item.baseUrl.isNotEmpty,
    )
    .toList(growable: false);
```

同时补一条选择归一化约束：当当前 provider 没有 models 时，不自动生成无效的 selected/default model id。

- [ ] **Step 4: 为模型探测服务写失败测试**

```dart
test('discovers models from OpenAI-compatible /models endpoint', () async {
  final service = LlmModelDiscoveryService(
    httpClient: _FakeHttpClient(
      handler: (request) async {
        expect(request.url.toString(), 'https://api.example.com/models');
        return http.Response(
          jsonEncode({
            'data': [
              {'id': 'gpt-4o-mini'},
              {'id': 'gpt-4.1'},
            ],
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      },
    ),
  );

  final models = await service.discoverModels(
    provider: const LlmProviderConfig(
      id: 'provider',
      name: 'Provider',
      apiKey: 'key',
      baseUrl: 'https://api.example.com/v1',
      models: [],
    ),
  );

  expect(models.map((item) => item.id), ['gpt-4o-mini', 'gpt-4.1']);
});
```

- [ ] **Step 5: 为探测失败和空返回写失败测试**

```dart
test('throws readable error when discovery request fails', () async { ... });
test('throws readable error when endpoint returns no models', () async { ... });
```

- [ ] **Step 6: 实现 `LlmModelDiscoveryService`**

```dart
class LlmModelDiscoveryService {
  Future<List<LlmProviderModel>> discoverModels({
    required LlmProviderConfig provider,
  }) async {
    _validateProvider(provider);
    final response = await _httpClient.get(
      _buildModelsUri(provider.baseUrl),
      headers: _buildHeaders(provider),
    );
    if (response.statusCode != 200) {
      throw Exception('模型探测失败: ...');
    }
    final models = _extractModels(response.body);
    if (models.isEmpty) {
      throw Exception('模型探测失败: 未返回可用模型');
    }
    return models;
  }
}
```

- [ ] **Step 7: 运行底层测试，确认全部通过**

Run:
- `fvm flutter test test/repositories/app_settings_repository_test.dart`
- `fvm flutter test test/services/llm_model_discovery_service_test.dart`

Expected: PASS

- [ ] **Step 8: 提交底层能力改动**

```bash
git add \
  lib/repositories/app_settings_repository.dart \
  lib/services/llm_model_discovery_service.dart \
  test/repositories/app_settings_repository_test.dart \
  test/services/llm_model_discovery_service_test.dart
git commit -m "feat: add provider model discovery foundation"
```

---

### Task 2: 重构模型配置页为 provider 列表页 + provider 详情页

**Files:**
- Modify: `lib/pages/model_management_page.dart`
- Modify: `lib/pages/provider_form_page.dart`
- Modify: `lib/services/llm_model_test_service.dart`
- Modify: `test/pages/model_management_page_test.dart`
- Modify: `test/services/llm_model_test_service_test.dart`

- [ ] **Step 1: 为模型配置列表页的新结构写失败测试**

```dart
testWidgets('model management renders provider-first list with summary actions',
    (tester) async {
  ...
  expect(find.text('当前默认模型'), findsOneWidget);
  expect(find.text('新增 Provider'), findsOneWidget);
  expect(find.text('AIGoCode'), findsOneWidget);
  expect(find.text('2 个模型'), findsOneWidget);
  expect(find.text('编辑'), findsWidgets);
  expect(find.text('删除'), findsWidgets);
  expect(find.text('使用此模型'), findsNothing);
});
```

- [ ] **Step 2: 为 provider 详情页的探测主路径写失败测试**

```dart
testWidgets('provider detail promotes discover models and fallback manual add',
    (tester) async {
  ...
  expect(find.text('探测模型'), findsOneWidget);
  expect(find.text('手动新增模型'), findsOneWidget);
  expect(find.text('设为默认'), findsNothing);
});
```

- [ ] **Step 3: 为探测后写回 provider models 的行为写失败测试**

```dart
testWidgets('discovered models are persisted and can become default',
    (tester) async {
  ...
  expect(find.text('gpt-4o-mini'), findsOneWidget);
  await tester.tap(find.text('设为默认').first);
  final selection = await repository.getSelectionState();
  expect(selection.defaultModelId, 'gpt-4o-mini');
});
```

- [ ] **Step 4: 重构 `ModelManagementPage` 为 provider 列表页**

```dart
// 保留顶部状态区 + provider 列表
// provider 行只提供进入详情、编辑、删除
// 不在列表页直接堆叠 model 级按钮
```

页面需要满足：
- 顶部显示默认 provider/model 摘要
- 提供 `新增 Provider`、`测试当前模型`
- provider 行视觉上更轻，贴合现有主题

- [ ] **Step 5: 重构 `ProviderFormPage` 为 provider 详情/编辑页**

```dart
// 连接配置
TextFormField(labelText: 'Provider 名称')
TextFormField(labelText: 'Base URL')
TextFormField(labelText: 'API Key')

// 主动作
FilledButton(onPressed: _save, child: const Text('保存'))
OutlinedButton(onPressed: _discoverModels, child: const Text('探测模型'))

// 模型列表
ListView(...)
TextButton(onPressed: _addModelRow, child: const Text('手动新增模型'))
```

实现要求：
- 探测模型是主操作
- 手动新增模型是弱化兜底能力
- model 行只保留 `设为默认`、`删除`
- 编辑和删除流程尽量直接，避免复杂弹层

- [ ] **Step 6: 补齐 `LlmModelTestService` 对“无默认模型”场景的可读报错**

```dart
if (model.id.trim().isEmpty) {
  throw Exception('请先选择一个默认模型');
}
```

- [ ] **Step 7: 运行页面与服务测试**

Run:
- `fvm flutter test test/pages/model_management_page_test.dart`
- `fvm flutter test test/services/llm_model_test_service_test.dart`

Expected: PASS

- [ ] **Step 8: 提交模型配置页重构**

```bash
git add \
  lib/pages/model_management_page.dart \
  lib/pages/provider_form_page.dart \
  lib/services/llm_model_test_service.dart \
  test/pages/model_management_page_test.dart \
  test/services/llm_model_test_service_test.dart
git commit -m "feat: redesign provider-first model management"
```

---

### Task 3: 首页空态引导卡与输入区 Model 胶囊

**Files:**
- Modify: `lib/widgets/chat_empty_state.dart`
- Modify: `lib/widgets/chat_message_list.dart`
- Modify: `lib/widgets/chat_input.dart`
- Modify: `test/widgets/chat_message_list_test.dart`
- Modify: `test/widgets/chat_input_test.dart`
- Modify: `test/pages/chat_page_test.dart`

- [ ] **Step 1: 为“未配置模型覆盖推荐案例”写失败测试**

```dart
testWidgets('empty conversation shows model setup callout before suggestions',
    (tester) async {
  ...
  expect(find.text('去配置模型'), findsOneWidget);
  expect(find.text('开始一段新的对话'), findsNothing);
});
```

- [ ] **Step 2: 为“已配置时仍显示推荐案例”写回归测试**

```dart
testWidgets('configured conversation still shows default empty suggestions',
    (tester) async {
  ...
  expect(find.text('开始一段新的对话'), findsOneWidget);
});
```

- [ ] **Step 3: 为输入区第二行 model 胶囊写失败测试**

```dart
testWidgets('chat input shows current model chip before token usage', (tester) async {
  ...
  expect(find.text('gpt-4o-mini'), findsOneWidget);
  expect(find.byKey(const ValueKey('chat-input-model-chip')), findsOneWidget);
});
```

- [ ] **Step 4: 为“未配置模型”文案和入口写失败测试**

```dart
testWidgets('chat input shows unconfigured model chip when no model selected',
    (tester) async {
  ...
  expect(find.text('未配置模型'), findsOneWidget);
});
```

- [ ] **Step 5: 为 model sheet 的二级 provider 选择写失败测试**

```dart
testWidgets('model picker prioritizes models and nests provider switch',
    (tester) async {
  ...
  await tester.tap(find.byKey(const ValueKey('chat-input-model-chip')));
  expect(find.text('切换 Provider'), findsOneWidget);
  expect(find.text('gpt-4o-mini'), findsOneWidget);
});
```

- [ ] **Step 6: 实现 `ChatEmptyState` 的未配置引导卡变体**

```dart
class ChatEmptyState extends StatelessWidget {
  final bool showModelSetupCallout;
  final VoidCallback? onConfigureModel;
  ...
}
```

实现要求：
- 未配置时覆盖推荐案例区域
- 保持与现有空态主题一致，但更像克制的主 CTA 卡片
- 已配置时不影响现有推荐案例逻辑

- [ ] **Step 7: 在 `chat_message_list.dart` 的空态路径接入 provider/model 配置状态**

```dart
final hasConfiguredModel = ...;
return ChatEmptyState(
  showModelSetupCallout: !hasConfiguredModel,
  onConfigureModel: () => ...,
);
```

优先从 repository selection + provider models 判断，不新建第二套配置标志。

- [ ] **Step 8: 在 `chat_input.dart` 增加 model 胶囊与二级选择 sheet**

```dart
Widget _ModelSelectionChip(...)
Future<void> _openModelSelectionSheet() async { ... }
Future<void> _openProviderSelectionSheet() async { ... }
```

实现要求：
- 第二行左侧显示 model 胶囊
- 默认路径先选 model
- provider 切换作为 sheet 内次级入口
- 继续复用 `selectProviderAndModel`
- 未配置时点按也能进入模型配置页

- [ ] **Step 9: 运行首页与输入区测试**

Run:
- `fvm flutter test test/widgets/chat_message_list_test.dart`
- `fvm flutter test test/widgets/chat_input_test.dart`
- `fvm flutter test test/pages/chat_page_test.dart`

Expected: PASS

- [ ] **Step 10: 提交首页入口改动**

```bash
git add \
  lib/widgets/chat_empty_state.dart \
  lib/widgets/chat_message_list.dart \
  lib/widgets/chat_input.dart \
  test/widgets/chat_message_list_test.dart \
  test/widgets/chat_input_test.dart \
  test/pages/chat_page_test.dart
git commit -m "feat: add chat home model setup entrypoints"
```

---

### Task 4: 设置页收口与无效项清理

**Files:**
- Modify: `lib/pages/settings_page.dart`
- Modify: `test/pages/settings_page_tool_settings_test.dart`

- [ ] **Step 1: 为移除顶部展示卡写失败测试**

```dart
testWidgets('settings page removes decorative hero copy', (tester) async {
  ...
  expect(find.text('Precision Settings'), findsNothing);
});
```

- [ ] **Step 2: 为“模型与连接只保留摘要和入口”写失败测试**

```dart
testWidgets('settings page shows model summary instead of inline pickers',
    (tester) async {
  ...
  expect(find.text('进入模型配置'), findsOneWidget);
  expect(find.byKey(const Key('provider-switcher')), findsNothing);
});
```

- [ ] **Step 3: 为删除无效偏好项写失败测试**

```dart
testWidgets('settings page removes inactive keyboard and cache toggles',
    (tester) async {
  ...
  expect(find.text('自动显示键盘'), findsNothing);
  expect(find.text('清除缓存'), findsNothing);
});
```

- [ ] **Step 4: 为删除主题冗余说明写失败测试**

```dart
testWidgets('appearance section keeps theme choices without filler copy',
    (tester) async {
  ...
  expect(find.textContaining('主题作为一等公民管理'), findsNothing);
});
```

- [ ] **Step 5: 重构 `settings_page.dart` 的模型与连接分组**

```dart
SettingsGroupSection(
  title: '模型与连接',
  child: Column(
    children: [
      SettingsRow(title: '当前默认模型', ...),
      SettingsRow(title: '当前 Provider', ...),
      FilledButton(onPressed: _openModelManagement, child: const Text('进入模型配置')),
      OutlinedButton(onPressed: _testCurrentModel, child: const Text('测试当前模型')),
    ],
  ),
)
```

实现要求：
- 不再显示 provider/model 选择器
- 删除顶部装饰卡
- 主题区域只保留实际选择
- 删除无效的 `自动显示键盘`、`清除缓存`

- [ ] **Step 6: 运行设置页测试**

Run: `fvm flutter test test/pages/settings_page_tool_settings_test.dart`
Expected: PASS

- [ ] **Step 7: 运行本次改动的串行回归测试**

Run:
- `fvm flutter test test/repositories/app_settings_repository_test.dart`
- `fvm flutter test test/services/llm_model_discovery_service_test.dart`
- `fvm flutter test test/services/llm_model_test_service_test.dart`
- `fvm flutter test test/pages/model_management_page_test.dart`
- `fvm flutter test test/pages/settings_page_tool_settings_test.dart`
- `fvm flutter test test/widgets/chat_message_list_test.dart`
- `fvm flutter test test/widgets/chat_input_test.dart`
- `fvm flutter test test/pages/chat_page_test.dart`

Expected: PASS

- [ ] **Step 8: 提交设置页收口**

```bash
git add \
  lib/pages/settings_page.dart \
  test/pages/settings_page_tool_settings_test.dart
git commit -m "feat: streamline settings entrypoints"
```

---

### Task 5: 文档与验收收尾

**Files:**
- Modify: `README.md`
- Modify: `AGENTS.md`
- Modify: `docs/superpowers/specs/2026-06-03-settings-and-model-config-redesign-design.md` (如实现细节需轻微校正)

- [ ] **Step 1: 检查 README 是否需要同步新的入口描述**

```md
- 首页输入区第二行提供当前模型入口
- 设置页中的模型配置已迁移为摘要 + 入口
```

- [ ] **Step 2: 检查 AGENTS.md 是否需要补充新的模型配置约定**

```md
- 首页的 provider/model 轻切换入口位于输入区第二行
- 设置页不再承载 provider/model 直接切换
```

- [ ] **Step 3: 运行必要文档相关测试或格式检查**

Run: `git diff -- README.md AGENTS.md docs/superpowers/specs/2026-06-03-settings-and-model-config-redesign-design.md`
Expected: 变更与实现一致，无历史描述残留

- [ ] **Step 4: 提交文档收尾**

```bash
git add \
  README.md \
  AGENTS.md \
  docs/superpowers/specs/2026-06-03-settings-and-model-config-redesign-design.md
git commit -m "docs: align model setup entrypoint documentation"
```

---

## 额外说明

- 本计划按 TDD 顺序编排，但 Flutter UI 测试需要串行执行，避免并发命令触发 Flutter 启动锁。
- 当前未使用子 agent 做 plan review，因为本轮没有收到显式的委派授权；后续若选择 `Subagent-Driven` 执行方式，再按技能要求切换到对应执行流程。
