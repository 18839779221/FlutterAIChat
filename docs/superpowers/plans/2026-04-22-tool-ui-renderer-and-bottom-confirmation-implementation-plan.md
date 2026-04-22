# Tool UI Renderer And Bottom Confirmation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在保持现有 tool 状态枚举和主数据结构稳定的前提下，引入工具专属 UI renderer、保留默认通用卡片兜底，并把 `requiresConfirmation` 交互迁移为底部统一确认区。

**Architecture:** 继续使用 `ChatSendCoordinator -> ChatBlockBuilder -> ChatMessageList` 的主链路，不新增强约束展示 schema。新增 renderer registry 作为 block 到 widget 的分发层，让工具专属 UI 直接消费 `ToolWorkflowStep.details` 与 `ToolResult.data`；默认卡片继续消费稳定通用字段作为 fallback。确认交互从 `ToolWorkflowCard` 内部移出，改由 `ChatPage` 底部统一确认条驱动原有 `confirmToolInvocation()` / `cancelToolInvocation()` 状态流。

**Tech Stack:** Flutter、Dart、Riverpod、flutter_test、fvm Flutter 3.29.2

---

## 文件边界

### 新增文件

- `lib/services/tool_ui_renderer_registry.dart`
  - 维护 workflow/result renderer 注册与查找逻辑。
- `lib/widgets/tool_confirmation/tool_confirmation_bottom_bar.dart`
  - 底部统一确认区，承载继续、取消、继续并信任操作。
- `lib/widgets/tool_renderers/write_tool_workflow_card.dart`
  - `Write` workflow 专属卡片。
- `lib/widgets/tool_renderers/write_tool_result_card.dart`
  - `Write` result 专属卡片。
- `lib/widgets/tool_renderers/edit_tool_workflow_card.dart`
  - `Edit` workflow 专属卡片。
- `lib/widgets/tool_renderers/edit_tool_result_card.dart`
  - `Edit` result 专属卡片。
- `lib/widgets/tool_renderers/web_search_tool_workflow_card.dart`
  - `web_search` workflow 专属卡片。
- `lib/widgets/tool_renderers/web_search_tool_result_card.dart`
  - `web_search` result 专属卡片。
- `lib/widgets/tool_renderers/fetch_webpage_tool_workflow_card.dart`
  - `fetch_webpage` workflow 专属卡片。
- `lib/widgets/tool_renderers/fetch_webpage_tool_result_card.dart`
  - `fetch_webpage` result 专属卡片。
- `test/services/tool_ui_renderer_registry_test.dart`
- `test/providers/active_pending_tool_confirmation_provider_test.dart`
- `test/widgets/tool_confirmation/tool_confirmation_bottom_bar_test.dart`
- `test/widgets/tool_renderers/write_tool_cards_test.dart`
- `test/widgets/tool_renderers/edit_tool_cards_test.dart`
- `test/widgets/tool_renderers/web_search_tool_cards_test.dart`
- `test/widgets/tool_renderers/fetch_webpage_tool_cards_test.dart`

### 修改文件

- `lib/widgets/chat_message_list.dart`
  - 改为通过 renderer registry 分发 tool workflow/result block。
- `lib/widgets/chat_blocks/tool_workflow_card.dart`
  - 收缩为纯兜底 workflow 展示，不再内置确认按钮。
- `lib/widgets/chat_blocks/tool_outcome_card.dart`
  - 保持兜底 result 卡片职责，必要时补少量通用字段。
- `lib/widgets/chat_blocks/tool_exception_card.dart`
  - 保持兜底异常卡片职责，必要时补少量通用字段。
- `lib/widgets/chat_blocks/tool_inline_step_row.dart`
  - 继续作为低噪音兜底 inline step。
- `lib/providers/chat_ui_providers.dart`
  - 新增 `activePendingToolConfirmationProvider`。
- `lib/pages/chat_page.dart`
  - 在消息列表与输入框之间接入底部统一确认区。
- `lib/services/chat_block_builder.dart`
  - 只做最小补充，确保专属 renderer 能稳定拿到 `sourceMessageId` 和现有 payload。
- `lib/models/chat/tool_workflow_step.dart`
  - 增补注释或小 helper，但不改主语义。
