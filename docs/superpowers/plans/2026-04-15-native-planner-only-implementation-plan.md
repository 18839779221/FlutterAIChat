# Native Planner 单一路径实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 去掉 agent loop 对 legacy planner 的自动回退，让 native planner 失败时显式结束当前 turn。

**Architecture:** 保持 `AgentPlannerService.planNextDecision()` 作为 loop 唯一的生产规划入口。将原来的 fallback 分支替换成明确的 terminal failure decision，同时沿用 `TurnHarness` 现有的 terminal-answer 渲染路径，确保用户仍能看到可感知的失败提示。

**Tech Stack:** Flutter、Dart、flutter_test、基于 Riverpod 的 agent loop 服务层

---

### Task 1: 用测试锁定 Native-Only 行为

**Files:**
- Modify: `test/services/agent_planner_service_test.dart`

- [ ] **Step 1: 先写 native 返回 `null` 的失败测试**

新增一个测试，让 planner LLM 的 `planTurnDecision()` 返回 `null`，并断言 `planNextDecision()` 会直接返回 terminal failure decision，而不是再去调用 legacy planner。

- [ ] **Step 2: 跑定向测试，确认它先失败**

Run: `fvm flutter test test/services/agent_planner_service_test.dart --plain-name "planNextDecision returns terminal planner failure when native planner returns null"`
Expected: FAIL，因为当前实现仍会 fallback 到 legacy planner。

- [ ] **Step 3: 再写 native 抛异常的失败测试**

新增第二个测试，让 `planTurnDecision()` 抛错，并断言结果同样是 terminal failure，且不会触发 legacy planner。

- [ ] **Step 4: 跑第二个定向测试，确认它先失败**

Run: `fvm flutter test test/services/agent_planner_service_test.dart --plain-name "planNextDecision returns terminal planner failure when native planner throws"`
Expected: FAIL，因为当前实现仍会 fallback 到 legacy planner。

### Task 2: 移除 `planNextDecision` 中的自动 Legacy Fallback

**Files:**
- Modify: `lib/services/agent_planner_service.dart`
- Test: `test/services/agent_planner_service_test.dart`

- [ ] **Step 1: 只写最小实现**

修改 `planNextDecision()`：

- native planner 成功时，仍返回 `_sanitizeDecision(...)`
- native planner 返回 `null` 或抛错时，直接返回：

```dart
const ModelTurnDecision(
  toolCalls: [],
  assistantMessage: '抱歉，我暂时无法规划下一步动作，请直接重试。',
  diagnosticCode: 'planner_request_failed',
  providerState: {},
  isTerminal: true,
)
```

这个方法不再调用 `_requestLegacyPlannerRaw(...)`。

- [ ] **Step 2: 跑两个新测试**

Run:
- `fvm flutter test test/services/agent_planner_service_test.dart --plain-name "planNextDecision returns terminal planner failure when native planner returns null"`
- `fvm flutter test test/services/agent_planner_service_test.dart --plain-name "planNextDecision returns terminal planner failure when native planner throws"`

Expected: PASS

- [ ] **Step 3: 改写旧的 fallback 回归测试**

把原来断言“会 fallback”的测试改成断言“会直接返回 native-only failure”，让测试语义与新架构一致。

- [ ] **Step 4: 跑完整个 planner-service 测试文件**

Run: `fvm flutter test test/services/agent_planner_service_test.dart`
Expected: PASS

### Task 3: 确认 Turn 级行为仍然能展示失败消息

**Files:**
- Modify: `test/services/turn_harness_test.dart`（如果缺测试才改）

- [ ] **Step 1: 先检查现有 turn harness 覆盖**

确认当前测试是否已经证明：terminal planner failure decision 会继续走最终回答路径，并正常结束 turn。

- [ ] **Step 2: 如果缺覆盖，再补一个失败测试**

如果没有现成覆盖，就新增一个测试：planner 返回 terminal failure decision 时，harness 仍会发出 assistant text / final answer 事件并完成 turn。

- [ ] **Step 3: 跑 turn harness 的定向测试**

Run: `fvm flutter test test/services/turn_harness_test.dart --plain-name "planner failure decision completes turn with visible failure message"`
Expected: PASS

### Task 4: 验证并清理表述

**Files:**
- Modify: `docs/superpowers/specs/2026-04-15-native-planner-only-design.md`（如实现细节有偏移）
- Modify: `docs/superpowers/plans/2026-04-15-native-planner-only-implementation-plan.md`（如步骤文案需修正）

- [ ] **Step 1: 跑聚焦验证**

Run:
- `fvm flutter test test/services/agent_planner_service_test.dart test/services/turn_harness_test.dart`
- `fvm flutter analyze lib/services/agent_planner_service.dart test/services/agent_planner_service_test.dart test/services/turn_harness_test.dart`

Expected: PASS

- [ ] **Step 2: 清理遗留的 fallback 文案**

检查注释、测试名或说明里是否还把 `planNextDecision()` 描述成 legacy-fallback 路径；只更新这次变更直接影响到的表述。

- [ ] **Step 3: 在 native-only 路径全绿后提交**

```bash
git add lib/services/agent_planner_service.dart \
  test/services/agent_planner_service_test.dart \
  test/services/turn_harness_test.dart \
  docs/superpowers/specs/2026-04-15-native-planner-only-design.md \
  docs/superpowers/plans/2026-04-15-native-planner-only-implementation-plan.md
git commit -m "refactor: remove legacy planner fallback from agent loop"
```
