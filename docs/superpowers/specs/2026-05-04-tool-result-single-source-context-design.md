# ToolResult 单一结果源与上下文投影收口设计

## 背景

当前 tool use 架构已经具备 append-only transcript、turn ledger、Session Context 三层边界，但 `toolResult` 的正式语义仍未完全收口：

- [`ToolResult`](/Users/skka/flutterSpace/FlutterAIChat/lib/models/tool/tool_result.dart) 一度同时承载 `summary`、`uiSummaryText`、`contextText` 等多套文本语义
- [`ToolPreparationResult`](/Users/skka/flutterSpace/FlutterAIChat/lib/services/tool_call_service.dart) 曾承载 `additionalContextMessages`
- [`DecisionToolCallExecutor`](/Users/skka/flutterSpace/FlutterAIChat/lib/services/decision_tool_call_executor.dart) / [`TurnHarness`](/Users/skka/flutterSpace/FlutterAIChat/lib/services/turn_harness.dart) 会把 tool result 的短摘要写入 transcript `content`
- [`SessionContextProjector`](/Users/skka/flutterSpace/FlutterAIChat/lib/services/session_context_projector.dart) 需要决定“下一轮 planner 究竟应该看哪一份 tool result 语义”

已经暴露出来的表面问题是：`web_search` 在上下文回放时只回到摘要，而不是实际结果。  
但根因不是某一个 tool 没有写好某个文本字段，而是 `ToolResult` contract 曾经允许多套并行文本来源共存，导致系统可以随时退回“拿摘要充当语义”。

## 目标

- 将 `ToolResult` 收口为稳定正式 contract：`summary + data`
- 删除 `uiSummaryText`
- 删除 `contextText`
- 删除 `toolResultText`
- 删除 `additionalContextMessages`
- 明确 `summary` 只承担展示/紧凑 transcript `content` 职责，不再承担 planner 语义职责
- 明确 `data` 是 tool result 的唯一结果真相
- 明确 planner / Session Context 中看到的 tool result 文本，必须由上下文投影层基于 `toolName + status + data + errorMessage` 派生
- 通过代码注释、架构文档、测试不变量共同防止后续重新引入“第二份 tool result 语义文本”

## 非目标

- 本轮不改变 tool invocation / confirmation 的 UI 交互形态
- 本轮不改造 provider-native continuation 协议
- 本轮不重写 `history summary` 生成策略
- 本轮不引入复杂的通用工具结果 DSL
- 本轮不做 timeline 视觉 redesign

## 核心问题

### 1. `contextText` 不是独立真相，而是 `data` 的派生副本

一旦同时存在：

- `summary`
- `contextText`
- `data`

就等于允许一个 tool result 同时存在三份语义表达。

其中：

- `summary` 是给人看的短句
- `data` 是结构化结果真相
- `contextText` 本质上只是“把 `data` 再翻译成一段文本”

这意味着 `contextText` 并不是独立层级，而是 `data` 的镜像。它天然容易与 `data` 漂移：

- `data` 更新了，`contextText` 忘了同步
- 不同 tool 对 `contextText` 的写法不一致
- 有的 tool 填完整，有的 tool 只填摘要
- 预算压力出现时，又会诱导重新发明一套回退链

从架构角度看，这不是稳定抽象，更像长期漂移源。

### 2. `summary` 被回退成 planner 语义，是旧问题的根

`summary` 的正确职责一直是：

- UI 时间线摘要
- tool result 卡片摘要
- transcript `content` 的紧凑可读文本

如果系统允许：

```text
tool result 没有上下文文本
=> 回退到 summary
=> planner 继续基于 summary 决策
```

那就等于重新把“展示文本”升级成了“语义真相”。

这正是 `web_search` 现在掉进的陷阱。  
所以本轮不只是删掉 `contextText`，还必须一起删除“回退到 `summary` 作为 planner 语义”的机制。

### 3. `additionalContextMessages` 是平行语义通道

`additionalContextMessages` 允许 handler 绕过 transcript，再平行塞一份“给模型看的消息列表”。

这会导致：

- transcript 里是一份东西
- planner 实际又看另一份东西
- replay 无法仅凭 transcript 稳定重建

它与 append-only transcript 的架构目标直接冲突，必须删除，不保留“以后也许有用”的兼容口。

## 设计原则

### 1. `data` 是唯一结果真相

tool result 的正式结果语义必须统一进入 `data`。

如果一个结果值得被后续 planner 使用，它首先应该以结构化形式存在于 `data` 中，而不是先写成一段临时文本。

