# Provider / Model 管理与 Session 选择语义简化 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 删除 `defaultProviderId/defaultModelId` 与相关 UI/仓库/运行时依赖，把主模型选择收敛为 session-first + first-item fallback，并补齐 provider 级 side model 与独立 image generation model 语义。

**Architecture:** 先从仓库层和 session runtime 解析层移除 `default*` 双轨回退，统一为 `current runtime or selected -> first provider/first model`。随后把新会话初始化改成“继承当前 session runtime，否则回退首项”，再清理设置页与 provider 管理页中的默认概念，并新增 provider 级 `sideModelId` 的最小承载。生图模型保持独立配置入口，不复用聊天主链路 selection。

**Tech Stack:** Flutter 3.35.7, Dart, Riverpod, SharedPreferences, sqflite, flutter_test

---

## File Structure

| Path | Responsibility |
| --- | --- |
| `lib/models/llm/llm_selection_state.dart` | 移除 `default*` 字段，只保留最小 selected 状态 |
| `lib/repositories/app_settings_repository.dart` | 统一 selection 归一化、删除 `setDefaultProviderAndModel`、改写 fallback |
| `lib/services/session_runtime_config_service.dart` | 新会话 runtime 继承当前 session 或首项回退 |
| `lib/controllers/chat_session_coordinator.dart` | 创建新会话时使用新的 draft runtime 规则 |
| `lib/widgets/chat_input.dart` | 模型切换后不再写 default 状态 |
| `lib/widgets/chat_message_list.dart` | 空态判断改为 selected/runtime + 首项回退 |
| `lib/pages/model_management_page.dart` | 删除默认模型相关主文案与状态展示 |
| `lib/pages/provider_form_page.dart` | 删除“设为默认”，接入 provider 级 side model |
| `lib/models/llm/llm_provider_config.dart` | 新增可选 `sideModelId` |
| `lib/services/image_generation_config_resolver.dart` | 确认继续独立于主 selection |
| `README.md` | 更新 provider/model 选择语义说明 |
| `AGENTS.md` | 如有必要，更新设置页与 runtime 规则说明 |
| `test/...` | 覆盖 selection/runtime/provider 管理页相关回归 |

## Task 1: 移除 `LlmSelectionState.default*` 并统一仓库 fallback

**Files:**
- Modify: `lib/models/llm/llm_selection_state.dart`
- Modify: `lib/repositories/app_settings_repository.dart`
- Test: `test/repositories/app_settings_repository_test.dart`
- Test: `test/services/session_llm_config_resolver_test.dart`

- [ ] **Step 1: 写失败测试，验证 selection 只保留 selected 字段**

```dart
test('selection json ignores legacy default provider and model fields', () {
  final selection = LlmSelectionState.fromJson({
    'selected_provider_id': 'openai',
    'selected_model_id': 'gpt-5',
    'default_provider_id': 'legacy-provider',
    'default_model_id': 'legacy-model',
  });

  expect(selection.selectedProviderId, 'openai');
  expect(selection.selectedModelId, 'gpt-5');
  expect(selection.toJson().containsKey('default_provider_id'), isFalse);
  expect(selection.toJson().containsKey('default_model_id'), isFalse);
});
```

- [ ] **Step 2: 写失败测试，验证 repository 改成 `selected -> first`**

```dart
test('getLlmConfig falls back to first provider and first model when selected is invalid',
    () async {
  final repository = await createRepositoryWithProviders([
    provider('openai', models: ['gpt-5']),
    provider('anthropic', models: ['claude-sonnet']),
  ]);

  await repository.saveSelectionState(
    const LlmSelectionState(
      selectedProviderId: 'missing',
      selectedModelId: 'missing-model',
    ),
  );

  final config = await repository.getLlmConfig();
  expect(config.apiUrl, 'https://api.openai.com/v1');
  expect(config.model, 'gpt-5');
});
```

- [ ] **Step 3: 运行失败测试**

Run:
- `fvm flutter test test/repositories/app_settings_repository_test.dart`
- `fvm flutter test test/services/session_llm_config_resolver_test.dart`

Expected: FAIL，因为当前实现仍读取/写回 `default*`

- [ ] **Step 4: 最小实现 `LlmSelectionState` 收缩**

```dart
class LlmSelectionState {
  final String? selectedProviderId;
  final String? selectedModelId;
}
```

同时删除：

- `defaultProviderId`
- `defaultModelId`
- `clearDefaultProviderId`
- `clearDefaultModelId`

