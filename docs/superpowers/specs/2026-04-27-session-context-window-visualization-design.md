# Session 上下文窗口可视化设计

## 背景

当前项目已经完成 Session 级上下文管理重构，真实发给模型的 planner 可见上下文不再直接来自 UI `messages`，而是由 [`SessionContextService`](/Users/zyb_wl/flutterSpace/FlutterAIChat/lib/services/session_context_service.dart) 统一构建。

当前实现的主链路是：

1. 读取当前模型预算配置
2. 读取 runtime user context
3. 读取最新 `session_context_snapshots`
4. 读取 snapshot 边界之后的 completed turns
5. 读取 current turn transcript
6. 用 [`SessionContextProjector`](/Users/zyb_wl/flutterSpace/FlutterAIChat/lib/services/session_context_projector.dart) 投影为模型可见上下文
7. 用 [`SessionTokenBudgetService`](/Users/zyb_wl/flutterSpace/FlutterAIChat/lib/services/session_token_budget_service.dart) 估算 token 占用，并在必要时触发历史压缩

当前项目已经具备较完整的内部上下文策略，但普通用户无法理解：

- 当前会话距离上下文上限还有多少
- 为什么历史会被压缩
- 当前 planner 实际携带了哪些上下文段
- 哪些占用是“真实输入上下文”，哪些只是预算保留区

因此需要新增一套正式、用户可见、但不过度制造压力的上下文窗口可视化能力。

## 目标

本次设计目标：

- 在聊天主界面提供一个极轻量的上下文占用状态条
- 允许用户通过详情面板查看当前上下文窗口的分段填充情况
- 同时展示“占总上下文窗口比例”和“占可用输入预算比例”
- 保证 UI 展示与真实 planner 构建过程同源
- 使用当前本地 token 估算体系，不依赖 provider 是否返回精确 usage

## 非目标

- 本轮不引入 provider 真实 usage 作为唯一数据源
- 本轮不把上下文可视化做成 debug-only 工具
- 本轮不在主界面显示文案说明、预警句子或显式焦虑型提示
- 本轮不改单轮上下文压缩规则本身
- 本轮不把历史 turn 列表完整展开成复杂排障页

## 当前实现事实

### 1. 上下文真实入口

当前真实入口是 [`SessionContextService.buildPlannerMessages()`](/Users/zyb_wl/flutterSpace/FlutterAIChat/lib/services/session_context_service.dart)。

planner 上下文固定由以下部分组成：

1. `runtime user context`
2. `history summary`
3. `recent completed turns`
4. `current turn transcript`

并且：

- `current turn transcript` 不与 `recent completed turns` 重叠
- `history summary` 由 `session_context_snapshots` 持久化
- 是否压缩由 token budget pressure 决定，而不是固定消息数

### 2. 投影规则

[`SessionContextProjector`](/Users/zyb_wl/flutterSpace/FlutterAIChat/lib/services/session_context_projector.dart) 当前真实实现会保留：

- user message
- assistant message
- assistant tool use
- user tool result
- 交互问题与交互结果

需要明确以当前代码为准，不再沿用过期文档中“过滤 assistant tool call”的旧口径。

### 3. 预算规则

[`ModelBudgetRegistry`](/Users/zyb_wl/flutterSpace/FlutterAIChat/lib/services/model_budget_registry.dart) 与 [`SessionTokenBudgetService`](/Users/zyb_wl/flutterSpace/FlutterAIChat/lib/services/session_token_budget_service.dart) 共同定义：

- `maxContextTokens`
- `reservedOutputTokens`
- `reasoningReserveTokens`
- `safetyMarginTokens`
- `usableInputBudget`
- `compressionTriggerRatio`

因此“当前会话离上下文上限还有多少”与“当前输入上下文占可用输入预算多少”本身是两个不同维度，UI 必须同时支持。

## 方案选择

本轮采用“同源只读快照”方案，而不是 UI 自己单独复算。

### 方案 A：同源只读快照

