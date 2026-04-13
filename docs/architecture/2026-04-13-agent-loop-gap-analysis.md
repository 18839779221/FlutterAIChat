# Agent Loop 与基线差异分析

## 目标

本文档对照 [Agent Loop 架构基线](./2026-04-13-agent-loop-architecture-baseline.md)，分析当前代码实现与目标架构之间的差异。

本文档服务于当前架构整改目标，不作为长期基线的一部分。

## 范围

本次差异分析覆盖以下链路：

- UI / Controller 到 turn 启动链路
- planner 决策链路
- tool call loop 主编排链路
- tool exposure / tool policy / verifier
- transcript / step / turn 持久化边界

## 总体判断

当前项目已经具备一个可运行的多步 tool call loop 雏形，核心主干已经形成：

- 发送链路已收口到 `ChatSendCoordinator`
- turn 级 loop 已收口到 `TurnHarness`
- planner 决策、tool execution、turn step 持久化已初步拆开
- 运行时 registry / handler 模型已经替代了早期的大型 `switch`
- `TurnVerifier`、`ToolAccessSnapshot`、`ToolPolicyService` 已成为主链术语与主实现
- planner / runtime / UI payload 已开始围绕 `toolAccess` 共享快照收敛

但从基线视角看，当前实现仍然存在四类关键问题：

1. verifier 过弱，尚未承担真实的 turn 完整性判断职责
2. controller 层仍承担了较多事件到 UI message 的协议映射逻辑，导致 UI 协议与 loop 事件强耦合
3. payload 虽已收敛到 `toolAccess` 主契约，但兼容字段仍未完全退出
4. 运行时能力装配仍有少量硬编码残留

## 差异分类

## 一、Loop 所有权与运行边界

### 已对齐部分

- `ChatController` 只是薄门面，发送动作委托给 `ChatSendCoordinator`
- `ChatSendCoordinator` 负责 turn 创建与订阅 harness 事件
- `TurnHarness` 是当前唯一的 turn loop 主编排入口

对应代码：

- `lib/controllers/chat_controller.dart`
- `lib/controllers/chat_send_coordinator.dart`
- `lib/services/turn_harness.dart`

### 差异点

`ChatSendCoordinator` 仍然包含大量 `ChatEventType -> ChatMessage/ChatSendPhase` 的手写映射逻辑。
这意味着 controller 层不仅负责发送事务，还承担了“运行时事件协议 -> UI 消息协议”的硬编码转换。

这不直接违背“loop 由 harness 拥有”的基线，但会让：

- loop 事件类型扩展时，controller 层持续膨胀
- UI 呈现协议与 runtime event 紧耦合
- 后续引入新的 step 类型时需要修改多个分支

对应代码：

- `lib/controllers/chat_send_coordinator.dart`

### 结论

当前 loop 所有权大体正确，但 controller 层仍然承担了过多 loop event 映射逻辑，后续应继续收口。

## 二、Planner 决策契约

### 已对齐部分

- `TurnHarness` 统一消费 `planNextDecision()`
- provider-specific 的 native 决策路径和 legacy fallback 已集中在 `AgentPlannerService`
- `ConfigurableHttpLLM` 已能返回统一的 `ModelTurnDecision`

对应代码：

- `lib/services/turn_harness.dart`
- `lib/services/agent_planner_service.dart`
- `lib/models/llm/configurable_http_llm.dart`

### 差异点

前一版差异分析中的几项 planner 主链问题已经完成收敛：

1. 静态 allowlist fallback 已移除
2. 按具体 retrieval 工具名写死的短路规则已移除
3. planner 在解析工具访问策略时已显式依赖 `ToolPolicyService`
4. `TurnHarness` 已统一消费 `planNextDecision()` 主链

当前剩余差异主要在于 legacy fallback 仍然保留，用于兼容 provider 能力差异；它已经不再是按工具名驱动流程的主链规则。

对应代码：

- `lib/services/agent_planner_service.dart`

### 结论

planner 统一契约已经基本成型，当前主要剩余的是兼容路径保留，而不是按工具名驱动的主链硬规则。

## 三、工具暴露与工具选择

### 已对齐部分

- `ToolDefinition` 已经承载 schema、capability、risk、platform 等 planner-facing 元数据
- `ToolRuntimeRegistry` 已能返回平台维度可用工具
- `ConfigurableHttpLLM` 已使用结构化 tool schema 发起 planner 请求