- [ ] **Step 5: 最小实现 repository fallback 改造**

统一替换以下解析模式：

```dart
final resolvedProvider = _resolveProvider(
  providers,
  selection.selectedProviderId,
);
final resolvedModel = _resolveModel(
  resolvedProvider,
  selection.selectedModelId,
);
```

并删除：

- `setDefaultProviderAndModel(...)`
- `_normalizeSelection()` 中对 `default*` 的任何读写
- `ensureSeededProviders()` 中的 `default*` 写入

- [ ] **Step 6: 重跑测试**

Run:
- `fvm flutter test test/repositories/app_settings_repository_test.dart`
- `fvm flutter test test/services/session_llm_config_resolver_test.dart`

Expected: PASS

- [ ] **Step 7: 提交**

```bash
git add \
  lib/models/llm/llm_selection_state.dart \
  lib/repositories/app_settings_repository.dart \
  test/repositories/app_settings_repository_test.dart \
  test/services/session_llm_config_resolver_test.dart
git commit -m "refactor: remove default provider selection state"
```

## Task 2: 新会话改为继承当前 runtime，否则回退首项

**Files:**
- Modify: `lib/services/session_runtime_config_service.dart`
- Modify: `lib/controllers/chat_session_coordinator.dart`
- Test: `test/services/session_runtime_config_service_test.dart`
- Test: `test/controllers/chat_controller_test.dart`

- [ ] **Step 1: 写失败测试，验证新 draft 会话继承当前 runtime**

```dart
test('createDraftRuntime inherits current runtime when it remains valid', () async {
  final currentRuntime = SessionRuntimeConfig(
    groupId: 10,
    providerId: 'anthropic',
    modelId: 'claude-opus',
    providerStyle: ChatTurnProviderStyle.anthropic,
  );
  final service = createService(
    currentRuntime: currentRuntime,
    providers: [
      provider('anthropic', models: ['claude-opus', 'claude-haiku']),
    ],
  );

  final draft = await service.createDraftRuntime();
  expect(draft.providerId, 'anthropic');
  expect(draft.modelId, 'claude-opus');
});
```

- [ ] **Step 2: 写失败测试，验证 runtime 失效时回退首项**

```dart
test('createDraftRuntime falls back to first provider and first model when current runtime is invalid',
    () async {
  final service = createService(
    currentRuntime: SessionRuntimeConfig(
      groupId: 10,
      providerId: 'missing',
      modelId: 'missing-model',
      providerStyle: ChatTurnProviderStyle.openaiResponses,
    ),
    providers: [
      provider('openai', models: ['gpt-5']),
      provider('anthropic', models: ['claude-sonnet']),
    ],
  );

  final draft = await service.createDraftRuntime();
  expect(draft.providerId, 'openai');
  expect(draft.modelId, 'gpt-5');
});
```

- [ ] **Step 3: 运行失败测试**

Run:
- `fvm flutter test test/services/session_runtime_config_service_test.dart`
- `fvm flutter test test/controllers/chat_controller_test.dart`

Expected: FAIL，因为当前 draft runtime 仍走旧全局 default 初始化

- [ ] **Step 4: 最小实现 runtime 继承规则**

`SessionRuntimeConfigService.createDraftRuntime()` 改成：

```dart
Future<SessionRuntimeConfig> createDraftRuntime({
  SessionRuntimeConfig? currentRuntime,
}) async {
  final providers = await settingsRepository.getProviders();
  final inherited = _resolveRuntimeIfValid(currentRuntime, providers);
  final resolved = inherited ?? _resolveFirstAvailableRuntime(providers);
  return SessionRuntimeConfig(
    groupId: draftGroupId,
    providerId: resolved.providerId,
    modelId: resolved.modelId,
    providerStyle: resolved.providerStyle,
  );
}
```

并在 `ChatSessionCoordinator.createNewGroup()` 中把当前 runtime 传进去。

- [ ] **Step 5: 重跑测试**

Run:
- `fvm flutter test test/services/session_runtime_config_service_test.dart`
- `fvm flutter test test/controllers/chat_controller_test.dart`

Expected: PASS

- [ ] **Step 6: 提交**

```bash
git add \
  lib/services/session_runtime_config_service.dart \
  lib/controllers/chat_session_coordinator.dart \
  test/services/session_runtime_config_service_test.dart \
  test/controllers/chat_controller_test.dart
git commit -m "refactor: inherit runtime for new sessions"
```

## Task 3: 删除首页模型切换里的 default 写入

