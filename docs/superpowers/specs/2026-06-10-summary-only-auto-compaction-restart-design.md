# Summary-Only 自动压缩续跑设计

## 摘要

本设计解决当前 session compaction 的两个核心问题：

1. 自动压缩只能压缩已完成历史，无法拯救“当前活跃 turn 内工具结果持续膨胀”的场景。
2. 压缩触发口径与 UI 百分比展示口径不一致，导致用户看到“已经 170% 但并未自动压缩”“下一条消息又变成 33%”这类不稳定表现。

本轮设计明确采用一套更接近 Claude Code 的策略，但保留本项目自己的架构边界：

- 只做 `conversation compaction`
- 不做 `session memory`
- 不做跨 session `memory`
- 不做 `messagesToKeep`
- 压缩后采用 `summary-only` 重启
- 自动压缩后系统自动续跑
- 续跑只能依赖 summary，不依赖旧上下文原文

这意味着：

> 当活跃 turn 中途触发自动压缩时，系统会把“当前 planner 可见的已发生上下文”压缩成一条新的 snapshot summary，结束旧 turn，并立即启动一个内部 continuation turn。新的 planner 请求只从 `runtime user context + summary + continuation turn 新增 transcript` 继续。

## 背景

当前项目已经有 session context、summary snapshot、自动压缩和上下文窗口 UI，但它们仍停留在“第一版历史压缩”：

- `SessionContextService` 只会压缩 `completed turns`
- `SessionContextSnapshot` 只记录 `coveredUntilTurnId`
- `TurnHarness` 在活跃 turn 内会不断把 `toolResult` / `toolError` / `userInteractionResult` 追加到 transcript，再继续 planner loop
- UI indicator 显示的是 `totalWindowUsageRatio`
- 自动压缩判断使用的是 `usableInputBudget` 上的 ratio

这套实现能处理“会话长期累积”的问题，但无法处理“单个 turn 内不断膨胀”的问题。

## 本轮明确决策

基于本次对齐，以下结论视为本轮设计前提：

- `session memory` 不纳入范围
- 跨 session memory 不纳入范围
- `messagesToKeep` 不纳入 V1
- summary 仍然存为一个原始文本 blob，不做结构化解析存储
- summary prompt 尽量复用 Claude Code 的原始约束，不优先自行发明另一套模板
- 自动压缩触发后应自动续跑，不应停住等待用户再次发送
- 续跑时不引入新的“请继续” synthetic user message
- 续跑时只能依赖新的 summary 继续
- 自动压缩检查点先保持简单统一，不做多套复杂阈值

## 目标

本轮目标如下：

- 让自动压缩可以在活跃 turn 中途生效，而不是只压缩已完成 turn
- 让压缩触发指标与 UI 主展示指标回到同一预算口径
- 保留 Claude Code 风格的高密度 continuation summary 约束
- 在压缩后自动续跑当前任务，不要求用户重新发送
- 保持现有 UI 表现尽量不变，继续使用 `已压缩历史上下文` 作为轻量边界
- 保持 append-only transcript 作为唯一语义事实源

## 非目标

本轮不包含以下内容：

- 不引入 session memory 文件或 markdown notes
- 不引入 memdir / persistent memory
- 不实现 Claude Code 的 `messagesToKeep`
- 不在压缩后保留上一轮原始 recent tail
- 不重做 tool result projection 规则
- 不引入复杂的多阶段 warning / block / compact 策略
- 不新增明显的 UI 流程打断或让用户处理“是否压缩”的交互

## 现状问题

## 1. 当前自动压缩只作用于 completed history

当前 `SessionContextService.buildPlannerContextState()` 会在预算压力过高时调用 `_compactHistory()`，但 compaction source 来自历史 completed turns，当前 turn transcript 不在可压缩边界内。

结果是：

- 老历史可能已经被压掉
- 但活跃 turn 中持续追加的 tool results 仍会不断膨胀
- 只要超限压力主要来自当前 turn，现有自动压缩就救不了

这正是连续 `web_search`、`fetch_webpage`、多轮工具调用时最容易触发的问题。

## 2. 当前 UI 百分比与自动压缩判断不是同一口径

当前实现里：

- 自动压缩判断看的是 `usableInputBudget`
- composer indicator 看的是 `totalWindowUsageRatio`

这会造成两个用户不可理解的现象：

