# Agent Loop Phase 2 实施计划

> **给执行型 agent：** 必须沿当前 `TurnHarness / TurnVerifier / ToolAccessSnapshot` 主链继续推进，不要回退到旧命名，也不要重新引入按工具名驱动的硬规则。步骤使用复选框（`- [ ]`）追踪进度。

**目标：** 把 tool exposure、execution policy、confirmation policy、UI projection 四条链路进一步收拢成统一契约，减少“planner 看一套、runtime 执行一套、UI 展示再手搓一套”的分叉。

**架构说明：** Phase 2 不做大重写，重点是把已经存在的 `toolAccess / executionPolicy` 语义推成真正稳定的中间层，并开始收缩 `ChatSendCoordinator` / `ChatBlockBuilder` 的硬映射逻辑。该阶段仍以“先稳定契约，再挪实现”为原则。

**技术栈：** Flutter、Dart、Riverpod、repository 持久化、`flutter_test`

---

## 文件边界

### 需要修改的核心文件

- `lib/services/planner_tool_exposure_service.dart`
  - 从“仅过滤 blocked / visible”升级为真实 exposure 选择层
  - 输入输出继续围绕 `ToolAccessSnapshot`

- `lib/services/tool_policy_service.dart`
  - 明确 visibility / execution / confirmation 三类策略语义
  - 避免 UI、planner、runtime 各自解释同一策略

- `lib/services/tool_orchestrator_service.dart`
  - 确保 runtime 严格消费统一 policy 结果
  - 不再在运行时临时拼另一套确认/阻断语义

- `lib/controllers/chat_send_coordinator.dart`
  - 继续缩小 `ChatEventType -> ChatMessage/ChatSendPhase` 的手写映射

- `lib/services/chat_block_builder.dart`
  - 让 UI block 投影尽量基于统一 payload 语义，而不是按 message type 分散猜测

### 需要修改或新增的测试文件

- `test/services/planner_tool_exposure_service_test.dart`
- `test/services/tool_policy_service_test.dart`
- `test/services/tool_orchestrator_service_test.dart`
- `test/providers/chat_controller_tool_flow_test.dart`
- `test/services/chat_block_builder_test.dart`

### 行为变化明显时再考虑更新的文档

- `README.md`
- `AGENTS.md`
- `docs/architecture/2026-04-13-agent-loop-gap-analysis.md`
- `docs/architecture/2026-04-13-agent-loop-remediation-roadmap.md`

---

## 任务 1：让 Planner Exposure 真正基于 ToolAccessSnapshot

**文件：**
- 修改：`lib/services/planner_tool_exposure_service.dart`
- 测试：`test/services/planner_tool_exposure_service_test.dart`

- [ ] **步骤 1：先补失败测试，锁定 exposure 选择规则**

新增测试，至少覆盖以下点：

```dart
test('planner exposure 只消费 ToolAccessSnapshot，不再额外依赖 blocked name set', () async {
  // 期望：planner 看到的集合只由 snapshot 决定。
});

test('blocked tool 不会出现在 planner exposure 中，auto_run / require_confirmation 会保留', () async {
  // 期望：blocked 被过滤，其余策略都保留。
});
```

- [ ] **步骤 2：运行 exposure 测试**

运行：

```bash
~/.pub-cache/bin/fvm flutter test test/services/planner_tool_exposure_service_test.dart
```

- [ ] **步骤 3：收拢 `PlannerToolExposureService` 输入模型**

目标：

- 默认以 `List<ToolAccessSnapshot>` 作为主输入
- `selectVisibleTools()` 若仍保留，只作为兼容入口
- 不再让 planner exposure 自己重复解释 blocked 名单

- [ ] **步骤 4：重新运行 exposure 测试**

运行：

```bash
~/.pub-cache/bin/fvm flutter test test/services/planner_tool_exposure_service_test.dart
```

---

## 任务 2：把 Tool Policy 语义扩成真正统一的访问策略

**文件：**
- 修改：`lib/services/tool_policy_service.dart`
- 修改：`lib/models/tool/tool_access_snapshot.dart`
- 测试：`test/services/tool_policy_service_test.dart`

- [ ] **步骤 1：先补失败测试，锁定 policy 输出语义**

新增测试，至少覆盖以下点：

```dart
test('tool policy 会稳定输出 blocked / require_confirmation / auto_run 三种 execution policy', () async {
  // 期望：同一入口同时服务 planner、runtime、UI。
});

test('tool policy 输出的 planner visibility 与 execution policy 不会彼此矛盾', () async {
  // 期望：blocked 不可见；可见工具必须带明确 execution policy。
});
```

- [ ] **步骤 2：运行 policy 测试**

运行：

```bash
~/.pub-cache/bin/fvm flutter test test/services/tool_policy_service_test.dart
```

- [ ] **步骤 3：收紧 policy 语义**

目标：

- `ToolAccessSnapshot` 成为唯一共享快照
- 不再在其他层重复推导“是否可见 / 是否需确认 / 是否阻断”
- 策略标签和值的命名保持稳定，避免 UI 再做字符串映射

- [ ] **步骤 4：重新运行 policy 测试**

运行：

```bash
~/.pub-cache/bin/fvm flutter test test/services/tool_policy_service_test.dart
```

