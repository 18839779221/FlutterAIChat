# Agent Loop Phase 1 实施计划

> **给执行型 agent：** 必须使用 `superpowers:subagent-driven-development`（推荐）或 `superpowers:executing-plans` 按任务逐步实现本计划。步骤使用复选框（`- [ ]`）追踪进度。

**目标：** 去除风险最高的 planner 硬编码规则，并把当前过弱的 stop condition 升级为真正具备运行时感知能力的 verifier。

**架构说明：** Phase 1 保持现有 turn loop 与 tool runtime 主干不变，只聚焦于两件事：一是去掉 planner 兼容层中按工具名驱动的硬规则，二是让 stop verification 基于 turn 与 step 的真实运行状态做判断。该阶段刻意不动 UI 协议和 transcript 主结构，优先修正 loop 正确性。

**技术栈：** Flutter、Dart、Riverpod、基于 repository 的 turn/step 持久化、`flutter_test` 单元测试

---

## 文件边界

### 需要修改的核心文件

- `lib/services/agent_planner_service.dart`
  - 去除 planner 路径上的静态 fallback allowlist
  - 去除按具体工具名写死的 repeated-empty-retrieval 短路规则
  - 保留 provider 兼容逻辑，但收口为解析与归一化职责

- `lib/services/turn_verifier.dart`
  - 把当前基于“文本是否为空”的 stop 判断替换为 turn-aware / step-aware 验证

- `lib/services/turn_harness.dart`
  - 向 verifier 传递正确的运行时状态
  - 保持 loop 所有权在这里，但不能继续默认 verifier 很弱

- `lib/repositories/chat_turn_step_repository.dart`
  - 仅当 verifier 需要新的 step 查询辅助方法时才修改

### 需要修改或新增的测试文件

- `test/services/agent_planner_service_test.dart`
  - 移除对静态 allowlist 或 retrieval 短路补丁的既有假设
  - 补充基于 metadata 的 planner 决策回归测试

- `test/services/stop_verifier_service_test.dart`
  - 从简单文本检查扩展到运行时感知 stop 判断

- `test/services/turn_harness_test.dart`
  - 验证 verifier 拒绝 stop 时 loop 会继续
  - 验证删除硬编码 planner 短路后主链仍能正常运行

### 行为变化明显时才考虑更新的文档

- `README.md`
- `AGENTS.md`

只有当 Phase 1 实现真的改变了项目级行为说明或协作约束时才更新这些文档。

---

### 任务 1：移除静态 Planner Allowlist 回退

**文件：**
- 修改：`lib/services/agent_planner_service.dart`
- 测试：`test/services/agent_planner_service_test.dart`

- [ ] **步骤 1：先写失败测试，锁定 planner 工具过滤行为**

新增测试，至少覆盖以下两个点：

```dart
test('planNextDecision 在 visible tools 为空时不会退回静态工具名 allowlist', () async {
  // 期望：planner 输出归一化后不会偷偷复活一组隐藏的 legacy allowlist。
});

test('planNextDecision 只基于当前真实 visible tool set 过滤工具', () async {
  // 期望：不支持的工具是因为当前不可见而被拒绝，
  // 而不是因为命中了另一套手写 legacy 工具列表。
});
```

- [ ] **步骤 2：运行 planner 测试文件，确认当前行为**

运行：

```bash
~/.pub-cache/bin/fvm flutter test test/services/agent_planner_service_test.dart
```

预期：
- 至少有一个新测试失败，因为当前实现仍然使用 `_legacyAllowedToolNames`

- [ ] **步骤 3：从 `AgentPlannerService` 中移除静态 allowlist fallback**

做最小实现修改，使得：

- visible tools 只来自当前 exposure 路径
- planner 决策归一化不再复活另一套静态 allowlist
- 不支持的工具仍只基于当前暴露出来的集合过滤

不要添加新的手写替代列表。

- [ ] **步骤 4：重新运行 planner 测试**