**Files:**
- Modify: `lib/widgets/chat_input.dart`
- Test: `test/widgets/chat_input_test.dart`

- [ ] **Step 1: 写失败测试，验证切换模型后不再调用 default 写入路径**

```dart
testWidgets('model picker updates current session runtime without writing default selection',
    (tester) async {
  final repository = SpyAppSettingsRepository(...);
  await pumpChatInput(tester, repository: repository);

  await openModelPickerAndSelect(tester, providerId: 'openai', modelId: 'gpt-5');

  expect(repository.setDefaultProviderAndModelCallCount, 0);
  expect(repository.lastSelectedProviderId, 'openai');
  expect(repository.lastSelectedModelId, 'gpt-5');
});
```

- [ ] **Step 2: 运行失败测试**

Run: `fvm flutter test test/widgets/chat_input_test.dart`
Expected: FAIL，因为当前实现仍写 `setDefaultProviderAndModel(...)`

- [ ] **Step 3: 删除 default 写入并保留最小状态同步**

删除：

```dart
await repository.setDefaultProviderAndModel(
  providerId: result.providerId,
  modelId: result.modelId,
);
```

如需要保留最小全局锚点，则改成：

```dart
await repository.selectProviderAndModel(
  providerId: result.providerId,
  modelId: result.modelId,
);
```

- [ ] **Step 4: 重跑测试**

Run: `fvm flutter test test/widgets/chat_input_test.dart`
Expected: PASS

- [ ] **Step 5: 提交**

```bash
git add lib/widgets/chat_input.dart test/widgets/chat_input_test.dart
git commit -m "refactor: stop writing default model selection"
```

## Task 4: 改造空态与 selection 归一化路径

**Files:**
- Modify: `lib/widgets/chat_message_list.dart`
- Modify: `lib/repositories/app_settings_repository.dart`
- Test: `test/widgets/chat_message_list_test.dart`
- Test: `test/repositories/app_settings_repository_test.dart`

- [ ] **Step 1: 写失败测试，验证空态判断只依赖 selected/首项回退**

```dart
testWidgets('empty state requires setup only when no valid first available model exists',
    (tester) async {
  final repository = await createRepositoryWithProviders([
    provider('openai', models: ['gpt-5']),
  ]);
  await repository.saveSelectionState(
    const LlmSelectionState(
      selectedProviderId: 'missing',
      selectedModelId: 'missing',
    ),
  );

  final state = await buildEmptyState(repository);
  expect(state.requiresSetup, isFalse);
});
```

- [ ] **Step 2: 写失败测试，验证 provider 删除后归一到首项**

```dart
test('deleting selected provider re-normalizes selection to first available provider and model',
    () async {
  final repository = await createRepositoryWithProviders([
    provider('openai', models: ['gpt-5']),
    provider('anthropic', models: ['claude-sonnet']),
  ]);
  await repository.saveSelectionState(
    const LlmSelectionState(
      selectedProviderId: 'anthropic',
      selectedModelId: 'claude-sonnet',
    ),
  );

  await repository.deleteProvider('anthropic');

  final selection = await repository.getSelectionState();
  expect(selection.selectedProviderId, 'openai');
  expect(selection.selectedModelId, 'gpt-5');
});
```

- [ ] **Step 3: 运行失败测试**

Run:
- `fvm flutter test test/widgets/chat_message_list_test.dart`
- `fvm flutter test test/repositories/app_settings_repository_test.dart`

Expected: FAIL，因为当前路径仍含 `default*` 假设

- [ ] **Step 4: 最小实现归一化逻辑**

统一使用：

```dart
final selectedProvider =
    _resolveProvider(availableProviders, selection.selectedProviderId) ??
    availableProviders.first;
final selectedModel = _resolveModel(
  selectedProvider,
  selection.selectedModelId,
);
```

并在 `chat_message_list.dart` 中删除对 `defaultProviderId/defaultModelId` 的读取。

- [ ] **Step 5: 重跑测试**

Run:
- `fvm flutter test test/widgets/chat_message_list_test.dart`
- `fvm flutter test test/repositories/app_settings_repository_test.dart`

Expected: PASS

- [ ] **Step 6: 提交**

```bash
git add \
  lib/widgets/chat_message_list.dart \
  lib/repositories/app_settings_repository.dart \
  test/widgets/chat_message_list_test.dart \
  test/repositories/app_settings_repository_test.dart
git commit -m "refactor: normalize selection with first-item fallback"
```