- 同一份上下文，在“总窗口占比”上已经看起来爆表，但在“可用输入预算”上未必越线
- 一旦压缩后某些保留项或预留项变化，显示百分比会和用户直觉断裂

结论很直接：

> 自动压缩的正式判定指标与 UI 的主百分比展示，必须回到同一个预算基准。

## 3. `web_search` 的确会显著吃掉当前 turn input

当前并不是把 `web_search` 的原始 JSON 全量塞回 planner context，但它的结果会进入 planner-visible transcript 投影：

- `web_search` 会保留 query、前几条结果、url、snippet
- `fetch_webpage` 还可能带入较长的 `processedContent` 或首个 chunk 文本
- 同一 turn 内多次调用会持续累加

因此：

- `web_search` 不是“全量 raw payload 直接回灌”
- 但它仍然是当前 turn input 膨胀的重要来源
- `fetch_webpage` 往往比单次 `web_search` 更重

本轮不通过“进一步削工具结果”来解决原始 bug，而是通过“允许活跃 turn 自动压缩重启”来解决。

## 设计原则

## 1. Session memory 对模型来说就是下一次请求的完整输入

本项目从模型视角的唯一 session memory，就是“下一次真正发给模型的全部上下文”。

数据库里存了多少历史并不重要，只有被重新组装进下一次 planner 请求的那部分才算 input。

## 2. 压缩的目标是保留继续工作所需信息，而不是保留展示友好性

压缩是为了解决上下文长度受限问题，因此应优先保留：

- 用户真实请求和纠偏
- 已确认事实、约束、决策
- 关键工具结论
- 当前工作状态
- 继续当前任务所需的下一步上下文

而不是优先保留原始聊天展示形态。

## 3. 活跃 turn 中途自动压缩后，不再依赖旧原文继续

本轮选择 `summary-only`，因此一旦压缩完成：

- 旧上下文原文不再继续进入下一次 planner 请求
- 系统只能依赖新的 summary 继续
- 这是刻意设计，不是兼容退化

## 4. Transcript 事实源不变，只改变其后续是否被重新带入 planner

压缩后并不是删除旧 transcript 事实；事实仍保存在：

- `chat_events`
- `chat_turns`
- `chat_turn_steps`

改变的是：

- 下一次 planner 请求不再携带旧原文
- 而改为携带新的 summary snapshot

## 预算模型与正式触发指标

## 1. 术语

### `maxContextTokens`

模型或应用为该模型设定的总上下文窗口上限。

### `providerInputCap`

某些平台或网关可能额外限制“单次输入最多多少 tokens”。该值不一定存在，但一旦存在，必须参与最终预算计算。

### `effectiveInputBudget`

本轮定义的正式输入预算：

```text
effectiveInputBudget =
  min(
    providerInputCap 或 +inf,
    maxContextTokens
      - reservedOutputTokens
      - reasoningReserveTokens
      - safetyMarginTokens
  )
```

说明：

- 如果 provider 没有单独 input cap，则退化为当前 `usableInputBudget`
- 如果 provider 明确限制 input 小于总窗口，则以较小者为准

### `estimatedPlannerInputTokens`

下一次 planner 请求预计会发送的输入 token 数：

```text
estimatedPlannerInputTokens =
  fixedPrefixTokens
  + summaryTokens
  + recentTurnsTokens
  + currentTurnTokens
  + toolSchemaTokens
```

其中：

- `fixedPrefixTokens` = system prompt + runtime user context
- `summaryTokens` = snapshot summary
- `recentTurnsTokens` = 本轮保留的 recent raw turns
- `currentTurnTokens` = 当前 turn transcript
- `toolSchemaTokens` = tools description / schema / planner-side tool config

当前实现对 `toolSchemaTokens` 估算不足，本轮需要补进正式预算。

## 2. 正式自动压缩阈值

本轮不再把 ratio 作为第一判定指标，而改为基于 token threshold：

```text
autoCompactTriggerTokens =
  effectiveInputBudget - autoCompactBufferTokens
```

V1 采用：

- `autoCompactBufferTokens = 13_000` 默认值
- 支持按模型 profile 覆盖

选择理由：

- 与 Claude Code 的“effective window - buffer”思路一致
- 比纯 ratio 更容易稳定地解释“为什么现在压缩”
- 对 128k 级模型足够保守，能给工具 schema、估算误差和 provider 波动留余量

