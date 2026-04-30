# Streaming Planner Tool Call Assembly Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在不改变上层 planner / turn loop / tool runtime 合约的前提下，为 `ConfigurableHttpLLM.planTurnDecision(...)` 引入内部流式 tool-call 参数组装能力，按 `Anthropic Messages -> OpenAI Chat Completions -> OpenAI Responses` 的顺序渐进接入。

**Architecture:** 这次改动把 provider streaming 严格限制在 `ConfigurableHttpLLM`、`ApiStreamParser` 和新的内部 accumulator 范围内。上层仍然只消费完整的 `ModelTurnDecision`，不接触中间流式 delta，也不改变 tool 执行时机；三类 provider 通过统一的内部 chunk 模型和 `StreamingDecisionAccumulator` 收敛为同一条终态 decision 生产路径。

**Tech Stack:** Flutter / Dart、现有 `ConfigurableHttpLLM`、`ApiStreamParser`、三类 `ApiStyleAdapter`、HTTP SSE / streamed response、现有 LLM / planner 测试体系。

---

## 代码结构与职责

### 需要修改的文件

- 修改：`lib/models/llm/configurable_http_llm.dart`
  - 为 `planTurnDecision(...)` 增加内部流式分支
  - 按 `ApiStyle` 路由到 streaming planner 收敛路径
  - 保持外部接口和返回类型不变
- 修改：`lib/models/llm/api_stream_parser.dart`
  - 扩展三类 provider 的 tool-call / 参数增量解析
  - 产出统一内部流块
- 修改：`lib/models/llm/adapters/anthropic_messages_adapter.dart`
  - planner payload 支持 streaming 分支所需字段
  - 如需要，补充 provider-specific tool streaming 辅助解析逻辑
- 修改：`lib/models/llm/adapters/chat_completions_adapter.dart`
  - 同上，支持 streaming planner payload
- 修改：`lib/models/llm/adapters/responses_adapter.dart`
  - 同上，支持 streaming planner payload
- 修改：`test/models/llm/configurable_http_llm_test.dart`
  - 覆盖 planner 内部 streaming 收敛后的最终 decision 行为
- 修改：`test/models/llm/api_stream_parser_test.dart`
  - 补齐 tool-call / 参数增量解析测试

### 需要新增的文件

- 新增：`lib/models/llm/streaming_planner_chunk.dart`
  - 定义统一内部流块模型
- 新增：`lib/models/llm/streaming_decision_accumulator.dart`
  - 增量组装最终 `ModelTurnDecision`
- 新增：`test/models/llm/streaming_decision_accumulator_test.dart`
  - 锁定 accumulator 在多 provider 风格下的聚合行为

## 任务 1：锁定当前 planner 行为与流式接入边界

**Files:**
- Modify: `test/models/llm/configurable_http_llm_test.dart`
- Test: `test/models/llm/configurable_http_llm_test.dart`

- [ ] **Step 1: 盘点现有 `planTurnDecision(...)` 测试覆盖**

梳理当前已覆盖的 planner 行为：

- tool call decision
- terminal assistant decision
- providerState / continuation
- planner failure

记录哪些断言可直接复用，哪些需要在“内部流式收敛但外部仍返回完整 decision”的新路径上补强。

- [ ] **Step 2: 补一组“流式收敛后最终 decision 不变”的行为测试用例**

在 `test/models/llm/configurable_http_llm_test.dart` 中新增测试输入骨架，先只描述目标：

- 当 provider 流式返回 tool call 参数增量时，最终仍返回与非流式等价的 `ModelTurnDecision`
- 当 provider 流式返回 assistant 文本时，最终返回相同 terminal decision
- 当 provider 中途断流且未形成完整 tool call / assistant message 时，返回 `planner_request_failed`

此时可以先以 TODO 式 placeholder 或最小 fake stream fixture 固定用例形状。

- [ ] **Step 3: 运行现有 configurable_http_llm 测试，确保基线稳定**

Run:

```bash
fvm flutter test test/models/llm/configurable_http_llm_test.dart
```

Expected:

- PASS，作为后续重构基线

## 任务 2：建立统一内部流块模型

**Files:**
- Create: `lib/models/llm/streaming_planner_chunk.dart`
- Modify: `lib/models/llm/api_stream_parser.dart`
- Test: `test/models/llm/api_stream_parser_test.dart`

