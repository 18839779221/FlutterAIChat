# 最新消息底部连续运行状态尾注增量 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 让最新消息底部运行尾注在一个 `turn` 结束前尽量不断档，并采用系统动作视角文案，支持“单工具具体化、并行退化为正在执行工具”，同时去掉尾注的块状边框感。

**Architecture:** 在现有 `ChatSendPhase`、最新消息块装配层和 tool workflow 数据之上增加一个专门的状态解析器，统一输出“是否显示尾注 + 当前系统动作文案”。消息列表只负责挂载，尾注组件只负责渲染，避免把连续性规则和并行判断散落在多个 widget 中。

**Tech Stack:** Flutter、Dart、flutter_riverpod、现有 `ChatSendPhase` / tool workflow / widget tests

---

## 文件结构与职责

### 现有文件

- `lib/widgets/chat_message_list.dart`
  - 当前负责最新 assistant/tool block 的装配与尾注挂载；本次继续作为挂载入口，但不再直接内嵌复杂文案判断。
- `lib/widgets/chat_blocks/latest_message_running_status_tail.dart`
  - 当前尾注渲染组件；本次要去边框化、去底色块感，收轻为动态脚注。
- `lib/providers/chat_send_state_providers.dart`
  - 当前只有 `phase` 和 `isGenerating`；本次评估是否需要增加“发送事务仍活跃”的辅助语义，或在 resolver 层组合已有状态。
- `lib/controllers/chat_send_coordinator.dart`
  - 当前管理 send transaction 生命周期；需要确认尾注“持续显示到 turn 结束”所需的运行态信号是否足够。
- `lib/controllers/agent_event_processor.dart`
  - 当前根据事件驱动 `chatSendStateProvider`；需要检查是否存在 phase 空窗期导致尾注断档。
- `test/widgets/chat_message_list_test.dart`
  - 当前已有尾注基础测试；本次作为连续性、并行降级和文案映射的主要测试入口。
- `test/widgets/chat_input_test.dart`
  - 保持输入区不再显示旧状态文案的回归测试。

### 新增文件

- `lib/services/latest_message_running_status_resolver.dart`
  - 新增专门解析器，统一输出：
    - 当前是否应展示尾注
    - 当前应显示的系统动作文案
    - 并行场景是否退化为 `正在执行工具`

## 实现原则

- 不新增新的 UI 状态机。
- 尽量基于现有 `ChatSendPhase`、tool workflow steps、最新消息块信息进行解析。
- 优先保证“不断档”，其次才是文案尽量具体。
- 单工具明确时显示具体动作；并行或主动作不明确时退化为 `正在执行工具`。
- 尾注必须去块化，不保留边框感或独立卡片感。

## 任务拆解

### Task 1: 固化连续性与文案规则的测试

**Files:**
- Modify: `test/widgets/chat_message_list_test.dart`
- Modify: `test/widgets/chat_input_test.dart`

- [ ] **Step 1: 为“turn 未结束前尾注不断档”写失败测试**

补至少这些用例：

- `preparing` 阶段显示 `正在请求模型` 或 `正在规划下一步`
- `executingTool` 阶段显示尾注
- `streamingResponse` 阶段显示 `正在生成回复`
- `idle` 时尾注消失

重点是验证：

- 非 `idle` 时尾注都存在
- 文案随阶段切换，但尾注本体不消失

- [ ] **Step 2: 为并行场景写失败测试**

构造最新 workflow block 对应多个 running steps 的场景，断言：

- 不显示某个具体工具文案
- 统一显示 `正在执行工具`

- [ ] **Step 3: 为单工具具体化写失败测试**

至少补：

- 单个 `web_search` -> `正在联网搜索`
- 单个 `fetch_webpage` -> `正在读取网页`
- 单个 `Read` -> `正在读取文件`

- [ ] **Step 4: 为尾注视觉去块化保留最小结构测试**

不要求像素测试，但可以断言：

- 仍存在尾注 key
- 不再依赖独立背景块 key / 容器语义

- [ ] **Step 5: 运行测试，确认新增用例先失败**

Run:

```bash
"$HOME/.pub-cache/bin/fvm" flutter test test/widgets/chat_message_list_test.dart test/widgets/chat_input_test.dart
```

Expected:
- 新增连续性、并行降级或具体文案测试失败

- [ ] **Step 6: 提交这一小步**

```bash
git add test/widgets/chat_message_list_test.dart test/widgets/chat_input_test.dart
git commit -m "test: cover continuous running tail behavior"
```

### Task 2: 引入尾注状态解析器

**Files:**
- Create: `lib/services/latest_message_running_status_resolver.dart`
- Modify: `lib/widgets/chat_message_list.dart`
- Test: `test/widgets/chat_message_list_test.dart`

