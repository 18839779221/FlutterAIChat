# Create Artifact Guideline Token Contract Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 为解释增强型 artifact 增加 `create_artifact__guideline` 前置工具，并让 artifact WebView 通过项目级全局 design token 注入实现主题一致的原生化渲染。

**Architecture:** 在现有 `create_artifact` 管线旁新增一个只读前置 tool，用结构化 guideline 返回宿主包裹 contract、token 引用与渲染约束；同时扩展 `AppThemeSpec` 的全局可视化 token，并在 artifact 预览文档构建层把这些 token 映射成 CSS variables。`create_artifact` 与 `guideline` 仅通过 prompt-contract 协作，不增加 execution-time 硬阻断。

**Tech Stack:** Flutter 3.35.7（优先 `fvm flutter`）、flutter_riverpod、ThemeExtension(`AppThemeSpec`)、webview_flutter、flutter_test

---

## 文件边界

### 预计修改

- `lib/theme/app_theme_spec.dart`
  - 扩展项目级全局 artifact/chart 语义 token
- `lib/tools/handlers/create_artifact_tool_handler.dart`
  - 更新 `create_artifact` 的 `descriptionForModel`
- `lib/tools/default_tool_runtime_registry.dart`
  - 注册新的 `create_artifact__guideline`
- `lib/providers/chat_dependency_providers.dart`
  - 注入 guideline handler 需要的依赖
- `lib/widgets/chat_blocks/artifact_preview_surface.dart`
  - 接收主题 token 注入，主题变化时重载文档
- `README.md`
  - 更新 artifact 能力说明与设计语言对齐描述

### 预计新增

- `lib/models/artifact/artifact_guideline_contract.dart`
  - guideline tool 返回结果的数据模型
- `lib/services/artifact/artifact_theme_token_mapper.dart`
  - `AppThemeSpec -> artifact CSS variable` 映射
- `lib/services/artifact/artifact_guideline_contract_builder.dart`
  - 构建 guideline 返回的 JSON + host markup contract
- `lib/tools/handlers/create_artifact_guideline_tool_handler.dart`
  - 新的前置工具 handler
- `test/services/artifact/artifact_theme_token_mapper_test.dart`
  - token 映射测试
- `test/services/artifact/artifact_guideline_contract_builder_test.dart`
  - guideline contract 构建测试
- `test/tools/handlers/create_artifact_guideline_tool_handler_test.dart`
  - guideline tool handler 测试

### 重点回归

- `test/tools/handlers/create_artifact_tool_handler_test.dart`
- `test/widgets/chat_blocks/artifact_preview_surface_test.dart`
- `test/theme/app_theme_test.dart`
- 如需新增 provider 依赖回归：`test/providers/chat_dependency_providers_test.dart`

---

### Task 1: 扩展项目级 artifact / chart 全局 token

**Files:**
- Modify: `lib/theme/app_theme_spec.dart`
- Test: `test/theme/app_theme_test.dart`

- [ ] **Step 1: 先写 theme token 失败测试**

在 `test/theme/app_theme_test.dart` 增加断言，覆盖：

- `AppThemeSpec.claude()` 提供 artifact 页面背景、surface、text、border、accent
- `AppThemeSpec.claude()` 提供 chart-1 ~ chart-5、chart-grid、chart-axis、chart-highlight
- `AppThemeSpec.olivePaper()` 也提供同名 token

示例断言：

```dart
test('claude theme exposes artifact and chart semantic tokens', () {
  final spec = AppThemeSpec.claude();
  expect(spec.artifactPageBackground, isNotNull);
  expect(spec.artifactChart1, isNotNull);
  expect(spec.artifactChartGrid, isNotNull);
});
```

- [ ] **Step 2: 运行测试确认失败**

Run: `fvm flutter test test/theme/app_theme_test.dart`

Expected: FAIL，提示缺少新的 token getter 或字段。

- [ ] **Step 3: 在 `AppThemeSpec` 中补齐语义 token**

在 `lib/theme/app_theme_spec.dart`：

- 为 artifact/WebView 暴露稳定 getter
- 优先复用现有 `surfaces / text / state / interaction`
- 新增最小够用的 chart 语义 token

建议补齐的 getter 方向：

```dart
Color get artifactPageBackground => ...;
Color get artifactSurface => ...;
Color get artifactSurfaceMuted => ...;
Color get artifactTextPrimary => ...;
Color get artifactTextSecondary => ...;
Color get artifactTextTertiary => ...;
Color get artifactBorderSubtle => ...;
Color get artifactBorderStrong => ...;
Color get artifactAccent => ...;
Color get artifactChart1 => ...;
Color get artifactChart2 => ...;
Color get artifactChart3 => ...;
Color get artifactChart4 => ...;
Color get artifactChart5 => ...;
Color get artifactChartGrid => ...;
Color get artifactChartAxis => ...;
Color get artifactChartHighlight => ...;
```