- `lib/models/tool/tool_result.dart`
  - 增补注释或小 helper，但不改主语义。
- `lib/providers/chat_providers.dart`
  - 接入 renderer registry provider（如放在 provider 组合入口）。
- `test/widgets/chat_message_list_test.dart`
- `test/services/chat_block_builder_test.dart`

### 删除文件

- `lib/widgets/tool_call/tool_invocation_card_widget.dart`
- `lib/widgets/tool_call/tool_result_card_widget.dart`
- `lib/widgets/tool_call/tool_confirmation_card_widget.dart`

### 实现完成后需要同步更新的文档

- `README.md`
- `AGENTS.md`
- `docs/superpowers/specs/2026-04-22-tool-ui-renderer-and-bottom-confirmation-design.md`

---

## Task 1: Add Renderer Registry Without Changing Existing State Models

**Files:**
- Create: `lib/services/tool_ui_renderer_registry.dart`
- Modify: `lib/providers/chat_providers.dart`
- Modify: `lib/models/chat/tool_workflow_step.dart`
- Modify: `lib/models/tool/tool_result.dart`
- Test: `test/services/tool_ui_renderer_registry_test.dart`

- [ ] **Step 1: Write failing registry tests**

新增测试，先锁定 registry 的最小行为：

```dart
test('returns null for unregistered workflow renderer', () {
  final registry = ToolUiRendererRegistry(renderers: const []);

  expect(registry.findWorkflowRenderer('Read'), isNull);
});

test('returns matching result renderer for Write', () {
  final registry = ToolUiRendererRegistry(
    renderers: [FakeWriteRenderer()],
  );

  expect(registry.findResultRenderer('Write'), isA<FakeWriteRenderer>());
});
```

- [ ] **Step 2: Run registry test to verify it fails**

Run:

```bash
fvm flutter test test/services/tool_ui_renderer_registry_test.dart
```

Expected: FAIL because the registry does not exist yet.

- [ ] **Step 3: Implement the registry and its provider wiring**

实现 `ToolUiRendererRegistry`，要求：

- 支持 workflow/result 两条查找路径
- 支持多个 renderer 注册
- 未命中时稳定返回 `null`
- 不在 registry 内硬编码具体工具展示逻辑

同时把 registry 接入 provider 组合入口，供 `ChatMessageList` 使用。

- [ ] **Step 4: Add only minimal helpers/comments on workflow and result models**

仅补充对 renderer 有价值的稳定说明或 helper，例如：

- 继续保留 `details` 作为 workflow 原始参数来源
- 继续保留 `data` 作为 result 原始结果来源
- 不新增统一展示 schema

- [ ] **Step 5: Re-run the registry test**

Run:

```bash
fvm flutter test test/services/tool_ui_renderer_registry_test.dart
```

Expected: PASS.

- [ ] **Step 6: Commit the registry foundation**

```bash
git add \
  lib/services/tool_ui_renderer_registry.dart \
  lib/providers/chat_providers.dart \
  lib/models/chat/tool_workflow_step.dart \
  lib/models/tool/tool_result.dart \
  test/services/tool_ui_renderer_registry_test.dart
git commit -m "feat: add tool ui renderer registry"
```

---

## Task 2: Move Confirmation Actions Into a Bottom Bar

**Files:**
- Create: `lib/widgets/tool_confirmation/tool_confirmation_bottom_bar.dart`
- Modify: `lib/providers/chat_ui_providers.dart`
- Modify: `lib/pages/chat_page.dart`
- Modify: `lib/widgets/chat_blocks/tool_workflow_card.dart`
- Test: `test/providers/active_pending_tool_confirmation_provider_test.dart`
- Test: `test/widgets/tool_confirmation/tool_confirmation_bottom_bar_test.dart`

- [ ] **Step 1: Write failing provider tests for active pending confirmation**

新增测试，覆盖：

- 只选中最新未决的确认消息
- 已被替换为 running/result/plainText 的旧确认消息不会再被选中
- 无确认消息时返回 `null`

示例：

```dart
test('selects the latest awaiting confirmation tool message', () {
  // 构造两条 actionConfirmation/toolInvocation message，
  // 断言 provider 只返回最新且仍 awaitingConfirmation 的那条。
});
```

