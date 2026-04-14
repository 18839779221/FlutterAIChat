# Agent Loop 架构整改路线图

## 目标

本文档基于以下两份文档制定当前架构整改路线：

- [Agent Loop 架构基线](./2026-04-13-agent-loop-architecture-baseline.md)
- [Agent Loop 与基线差异分析](./2026-04-13-agent-loop-gap-analysis.md)

本文档只描述整改阶段、优先级、目标产物与推进顺序，不展开具体实现细节。

## 总体策略

整改遵循以下原则：

1. 先修 loop 正确性，再修分层纯度
2. 先修运行时硬规则，再修命名和投影层
3. 先建立稳定契约，再推动代码迁移
4. 每一阶段都应形成可验证的中间状态，而不是一次性大重写

## 阶段划分

整改分为四个阶段：

1. Phase 0：确立统一术语与运行契约
2. Phase 1：消除 P0 级硬规则
3. Phase 2：收拢策略层与验证层
4. Phase 3：收敛 UI 投影与命名一致性

当前状态概览：

- Phase 0：已完成
- Phase 1：核心目标已完成
- Phase 2：主体已完成，剩余 verifier 能力补强
- Phase 3：已完成命名主链收口，UI projection 去耦仍在继续

---

## Phase 0：确立统一术语与运行契约

### 目标

在改代码之前，先让团队对以下内容达成一致：

- turn loop 的标准生命周期
- harness / planner / policy / verifier 的职责边界
- 关键业务术语与实现命名的映射关系

### 本阶段产物

- 长期基线文档
- 差异分析文档
- 本整改路线图
- 一份“规范术语 -> 当前代码组件”映射表

### 本阶段完成标准

- 团队讨论时不再混用多个概念名指向同一职责
- 后续整改需求能够明确归类到 harness / planner / policy / verifier 中的一类

### 当前状态

已完成。

### 命名对齐建议

建议首先建立如下映射：

- `Harness` -> 当前 `TurnHarness`
- `Planner` -> 当前 `AgentPlannerService`
- `Verifier` -> 当前 `TurnVerifier`
- `Tool Policy` -> 当前 `ToolPolicyService`
- `Session Manager` -> 当前 `ChatSessionCoordinator` 及其 session 相关 provider

本阶段不强制立刻重命名代码，但必须先让映射关系明确且文档化。

---

## Phase 1：消除 P0 级硬规则

### 目标

把当前最直接破坏基线的硬规则从主链路中移除或替换掉。

### 本阶段重点

#### 1. 清理 planner 兼容层中的静态 allowlist

目标：

- 不再依赖静态工具名 allowlist 作为 loop 主控制机制
- planner 决策过滤应建立在 exposure / policy / registry 的组合结果上

当前重点对象：

- `AgentPlannerService._legacyAllowedToolNames`
- `AgentPlannerService._resolveAllowedToolNames()`
- `AgentPlannerService._sanitizeDecision()`

#### 2. 清理按工具名写死的 retrieval 短路规则

目标：

- 不再在 planner 兼容层里按具体工具名写死 loop 中止逻辑
- 重复调用、空结果、无效继续等判断应回归 verifier 或标准 step 语义

当前重点对象：

- `_buildRepeatedEmptyRetrievalDecision()`
- `_isEmptyRetrievalResult()`

#### 3. 升级 verifier，使其承担真实 stop 判断

目标：

- verifier 不再仅依赖“文本是否为空”
- verifier 能检查 turn 是否真的达到完整结束点

当前重点对象：

- `TurnVerifier`

### 本阶段完成标准

- harness 不再依赖静态工具名规则维持主流程正确性
- verifier 能够基于运行时状态，而不是输出表象，判断 turn 是否可结束
- 相同问题不再依赖 planner 兼容层中的补丁式短路逻辑修正

### 当前状态

本阶段核心目标已基本完成：

- planner 静态 allowlist 已移除
- retrieval 短路硬规则已移除
- `TurnHarness` / `planNextDecision()` 主链已经稳定

当前唯一未完成项是 verifier 仍然偏弱，因此这里的剩余工作已转移到后续阶段继续补强。

---

## Phase 2：收拢策略层与验证层

### 目标

让 tool exposure、tool confirmation、tool blocking、turn verification 形成真正独立的规则层，而不是分散在 prompt、planner 后处理和执行前检查中。

### 本阶段重点

#### 1. 把 `PlannerToolExposureService` 变成真实策略层

目标：

- 工具是否可见应由能力、风险、平台、上下文共同决定
- 不再由“注入了哪些工具 + prompt 里怎么写”间接决定

当前重点对象：

- `PlannerToolExposureService`
- `ToolDefinition`
- `ToolRuntimeRegistry`

#### 2. 统一 tool visibility / execution / confirmation 语义

目标：

- 暴露策略与执行策略来自同一个 policy 体系
- “可见但不可执行”“可执行但需确认”等状态具备一致表达

当前重点对象：