- [ ] **Step 4: 运行测试确认通过**

Run: `fvm flutter test test/theme/app_theme_test.dart`

Expected: PASS

- [ ] **Step 5: 提交**

```bash
git add lib/theme/app_theme_spec.dart test/theme/app_theme_test.dart
git commit -m "feat(theme): add artifact semantic tokens"
```

---

### Task 2: 新增 artifact token mapper 与 guideline contract builder

**Files:**
- Create: `lib/models/artifact/artifact_guideline_contract.dart`
- Create: `lib/services/artifact/artifact_theme_token_mapper.dart`
- Create: `lib/services/artifact/artifact_guideline_contract_builder.dart`
- Test: `test/services/artifact/artifact_theme_token_mapper_test.dart`
- Test: `test/services/artifact/artifact_guideline_contract_builder_test.dart`

- [ ] **Step 1: 先写 token mapper 失败测试**

在 `test/services/artifact/artifact_theme_token_mapper_test.dart` 增加测试，覆盖：

- mapper 会把 `AppThemeSpec` 映射为稳定 CSS variable 名
- 返回值包含 page/surface/text/border/accent/chart/scale/font/shadow
- 不泄露 Flutter 内部字段名到外部 contract

示例断言：

```dart
test('maps app theme spec to stable artifact css variables', () {
  final variables = ArtifactThemeTokenMapper.fromSpec(AppThemeSpec.claude());
  expect(variables['--app-artifact-page-bg'], isNotEmpty);
  expect(variables['--app-artifact-chart-1'], isNotEmpty);
  expect(variables.containsKey('--semantic.surfaces.pageBackground'), isFalse);
});
```

- [ ] **Step 2: 先写 guideline builder 失败测试**

在 `test/services/artifact/artifact_guideline_contract_builder_test.dart` 增加测试，覆盖：

- `usage` 为简短职责说明
- `host_markup_contract` 以代码片段形式包含 `:root`、`html, body`、`#artifact-root`
- `layout_constraints` 和 `rendering_rules` 非空
- contract 不直接暴露具体运行时文件路径或实现细节

- [ ] **Step 3: 运行测试确认失败**

Run: `fvm flutter test test/services/artifact/artifact_theme_token_mapper_test.dart test/services/artifact/artifact_guideline_contract_builder_test.dart`

Expected: FAIL，提示类或方法不存在。

- [ ] **Step 4: 实现 contract 数据模型**

在 `lib/models/artifact/artifact_guideline_contract.dart` 定义：

```dart
class ArtifactGuidelineContract {
  final String usage;
  final String hostMarkupContract;
  final List<String> layoutConstraints;
  final List<String> renderingRules;

  Map<String, dynamic> toJson() { ... }
}
```

为公开字段写简短注释，说明其模型侧用途。

- [ ] **Step 5: 实现 token mapper**

在 `lib/services/artifact/artifact_theme_token_mapper.dart`：

- 输入 `AppThemeSpec`
- 输出 `Map<String, String>`
- 统一负责颜色、spacing、radius、font、shadow 到 CSS variable 的字符串映射

- [ ] **Step 6: 实现 guideline contract builder**

在 `lib/services/artifact/artifact_guideline_contract_builder.dart`：

- 依赖 token mapper
- 生成 `usage`
- 生成代码化 `hostMarkupContract`
- 生成默认 `layoutConstraints`
- 生成默认 `renderingRules`

`hostMarkupContract` 中应直接内嵌真实 token 名示意，例如：

```html
<style>
  :root {
    --app-artifact-page-bg: ...;
    --app-artifact-chart-1: ...;
  }
</style>
```

- [ ] **Step 7: 运行测试确认通过**

Run: `fvm flutter test test/services/artifact/artifact_theme_token_mapper_test.dart test/services/artifact/artifact_guideline_contract_builder_test.dart`

Expected: PASS

- [ ] **Step 8: 提交**

```bash
git add lib/models/artifact/artifact_guideline_contract.dart lib/services/artifact/artifact_theme_token_mapper.dart lib/services/artifact/artifact_guideline_contract_builder.dart test/services/artifact/artifact_theme_token_mapper_test.dart test/services/artifact/artifact_guideline_contract_builder_test.dart
git commit -m "feat(artifact): add guideline contract builder"
```