- [ ] **Step 1: 创建 resolver 的最小接口**

定义一个轻量结果模型，例如：

- `bool isVisible`
- `String? statusText`

输入建议包含：

- 当前 `ChatSendPhase`
- 当前最新 block
- 当前 block 所属 steps / tool 信息
- 当前活跃工具数量

- [ ] **Step 2: 先实现模型阶段文案**

先支持：

- `preparing -> 正在请求模型` 或 `正在规划下一步`
- `streamingResponse -> 正在生成回复`
- `idle -> 不显示`

此阶段先不做工具并行逻辑。

- [ ] **Step 3: 在消息列表中替换当前内联文案判断**

把 `chat_message_list.dart` 里现有的：

- `_latestRunningTailText`
- `_toolRunningText`

迁移为调用 resolver，避免逻辑继续堆在 widget 中。

- [ ] **Step 4: 运行定向测试**

Run:

```bash
"$HOME/.pub-cache/bin/fvm" flutter test test/widgets/chat_message_list_test.dart --plain-name "streaming"
```

Expected:
- 模型阶段尾注测试通过

- [ ] **Step 5: 提交这一小步**

```bash
git add lib/services/latest_message_running_status_resolver.dart lib/widgets/chat_message_list.dart test/widgets/chat_message_list_test.dart
git commit -m "refactor: resolve running tail status via dedicated resolver"
```

### Task 3: 实现单工具具体化与并行退化规则

**Files:**
- Modify: `lib/services/latest_message_running_status_resolver.dart`
- Modify: `lib/widgets/chat_message_list.dart`
- Test: `test/widgets/chat_message_list_test.dart`

- [ ] **Step 1: 为 resolver 增加活跃工具判定**

在 resolver 中根据当前 latest workflow / available steps 识别：

- 当前是否只有一个活跃工具
- 当前是否有多个活跃工具

注意：

- 活跃工具判定基于 running / awaiting-like active 状态
- 若无法安全判断唯一主动作，则按并行或不明确处理

- [ ] **Step 2: 加入单工具具体文案映射**

先支持：

- `web_search -> 正在联网搜索`
- `fetch_webpage -> 正在读取网页`
- `Read -> 正在读取文件`
- `LS -> 正在列出目录`
- `Grep -> 正在搜索文件内容`
- `Glob -> 正在查找文件`

- [ ] **Step 3: 加入并行退化规则**

当存在多个活跃工具时，统一返回：

- `正在执行工具`

不要因为最新消息块是某个具体工具卡片就仍返回具体文案。

- [ ] **Step 4: 加入短暂兜底文案**

若当前 `turn` 仍活跃，但既拿不到具体工具动作，也不属于模型输出阶段，则返回：

- `正在等待结果`

此处只作为桥接，不作为主常态。

- [ ] **Step 5: 运行定向测试**

Run:

```bash
"$HOME/.pub-cache/bin/fvm" flutter test test/widgets/chat_message_list_test.dart --plain-name "running tail"
```

Expected:
- 单工具具体化测试通过
- 并行退化测试通过

- [ ] **Step 6: 提交这一小步**

```bash
git add lib/services/latest_message_running_status_resolver.dart lib/widgets/chat_message_list.dart test/widgets/chat_message_list_test.dart
git commit -m "feat: support specific and parallel-safe running tail text"
```

### Task 4: 去块化尾注视觉

**Files:**
- Modify: `lib/widgets/chat_blocks/latest_message_running_status_tail.dart`
- Modify: `lib/widgets/tool_renderers/tool_running_effects.dart`
- Test: `test/widgets/chat_message_list_test.dart`

- [ ] **Step 1: 为尾注轻量化调整写失败测试或结构断言**

如果测试不好直接验证外观，至少新增结构约束：

- 尾注仍是一行附注
- 不引入新的卡片容器层

- [ ] **Step 2: 移除尾注的块状装饰**

在 `latest_message_running_status_tail.dart` 中：

- 去掉明显 `BoxDecoration` 背景块
- 不使用边框
- 保留更轻的间距

- [ ] **Step 3: 调整 sweep 只做轻提示**

在 `tool_running_effects.dart` 中为尾注场景提供更轻的 sweep 方案，或给现有 sweep 增加低强度配置。

要求：

- 不形成轮廓感
- 不像一块发亮的面
- 更像掠过文字区域的一层提示

- [ ] **Step 4: 调整状态点与文案节奏**

保持：

- 小绿点呼吸
- 文案稳定、易读

避免：

- 尾注过于显眼
- 和正文产生竞争

- [ ] **Step 5: 运行定向测试与本地预览**

Run:

```bash
"$HOME/.pub-cache/bin/fvm" flutter test test/widgets/chat_message_list_test.dart
```