运行：

```bash
~/.pub-cache/bin/fvm flutter test test/services/agent_planner_service_test.dart
```

预期：
- planner 测试通过

- [ ] **步骤 5：提交**

```bash
git add lib/services/agent_planner_service.dart test/services/agent_planner_service_test.dart
git commit -m "refactor: remove legacy planner allowlist fallback"
```

---

### 任务 2：移除按工具名写死的 Retrieval 短路规则

**文件：**
- 修改：`lib/services/agent_planner_service.dart`
- 测试：`test/services/agent_planner_service_test.dart`
- 测试：`test/services/turn_harness_test.dart`

- [ ] **步骤 1：先写失败测试，锁定目标行为**

新增测试，至少覆盖以下两个点：

```dart
test('planner 不会基于工具名专门对空 retrieval 结果做硬停止', () async {
  // 期望：不再存在绑定 search_chat_history/web_search/fetch_webpage 的特殊短路。
});

test('harness 行为不依赖 planner 兼容层中的 retrieval 补丁', () async {
  // 期望：turn 是否继续推进，取决于 loop 状态与 verifier，
  // 而不是一个 planner 补丁。
});
```

- [ ] **步骤 2：运行受影响的测试**

运行：

```bash
~/.pub-cache/bin/fvm flutter test test/services/agent_planner_service_test.dart
~/.pub-cache/bin/fvm flutter test test/services/turn_harness_test.dart
```

预期：
- 新测试失败，因为 `_buildRepeatedEmptyRetrievalDecision()` 或其相关辅助方法仍在驱动 loop 行为

- [ ] **步骤 3：删除 retrieval 专用 planner 补丁**

删除或停用以下逻辑：

- `_buildRepeatedEmptyRetrievalDecision()`
- `_findLatestCompletedStep()`（若删除补丁后不再需要）
- `_isEmptyRetrievalResult()`（若删除补丁后不再需要）

保留的 planner 兼容层职责只应包括：

- provider 归一化
- 结构化解析
- 基于 exposed tools 的 decision sanitization

- [ ] **步骤 4：重新运行受影响测试**

运行：

```bash
~/.pub-cache/bin/fvm flutter test test/services/agent_planner_service_test.dart
~/.pub-cache/bin/fvm flutter test test/services/turn_harness_test.dart
```

预期：
- 更新后的测试通过
- 这两个测试文件中无额外无关回归

- [ ] **步骤 5：提交**

```bash
git add lib/services/agent_planner_service.dart test/services/agent_planner_service_test.dart test/services/turn_harness_test.dart
git commit -m "refactor: remove retrieval-specific planner short-circuit"
```

---

### 任务 3：把弱 Stop Verification 升级为运行时感知验证

**文件：**
- 修改：`lib/services/turn_verifier.dart`
- 修改：`lib/services/turn_harness.dart`
- 测试：`test/services/stop_verifier_service_test.dart`
- 测试：`test/services/turn_harness_test.dart`

- [ ] **步骤 1：先写 verifier 失败测试**

新增测试，至少覆盖以下两个点：

```dart
test('当 final text 非空但 turn 仍有未完成运行时工作时 verifier 会拒绝 stop', () async {
  // 例如：存在 pending confirmation、unfinished step，或 turn 状态仍不完整。
});

test('只有运行时状态完整时 verifier 才允许 stop', () async {
  // 例如：turn 已进入合法终止路径、没有 pending confirmation、没有未完成工作。
});
```

- [ ] **步骤 2：补一个 harness 回归测试，验证 verifier 拒绝 stop 时 loop 继续**

新增测试，至少覆盖以下点：

```dart
test('当 verifier 拒绝 stop 时 harness 会继续 loop', () async {
  // 期望：不是直接 mark completed，而是继续下一轮迭代。
});
```

- [ ] **步骤 3：运行 verifier 和 harness 测试**

运行：