---

### Task 3: 新增 `create_artifact__guideline` tool handler 与注册

**Files:**
- Create: `lib/tools/handlers/create_artifact_guideline_tool_handler.dart`
- Modify: `lib/tools/default_tool_runtime_registry.dart`
- Modify: `lib/providers/chat_dependency_providers.dart`
- Test: `test/tools/handlers/create_artifact_guideline_tool_handler_test.dart`
- Test: `test/providers/chat_dependency_providers_test.dart`

- [ ] **Step 1: 先写 guideline tool handler 失败测试**

在 `test/tools/handlers/create_artifact_guideline_tool_handler_test.dart` 增加测试，覆盖：

- tool name 为 `create_artifact__guideline`
- `descriptionForModel` 包含首次 `create_artifact` 前必须先读 guideline 的 `IMPORTANT:` 约束
- 返回结果包含 `usage / host_markup_contract / layout_constraints / rendering_rules`

示例断言：

```dart
test('guideline tool description requires first-call pairing', () {
  final handler = buildHandler();
  expect(handler.definition.name, 'create_artifact__guideline');
  expect(handler.definition.descriptionForModel, contains('IMPORTANT:'));
  expect(
    handler.definition.descriptionForModel,
    contains('before the first `create_artifact` call'),
  );
});
```

- [ ] **Step 2: 运行测试确认失败**

Run: `fvm flutter test test/tools/handlers/create_artifact_guideline_tool_handler_test.dart`

Expected: FAIL，提示 handler 不存在。

- [ ] **Step 3: 实现 guideline handler**

在 `lib/tools/handlers/create_artifact_guideline_tool_handler.dart`：

- 定义只读工具
- arguments 可保持最小，若无必要可不要求额外参数
- `descriptionForModel` 使用本次 spec 中确认的英文草案
- `execute()` 通过 `ArtifactGuidelineContractBuilder` 返回结构化结果

- [ ] **Step 4: 注册到默认 runtime registry**

在 `lib/tools/default_tool_runtime_registry.dart`：

- 导入新的 handler
- 确保其出现在 `create_artifact` 可见之前或附近，强调配套语义

- [ ] **Step 5: 接入 provider 依赖**

在 `lib/providers/chat_dependency_providers.dart`：

- 注入 `ArtifactThemeTokenMapper` / `ArtifactGuidelineContractBuilder`
- 构造 `CreateArtifactGuidelineToolHandler`

- [ ] **Step 6: 运行测试确认通过**

Run: `fvm flutter test test/tools/handlers/create_artifact_guideline_tool_handler_test.dart test/providers/chat_dependency_providers_test.dart`

Expected: PASS

- [ ] **Step 7: 提交**

```bash
git add lib/tools/handlers/create_artifact_guideline_tool_handler.dart lib/tools/default_tool_runtime_registry.dart lib/providers/chat_dependency_providers.dart test/tools/handlers/create_artifact_guideline_tool_handler_test.dart test/providers/chat_dependency_providers_test.dart
git commit -m "feat(artifact): add create_artifact guideline tool"
```

---

### Task 4: 收敛 `create_artifact` prompt contract

**Files:**
- Modify: `lib/tools/handlers/create_artifact_tool_handler.dart`
- Test: `test/tools/handlers/create_artifact_tool_handler_test.dart`

- [ ] **Step 1: 先写 prompt 文案回归测试**

在 `test/tools/handlers/create_artifact_tool_handler_test.dart` 增加或更新断言，覆盖：

- desc 开头包含 `IMPORTANT:`
- 明确要求首次解释增强型 `create_artifact` 前先调 `create_artifact__guideline`
- 删除“优先 `Read/Edit/Write` 继续改 artifact”的推荐描述
- 删除“透明背景优先”的旧描述

示例断言：

```dart
test('prompt requires guideline before first explanatory artifact creation', () {
  final description = buildHandler().definition.descriptionForModel;
  expect(description, contains('IMPORTANT:'));
  expect(description, contains('MUST first call `create_artifact__guideline`'));
  expect(description, isNot(contains('prefer using Read/Edit/Write')));
  expect(description, isNot(contains('background to transparent')));
});
```

- [ ] **Step 2: 运行测试确认失败**

Run: `fvm flutter test test/tools/handlers/create_artifact_tool_handler_test.dart`

Expected: FAIL，提示旧 prompt 内容不匹配。

- [ ] **Step 3: 更新 `create_artifact` 中英文 desc**

在 `lib/tools/handlers/create_artifact_tool_handler.dart`：

