# Provider Capability Boundary Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在不改写 Agent Loop Core 的前提下，把“provider 风格识别”与“provider 能力声明”分离出来，让 `ConfigurableHttpLLM`、live contract tests、side-task / planner 选路能显式识别 streaming-only / stateless-only / partial compatibility provider。

**Architecture:** 本计划只触达 `Model Gateway / Provider Adapter` 及其测试与文档。`TurnHarness`、`TurnVerifier`、projection/UI 边界不在本计划内直接调整。实现目标是：provider 兼容问题继续留在 gateway 边界，不反向污染 Agent Loop Core。

**Tech Stack:** Flutter 3.29.2、Dart、flutter_test、真实 provider live contract tests、现有 `ConfigurableHttpLLM` adapter split 架构

---

## 范围与边界

本计划覆盖：

- 定义 provider capability 最小模型
- 让运行时 capability 与 API style 同时存在
- 让 live contract tests 按 capability 维度验证
- 让非流式 side-task / planner 路径对 capability 不足有清晰降级或失败语义

本计划明确不覆盖：

- `TurnHarness` 主循环重写
- UI projection 边界重构
- 将所有 provider 改造成统一的高级会话抽象
- 为半兼容 relay 引入过厚特判 DSL

## 背景结论

真实验证已确认至少存在一种 `responses`-like provider 具备以下能力组合：

- 支持 `stream:true`
- 支持 stateless continuation
- 支持 tool call -> tool result -> final answer round-trip
- 不支持 `stream:false`
- 不支持 `previous_response_id`

因此：

- `ApiStyle.responses` 不能再被默认为“完整 OpenAI Responses 能力”
- live contract tests 不能只按 `responses/chat completions/anthropic` 分类
- planner / summary / webpage side-task 的可用性需要 capability 边界来保护

---

## Task 1: 定义最小 Provider Capability Contract

**Files:**
- Create: `lib/models/llm/provider_capabilities.dart`
- Modify: `lib/models/llm/configurable_http_llm.dart`
- Create: `test/models/llm/provider_capabilities_test.dart`

- [ ] **Step 1: 先写 capability 失败测试**

测试至少覆盖：

```dart
test('responses style does not imply previous_response_id support');
test('responses style can be marked streaming-only');
test('capability defaults remain conservative when provider metadata is absent');
```

- [ ] **Step 2: 实现最小 capability 模型**

首批字段固定为：

- `supportsStreamingResponses`
- `supportsNonStreamingResponses`
- `supportsPreviousResponseId`
- `supportsStatelessContinuation`
- `supportsToolRoundTrip`

要求：

- 模型要轻量，避免一开始演进成 provider policy DSL
- 缺省值要保守，不要自动假定所有能力都存在

- [ ] **Step 3: 将 capability 接入 `ConfigurableHttpLLM` 的运行时决策**

至少先做到：

- `previous_response_id` 只在 capability 支持时优先走
- 若 capability 明确不支持，则直接走 stateless continuation
- 对非流式 side-task 路径，若 provider 明确不支持非流式，要么清晰失败，要么走后续阶段定义的受控替代路径

- [ ] **Step 4: 跑单测**

Run:
```bash
fvm flutter test test/models/llm/provider_capabilities_test.dart test/models/llm/configurable_http_llm_test.dart
```

- [ ] **Step 5: 提交这一小步**

```bash
git add lib/models/llm/provider_capabilities.dart lib/models/llm/configurable_http_llm.dart test/models/llm/provider_capabilities_test.dart test/models/llm/configurable_http_llm_test.dart
git commit -m "refactor: add provider capability contract"
```

## Task 2: 将 Live Contract Tests 从 API Style 扩展到 Capability 维度

**Files:**
- Modify: `test/models/llm/configurable_http_llm_live_test.dart`
- Modify: `scripts/run_live_llm_contract_tests.sh`
- Modify: `README.md`
- Modify: `AGENTS.md`

- [ ] **Step 1: 为 capability 维度补测试结构**

至少区分三类 live probe：

1. 基础首轮请求
2. tool continuation round-trip
3. `previous_response_id` 支持性探测

要求：

- “不支持某能力”与“实现回归失败”要在测试输出上区分清楚
- 不要把 capability 缺失伪装成全部测试通过

- [ ] **Step 2: 对 streaming-only provider 明确标注验证结果**

例如：

- 首轮流式通过
- stateless tool continuation 通过
- `previous_response_id` 不支持
- 非流式 contract 不通过

让真实 provider 报告更像 capability matrix，而不是单个 PASS/FAIL。

- [ ] **Step 3: 跑本地和 opt-in live tests**

建议至少验证：

```bash
fvm flutter test test/models/llm/configurable_http_llm_test.dart
bash scripts/run_live_llm_contract_tests.sh beehears-responses
bash scripts/run_live_llm_contract_tests.sh minimax-openai-chat-completions minimax-anthropic
```

- [ ] **Step 4: 提交这一小步**

```bash
git add test/models/llm/configurable_http_llm_live_test.dart scripts/run_live_llm_contract_tests.sh README.md AGENTS.md
git commit -m "test: report live provider capabilities explicitly"
```

## Task 3: 为非流式 Side Tasks 设定清晰边界

**Files:**
- Modify: `lib/models/llm/configurable_http_llm.dart`
- Modify: `test/models/llm/configurable_http_llm_test.dart`
- Modify: `docs/architecture/agent-loop-boundaries-and-decoupling.md`

- [ ] **Step 1: 先明确当前 side-task 受影响范围**

列出并确认：

- `planTurnDecision()`
- `summarizeConversation()`
- `processWebpageContent()`

其中哪些必须保留非流式，哪些可在后续阶段探索 streaming 替代。

- [ ] **Step 2: 为 capability 不足时的行为写失败测试**

至少覆盖：

```dart
test('summary path fails clearly on streaming-only provider');
test('planner path prefers stateless continuation when previous_response_id is unsupported');
```

- [ ] **Step 3: 实现清晰边界**

要求：

- 不要静默把 provider 兼容缺陷伪装成空结果成功
- 错误语义要能帮助区分“provider 不支持该能力”与“loop 决策失败”
- 不要把这类差异下沉到 Core

- [ ] **Step 4: 跑测试**

Run:
```bash
fvm flutter test test/models/llm/configurable_http_llm_test.dart
```

- [ ] **Step 5: 提交这一小步**

```bash
git add lib/models/llm/configurable_http_llm.dart test/models/llm/configurable_http_llm_test.dart docs/architecture/agent-loop-boundaries-and-decoupling.md
git commit -m "refactor: clarify streaming-only provider boundaries"
```

## 完成标准

- API style 与 provider capability 在文档和代码层都不再混用
- live contract tests 能明确报告 provider 的能力矩阵
- `previous_response_id` 不再被默认为所有 `responses` provider 都支持
- streaming-only / stateless-only provider 不会再被误判成“完整 OpenAI Responses provider”
- Agent Loop Core 不引入 provider 私有兼容逻辑