```bash
~/.pub-cache/bin/fvm flutter test test/services/stop_verifier_service_test.dart
~/.pub-cache/bin/fvm flutter test test/services/turn_harness_test.dart
```

预期：
- 新测试失败，因为当前 `TurnVerifier`（历史名称：`StopVerifierService`）仍把“文本非空”视作足够结束条件

- [ ] **步骤 4：实现运行时感知 stop verification**

更新 `TurnVerifier`，让它能够基于以下信息做判断：

- turn status
- 是否存在 pending confirmation
- 是否还有未完成 step
- 当前 loop 是否已经达到合法关闭点

同时更新 `TurnHarness`（兼容实现名：`AgentTurnOrchestrator`），把 verifier 需要的运行时状态传进去。

优先使用小而明确的运行时谓词，不要再引入另一套按工具名写的启发式规则。

- [ ] **步骤 5：重新运行 verifier 和 harness 测试**

运行：

```bash
~/.pub-cache/bin/fvm flutter test test/services/stop_verifier_service_test.dart
~/.pub-cache/bin/fvm flutter test test/services/turn_harness_test.dart
```

预期：
- 测试通过

- [ ] **步骤 6：提交**

```bash
git add lib/services/turn_verifier.dart lib/services/stop_verifier_service.dart lib/services/turn_harness.dart lib/services/agent_turn_orchestrator.dart test/services/stop_verifier_service_test.dart test/services/turn_harness_test.dart
git commit -m "refactor: make turn stop verification runtime-aware"
```

---

### 任务 4：执行 Phase 1 验证套件

**文件：**
- 预期不改代码
- 测试：`test/services/agent_planner_service_test.dart`
- 测试：`test/services/stop_verifier_service_test.dart`
- 测试：`test/services/turn_harness_test.dart`

- [ ] **步骤 1：运行 Phase 1 定向测试套件**

运行：

```bash
~/.pub-cache/bin/fvm flutter test test/services/agent_planner_service_test.dart
~/.pub-cache/bin/fvm flutter test test/services/stop_verifier_service_test.dart
~/.pub-cache/bin/fvm flutter test test/services/turn_harness_test.dart
```

预期：
- 所有 Phase 1 定向测试通过

- [ ] **步骤 2：运行更大范围的安全验证**

运行：

```bash
~/.pub-cache/bin/fvm flutter test
```

预期：
- 全量测试通过，或明确识别任何既有失败项

- [ ] **步骤 3：运行静态分析**

运行：

```bash
~/.pub-cache/bin/fvm flutter analyze
```

预期：
- Phase 1 改动没有引入新的 analyzer 错误

- [ ] **步骤 4：仅在行为变化明显时更新文档**

必要时更新：

- `README.md`
- `AGENTS.md`

只有当 Phase 1 真的改变了项目级架构说明或协作规则时才执行。

- [ ] **步骤 5：提交最终验证或文档更新**

```bash
git add README.md AGENTS.md
git commit -m "docs: align agent loop notes with phase 1 runtime changes"
```

如果没有文档变更，就跳过这次提交。

---

## 执行注意事项

- 不要引入新的静态 allowlist 去替代被删除的 legacy allowlist。
- 不要把 retrieval 专用 stop 逻辑从 planner 搬到另一层手写补丁里。
- Phase 1 保持现有 turn loop 形状稳定，更深的分层调整属于 Phase 2 和 Phase 3。
- 某个辅助方法在删除 planner 补丁后如果已经失效，应直接删除，不要保留历史脚手架。
- 除非测试证明运行时契约需要变化，否则保持当前用户可见 confirmation 语义不变。

## 完成标准

当以下条件全部满足时，Phase 1 才算完成：

- planner 兼容层不再依赖静态工具名 allowlist
- planner 兼容层不再包含 retrieval 专用硬编码短路规则
- stop verification 基于运行时完整性，而不是仅基于最终文本是否存在
- 定向测试、全量测试和静态分析命令都通过