---

## 任务 3：让 Runtime 严格消费统一 policy，而不是再造局部规则

**文件：**
- 修改：`lib/services/tool_orchestrator_service.dart`
- 修改：`lib/services/tool_call_service.dart`
- 测试：`test/services/tool_orchestrator_service_test.dart`

- [ ] **步骤 1：先补失败测试**

新增测试，至少覆盖以下点：

```dart
test('runtime 会基于 shared toolAccess 产出 blocked tool result', () async {
  // 期望：blocked 不会落入 handler 执行分支。
});

test('runtime 会保留 require_confirmation 语义，而不是在 UI 层重新猜测', () async {
  // 期望：awaiting confirmation 的 payload 与 snapshot 一致。
});
```

- [ ] **步骤 2：运行 runtime 测试**

运行：

```bash
~/.pub-cache/bin/fvm flutter test test/services/tool_orchestrator_service_test.dart
```

- [ ] **步骤 3：实现统一消费**

目标：

- runtime 只消费 `ToolAccessSnapshot`
- blocked / confirmation / auto-run 三条分支只由统一快照驱动
- 不再在 runtime 中偷偷补一套“执行前特判”

- [ ] **步骤 4：重新运行 runtime 测试**

运行：

```bash
~/.pub-cache/bin/fvm flutter test test/services/tool_orchestrator_service_test.dart
```

---

## 任务 4：开始收缩 UI 投影层的硬映射

**文件：**
- 修改：`lib/controllers/chat_send_coordinator.dart`
- 修改：`lib/services/chat_block_builder.dart`
- 测试：`test/providers/chat_controller_tool_flow_test.dart`
- 测试：`test/services/chat_block_builder_test.dart`

- [ ] **步骤 1：先补失败测试**

新增测试，至少覆盖以下点：

```dart
test('chat block builder 会优先读取 executionPolicy / toolAccess，而不是从 message type 反推状态', () async {
  // 期望：UI block 投影直接依赖统一 payload。
});

test('send coordinator 不会为 blocked / require_confirmation / auto_run 再维护另一套独立状态语义', () async {
  // 期望：UI message 的关键策略字段来自事件 payload。
});
```

- [ ] **步骤 2：运行 UI 投影相关测试**

运行：

```bash
~/.pub-cache/bin/fvm flutter test test/services/chat_block_builder_test.dart
~/.pub-cache/bin/fvm flutter test test/providers/chat_controller_tool_flow_test.dart
```

- [ ] **步骤 3：实现最小收口**

目标：

- `ChatBlockBuilder` 优先消费 payload 中的统一策略字段
- `ChatSendCoordinator` 只负责事务和少量投影，不再扩张策略解释职责
- 避免新增新的 message-type-specific 状态推断

- [ ] **步骤 4：重新运行 UI 投影相关测试**

运行：

```bash
~/.pub-cache/bin/fvm flutter test test/services/chat_block_builder_test.dart
~/.pub-cache/bin/fvm flutter test test/providers/chat_controller_tool_flow_test.dart
```

---

## 任务 5：做一轮定向集成验证

**文件：**
- 核心链路：
  - `lib/services/turn_harness.dart`
  - `lib/services/turn_verifier.dart`
  - `lib/services/tool_policy_service.dart`
  - `lib/services/planner_tool_exposure_service.dart`
  - `lib/services/tool_orchestrator_service.dart`
  - `lib/controllers/chat_send_coordinator.dart`
  - `lib/services/chat_block_builder.dart`

- [ ] **步骤 1：运行定向 analyze**

```bash
~/.pub-cache/bin/fvm flutter analyze \
  lib/services/turn_harness.dart \
  lib/services/turn_verifier.dart \
  lib/services/tool_policy_service.dart \
  lib/services/planner_tool_exposure_service.dart \
  lib/services/tool_orchestrator_service.dart \
  lib/controllers/chat_send_coordinator.dart \
  lib/services/chat_block_builder.dart \
  test/services/turn_harness_test.dart \
  test/services/tool_policy_service_test.dart \
  test/services/planner_tool_exposure_service_test.dart \
  test/services/tool_orchestrator_service_test.dart \
  test/services/chat_block_builder_test.dart \
  test/providers/chat_controller_tool_flow_test.dart
```

- [ ] **步骤 2：运行定向测试**

```bash
~/.pub-cache/bin/fvm flutter test test/services/turn_harness_test.dart
~/.pub-cache/bin/fvm flutter test test/services/tool_policy_service_test.dart
~/.pub-cache/bin/fvm flutter test test/services/planner_tool_exposure_service_test.dart
~/.pub-cache/bin/fvm flutter test test/services/tool_orchestrator_service_test.dart
~/.pub-cache/bin/fvm flutter test test/services/chat_block_builder_test.dart
~/.pub-cache/bin/fvm flutter test test/providers/chat_controller_tool_flow_test.dart
```

### 本阶段完成标准

- planner / runtime / UI 三层都消费同一套 `toolAccess / executionPolicy` 语义
- blocked / require_confirmation / auto_run 三类状态不再被多处重复解释
- `ChatSendCoordinator` 和 `ChatBlockBuilder` 的投影逻辑明显收缩
- 不新增按工具名驱动的硬规则，也不回退到旧命名主链