对应代码：

- `lib/models/tool/tool_definition.dart`
- `lib/tools/core/tool_runtime_registry.dart`
- `lib/tools/default_tool_runtime_registry.dart`
- `lib/models/llm/configurable_http_llm.dart`

### 差异点

`PlannerToolExposureService` 已经完成关键契约收敛：

- planner exposure 主入口已统一为 `List<ToolAccessSnapshot>`
- 旧的 `selectVisibleTools()` 兼容入口已删除
- planner 不再单独维护 blocked-name 过滤逻辑

当前剩余差异不是“是否存在 exposure 层”，而是 exposure 选择逻辑仍较轻，主要消费 `isVisibleToPlanner`，尚未演进到更丰富的上下文策略层。

对应代码：

- `lib/services/planner_tool_exposure_service.dart`

### 结论

registry 与 exposure 主契约已经对齐，后续重点是增强策略丰富度，而不是继续清理旧入口。

## 四、Harness 中的硬编码业务规则

### 已对齐部分

- 工具真正执行已通过 `ToolRuntimeRegistry + ToolHandler` 机制收口
- `ToolOrchestratorService` 不再依赖大型业务型 `switch case`

对应代码：

- `lib/services/tool_orchestrator_service.dart`
- `lib/tools/default_tool_runtime_registry.dart`

### 差异点

harness 虽然没有大型工具执行 `switch`，但仍包含多处手写 loop 规则：

1. 明确按 `decision.toolCalls.isNotEmpty`、`decision.isTerminal` 分叉
2. 明确按 turn status 判断 batch 是否中断
3. 明确按失败次数 / 最大轮次决定退出
4. `_decisionStatusContent()` 中包含面向当前诊断码的状态拼装逻辑

其中前 3 类属于 loop runtime 的必要控制流，不应简单删除；
但第 4 类以及部分中断判定逻辑，未来应继续从“手写状态拼装”转向“标准 step / state transition 驱动”。

对应代码：

- `lib/services/turn_harness.dart`

### 结论

harness 的整体控制权是对的，但部分状态表达与中断语义仍偏手写，需要进一步模型化。

## 五、Tool Policy 与 Human-in-the-loop

### 已对齐部分

- `ToolOrchestratorService` 已引入 `ToolPolicyService`
- confirmation-required 工具已经能中断 turn 并进入 `awaiting confirmation`
- confirmed invocation 可以恢复原 turn 继续执行

对应代码：

- `lib/services/tool_orchestrator_service.dart`
- `lib/controllers/chat_send_coordinator.dart`
- `lib/services/turn_harness.dart`

### 差异点

这一块与前一版相比已经明显改善：

- `ToolAccessSnapshot` 已成为 planner / runtime / UI 共享快照
- `ToolPolicyService` 已复用统一快照模型，而不是维护独立映射
- planner 与 runtime 在无 policy service 时会显式失败，不再静默 fallback
- UI 侧确认按钮判断已回收到模型层，并优先消费 `toolAccess.executionPolicy`

当前剩余差异主要是兼容 payload 中仍保留部分重复字段，用于兼容旧消息与旧序列化数据。

### 结论

human-in-the-loop 主路径与 policy 主契约已经成立，剩余工作主要是继续去除兼容重复字段并强化文档约束。

## 六、Verifier 与停止条件

### 已对齐部分

- 系统已经单独抽出 `TurnVerifier`
- harness 在最终回答后会调用 verifier 决定是否停止

对应代码：

- `lib/services/turn_verifier.dart`
- `lib/services/turn_harness.dart`

### 差异点

当前 verifier 明显过弱：

- 如果文本为空，则继续
- 如果文本非空，则结束
- 仅对 `maxIterationsReached` 和 `cancelled` 做简单特判

它没有真正检查：

- 是否还有未闭合 step
- 是否存在待消费的 tool result
- 是否还有 pending confirmation
- 是否存在 provider continuation state 未继续
- 是否存在“形式上有文本，但语义上未完成”的情况

### 结论

这是当前实现与架构基线之间最明显、最核心的差距之一。

## 七、Transcript、Turn、Step 持久化

### 已对齐部分

- turn、step、event 已分别持久化
- tool result / tool error / assistant delta / final answer 都能进入 transcript/event store
- step 能记录 provider response id、call id、args、result、status