- [ ] **Step 2: Write failing widget tests for the bottom bar**

至少覆盖：

- 展示工具名称和摘要
- 点击 `继续` 调用 `confirmToolInvocation`
- 点击 `取消` 调用 `cancelToolInvocation`
- 点击 `继续，以后不再确认` 调用带 `trustTool: true` 的确认方法

- [ ] **Step 3: Run the new tests to confirm failure**

Run:

```bash
fvm flutter test test/providers/active_pending_tool_confirmation_provider_test.dart
fvm flutter test test/widgets/tool_confirmation/tool_confirmation_bottom_bar_test.dart
```

Expected: FAIL because the provider and bottom bar do not exist yet.

- [ ] **Step 4: Implement the active-pending provider**

在 `chat_ui_providers.dart` 中实现 `activePendingToolConfirmationProvider`，要求：

- 基于 `messagesProvider`
- 识别 `awaitingConfirmation` 的 tool invocation / action confirmation message
- 与 `activeAskUserQuestionMessageProvider` 一样遵循“最新未解决优先”

- [ ] **Step 5: Implement the bottom confirmation bar**

实现 `ToolConfirmationBottomBar`，要求：

- 展示工具显示名、摘要、状态提示
- 承载三个统一动作按钮
- 视觉上独立于具体工具卡片
- 不解析工具专属细节，只展示必要确认上下文

- [ ] **Step 6: Integrate the bar into ChatPage**

在 [chat_page.dart](/Users/skka/flutterSpace/FlutterAIChat/lib/pages/chat_page.dart) 中将其放在：

- `ChatMessageList`
- `ChatInput`

之间，仅在 provider 返回活动确认消息时显示。

- [ ] **Step 7: Remove inline confirmation buttons from ToolWorkflowCard**

从兜底 `ToolWorkflowCard` 中移除：

- `onContinue`
- `onCancel`
- `onContinueAndTrust`
- 确认按钮 UI

保留待确认状态标签与高亮表达。

- [ ] **Step 8: Re-run provider and widget tests**

Run:

```bash
fvm flutter test test/providers/active_pending_tool_confirmation_provider_test.dart
fvm flutter test test/widgets/tool_confirmation/tool_confirmation_bottom_bar_test.dart
```

Expected: PASS.

- [ ] **Step 9: Commit the bottom-confirmation refactor**

```bash
git add \
  lib/widgets/tool_confirmation/tool_confirmation_bottom_bar.dart \
  lib/providers/chat_ui_providers.dart \
  lib/pages/chat_page.dart \
  lib/widgets/chat_blocks/tool_workflow_card.dart \
  test/providers/active_pending_tool_confirmation_provider_test.dart \
  test/widgets/tool_confirmation/tool_confirmation_bottom_bar_test.dart
git commit -m "feat: move tool confirmation into bottom bar"
```

---

## Task 3: Route Tool Blocks Through the Registry With Default Fallback

**Files:**
- Modify: `lib/widgets/chat_message_list.dart`
- Modify: `lib/services/chat_block_builder.dart`
- Test: `test/widgets/chat_message_list_test.dart`
- Test: `test/services/chat_block_builder_test.dart`

- [ ] **Step 1: Add failing list-rendering tests for registry dispatch**

新增测试，覆盖：

- 已注册工具命中专属 renderer
- 未注册工具继续走 `ToolWorkflowCard` 或现有兜底 result 卡片
- workflow/result 都能独立 fallback

- [ ] **Step 2: Run the message-list tests to verify they fail**

Run:

```bash
fvm flutter test test/widgets/chat_message_list_test.dart
fvm flutter test test/services/chat_block_builder_test.dart
```

Expected: FAIL because the list still hardcodes direct widget selection.

- [ ] **Step 3: Refactor ChatMessageList to use the registry**

改造 `toolWorkflow` / `toolResultSummary` 分支：

- 先查 registry
- 命中专属 renderer 则优先渲染
- 未命中再走当前兜底卡片

要求：

- 不破坏 `AskUserQuestion` 与普通 assistant block 的现有行为
- 不把工具名判断散落回 `ChatMessageList`

- [ ] **Step 4: Keep block-builder changes minimal**

如需补充 metadata，只允许：