- [ ] **Step 4: 新增 `StreamingPlannerChunk` 模型**

定义只供 LLM 内部使用的统一流块类型，至少覆盖：

- `contentDelta`
- `reasoningDelta`
- `toolCallStarted`
- `toolCallArgumentsDelta`
- `toolCallCompleted`
- `streamCompleted`

字段保持通用，只表达：

- tool call identity
- tool name
- 参数文本增量
- provider metadata

不要为任何具体工具或参数字段做特判。

- [ ] **Step 5: 扩展 `ApiStreamParser` 的内部输出能力**

在不破坏现有文本流解析测试的前提下，新增 / 扩展 parser 逻辑，让三类 provider 最终都能产出统一 chunk。

第一步可以先让 parser 同时保留旧文本路径和新内部 chunk 路径，避免一次性推翻现有调用方。

- [ ] **Step 6: 为 parser 新增聚焦测试**

在 `test/models/llm/api_stream_parser_test.dart` 中覆盖：

- Anthropic tool use / 参数增量
- Chat Completions `tool_calls[].function.arguments` 增量
- Responses function call arguments delta / done

测试目标只锁“协议事件 -> 内部 chunk”映射，不碰最终 decision。

- [ ] **Step 7: 运行 parser 测试**

Run:

```bash
fvm flutter test test/models/llm/api_stream_parser_test.dart
```

Expected:

- PASS

## 任务 3：实现通用 `StreamingDecisionAccumulator`

**Files:**
- Create: `lib/models/llm/streaming_decision_accumulator.dart`
- Create: `test/models/llm/streaming_decision_accumulator_test.dart`

- [ ] **Step 8: 新增 `StreamingDecisionAccumulator` 与 `ToolCallDraft`**

实现 accumulator，职责包括：

- 聚合 assistant text
- 聚合 visible reasoning
- 维护一个或多个 `ToolCallDraft`
- 对 tool 参数做“原始缓冲 + 最终解析”
- 在流结束时产出最终 `ModelTurnDecision`

`ToolCallDraft` 至少包含：

- `providerCallId`
- `toolName`
- `rawArgumentsBuffer`
- `parsedArguments`
- `isCompleted`

- [ ] **Step 9: 写 accumulator 单测**

覆盖：

- 多段 assistant text 聚合
- 多段 reasoning 聚合
- 单 tool call 参数多段追加后成功解析
- 多 tool calls 并行 / 交错增量时仍能按 identity 正确归并
- 流结束但参数仍不可解析时，产出 failure / invalid decision 路径

- [ ] **Step 10: 运行 accumulator 测试**

Run:

```bash
fvm flutter test test/models/llm/streaming_decision_accumulator_test.dart
```

Expected:

- PASS

## 任务 4：先接入 Anthropic Messages 内部流式 planner 收敛

**Files:**
- Modify: `lib/models/llm/configurable_http_llm.dart`
- Modify: `lib/models/llm/api_stream_parser.dart`
- Modify: `lib/models/llm/adapters/anthropic_messages_adapter.dart`
- Modify: `test/models/llm/configurable_http_llm_test.dart`

- [ ] **Step 11: 为 Anthropic planner 请求增加 streaming 分支**

在 `ConfigurableHttpLLM.planTurnDecision(...)` 内，针对 `ApiStyle.anthropicMessages` 增加内部流式实现：

- 请求 `stream: true`
- 使用新的 parser + accumulator
- 最终仍返回完整 `ModelTurnDecision`

第一版只改 Anthropic 路径，其他 style 暂保持现有非流式实现。

- [ ] **Step 12: 处理 Anthropic 中途不完整参数容错**

确保：

- 中途参数片段不可解析时不立即失败
- 只有流结束后仍无法形成完整 tool call，才返回 planner failure

- [ ] **Step 13: 补 Anthropic 流式 planner 行为测试**

在 `test/models/llm/configurable_http_llm_test.dart` 中新增：

- Anthropic tool call 参数分段流式到达 -> 最终完整 decision
- Anthropic terminal assistant 流式到达 -> 最终 terminal decision
- Anthropic 中途断流 -> `planner_request_failed`

- [ ] **Step 14: 运行定向测试**

Run:

```bash
fvm flutter test test/models/llm/configurable_http_llm_test.dart
```

Expected:

- PASS