- 在英文与中文 desc 开头插入 guideline 前置规则
- 把背景建议改成“优先使用宿主提供的背景与 surface token”
- 去掉对 `Read/Edit/Write` 的推荐默认路径描述

- [ ] **Step 4: 运行测试确认通过**

Run: `fvm flutter test test/tools/handlers/create_artifact_tool_handler_test.dart`

Expected: PASS

- [ ] **Step 5: 提交**

```bash
git add lib/tools/handlers/create_artifact_tool_handler.dart test/tools/handlers/create_artifact_tool_handler_test.dart
git commit -m "feat(artifact): align create_artifact prompt contract"
```

---

### Task 5: 把项目级 token 注入 artifact 预览文档并处理主题变化重载

**Files:**
- Modify: `lib/widgets/chat_blocks/artifact_preview_surface.dart`
- Possibly Modify: `lib/models/artifact/runtime_artifact_preview.dart`
- Test: `test/widgets/chat_blocks/artifact_preview_surface_test.dart`

- [ ] **Step 1: 先写预览文档注入失败测试**

在 `test/widgets/chat_blocks/artifact_preview_surface_test.dart` 增加测试，覆盖：

- 构建出的预览文档包含 artifact CSS variables
- 文档中包含宿主级 `html, body` / `#artifact-root` 基础样式
- 主题标识变化时，即使 `source` 不变，也会触发重载

可先把 token 注入构建逻辑提取为纯函数，方便测试。

- [ ] **Step 2: 运行测试确认失败**

Run: `fvm flutter test test/widgets/chat_blocks/artifact_preview_surface_test.dart`

Expected: FAIL，提示文档中没有 token 注入或缺少主题变化路径。

- [ ] **Step 3: 扩展预览文档构建函数**

在 `lib/widgets/chat_blocks/artifact_preview_surface.dart`：

- 为 `buildArtifactPreviewDocument(...)` 增加 host token/style 注入能力
- 将 `AppThemeSpec` 映射后的 CSS variables 注入 `:root`
- 注入宿主基础规则：
  - `html, body`
  - `* { box-sizing: border-box; }`
  - `#artifact-root`

- [ ] **Step 4: 为 Widget 引入主题变化重载条件**

在 `ArtifactPreviewSurface`：

- 记录上次主题签名或 token 签名
- `didUpdateWidget` 中除 `source` 变化外，也监听主题 contract 变化
- 主题变化时重载 HTML，即使 `source` 未变化

- [ ] **Step 5: 运行测试确认通过**

Run: `fvm flutter test test/widgets/chat_blocks/artifact_preview_surface_test.dart`

Expected: PASS

- [ ] **Step 6: 提交**

```bash
git add lib/widgets/chat_blocks/artifact_preview_surface.dart test/widgets/chat_blocks/artifact_preview_surface_test.dart
git commit -m "feat(artifact): inject theme tokens into preview document"
```

---

### Task 6: 更新文档说明与回归验证

**Files:**
- Modify: `README.md`
- Modify: `docs/superpowers/specs/2026-05-26-create-artifact-guideline-token-contract-design.md`（如实现后需补充最终落地差异）

- [ ] **Step 1: 更新 README 中的 artifact 能力说明**

在 `README.md` 补充：

- `create_artifact__guideline` 的前置定位
- artifact 会复用项目级 design token 与主题语言
- 解释增强型 artifact 的原生化渲染方向

- [ ] **Step 2: 运行最小回归集**

Run:

```bash
fvm flutter test test/theme/app_theme_test.dart \
  test/services/artifact/artifact_theme_token_mapper_test.dart \
  test/services/artifact/artifact_guideline_contract_builder_test.dart \
  test/tools/handlers/create_artifact_guideline_tool_handler_test.dart \
  test/tools/handlers/create_artifact_tool_handler_test.dart \
  test/widgets/chat_blocks/artifact_preview_surface_test.dart
```

Expected: 全部 PASS

- [ ] **Step 3: 运行 analyze**

Run: `fvm flutter analyze`

Expected: 无新增 analyzer error

- [ ] **Step 4: 提交**

```bash
git add README.md docs/superpowers/specs/2026-05-26-create-artifact-guideline-token-contract-design.md
git commit -m "docs: document artifact guideline token workflow"
```

---

## 备注

- 本计划按最小可落地顺序组织：先补项目级 token，再补 guideline contract，再接 tool，再改预览渲染
- 本轮不实现 execution-time 硬阻断；如后续观测到模型经常跳过 guideline，再单独立题处理
- 本轮不把 `Read/Edit/Write` 设为 artifact 默认迭代路径，模型后续如何继续编辑由运行时自行决策