新增一个正式只读数据模型 `ContextWindowSnapshot`，由 Session 上下文构建链路产出，供 UI 读取。

优点：

- UI 与真实 planner 上下文完全同源
- 主界面状态条与详情面板天然一致
- 压缩边界、recent working set、snapshot 覆盖范围都可解释
- 后续压缩规则调整时，只需维护一条链路

### 方案 B：UI 侧临时复算

不采用。

原因：

- 容易与 `SessionContextService` 真实结果分叉
- 主条、详情、planner 可能出现三套口径

### 方案 C：完全依赖 provider 返回 usage

不采用。

原因：

- 当前是多 provider 架构，usage 能力不统一
- 即使拿到总 usage，也无法自然拆解 `summary / recent / current turn` 分段

## 用户体验设计

### 主界面轻量状态条

主界面在输入区上方新增一条极细状态条：

- 无文案
- 无百分比数字
- 默认低对比度中性色
- 仅表达“当前会话离总上下文上限还有多少”
- 点击后打开详情 Bottom Sheet

设计原则：

- 默认不制造上下文焦虑
- 让懂的人能发现、能查看
- 不让它成为聊天主界面的注意力中心

视觉行为建议：

- 安全区间：细线、低对比度
- 接近压缩阈值：仅轻微增强颜色或对比度
- 不出现“危险”“不足”“即将超限”之类文案

### 详情 Bottom Sheet

详情使用底部抽屉，而不是独立页面。

原因：

- 更适合移动端
- 与聊天语境距离近
- 用户可以快速看一眼后继续对话

详情分为三块。

#### 1. 顶部总览

展示：

- 当前模型名
- `maxContextTokens`
- `usableInputBudget`
- 当前估算输入 tokens
- 占总上下文窗口比例
- 占可用输入预算比例

这部分解决“总窗”和“可用输入预算”不是一回事的问题。

#### 2. 中部构成拆解

用堆叠条 + 列表同时展示以下 segment：

- `system prompt`
- `runtime user context`
- `history summary`
- `recent completed turns`
- `current turn transcript`

每一段同时展示：

- `estimatedTokens`
- `shareOfTotalWindow`
- `shareOfUsableInput`

必要时可展开解释：

- `history summary` 覆盖到哪个 turn
- `recent completed turns` 当前保留了几轮
- `current turn transcript` 是否包含 tool use / tool result

#### 3. 保留区与压缩状态

单独展示预算保留区：

- `reserved output`
- `reasoning reserve`
- `safety margin`
- `free headroom`

同时展示压缩状态：

- 当前是否已发生历史压缩
- `snapshotCoveredUntilTurnId`
- `recentCompletedTurnCount`
- 当前距离压缩阈值还有多少

默认先展示核心数据，turn 边界说明放在可折叠区域，避免信息密度过高。

## 架构设计

### 总体原则

新增可视化能力必须复用当前 Session 上下文构建规则，不能在 UI 再造第二套策略。

### 新增模型

新增 `ContextWindowSnapshot`。

建议字段：

- `modelName`
- `maxContextTokens`
- `usableInputBudget`
- `compressionTriggerRatio`
- `totalEstimatedInputTokens`
- `totalWindowUsageRatio`
- `usableInputUsageRatio`
- `didCompactHistory`
- `snapshotCoveredUntilTurnId`
- `recentCompletedTurnCount`
- `segments`

新增 `ContextWindowSegment`。

建议字段：

- `type`
- `label`
- `estimatedTokens`
- `shareOfTotalWindow`
- `shareOfUsableInput`
- `isPlannerVisible`
- `details`

### Segment 类型

建议固定为以下枚举值。

planner 可见 segment：

- `systemPrompt`
- `runtimeUserContext`
- `historySummary`
- `recentCompletedTurns`
- `currentTurnTranscript`

预算保留 segment：

- `reservedOutput`
- `reasoningReserve`
- `safetyMargin`
- `freeHeadroom`

### 新增只读服务

新增 `SessionContextInspectorService`。

职责：