## 3. UI 百分比口径

自动压缩的正式判定用 token threshold，但 UI 仍可显示百分比。规则如下：

### 主百分比

主展示百分比改为：

```text
plannerInputUsageRatio =
  estimatedPlannerInputTokens / autoCompactTriggerTokens
```

这个百分比应成为：

- composer 小圆环
- 颜色分级
- “何时接近自动压缩” 的主展示指标

### 次级诊断百分比

以下值仍可在 bottom sheet 中展示，但属于诊断信息：

- `占总窗口比例`
- `占 effective input budget 比例`

这样可以保留调试价值，但避免把用户的主心智建立在错误指标上。

## 自动压缩检查点

本轮先采用简单统一的检查点策略：

## 1. 首次进入 turn planner 前

适用于：

- 用户刚发出新消息，准备进入第一轮 planner

目的：

- 避免“用户消息一进来就已经超限，但要等下一轮才压缩”

## 2. 每次 planner 决策前

位置上落在 `TurnHarness._continueTurnLoop()` 中，在真正调用 `planNextDecision()` 前执行。

目的：

- 覆盖多轮 tool loop 之后的再次规划
- 覆盖 auto-continue continuation turn 的每一次下一步规划

## 3. 每次新的 planner-visible 结果事件落地后

包括：

- `toolResult`
- `toolError`
- `userInteractionResult`

目的：

- 这些事件往往正是上下文暴涨来源
- 事件一旦落地，就应立刻判断是否需要在进入下一次 planner 前先压缩重启

## 4. 本轮不单独增加 final-answer 前检查点

理由：

- 本轮核心 bug 集中在 planner/tool loop 阶段
- final answer 阶段通常继承的就是刚刚通过上述检查点确认过的 planner input
- V1 先不扩散复杂度

后续如果发现 final-answer stage 也经常单独爆预算，再补专门检查点。

## Summary-Only 压缩与自动续跑流程

## 1. 触发条件

当某个检查点上：

```text
estimatedPlannerInputTokens >= autoCompactTriggerTokens
```

则触发自动压缩。

## 2. 自动压缩边界

本轮压缩边界不再只到 turn，而要能到 event。

触发时选择：

- 当前 group 下最新 active snapshot 之后的全部未压缩历史
- 外加当前 turn 中截至“当前检查点最后一个 planner-visible event”为止的 transcript 前缀

这意味着自动压缩可以覆盖：

- 已完成 turns
- 当前活跃 turn 中已经发生的 user / assistant planner / tool / interaction 事件

## 3. 压缩后旧 turn 如何处理

自动压缩发生在活跃 turn 内时：

1. 旧 turn 追加 `contextCompacted` 边界
2. 旧 turn 停止继续向下 planner
3. 旧 turn 以 `completed + stopReason=auto_compacted_continue` 结束

说明：

- V1 不新增新的 turn status 枚举
- turn 是否因压缩续跑结束，通过 stop reason 和 runtime marker 区分

## 4. continuation turn 如何创建

系统立即创建一个内部 continuation turn：

- 同 group
- 继承当前 provider style / model / runtime markers / workspace markers
- 不追加新的可见 user bubble
- 不生成 synthetic “请继续” user message

这个 continuation turn 的存在只服务于：

- 让 append-only transcript 继续保持清晰的 turn 边界
- 让后续 planner / tool loop / final answer 继续工作

## 5. continuation turn 的下一次输入从哪里来

本轮明确采用：

> 仅来自新的 snapshot summary 与 continuation turn 此后新增的 transcript。

也就是说 continuation turn 的第一次 planner 请求组成如下：

- system prompt
- runtime user context
- 最新 snapshot summary
- continuation turn 当前 transcript

其中 continuation turn 当前 transcript 在首次进入 planner 时通常为空。

这正是本轮 `summary-only` 的核心语义：

- 不保留旧 raw recent messages
- 不保留 `messagesToKeep`
- 不额外合成一条“请继续刚才任务”的用户消息
- 系统继续执行的能力完全依赖 summary 质量

## Summary Prompt 设计

## 1. 总体原则

summary prompt 尽量复用 Claude Code 的原始约束：

- 使用 `<analysis>...</analysis>` 作为模型内部草稿区
- 使用 `<summary>...</summary>` 作为唯一正式输出
- 要求 chronology、用户明确请求、技术决策、错误修复、当前工作、待办事项等都被覆盖
- 要求保留 `All user messages`