- 保持 `sourceMessageId`
- 保持 `steps`
- 保持 `result.toJson()` 的稳定 payload

不要借机重构 block payload schema。

- [ ] **Step 5: Re-run message-list and block-builder tests**

Run:

```bash
fvm flutter test test/widgets/chat_message_list_test.dart
fvm flutter test test/services/chat_block_builder_test.dart
```

Expected: PASS.

- [ ] **Step 6: Commit registry-based dispatch**

```bash
git add \
  lib/widgets/chat_message_list.dart \
  lib/services/chat_block_builder.dart \
  test/widgets/chat_message_list_test.dart \
  test/services/chat_block_builder_test.dart
git commit -m "refactor: route tool blocks through renderer registry"
```

---

## Task 4: Add Write/Edit Custom Renderers

**Files:**
- Create: `lib/widgets/tool_renderers/write_tool_workflow_card.dart`
- Create: `lib/widgets/tool_renderers/write_tool_result_card.dart`
- Create: `lib/widgets/tool_renderers/edit_tool_workflow_card.dart`
- Create: `lib/widgets/tool_renderers/edit_tool_result_card.dart`
- Modify: `lib/services/tool_ui_renderer_registry.dart`
- Test: `test/widgets/tool_renderers/write_tool_cards_test.dart`
- Test: `test/widgets/tool_renderers/edit_tool_cards_test.dart`

- [ ] **Step 1: Write failing tests for Write cards**

至少覆盖：

- workflow 卡显示文件路径与新建/覆盖语义
- result 卡默认显示文件路径、前后长度、状态
- 展开区显示 `filePreviouslyExisted`、`fileVersion`、`postWriteData`

- [ ] **Step 2: Write failing tests for Edit cards**

至少覆盖：

- workflow 卡显示文件路径与 `replace_all`
- result 卡默认显示替换次数与长度变化
- 展开区显示 `replacementCount` 与关键替换摘要

- [ ] **Step 3: Run the file-tool renderer tests to confirm failure**

Run:

```bash
fvm flutter test test/widgets/tool_renderers/write_tool_cards_test.dart
fvm flutter test test/widgets/tool_renderers/edit_tool_cards_test.dart
```

Expected: FAIL because the custom renderers do not exist yet.

- [ ] **Step 4: Implement Write custom cards**

要求默认摘要先回答：

- 写了哪个文件
- 新建还是覆盖
- 改动量多大

展开区再回答：

- `oldLength`
- `newLength`
- `fileVersion`
- `postWriteData`

- [ ] **Step 5: Implement Edit custom cards**

要求默认摘要先回答：

- 改了哪个文件
- 替换了几处
- 是否 `replace_all`

展开区再回答：

- `replacementCount`
- 长度变化
- `old_string` / `new_string` 摘要

- [ ] **Step 6: Register Write/Edit renderers**

将 `Write`、`Edit` 接入 registry，要求：

- workflow 与 result 都可命中专属 renderer
- 未命中时仍能 fallback

- [ ] **Step 7: Re-run the file-tool renderer tests**

Run:

```bash
fvm flutter test test/widgets/tool_renderers/write_tool_cards_test.dart
fvm flutter test test/widgets/tool_renderers/edit_tool_cards_test.dart
```

Expected: PASS.

- [ ] **Step 8: Commit the file-tool custom renderers**

```bash
git add \
  lib/widgets/tool_renderers/write_tool_workflow_card.dart \
  lib/widgets/tool_renderers/write_tool_result_card.dart \
  lib/widgets/tool_renderers/edit_tool_workflow_card.dart \
  lib/widgets/tool_renderers/edit_tool_result_card.dart \
  lib/services/tool_ui_renderer_registry.dart \
  test/widgets/tool_renderers/write_tool_cards_test.dart \
  test/widgets/tool_renderers/edit_tool_cards_test.dart
git commit -m "feat: add custom renderers for write and edit tools"
```

---

## Task 5: Add web_search/fetch_webpage Custom Renderers