## Task 5: 新增 provider 级 `sideModelId`，默认空值即主模型

**Files:**
- Modify: `lib/models/llm/llm_provider_config.dart`
- Modify: `lib/pages/provider_form_page.dart`
- Modify: `lib/services/session_runtime_config_service.dart`
- Test: `test/models/llm/llm_provider_config_test.dart`
- Test: `test/pages/provider_form_page_test.dart`

- [ ] **Step 1: 写失败测试，验证 provider 可持久化 side model**

```dart
test('provider config serializes optional side model id', () {
  const config = LlmProviderConfig(
    id: 'claude',
    name: 'Claude',
    apiKey: 'key',
    baseUrl: 'https://api.anthropic.com/v1/messages',
    sideModelId: 'claude-haiku',
    models: [
      LlmProviderModel(id: 'claude-opus', name: 'Claude Opus'),
      LlmProviderModel(id: 'claude-haiku', name: 'Claude Haiku'),
    ],
  );

  final json = config.toJson();
  expect(json['side_model_id'], 'claude-haiku');
  expect(LlmProviderConfig.fromJson(json).sideModelId, 'claude-haiku');
});
```

- [ ] **Step 2: 写失败测试，验证未指定 side model 时语义保持为空**

```dart
test('provider side model remains null when user does not specify it', () {
  const config = LlmProviderConfig(
    id: 'claude',
    name: 'Claude',
    apiKey: 'key',
    baseUrl: 'https://api.anthropic.com/v1/messages',
    models: [LlmProviderModel(id: 'claude-opus', name: 'Claude Opus')],
  );

  expect(config.sideModelId, isNull);
});
```

- [ ] **Step 3: 运行失败测试**

Run:
- `fvm flutter test test/models/llm/llm_provider_config_test.dart`
- `fvm flutter test test/pages/provider_form_page_test.dart`

Expected: FAIL，因为当前 provider config 还没有 `sideModelId`

- [ ] **Step 4: 最小实现数据模型与表单**

在 `LlmProviderConfig` 增加：

```dart
final String? sideModelId;
```

在 `ProviderFormPage`：

- 当模型列表非空时提供可选 `side model` 选择行
- 默认不选
- 只允许选当前 provider 下已有模型
- 若用户清空，则保存 `null`

- [ ] **Step 5: 为 runtime 解析补最小测试**

```dart
test('side slot falls back to primary when provider side model is unset', () async {
  ...
});
```

- [ ] **Step 6: 重跑测试**

Run:
- `fvm flutter test test/models/llm/llm_provider_config_test.dart`
- `fvm flutter test test/pages/provider_form_page_test.dart`
- `fvm flutter test test/services/session_runtime_config_service_test.dart`

Expected: PASS

- [ ] **Step 7: 提交**

```bash
git add \
  lib/models/llm/llm_provider_config.dart \
  lib/pages/provider_form_page.dart \
  lib/services/session_runtime_config_service.dart \
  test/models/llm/llm_provider_config_test.dart \
  test/pages/provider_form_page_test.dart \
  test/services/session_runtime_config_service_test.dart
git commit -m "feat: add provider side model configuration"
```

## Task 6: 清理设置页与 provider 管理页中的默认概念

**Files:**
- Modify: `lib/pages/model_management_page.dart`
- Modify: `lib/pages/provider_form_page.dart`
- Modify: `lib/pages/settings_page.dart`
- Test: `test/pages/model_management_page_test.dart`
- Test: `test/pages/provider_form_page_test.dart`
- Test: `test/pages/settings_page_tool_settings_test.dart`

- [ ] **Step 1: 写失败测试，验证管理页不再展示“当前默认模型”**

```dart
testWidgets('model management emphasizes provider and model management instead of default model',
    (tester) async {
  await pumpModelManagementPage(tester);
  expect(find.text('当前默认模型'), findsNothing);
  expect(find.text('设为默认'), findsNothing);
  expect(find.text('新增 Provider'), findsOneWidget);
});
```

- [ ] **Step 2: 写失败测试，验证 provider 编辑页不再展示“设为默认”**

```dart
testWidgets('provider form removes set-as-default action', (tester) async {
  await pumpProviderForm(tester, provider: seededProvider());
  expect(find.text('设为默认'), findsNothing);
});
```

- [ ] **Step 3: 运行失败测试**

Run:
- `fvm flutter test test/pages/model_management_page_test.dart`
- `fvm flutter test test/pages/provider_form_page_test.dart`
- `fvm flutter test test/pages/settings_page_tool_settings_test.dart`