## 2. 存储与解析

本项目只保留：

- `<summary>` 的纯文本内容

不做：

- `<analysis>` 持久化
- 结构化字段解析存储
- summary DTO 化

## 3. 对 Claude 模板的最小改造

本项目不是 coding-only 产品，因此只做以下最小调整：

### 保持原结构不变

继续保留 Claude 的核心栏目：

1. Primary Request and Intent
2. Key Technical Concepts
3. Files and Code Sections
4. Errors and fixes
5. Problem Solving
6. All user messages
7. Pending Tasks
8. Current Work 或 Work Completed
9. Optional Next Step 或 Context for Continuing Work

### 只补一条适配说明

对第 3 节增加补充约束：

- 如果当前任务没有代码文件，则该节改为记录关键工具结论、界面/内容对象、产物路径、配置对象或其他继续任务所需的重要工作表面

换言之：

- 不重写 Claude 的栏目体系
- 只在“非代码任务也可能发生”这一点上做最低限度适配

## 4. 本轮优先使用的模板语义

由于压缩后 summary 会成为新 continuation 的起点，本轮优先采用“summary 之后还会继续出现新消息”的模板语义。

因此更接近 Claude `PARTIAL_COMPACT_UP_TO_PROMPT` 的使用场景：

- summary 放在新会话前部
- 后续 continuation transcript 追加在它之后
- summary 需要承担 continuation handoff 职责

## Snapshot 与边界模型调整

## 1. 现有模型问题

当前 `SessionContextSnapshot` 只有：

- `coveredUntilTurnId`

这只能表达“整轮都被压缩掉”，无法表达：

- 活跃 turn 前半段已被压缩
- 活跃 turn 后半段仍需保留

## 2. V1 新边界字段

本轮为 snapshot 增加：

- `coveredUntilEventId INTEGER NULL`

语义如下：

- `coveredUntilTurnId` 之前的所有 turn 都被 summary 覆盖
- 如果 `coveredUntilEventId != null`，则 `coveredUntilTurnId` 这一 turn 内，`event.id <= coveredUntilEventId` 的前缀也被 summary 覆盖
- 如果 `coveredUntilEventId == null`，则表示 legacy whole-turn coverage

## 3. 读取规则

构建 planner context 时：

- 先跳过 snapshot 完全覆盖的历史 turns
- 如果当前 turn 就是 `coveredUntilTurnId` 且存在 `coveredUntilEventId`，则只保留该 turn 中边界之后的 transcript 后缀

这样可以实现“同一 turn 被从中间切开并重新开始”。

## 4. 写入规则

### 手动压缩

如果仍是 completed history compaction：

- 继续写 `coveredUntilTurnId = lastCompactedTurnId`
- `coveredUntilEventId = null`

### 自动压缩活跃 turn

如果压缩边界落在活跃 turn 内：

- `coveredUntilTurnId = currentTurnId`
- `coveredUntilEventId = boundaryEventId`

## UI 与诊断面板

## 1. composer indicator

indicator 的环形进度和颜色分级改为使用：

- `plannerInputUsageRatio`

而不是：

- `totalWindowUsageRatio`

这样用户看到的百分比就是“距离自动压缩触发线还有多少空间”。

## 2. bottom sheet

bottom sheet 中继续展示更多诊断项：

- planner input 主百分比
- total window ratio
- effective input budget ratio
- estimated input tokens
- trigger tokens
- reserved output / reasoning reserve / safety margin / free headroom

这样既保持可解释性，又不把错误指标放在主入口。

## 3. timeline 表现

timeline 继续只展示轻量边界：

- `已压缩历史上下文`

本轮不新增更重的消息卡片或说明块。

## 与当前实现的关系

## 1. 手动 `/compact`

手动压缩与自动压缩应复用：

- 同一 summary prompt 体系
- 同一 snapshot 文本格式
- 同一 context boundary UI

但本轮自动压缩新增的“活跃 turn 中途重启”能力，不要求手动 `/compact` 同步支持。

## 2. 当前 tool result projection

当前 `ToolResultContextProjector` 保持不变。

这意味着：

- `web_search` / `fetch_webpage` 仍可能是重要上下文来源
- 本轮优先解决“何时压缩、如何续跑”，不同时解决“工具结果该不该更短”