**Files:**
- Create: `lib/widgets/tool_renderers/web_search_tool_workflow_card.dart`
- Create: `lib/widgets/tool_renderers/web_search_tool_result_card.dart`
- Create: `lib/widgets/tool_renderers/fetch_webpage_tool_workflow_card.dart`
- Create: `lib/widgets/tool_renderers/fetch_webpage_tool_result_card.dart`
- Modify: `lib/services/tool_ui_renderer_registry.dart`
- Test: `test/widgets/tool_renderers/web_search_tool_cards_test.dart`
- Test: `test/widgets/tool_renderers/fetch_webpage_tool_cards_test.dart`

- [ ] **Step 1: Write failing tests for web_search cards**

至少覆盖：

- workflow 卡显示查询词和最大结果数
- result 卡默认显示查询词、结果数、主要来源概览
- 展开区显示标题、来源、snippet、URL 列表

- [ ] **Step 2: Write failing tests for fetch_webpage cards**

至少覆盖：

- workflow 卡显示 URL 与 extractMode
- result 卡默认显示网页标题与 host
- 展开区显示 URL、标题、正文预览

- [ ] **Step 3: Run the web-tool renderer tests to confirm failure**

Run:

```bash
fvm flutter test test/widgets/tool_renderers/web_search_tool_cards_test.dart
fvm flutter test test/widgets/tool_renderers/fetch_webpage_tool_cards_test.dart
```

Expected: FAIL because the custom renderers do not exist yet.

- [ ] **Step 4: Implement web_search custom cards**

默认摘要先回答：

- 搜了什么
- 找到多少结果
- 主要来源有哪些

展开区再展示：

- 标题
- 来源域名
- snippet
- URL

- [ ] **Step 5: Implement fetch_webpage custom cards**

默认摘要先回答：

- 读了哪个网页
- 网页标题是什么
- 是否提取到正文

展开区再展示：

- URL
- 标题
- 正文预览
- `extractMode`

- [ ] **Step 6: Register web_search and fetch_webpage renderers**

将两类工具接入 registry，保证 workflow/result 命中专属 UI。

- [ ] **Step 7: Re-run the web-tool renderer tests**

Run:

```bash
fvm flutter test test/widgets/tool_renderers/web_search_tool_cards_test.dart
fvm flutter test test/widgets/tool_renderers/fetch_webpage_tool_cards_test.dart
```

Expected: PASS.

- [ ] **Step 8: Commit the web-tool custom renderers**

```bash
git add \
  lib/widgets/tool_renderers/web_search_tool_workflow_card.dart \
  lib/widgets/tool_renderers/web_search_tool_result_card.dart \
  lib/widgets/tool_renderers/fetch_webpage_tool_workflow_card.dart \
  lib/widgets/tool_renderers/fetch_webpage_tool_result_card.dart \
  lib/services/tool_ui_renderer_registry.dart \
  test/widgets/tool_renderers/web_search_tool_cards_test.dart \
  test/widgets/tool_renderers/fetch_webpage_tool_cards_test.dart
git commit -m "feat: add custom renderers for web search tools"
```

---

## Task 6: Remove Legacy Tool-Call Widgets and Stabilize Fallbacks

**Files:**
- Delete: `lib/widgets/tool_call/tool_invocation_card_widget.dart`
- Delete: `lib/widgets/tool_call/tool_result_card_widget.dart`
- Delete: `lib/widgets/tool_call/tool_confirmation_card_widget.dart`
- Modify: `lib/widgets/chat_blocks/tool_outcome_card.dart`
- Modify: `lib/widgets/chat_blocks/tool_exception_card.dart`
- Modify: `lib/widgets/chat_blocks/tool_inline_step_row.dart`
- Test: `test/widgets/chat_message_list_test.dart`

- [ ] **Step 1: Confirm there are no remaining runtime references**

Run:

```bash
rg -n "ToolInvocationCardWidget|ToolResultCardWidget|ToolConfirmationCardWidget|widgets/tool_call" lib test
```

Expected: only definitions remain, or zero matches after integration is complete.

- [ ] **Step 2: Add one fallback regression test**

新增测试，覆盖一个未接入专属 renderer 的工具，例如 `Read`：

- workflow 仍显示默认 `ToolWorkflowCard`
- result 仍显示默认 fallback 卡片

- [ ] **Step 3: Run the fallback regression test and verify current status**

Run:

```bash
fvm flutter test test/widgets/chat_message_list_test.dart
```

Expected: PASS after the fallback path is stable.