## 任务 5：接入 OpenAI Chat Completions 内部流式 planner 收敛

**Files:**
- Modify: `lib/models/llm/configurable_http_llm.dart`
- Modify: `lib/models/llm/api_stream_parser.dart`
- Modify: `lib/models/llm/adapters/chat_completions_adapter.dart`
- Modify: `test/models/llm/configurable_http_llm_test.dart`

- [ ] **Step 15: 为 Chat Completions planner 请求增加 streaming 分支**

按既定优先级接第二条协议：

- 请求 `stream: true`
- 从 `choices[].delta.tool_calls` 聚合 tool call
- 通过 accumulator 收敛为最终 decision

- [ ] **Step 16: 补 Chat Completions 流式 planner 行为测试**

覆盖：

- `tool_calls[].function.arguments` 多段追加
- assistant 文本流式返回
- 中途断流失败路径

- [ ] **Step 17: 运行定向测试**

Run:

```bash
fvm flutter test test/models/llm/configurable_http_llm_test.dart
```

Expected:

- PASS

## 任务 6：接入 OpenAI Responses 内部流式 planner 收敛

**Files:**
- Modify: `lib/models/llm/configurable_http_llm.dart`
- Modify: `lib/models/llm/api_stream_parser.dart`
- Modify: `lib/models/llm/adapters/responses_adapter.dart`
- Modify: `test/models/llm/configurable_http_llm_test.dart`

- [ ] **Step 18: 为 Responses planner 请求增加 streaming 分支**

按优先级接第三条协议：

- 请求 `stream: true`
- 解析 function call arguments delta / done
- 交由统一 accumulator 收敛

- [ ] **Step 19: 补 Responses 流式 planner 行为测试**

覆盖：

- tool 参数 delta 多段到达
- tool / assistant 终态正确收敛
- provider 断流 failure 路径

- [ ] **Step 20: 运行定向测试**

Run:

```bash
fvm flutter test test/models/llm/configurable_http_llm_test.dart
```

Expected:

- PASS

## 任务 7：把 planner 超时策略切到更适合 streaming 的模式

**Files:**
- Modify: `lib/models/llm/configurable_http_llm.dart`
- Modify: `test/models/llm/configurable_http_llm_test.dart`

- [ ] **Step 21: 区分 overall timeout 与 idle timeout**

在流式 planner 路径里，不再只依赖“整请求固定时长必须完整闭合”的策略。

实现方向：

- overall timeout：整次 planner 请求总上限
- idle timeout：一段时间内无任何 chunk 才判定卡死

只要持续收到增量 chunk，就不应因等待整包闭合而提前失败。

- [ ] **Step 22: 补 timeout 行为测试**

覆盖：

- 持续收到 chunk 时不会触发 idle timeout
- 长时间无 chunk 时触发 planner failure
- overall timeout 仍能兜底

- [ ] **Step 23: 运行定向测试**

Run:

```bash
fvm flutter test test/models/llm/configurable_http_llm_test.dart
```

Expected:

- PASS

## 任务 8：回归验证与文档对齐

**Files:**
- Modify: `README.md`
- Modify: `AGENTS.md`

- [ ] **Step 24: 检查 README 是否需要补充 planner streaming 内部实现说明**

若 README 中已有 `ConfigurableHttpLLM` / provider support / planner 路径说明，则更新为“planner 可在内部使用 streaming 收敛最终 decision”，避免文档滞后。

- [ ] **Step 25: 检查 AGENTS 是否需要补充相关实现约束**

若这次方案引入了新的长期边界（例如“planner streaming 不向上层暴露 delta”），则把约束同步到 `AGENTS.md`。

- [ ] **Step 26: 运行 analyze 与相关测试集合**

Run:

```bash
fvm flutter analyze
fvm flutter test test/models/llm/
```

Expected:

- Analyze PASS
- LLM 相关测试 PASS

## 风险提醒

- Anthropic fine-grained tool streaming 可能在中途提供不可直接解析的参数片段，不能把中间解析失败误当成 planner failure。
- 三类 provider 的 tool-call streaming 事件外观不同，parser 与 accumulator 的职责边界必须保持清晰，避免把 provider-specific 逻辑渗透进最终 decision 组装。
- 上层接口不变是这次方案的重要约束，任何让 `AgentPlannerService` / `TurnHarness` 感知中间流式过程的实现都应被视为越界。