Expected: FAIL，因为页面仍围绕默认状态组织

- [ ] **Step 4: 最小实现文案与动作清理**

删除：

- `当前默认模型`
- `默认`
- `设为默认`
- 设置页摘要中的默认状态表述

改成围绕：

- 当前 provider / model 资源是否可用
- provider 数量
- 模型数量
- 进入管理页

- [ ] **Step 5: 重跑测试**

Run:
- `fvm flutter test test/pages/model_management_page_test.dart`
- `fvm flutter test test/pages/provider_form_page_test.dart`
- `fvm flutter test test/pages/settings_page_tool_settings_test.dart`

Expected: PASS

- [ ] **Step 6: 提交**

```bash
git add \
  lib/pages/model_management_page.dart \
  lib/pages/provider_form_page.dart \
  lib/pages/settings_page.dart \
  test/pages/model_management_page_test.dart \
  test/pages/provider_form_page_test.dart \
  test/pages/settings_page_tool_settings_test.dart
git commit -m "refactor: remove default model management UI"
```

## Task 7: 确认生图配置不受主聊天 selection 去默认化影响

**Files:**
- Modify: `lib/services/image_generation_config_resolver.dart`
- Test: `test/services/image_generation_config_resolver_test.dart`

- [ ] **Step 1: 写失败测试，验证 image generation 继续独立解析**

```dart
test('image generation config resolves from dedicated provider and model settings only',
    () async {
  final config = await resolveImageGenerationConfig(
    providers: [
      provider('chat', models: ['gpt-5']),
      provider('image', models: ['gpt-image-2']),
    ],
    additionalConfig: {
      'image_generation.default_provider_id': 'image',
      'image_generation.default_model_id': 'gpt-image-2',
    },
    selection: const LlmSelectionState(
      selectedProviderId: 'chat',
      selectedModelId: 'gpt-5',
    ),
  );

  expect(config?.providerId, 'image');
  expect(config?.modelId, 'gpt-image-2');
});
```

- [ ] **Step 2: 运行失败测试**

Run: `fvm flutter test test/services/image_generation_config_resolver_test.dart`
Expected: FAIL only if resolver still hardcodes main selection fallback assumptions

- [ ] **Step 3: 最小实现或确认无需改动**

若已有实现已独立：

- 只更新测试与注释

若仍存在主 selection fallback：

- 删除该 fallback
- 只允许 dedicated image generation config + 支持生图模型列表

- [ ] **Step 4: 重跑测试**

Run: `fvm flutter test test/services/image_generation_config_resolver_test.dart`
Expected: PASS

- [ ] **Step 5: 提交**

```bash
git add \
  lib/services/image_generation_config_resolver.dart \
  test/services/image_generation_config_resolver_test.dart
git commit -m "test: lock image generation config independence"
```

## Task 8: 文档与全量验证收口

**Files:**
- Modify: `README.md`
- Modify: `AGENTS.md`

- [ ] **Step 1: 更新 README 中 provider/model 语义说明**

需要明确：

- 设置页不再维护 default provider/model
- 主模型以 session runtime 为准
- 新会话继承当前 runtime，失效时回退首项
- side model 为 provider 级可选配置
- 生图模型独立配置

- [ ] **Step 2: 如规则已变化，更新 AGENTS.md**

补充或替换与旧 default 语义冲突的说明。

- [ ] **Step 3: 运行串行验证**

Run:
- `fvm flutter test test/repositories/app_settings_repository_test.dart`
- `fvm flutter test test/services/session_runtime_config_service_test.dart`
- `fvm flutter test test/widgets/chat_input_test.dart`
- `fvm flutter test test/widgets/chat_message_list_test.dart`
- `fvm flutter test test/pages/model_management_page_test.dart`
- `fvm flutter test test/pages/provider_form_page_test.dart`
- `fvm flutter test test/pages/settings_page_tool_settings_test.dart`
- `fvm flutter analyze`

Expected: PASS

- [ ] **Step 4: 提交**

```bash
git add README.md AGENTS.md
git commit -m "docs: update provider model selection semantics"
```

## 交付检查

完成后应满足：

- 代码中不再存在 `defaultProviderId/defaultModelId`
- 不再存在 `setDefaultProviderAndModel(...)`
- 新会话从当前 runtime 或首项初始化
- 设置页与 provider 管理页不再暴露默认语义
- side model 可在 provider 级配置，默认空值即主模型
- 生图模型继续独立配置，不受主聊天 selection 影响