- 基于当前 group / current turn / config 生成最新 `ContextWindowSnapshot`
- 复用 `SessionContextService` 的上下文选择规则
- 复用 `SessionTokenBudgetService` 的 token 估算规则
- 产出供 UI 使用的结构化分段结果

重要约束：

- 它不应成为新的 planner 入口
- 它不负责修改压缩规则
- 它只负责“观察当前真实上下文窗口”

### 推荐的内部抽象

当前 `SessionContextService.buildPlannerMessages()` 最终直接返回 `List<ChatMessage>`，不利于 UI 读取中间结构。

建议抽出一层共享的内部 build result，例如：

- summary snapshot
- selected recent segments
- current turn encoded items
- fixed prefix token estimates
- planner budget evaluation
- compaction result

然后分别投影为：

1. planner messages
2. context window snapshot

这样可以避免重复遍历历史事件与重复做 segment 选择。

## Provider 与 UI 接线

建议新增一个只读 provider，例如：

- `contextWindowSnapshotProvider`

输入依赖至少包括：

- 当前 group
- 当前 active turn 或最近 turn
- 当前 chat config / model config
- `SessionContextInspectorService`

主界面轻量条读取该 provider 的聚合占比字段。

详情 Bottom Sheet 读取同一 provider 的完整 snapshot。

## 状态定义

### 无数据状态

以下情况主界面不展示状态条或展示为不可点击占位：

- 尚未选中 group
- 尚未有有效会话
- 尚未解析到模型配置
- 当前 turn / config 无法构建估算

### 正常状态

显示一条低对比度细线。

### 高压力状态

当总占比或输入预算占比接近压缩阈值时：

- 仅提升线条对比度或色相
- 详情面板中补充更明确说明
- 主界面仍不显示警告文案

## 测试策略

至少补以下测试：

### 服务层

- `ContextWindowSnapshot` 能正确区分总窗口占比与可用输入预算占比
- segment token 与总 token 汇总关系正确
- snapshot 边界、recent turn 数、compaction 状态正确映射
- 保留区与 planner 可见区不会混淆

### Provider 层

- 切换 group 时 snapshot 跟随变化
- 缺少 config / turn 时安全返回空态

### UI 层

- 主界面轻量条在正常状态下无文案
- 点击轻量条能打开 Bottom Sheet
- 详情面板能展示 segment 列表与两类占比

## 文档更新

实施时需要同步更新：

- [`README.md`](/Users/zyb_wl/flutterSpace/FlutterAIChat/README.md)
- [`docs/architecture/session-context-management.md`](/Users/zyb_wl/flutterSpace/FlutterAIChat/docs/architecture/session-context-management.md)

特别是要修正文档中关于 `assistantToolCall` 投影规则的过期描述，统一以当前代码实现为准。

## 风险与取舍

### 1. 估算值不等于 provider 精确 token

接受该取舍。

原因：

- 当前能力目标是统一、稳定、可解释
- 项目已有统一估算体系
- 多 provider 情况下精确 usage 并不稳定可得

后续若 provider 返回真实 usage，可把它作为校准层，而不是替换当前架构。

### 2. 轻量条过强会制造焦虑

因此主界面方案固定为：

- 无文案
- 无数字
- 无警告语气

所有解释性信息收敛到 Bottom Sheet。

### 3. UI 与真实上下文分叉

通过“共享中间 build result + 同源 snapshot”规避。

## 最终结论

本轮新增一项正式产品能力：

- 主界面：输入区上方一条极细、无文案、无数字的上下文占用状态条
- 详情：点击后打开 Bottom Sheet，展示上下文窗口分段、总窗口占比、可用输入预算占比、保留区与压缩状态
- 数据来源：新增 `SessionContextInspectorService` 与 `ContextWindowSnapshot`，复用当前 SessionContext 构建规则与 token 预算估算逻辑

这样既能让普通用户理解“当前会话离上下文上限还有多少”，又不会把上下文预算变成主界面的焦虑提示，同时还能为后续排障、产品解释和高级用户理解提供足够完整的细节视图。