### 2. `summary` 只负责展示

`summary` 只用于：

- timeline
- tool result summary row
- compact transcript `content`
- debug / trace 的短描述

不得作为 planner 语义输入来源。

### 3. planner 可见语义属于投影层，而不是结果模型本身

tool result 重新进入模型上下文的正式路径必须是：

1. tool runtime 生成 `ToolResult(summary + data + status...)`
2. append `toolResult` / `toolError` 事件到 transcript
3. `SessionContextProjector` 或专门的 `ToolResultContextProjector` 从 transcript payload 读取结构化 `ToolResult`
4. 基于 `toolName + status + data + errorMessage` 投影成 planner-visible context item

也就是说：

```text
ToolResult -> payloadJson -> context projector -> model-visible text
```

而不是：

```text
ToolResult -> contextText/resolvedContextText -> planner
```

### 4. 派生层不能反向发明第二份真相

UI、timeline、debug card、presentation mapper 都只能消费正式字段。

同样地，context projector 也不能依赖“某个 handler 临时写的一段自由文本”作为真正结果真相，而应尽量基于结构化 `data` 做投影。

### 5. 删除优于兼容

本项目仍处于内部开发阶段。

本轮应直接删除：

- `uiSummaryText`
- `contextText`
- `toolResultText`
- `additionalContextMessages`

以及相关注释、测试、文档中的旧叙述，而不是保留兼容分支。

## 目标态模型

### ToolResult

目标态字段：

- `toolName`
- `status`
- `summary`
- `data`
- `executionPolicy`
- `toolAccess`
- `errorMessage`

语义定义：

- `summary`
  - 面向用户时间线、tool result card、状态摘要
  - 要求短、稳、可扫读
- `data`
  - 面向系统与后续上下文投影的结构化结果真相
  - 承载搜索命中、文件路径、动作标识、错误细节、网页片段等机器可消费结果

删除字段：

- `uiSummaryText`
- `contextText`
- `toolResultText`

### ToolPreparationResult

目标态字段：

- `toolInvocation`
- `toolResult`
- `toolAccess`
- `executionStarted`

删除字段：

- `additionalContextMessages`

说明：

- tool handler 不再返回额外 context message 列表
- 所有后续 planner 上下文只通过 transcript payload 取得

## 上下文投影设计

### 1. ToolResult 不再内置 `resolvedContextText`

`ToolResult` 模型本身不再提供：

- `contextText`
- `resolvedContextText`
- 任意“回退到 summary”的 planner 语义 helper

因为这会把“如何给模型看”重新塞回结果模型层。

### 2. 引入 tool-result 上下文投影职责

建议将 `toolResult` / `toolError` 的 planner-visible 文本投影收敛到一个专门职责中：

- 可以继续放在 [`SessionContextProjector`](/Users/skka/flutterSpace/FlutterAIChat/lib/services/session_context_projector.dart) 内部
- 也可以拆为更窄的 `ToolResultContextProjector` / `ToolResultContextTransformer`

但职责必须明确：

- 输入：结构化 `ToolResult`
- 核心输入源：`data`
- 可辅助使用：`toolName`、`status`、`errorMessage`
- 输出：适合 `ModelContextItem.userToolResult(...)` 的文本

### 3. 禁止 summary fallback

统一规则：

- `toolResult` / `toolError` 投影 planner 上下文时，不允许直接回退到 `summary`
- 若 `data` 为空，也只能基于 `toolName + status + errorMessage` 生成结构化失败/结果事实
- 不能因为“没有专门文本字段”就重新把 `summary` 当语义结果用

这条规则是本轮防回潮的关键不变量。

### 4. 工具级投影允许不同，但入口必须统一

不同工具的 `data` 结构不同，因此上下文投影可以是 tool-specific 的。例如：

- `web_search`
  - 从 `data.query`、`data.results` 生成搜索结果概览
- `fetch_webpage`
  - 从 `data.url`、`data.title`、`data.chunks` 生成网页处理结果
- `Write/Edit`
  - 从 `data.path`、`data.artifactId`、`data.diffSummary` 生成文件结果事实
- `create_reminder`
  - 从 `data.title`、`data.scheduledAt`、`data.reminderId` 生成动作结果事实

但这些差异应体现在“投影逻辑”里，而不是再次长出新的 `ToolResult` 文本字段。

## 关键流程变化

### 1. Tool runtime 输出

目标态：

- handler 只返回一个正式 `ToolResult`
- 结果语义统一进入 `data`
- `summary` 只写短摘要
- 不再返回 `contextText`
- 不再返回 `additionalContextMessages`

