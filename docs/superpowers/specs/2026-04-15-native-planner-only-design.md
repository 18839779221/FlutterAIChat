# Native Planner 单一路径设计

## 背景

当前 agent loop 会优先尝试 provider-native planner；一旦 native planner 超时、抛错或返回 `null`，系统就会静默切换到 legacy 文本 planner。这个 fallback 现在已经从“兼容保护”变成了架构负担：

- 它引入了第二套规划协议，状态语义与 native path 不一致。
- 它削弱了 `ask_user_question` 的恢复能力，因为 legacy planner 无法自然承接 provider-native continuation state。
- 它让运行时调试更困难，因为真实失败会被“换轨执行”掩盖。

最近这次 `ask_user_question` 恢复后卡住就是一个直接例子。用户回答后，loop 实际上已经继续执行，但 native planner 返回了空 body，系统转去 legacy planner，最终把真实故障点隐藏掉了。

## 决策

将 native planner 提升为唯一的生产规划路径。

当 native planning 失败时，系统不再回退到 legacy planner，而是直接以明确的 planner failure 响应结束当前 turn。

## 目标

- 去掉主 agent loop 中的静默 planner 模式切换。
- 让 `ask_user_question` 恢复后的 turn 生命周期保持确定性。
- 将 native planner 失败提升为一等运行结果，而不是兼容分支。
- 保留现有 terminal answer 渲染路径，让用户仍能看到明确可感知的失败提示。

## 非目标

- 本次改动不同时删除仓库内全部 legacy planner 代码。
- 不在本次改动里重做 planner prompt 或 tool schema。
- 不在本次改动里增加“重试本轮”UX。
- 不处理无关的 `askUserQuestionResult` 展示问题。

## 方案

### `AgentPlannerService.planNextDecision`

- 保持当前 `_llm.planTurnDecision(...)` 调用方式不变。
- native planner 成功返回时，继续走 `_sanitizeDecision(...)`。
- native planner 抛错或返回 `null` 时，直接返回一个 terminal `ModelTurnDecision`，其内容为：
  - 无 tool calls
  - 一个面向用户的失败提示
  - `diagnosticCode: 'planner_request_failed'`
  - 空的 `providerState`
  - `isTerminal: true`
- 这个方法不再调用 `_requestLegacyPlannerRaw(...)`。

### `TurnHarness._continueTurnLoop`

- 保持现有 terminal decision 的消费逻辑不变，继续沿用最终回答流式输出路径。
- 因为 planner failure 现在会作为显式 terminal decision 返回，所以 harness 不需要再增加额外 fallback 分支。
- 当前 turn 应该正常收敛并结束，界面展示明确失败提示，而不是停留在模糊的 running 状态。

### Legacy Planner 代码

- 暂时保留 `planNextAction()` 及其解析辅助代码，便于过渡阶段比对与后续清理。
- 它们不再属于 agent loop 的自动恢复路径。
- 等 native-only 路径稳定后，再做后续删除即可。

## 错误处理

native planner 失败应被视为规划层的确定性失败，而不是兼容机会。

我们希望只有以下三类结果：

- native planner 成功：继续执行 tool loop，或走 final answer 路径
- native planner 不可用 / 响应无效：直接返回 terminal planner failure
- turn verifier 拒绝停止：仍然只在 native path 内继续下一轮

这样可以保证运行时状态真实、透明，不再掩盖 provider 侧问题。

## 测试策略

补充或更新测试，覆盖以下行为：

- `planNextDecision()` 在 native planner 返回 `null` 时，直接返回 terminal planner failure
- `planNextDecision()` 在 native planner 抛错时，直接返回 terminal planner failure
- 上述两种情况下都不会再尝试 legacy planner
- 现有 native 成功路径行为保持不变

## 风险

- 由于不再有兼容 fallback，开发阶段的 planner 失败会更快暴露出来。
- 目前依赖 fallback 行为的回归测试需要同步改写。

这些代价是可接受的，因为当前 App 没有线上兼容包袱，而且整体架构已经明显围绕 provider-native turn state 在建设。