对应代码：

- `lib/repositories/chat_turn_repository.dart`
- `lib/repositories/chat_turn_step_repository.dart`
- `lib/repositories/chat_event_repository.dart`

### 差异点

当前 transcript 已经接近 append-only event log，但“运行时状态”与“用户可见消息协议”仍然存在双轨耦合：

- event store 记录运行事实
- message store 记录 UI 视图结构
- controller 负责把 event 再投影成 message

这会导致未来当 loop 事件变复杂时，双轨维护成本继续升高。

不过这一块也已出现明显收敛：

- 新生成 payload 已开始以 `toolAccess` 作为正式策略契约
- UI / block builder / widget 层已不再直接依赖 `executionDecision`
- `executionPolicy` 顶层字段已开始降为兼容读取或旧数据透传语义

### 结论

持久化基础已经很好，当前剩余问题不再是“缺少主契约”，而是 runtime event model 与 UI projection 之间仍需进一步去耦。

## 八、配置与运行时注入

### 已对齐部分

- `main.dart` 已集中完成 runtime wiring
- provider、tool executor、registry、planner、harness 的依赖关系已经比较清晰

### 差异点

当前 `main.dart` 中仍有部分能力选择是手写的，例如：

- `web_search.provider` 默认使用 `tavily`
- 非 `tavily` provider 直接视为 unsupported
- 默认 registry 中注册哪些工具完全写死在代码中

这些并非 loop 核心问题，但它们说明运行时能力注入仍未完全配置化。

对应代码：

- `lib/main.dart`
- `lib/tools/default_tool_runtime_registry.dart`

### 结论

运行时装配已经集中，但能力选择仍有硬编码残留。

## 九、命名与规范术语对齐

### 已对齐部分

- `Turn`、`Step`、`Tool Invocation`、`Tool Result` 这些核心术语已经在部分模型与仓储层中出现
- `TurnHarness` 已经成为规范中的 harness 主名
- `TurnVerifier` 已成为 verifier 主名
- `AgentTurnOrchestrator` 与 `agentTurnOrchestratorProvider` 兼容壳已移除

### 差异点

当前代码里的关键业务组件命名仍然存在“规范术语”和“实现命名”并行的问题，例如：

- 规范中的 `Harness`，当前主名已对齐为 `TurnHarness`
- 规范中的 `Session Manager`，当前能力分散在 `ChatSessionCoordinator` 及相关 provider 中
- 规范中的 `Verifier`，当前对应 `TurnVerifier`
- 规范中的 `Tool Policy`，当前对应 `ToolPolicyService`

这些映射目前还能理解，但如果后续继续沿用历史命名并新增新组件，会带来两个问题：

1. 架构讨论时，规范术语和代码术语不断来回翻译，容易产生误差
2. 实现演进时，旧名字会把职责边界继续模糊化，例如 orchestration、coordination、verification、policy 等概念重叠

### 结论

后续整改除了要修行为边界，也应逐步让关键业务组件命名贴齐规范术语。
否则即使架构分层改对了，团队在讨论和维护时仍会持续承担术语映射成本。

## 优先级判断

按对架构基线破坏程度排序，当前最应优先处理的是：

### P0

- `TurnVerifier` 过弱，无法承担真实 stop 判断

### P1

- controller / projection 层仍承担较多 runtime event 到 UI message 的映射逻辑
- payload 中的兼容重复字段仍未完全退出

### P2

- transcript event model 与 UI projection 之间边界仍可继续收紧
- 关键业务组件命名与规范术语尚未完全对齐，长期会放大理解误差

### P3

- `main.dart` 和默认 runtime registry 中的部分能力装配仍偏硬编码

## 总结

当前实现已经有一个值得继续演化的 turn loop 主干，且主链契约已经比前一版明显稳定，最宝贵的部分是：

- turn loop 已被单独收口
- tool execution 已经 handler 化
- step / event 持久化已具雏形
- tool access / execution policy / confirmation policy 已开始共享统一快照

当前最需要修正的，不是重写整条链路，而是把剩余问题继续收敛到 verifier 与 projection 去耦两条主线，逐步放回：

- verifier
- standardized event contracts
- 更清晰的 UI projection boundary

这会让后续 loop 的演进继续建立在稳定契约之上，而不是重新长出新的补丁式治理规则。