### 2. Tool orchestration 包装

[`ToolOrchestratorService`](/Users/skka/flutterSpace/FlutterAIChat/lib/services/tool_orchestrator_service.dart) 在附加 `toolAccess` / `executionPolicy` 时，必须完整保留：

- `summary`
- `data`
- `errorMessage`
- `toolAccess`
- `executionPolicy`

但不得新造 planner-facing 文本字段。

### 3. Transcript append

`appendToolResult()` / `appendToolError()` 保持：

- `content`：写入 `summary`
- `payloadJson`：写入完整 `ToolResult.toJson()`

原因：

- timeline / message projection 仍需要紧凑摘要
- transcript payload 仍保留唯一正式结果真相

### 4. Session context projection

[`SessionContextProjector`](/Users/skka/flutterSpace/FlutterAIChat/lib/services/session_context_projector.dart) 对 `toolResult` / `toolError` 的统一规则改为：

1. 解析 `ToolResult.fromJson(payload)`
2. 调用统一的 tool-result context projector
3. 基于 `data` 为主生成 planner-visible 文本
4. 若 `data` 不足，也只能基于结构化结果元信息生成事实文本
5. 不允许回退到 `summary`

### 5. UI 投影

所有 tool result 展示统一消费 `summary`：

- message timeline
- tool result summary row
- dedicated tool cards
- debug / inspector / presentation mappers

禁止 UI 使用上下文投影文本作为默认展示文案，避免“给模型看的文本”重新渗回用户界面。

## 防漂移设计

### 1. 架构文档互相引用

本轮需要统一更新并互相引用以下文档：

- [`docs/architecture/append-only-transcript.md`](/Users/skka/flutterSpace/FlutterAIChat/docs/architecture/append-only-transcript.md)
- [`docs/architecture/session-context-management.md`](/Users/skka/flutterSpace/FlutterAIChat/docs/architecture/session-context-management.md)
- 本 spec

要求文档共同声明：

- transcript payload 是 tool result 的唯一语义来源
- `ToolResult.summary` 只用于展示
- `ToolResult.data` 是唯一结果真相
- planner-visible tool result 文本来自统一 context projector
- 不允许通过 `summary fallback`、`contextText`、`additionalContextMessages` 引入第二条语义路径

### 2. 代码头注释与字段注释

下列代码位置应加或更新短注释，并直接引用相关架构文档：

- `lib/models/tool/tool_result.dart`
- `lib/services/tool_call_service.dart`
- `lib/services/tool_orchestrator_service.dart`
- `lib/services/session_context_projector.dart`

注释重点：

- `summary` 是展示字段，不是 planner 语义字段
- `data` 是 tool result 的唯一结果真相
- planner 回放必须走 transcript payload 投影

### 3. 测试不变量

至少补强以下不变量：

1. `ToolResult.toJson()/fromJson()` 不再出现 `uiSummaryText/contextText/toolResultText`
2. `ToolPreparationResult` 不再出现 `additionalContextMessages`
3. `toolResult` / `toolError` 进入 planner context 时，不读取 `summary`
4. `web_search`、`fetch_webpage`、`Write/Edit` 等至少各有一个测试证明 planner-visible 文本来自 `data`
5. 当 `data` 缺字段或工具失败时，仍能基于结构化结果生成事实文本，而不是回退到 `summary`

## 风险与取舍

### 1. 投影层会承担更多职责

删除 `contextText` 后，“给模型看的文本”不再由 tool handler 自带，而是由 projector 统一生成。

这是有意的职责迁移，不是副作用。  
因为“如何回放给模型”本来就属于 Session Context / projection 边界，而不是 tool runtime 边界。

### 2. 不同工具的 `data` 质量会直接影响后续 planner 质量

这会倒逼各工具把真正有价值的结果稳定写入 `data`。  
这是好事，因为它把系统收敛到一个真正可验证的结果真相源上。

### 3. 某些工具可能暂时缺少足够结构化数据

如果某些工具当前 `data` 过薄，应优先补足 `data` 结构，而不是重新添加一个文本兜底字段。

## 结论

本轮目标态不是：

- `uiSummaryText` 给 UI
- `contextText` 给模型

而是更进一步收口为：

- `summary`：只给展示
- `data`：唯一结果真相
- planner-visible tool result 文本：只由统一投影层从 `data` 派生

这样才能真正避免 `web_search` 这类问题在别的工具上以不同形式再次出现，也更符合整个 tool use 架构“单一语义源、统一投影、杜绝平行通道”的长期方向。