- [ ] **Step 4: Delete the legacy tool_call widgets**

删除三份遗留组件，要求：

- 新链路已完全由 registry + 默认卡片覆盖
- 不保留第二套 card system

- [ ] **Step 5: Re-run the regression test**

Run:

```bash
fvm flutter test test/widgets/chat_message_list_test.dart
```

Expected: PASS.

- [ ] **Step 6: Commit the legacy cleanup**

```bash
git add \
  lib/widgets/chat_blocks/tool_outcome_card.dart \
  lib/widgets/chat_blocks/tool_exception_card.dart \
  lib/widgets/chat_blocks/tool_inline_step_row.dart \
  test/widgets/chat_message_list_test.dart
git rm \
  lib/widgets/tool_call/tool_invocation_card_widget.dart \
  lib/widgets/tool_call/tool_result_card_widget.dart \
  lib/widgets/tool_call/tool_confirmation_card_widget.dart
git commit -m "refactor: remove legacy tool call widgets"
```

---

## Task 7: Verify End-to-End Behavior and Update Docs

**Files:**
- Modify: `README.md`
- Modify: `AGENTS.md`
- Modify: `docs/superpowers/specs/2026-04-22-tool-ui-renderer-and-bottom-confirmation-design.md`

- [ ] **Step 1: Run focused widget and service tests**

Run:

```bash
fvm flutter test test/services/tool_ui_renderer_registry_test.dart
fvm flutter test test/providers/active_pending_tool_confirmation_provider_test.dart
fvm flutter test test/widgets/tool_confirmation/tool_confirmation_bottom_bar_test.dart
fvm flutter test test/widgets/tool_renderers/write_tool_cards_test.dart
fvm flutter test test/widgets/tool_renderers/edit_tool_cards_test.dart
fvm flutter test test/widgets/tool_renderers/web_search_tool_cards_test.dart
fvm flutter test test/widgets/tool_renderers/fetch_webpage_tool_cards_test.dart
fvm flutter test test/widgets/chat_message_list_test.dart
```

Expected: PASS.

- [ ] **Step 2: Run analyzer**

Run:

```bash
fvm flutter analyze
```

Expected: no new analyzer errors.

- [ ] **Step 3: Manually validate the four key scenarios**

手动或通过现有调试入口验证：

- `Write`：能看懂写入了哪个文件、是新建还是覆盖
- `Edit`：能看懂改了哪个文件、替换了几处
- `web_search`：能看懂搜了什么、命中了哪些来源
- `fetch_webpage`：能看懂打开了哪个网页、提取到了什么
- 待确认工具：按钮不再在卡片内，而在底部统一确认区

- [ ] **Step 4: Update docs**

更新：

- `README.md`：说明 tool UI 现支持专属 renderer 与底部统一确认
- `AGENTS.md`：补充 tool UI 的实现方向与确认交互约束
- spec 文档：补充实现偏差或最终决定

- [ ] **Step 5: Commit verification and docs**

```bash
git add \
  README.md \
  AGENTS.md \
  docs/superpowers/specs/2026-04-22-tool-ui-renderer-and-bottom-confirmation-design.md
git commit -m "docs: document custom tool renderers and bottom confirmation"
```

---

## 执行说明

- 优先按任务顺序推进，不要跳过底部统一确认区再做专属卡片，否则会把确认按钮逻辑继续带进专属 UI。
- 专属 renderer 可以先实现最小摘要 + 可展开细节，不要在第一轮加入复杂 diff 算法或新的 payload schema。
- 如果某个工具字段不足以支撑专属 UI，应优先做最小补充并写测试，不要直接引入新的通用展示层。

## 交付标准

完成后应满足：

1. 状态枚举仍使用现有 `ToolInvocationStatus`、`ToolWorkflowStepStatus`、`ToolExecutionStatus`
2. `ChatMessageList` 已通过 registry 分发工具卡片
3. `Write`、`Edit`、`web_search`、`fetch_webpage` 拥有专属 UI
4. 未定制工具仍可靠回退到默认通用卡片
5. 确认操作已从 tool 卡片内部迁移到底部统一确认区
6. 遗留 `widgets/tool_call/*` 已删除
7. 测试与 analyze 通过