Expected:
- 尾注相关测试仍通过

- [ ] **Step 6: 提交这一小步**

```bash
git add lib/widgets/chat_blocks/latest_message_running_status_tail.dart lib/widgets/tool_renderers/tool_running_effects.dart test/widgets/chat_message_list_test.dart
git commit -m "style: make running tail feel like a dynamic footnote"
```

### Task 5: 收敛 phase 空窗与持续显示边界

**Files:**
- Modify: `lib/controllers/chat_send_coordinator.dart`
- Modify: `lib/controllers/agent_event_processor.dart`
- Modify: `lib/providers/chat_send_state_providers.dart`（仅在必要时）
- Modify: `lib/services/latest_message_running_status_resolver.dart`
- Test: `test/widgets/chat_message_list_test.dart`

- [ ] **Step 1: 排查 phase 空窗来源**

检查：

- `sendMessage()` 发起后到第一个 planner/tool 事件到达前
- tool 批次切换中
- tool 结束到 streamingResponse 开始前

确认是否存在 `chatSendStateProvider` 短暂回到 `idle` 或缺少“本轮仍活跃”信号的情况。

- [ ] **Step 2: 选最小修复路径**

优先顺序：

1. 复用已有 phase，不改 provider 结构
2. 若不足，再增加最小的“send transaction active”语义

不要先上重结构。

- [ ] **Step 3: 修复断档**

让 resolver 有稳定依据判断：

- 当前这一轮仍在运行
- 即使文案从具体态切换，也不让尾注消失

- [ ] **Step 4: 运行全套尾注定向测试**

Run:

```bash
"$HOME/.pub-cache/bin/fvm" flutter test test/widgets/chat_message_list_test.dart test/widgets/chat_input_test.dart
```

Expected:
- 连续性相关测试通过

- [ ] **Step 5: 提交这一小步**

```bash
git add lib/controllers/chat_send_coordinator.dart lib/controllers/agent_event_processor.dart lib/providers/chat_send_state_providers.dart lib/services/latest_message_running_status_resolver.dart test/widgets/chat_message_list_test.dart test/widgets/chat_input_test.dart
git commit -m "fix: keep running tail visible until turn finishes"
```

### Task 6: 回归验证与安装前检查

**Files:**
- Modify: `README.md`（仅当行为说明确实过时）
- Modify: `AGENTS.md`（仅当需要沉淀新 UI 约束）

- [ ] **Step 1: 跑定向 analyze**

Run:

```bash
"$HOME/.pub-cache/bin/fvm" flutter analyze lib/widgets/chat_message_list.dart lib/widgets/chat_blocks/latest_message_running_status_tail.dart lib/widgets/tool_renderers/tool_running_effects.dart lib/services/latest_message_running_status_resolver.dart lib/controllers/chat_send_coordinator.dart lib/controllers/agent_event_processor.dart test/widgets/chat_message_list_test.dart test/widgets/chat_input_test.dart
```

Expected:
- `No issues found!`

- [ ] **Step 2: 跑定向测试集**

Run:

```bash
"$HOME/.pub-cache/bin/fvm" flutter test test/widgets/chat_input_test.dart test/widgets/chat_message_list_test.dart test/widgets/chat_message_list_interaction_test.dart
```

Expected:
- 全部通过

- [ ] **Step 3: 判断是否需要更新文档**

仅在以下情况才改：

- README 仍明确说状态显示在输入区
- AGENTS 需要沉淀“运行态提示优先跟随最新消息块”的约束

- [ ] **Step 4: 最终提交**

```bash
git add lib/widgets/chat_message_list.dart lib/widgets/chat_blocks/latest_message_running_status_tail.dart lib/widgets/tool_renderers/tool_running_effects.dart lib/services/latest_message_running_status_resolver.dart lib/controllers/chat_send_coordinator.dart lib/controllers/agent_event_processor.dart lib/providers/chat_send_state_providers.dart test/widgets/chat_input_test.dart test/widgets/chat_message_list_test.dart test/widgets/chat_message_list_interaction_test.dart README.md AGENTS.md
git commit -m "feat: keep running tail continuous across a turn"
```

## 验收清单

- [ ] 一个 `turn` 开始后到结束前，尾注尽量不断档
- [ ] 单工具明确动作时显示具体系统动作文案
- [ ] 多工具并行时退化为 `正在执行工具`
- [ ] 极端空窗时才退化为 `正在等待结果`
- [ ] 尾注没有边框感或卡片感
- [ ] 输入区仍不显示旧状态文案
- [ ] 定向测试与 analyze 通过

## 备注

- 本计划是前一版“最新消息底部尾注”方案的增量实现计划，不重复拆输入区迁移本体。
- 当前会话继续采用 inline execution，不需要切换到 subagent 流程。
