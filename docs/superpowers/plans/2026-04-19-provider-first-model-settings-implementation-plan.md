# Provider-First 模型设置改造 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 将单模型设置改造成 provider-first 的多提供方多模型配置体系，使用 `SharedPreferences` 持久化当前目录与选择态，并提供设置页摘要、管理页、表单页和真实模型测试。

**Architecture:** 运行时配置真相源从单值 `api_key/base_url/model` 升级为 `providers + selection` 两段式数据。`AppSettingsRepository` 负责首次导入 `config/local_defaults.json`、持久化 `SharedPreferences`、回退选择逻辑和最终 `LLMConfig` 解析；UI 层只消费当前摘要和管理动作，模型测试通过独立 service 使用指定 provider/model 临时构造请求。

**Tech Stack:** Flutter, Riverpod, SharedPreferences, http, flutter_test

---

### Task 1: Provider 数据模型与 local defaults 解析

**Files:**
- Create: `lib/models/llm/llm_provider_config.dart`
- Create: `lib/models/llm/llm_provider_model.dart`
- Create: `lib/models/llm/llm_selection_state.dart`
- Modify: `lib/repositories/llm_local_defaults.dart`
- Modify: `config/local_defaults.json`
- Modify: `config/local_defaults.example.json`
- Test: `test/repositories/llm_local_defaults_test.dart`

- [ ] **Step 1: Write the failing tests**

覆盖新 `providers` 顶层结构解析、`web_search` 附加配置保留、空 provider/model 过滤。

- [ ] **Step 2: Run test to verify it fails**

Run: `fvm flutter test test/repositories/llm_local_defaults_test.dart`
Expected: FAIL，旧解析器不认识 `providers`

- [ ] **Step 3: Write minimal implementation**

新增 provider/model/selection 三个数据对象，`llm_local_defaults.dart` 改为直接解析新的 provider-first 结构，不保留旧 schema fallback。

- [ ] **Step 4: Run test to verify it passes**

Run: `fvm flutter test test/repositories/llm_local_defaults_test.dart`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add lib/models/llm/llm_provider_config.dart lib/models/llm/llm_provider_model.dart lib/models/llm/llm_selection_state.dart lib/repositories/llm_local_defaults.dart config/local_defaults.json config/local_defaults.example.json test/repositories/llm_local_defaults_test.dart
git commit -m "feat: add provider-first local defaults parsing"
```

### Task 2: AppSettingsRepository provider-first 持久化

**Files:**
- Modify: `lib/repositories/app_settings_repository.dart`
- Modify: `test/repositories/app_settings_repository_test.dart`

- [ ] **Step 1: Write the failing tests**

覆盖首次 seed、读取 providers、保存 provider、删除 provider、保存 selection、`getLlmConfig()` 解析当前 provider/model 与回退逻辑。

- [ ] **Step 2: Run test to verify it fails**

Run: `fvm flutter test test/repositories/app_settings_repository_test.dart`
Expected: FAIL，现有 repository 只支持单模型 key

- [ ] **Step 3: Write minimal implementation**

将 `SharedPreferences` 改为 `llm.providers_json + llm.selection_json + llm.providers_seeded`，实现 provider/model 目录读写与选择态解析。

- [ ] **Step 4: Run test to verify it passes**

Run: `fvm flutter test test/repositories/app_settings_repository_test.dart`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add lib/repositories/app_settings_repository.dart test/repositories/app_settings_repository_test.dart
git commit -m "feat: persist provider-first model settings"
```

### Task 3: 模型测试 service

**Files:**
- Create: `lib/services/llm_model_test_service.dart`
- Create: `test/services/llm_model_test_service_test.dart`

- [ ] **Step 1: Write the failing tests**

覆盖指定 provider/model 测试成功、失败透传错误、不会依赖当前激活选择态。

- [ ] **Step 2: Run test to verify it fails**

Run: `fvm flutter test test/services/llm_model_test_service_test.dart`
Expected: FAIL，service 不存在

- [ ] **Step 3: Write minimal implementation**

抽出构造临时 `LLMConfig` 和最小测试请求逻辑，优先复用 `ApiProtocolResolver`。

- [ ] **Step 4: Run test to verify it passes**

Run: `fvm flutter test test/services/llm_model_test_service_test.dart`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add lib/services/llm_model_test_service.dart test/services/llm_model_test_service_test.dart
git commit -m "feat: add provider model test service"
```

### Task 4: 设置页摘要与管理页/表单页

**Files:**
- Modify: `lib/pages/settings_page.dart`
- Create: `lib/pages/model_management_page.dart`
- Create: `lib/pages/provider_form_page.dart`
- Modify: `test/pages/settings_page_tool_settings_test.dart`
- Create: `test/pages/model_management_page_test.dart`

- [ ] **Step 1: Write the failing tests**

覆盖设置页当前 provider/model 摘要、进入管理页、新增编辑删除 provider、切换当前模型与设默认。

- [ ] **Step 2: Run test to verify it fails**

Run: `fvm flutter test test/pages/settings_page_tool_settings_test.dart test/pages/model_management_page_test.dart`
Expected: FAIL，旧设置页仍是单模型表单

- [ ] **Step 3: Write minimal implementation**

设置页改为摘要入口，独立管理页提供 provider 列表与模型操作，表单页承载 provider 基础字段和模型列表编辑。

- [ ] **Step 4: Run test to verify it passes**

Run: `fvm flutter test test/pages/settings_page_tool_settings_test.dart test/pages/model_management_page_test.dart`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add lib/pages/settings_page.dart lib/pages/model_management_page.dart lib/pages/provider_form_page.dart test/pages/settings_page_tool_settings_test.dart test/pages/model_management_page_test.dart
git commit -m "feat: add provider-first model management ui"
```

### Task 5: 运行时接线与回归

**Files:**
- Modify: `lib/models/llm/configurable_http_llm.dart`
- Modify: `README.md`
- Modify: `AGENTS.md`
- Test: `test/models/llm/configurable_http_llm_test.dart`

- [ ] **Step 1: Write the failing tests**

覆盖 `ConfigurableHttpLLM` 读取当前 provider/model，切换选择后新请求命中新配置。

- [ ] **Step 2: Run test to verify it fails**

Run: `fvm flutter test test/models/llm/configurable_http_llm_test.dart`
Expected: FAIL 或断言不匹配，旧实现仍是单模型仓库心智

- [ ] **Step 3: Write minimal implementation**

校正运行时配置读取、验证错误信息，并更新 README/AGENTS 中的 provider-first 说明。

- [ ] **Step 4: Run test to verify it passes**

Run: `fvm flutter test test/models/llm/configurable_http_llm_test.dart`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add lib/models/llm/configurable_http_llm.dart README.md AGENTS.md test/models/llm/configurable_http_llm_test.dart
git commit -m "feat: wire provider-first runtime config"
```

### Final Verification

**Files:**
- Verify only

- [ ] **Step 1: Run focused test suite**

Run: `fvm flutter test test/repositories/llm_local_defaults_test.dart test/repositories/app_settings_repository_test.dart test/services/llm_model_test_service_test.dart test/pages/settings_page_tool_settings_test.dart test/pages/model_management_page_test.dart test/models/llm/configurable_http_llm_test.dart`
Expected: PASS

- [ ] **Step 2: Run broad regression checks**

Run: `fvm flutter analyze`
Expected: PASS 或仅存在与本任务无关的历史问题

- [ ] **Step 3: Sanity-check docs and config**

确认 `config/local_defaults.json`、`config/local_defaults.example.json`、`README.md`、`AGENTS.md` 与最终实现一致。