- `ToolPolicyService`
- `ToolOrchestratorService`
- planner tool exposure path

#### 3. 将 verifier 与 step / turn 状态联动

目标：

- verifier 能读懂 step 状态
- verifier 能识别未闭合步骤、待确认动作、未消费 continuation state

### 本阶段完成标准

- tool policy 成为统一策略层，而不是若干散落规则的组合
- tool exposure 和 execution policy 的语义一致
- verifier 与 turn/step runtime state 形成闭环

### 当前状态

本阶段主体已完成：

- `ToolAccessSnapshot` 已成为统一共享快照
- `PlannerToolExposureService` 已统一到 snapshot 主入口
- `ToolPolicyService`、planner、runtime、UI payload 已围绕统一策略契约收敛
- planner 与 runtime 在缺少 policy service 时会显式失败，不再静默 fallback

当前剩余尾项主要是 verifier 还未真正读懂 step / continuation / pending confirmation 的完整闭环。

---

## Phase 3：收敛 UI 投影与命名一致性

### 目标

在 loop 主链稳定后，进一步降低事件模型、UI 消息协议、组件命名之间的映射误差。

### 本阶段重点

#### 1. 收拢 `ChatSendCoordinator` 中的事件投影逻辑

目标：

- controller 不再承担大量 runtime event 到 UI message 的硬编码映射
- event model 与 UI projection 的边界更加清晰

当前重点对象：

- `ChatSendCoordinator`
- message projection path
- send phase projection path

#### 2. 推动关键业务组件命名贴齐规范术语

目标：

- 让代码层命名尽量靠近长期基线术语
- 减少“规范名”和“实现名”长期并行造成的映射误差

建议优先对齐顺序：

1. `TurnHarness` 作为 harness 主名继续前推
2. `TurnVerifier` 保持 verifier 语义，不再继续沿用历史 stop-verifier 命名
3. `ChatSessionCoordinator` -> 更贴近 `SessionManager`
4. `ToolPolicyService` -> 维持术语一致，但补齐其完整 policy 语义

#### 3. 明确 transcript event model 与 UI message model 的投影边界

目标：

- runtime event model 服务运行时与 replay
- UI message model 服务界面呈现
- 两者之间通过明确投影层转换，而不是隐式混合

### 本阶段完成标准

- 关键业务职责讨论时，术语与代码命名基本一致
- UI 层对 loop 事件的依赖明显弱化
- runtime event model 和 UI projection model 明确分层

### 当前状态

本阶段已部分完成：

- `TurnHarness` / `TurnVerifier` 已成为主命名
- `AgentTurnOrchestrator` 与相关兼容 provider/export 已移除
- UI 层已经不再直接依赖 `executionDecision`
- 新生成 payload 已开始以 `toolAccess` 为正式策略契约

当前剩余工作主要集中在：

- `ChatSendCoordinator` 里的事件到 UI message 映射进一步收缩
- 顶层 `executionPolicy` 等兼容字段继续退出主链
- transcript event model 与 UI projection model 之间建立更明确的投影边界

---

## 建议执行顺序

后续推荐执行顺序应调整为：

1. 先补强 `TurnVerifier`
2. 再继续收缩 controller / projection 层
3. 最后清理残余兼容 payload 字段并做文档收尾

## 每阶段的回归验证重点

### Phase 1 验证重点

- 多工具 turn 能否在无静态 allowlist 补丁的前提下稳定推进
- 空结果、失败结果、重复意图是否还能正确收敛
- verifier 是否能阻止“有文本但未完成”的错误结束

### Phase 2 验证重点

- 同一工具在不同上下文下的可见性是否符合统一 policy
- confirmation-required 工具是否在所有路径上都遵守同一策略
- exposure / execution 已基本语义一致，verification 闭环仍待补强

### Phase 3 验证重点

- runtime event 新增类型时，是否仍需修改多处 UI/Controller 分支
- 关键业务组件命名是否已接近规范术语
- transcript 和 UI message 是否能各自独立演进

## 风险提示

### 风险 1：先改命名，后改行为

如果先大规模改名，而不先修 loop 规则，团队会获得“看起来更规范”的代码，但运行时问题仍在。

### 风险 2：先做 UI 收敛，后做 verifier

如果先把 controller 投影层收得很漂亮，但 verifier 仍然过弱，会把错误行为包装得更难发现。

### 风险 3：只删硬规则，不补统一策略

如果只删除 `_legacyAllowedToolNames` 或 retrieval 短路规则，但不补 exposure / policy / verifier 的统一契约，系统可能短期内变得更不稳定。

## 路线图结论

当前整改最合理的路径不是重写整条 agent loop，而是：

1. 优先补强 verifier，使停止条件真正建立在运行时完整性上
2. 继续收缩 controller 投影层与兼容 payload 字段
3. 把已经完成的契约收敛同步回长期维护文档

这样做可以在不破坏现有主干的前提下，把系统继续拉回并稳定在长期基线之上。