## 3. 当前 summary prompt

当前 `SessionSummaryService.summaryInstructionPrompt` 是较原始的固定栏目模板，本轮应升级为 Claude 风格高密度 continuation 模板。

## 主要改动文件

本轮预期主要涉及以下文件：

- `lib/models/session/model_budget_profile.dart`
- `lib/models/session/context_compaction_config.dart`
- `lib/models/session/session_context_snapshot.dart`
- `lib/models/session/context_window_snapshot.dart`
- `lib/services/model_budget_registry.dart`
- `lib/services/session_token_budget_service.dart`
- `lib/services/session_summary_service.dart`
- `lib/services/session_context_service.dart`
- `lib/services/turn_harness.dart`
- `lib/services/session_context_inspector_service.dart`
- `lib/widgets/context_window/context_window_usage_indicator.dart`
- `lib/widgets/context_window/context_window_usage_color.dart`
- `lib/widgets/context_window/context_window_bottom_sheet.dart`
- `lib/repositories/session_context_snapshot_repository.dart`
- `lib/database/database_helper.dart`
- 与 `chat_turn` 创建/续跑有关的 coordinator 或 harness 入口

## 实施要点

## 1. 先统一预算口径，再改续跑

推荐实现顺序：

1. 先把 `effectiveInputBudget` / `triggerTokens` / UI ratio 统一
2. 再把 `toolSchemaTokens` 补进预算
3. 再扩 snapshot 到 event 级边界
4. 最后实现 active-turn auto-compaction restart

原因：

- 这样可以先解决“显示与触发不一致”的问题
- 也能让后续续跑调试时有稳定的观测口径

## 2. auto-continue 入口应尽量靠近 TurnHarness

自动压缩续跑是 planner/tool loop 行为，不应散落到 UI controller 或 message projection 层。

因此主要编排入口应留在：

- `TurnHarness`
- `SessionContextService`

而不是在 UI 侧拼凑。

## 3. 不要让 provider continuation 成为续跑依赖

压缩后 continuation 只应依赖：

- 新的 snapshot summary
- 新 continuation turn 之后新增的 transcript

不应依赖：

- provider-native `previous_response_id`
- 原始 assistant message 续传
- 任何“虽然上下文没带，但 provider 还记得”的隐式状态

## 验证要求

本轮至少要覆盖以下验证场景：

## 1. 长历史 idle chat 手动压缩

确认：

- summary prompt 升级后 snapshot 内容正确
- UI 仍只显示 `已压缩历史上下文`

## 2. 活跃 turn 内 repeated web_search

构造：

- 同一 turn 内多次 `web_search`
- 触发自动压缩

确认：

- 自动压缩发生在当前 turn 内
- 不需要用户重新发送
- 系统自动进入 continuation turn 并继续规划

## 3. 活跃 turn 内 fetch_webpage 膨胀

构造：

- `fetch_webpage` 产生较大 planner-visible 文本

确认：

- 自动压缩在下一个 planner 前拦截
- 压缩后旧原文不再进入 planner

## 4. 百分比一致性

确认：

- composer 主百分比与自动压缩触发口径一致
- 不再出现“UI 170% 但未触发”“下一条消息又 33%”这类口径错乱

## 5. continuation 只靠 summary 继续

确认：

- continuation 首次 planner 请求中不再带旧 raw recent messages
- 不存在 synthetic “continue” 用户消息
- 任务仍能沿着 summary 指向继续

## 后续可选优化

以下内容明确留到本轮之后再看：

- `messagesToKeep` 恢复为可选高级策略
- 对 `web_search` / `fetch_webpage` projection 进一步瘦身
- final-answer stage 单独预算检查
- 更精细的 warning / blocking / compact 分层
- session memory / cross-session memory

## 结论

本轮设计的核心不是“再美化一次 summary”，而是把 compaction 真正升级为一个能处理中途上下文爆炸的运行时机制。

它有三个不可拆分的收口点：

- 用统一的 `effective input budget + trigger tokens` 解决显示与触发口径不一致
- 用 event 级 snapshot boundary 允许活跃 turn 中途压缩
- 用 `summary-only` continuation turn 让系统在压缩后自动续跑，但只依赖新的 summary 继续

这三个点同时成立，才能真正解决本次暴露出来的原始 bug。
