# Skills 子系统第二阶段完善 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 让现有显式 `skill` tool 机制具备同 turn 去重、上下文预算裁剪、Debug 可观测和端到端投影回归能力。

**Architecture:** 继续保留 “skills catalog reminder + `skill` tool + invoked skill reminder + session context projection” 主链路。新增逻辑放在 tool execution context、skill-specific formatter、runtime user context formatter、Debug projection 和 simulated integration tests 中，不引入隐式自动激活或关键词路由。

**Tech Stack:** Flutter, Dart, Riverpod, sqflite_common_ffi tests, existing TurnHarness / AgentEventProcessor / SessionContextService / DebugTurnInspectorProjectionService

---

## 相关设计

- Spec: `docs/superpowers/specs/2026-05-15-skills-subsystem-hardening-design.md`
- Baseline spec: `docs/superpowers/specs/2026-05-08-mobile-skills-subsystem-design.md`

## 文件结构与职责

### 需要新增

- `lib/services/skills/skill_invocation_guard.dart`
  - 从当前 turn transcript / execution history 中判断某个 skill 是否已经成功 invoked。

- `lib/services/skills/skill_context_formatter.dart`
  - 负责 skill catalog reminder 与 invoked skill reminder 的稳定裁剪、裁剪元数据和文本生成。

- `test/services/skills/skill_invocation_guard_test.dart`
  - 覆盖同 turn 已调用、未调用、失败调用不阻塞、不同 skill 不互相影响。

- `test/services/skills/skill_context_formatter_test.dart`
  - 覆盖 catalog 上限、body 上限、裁剪提示、排序稳定和原始 body 不被修改。

### 需要修改

- `lib/tools/core/tool_execution_context.dart`
  - 增加当前 turn transcript 或 tool execution facts 的只读字段，供 tool handler 做重复调用判断。

- `lib/services/tool_orchestrator_service.dart`
  - 创建 `ToolExecutionContext` 时传入当前 turn 可用的 transcript / events。

- `lib/tools/handlers/skill_tool_handler.dart`
  - 在执行前调用 `SkillInvocationGuard`，重复调用返回结构化 no-op / failure。
  - 成功返回时附带裁剪元数据。

- `lib/services/skills/invoked_skill_reminder_builder.dart`
  - 改为委托 `SkillContextFormatter` 生成 invoked reminder。

- `lib/services/tool_result_context_projector.dart`
  - 保持 `skill` result 由 dedicated formatter 投影，并消费裁剪元数据。

- `lib/services/prompt/runtime_user_context_service.dart`
  - 用 `SkillContextFormatter` 构建 catalog reminder，支持稳定上限。

- `lib/models/skill/invoked_skill_context.dart`
  - 增加可选裁剪字段，例如 `instructionBodyTruncated`、`originalInstructionLength`。

- `lib/models/skill/skill_catalog_entry.dart`
  - 如需 Debug 统计，补充可选排序/来源字段时必须保持 lightweight。

- `lib/services/debug/debug_turn_inspector_projection_service.dart`
  - 新增 Skills context section，展示 available / invoked / projected / truncated 状态。

- `test/tools/handlers/skill_tool_handler_test.dart`
  - 扩展重复调用与裁剪元数据测试。

- `test/services/prompt/runtime_user_context_service_skills_test.dart`
  - 扩展 catalog 上限测试。

- `test/services/session_context_service_skills_test.dart`
  - 扩展重复 projection 去重与长 body 裁剪测试。

- `test/services/debug/debug_turn_inspector_projection_service_test.dart`
  - 覆盖新增 Skills context section。

- `test/services/simulated_turn_projection_integration_test.dart`
  - 增加 `skill` tool 从调用到后续 planner 可见的完整链路回归。

## Task 1: 为 ToolExecutionContext 暴露当前 turn transcript

**Files:**
- Modify: `lib/tools/core/tool_execution_context.dart`
- Modify: `lib/services/tool_orchestrator_service.dart`
- Test: `test/tools/handlers/skill_tool_handler_test.dart`

- [ ] **Step 1: 写失败测试，证明 SkillToolHandler 可读取当前 turn 事实**

在 `test/tools/handlers/skill_tool_handler_test.dart` 中新增测试，构造 `ToolExecutionContext` 时传入一条既有 `skill` 成功 tool result 事实，期望后续 Task 2 能据此拒绝重复调用。

测试先只断言 `ToolExecutionContext` 支持该字段，例如：

```dart
final context = ToolExecutionContext(
  groupId: 1,
  toolName: 'skill',
  arguments: const {'skill': 'edge-to-edge'},
  history: const <ChatMessage>[],
  now: DateTime(2026, 5, 15),
  currentTurnEvents: [
    ChatEvent(
      turnId: 10,
      groupId: 1,
      sequence: 1,
      eventType: ChatEventType.toolResult,
      role: MessageRole.system,
      payloadJson: const {
        'toolName': 'skill',
        'status': 'success',
        'data': {'skillId': 'edge-to-edge'},
      },
    ),
  ],
);

expect(context.currentTurnEvents, hasLength(1));
```

- [ ] **Step 2: 运行测试并确认失败**

Run:

```bash
fvm flutter test test/tools/handlers/skill_tool_handler_test.dart
```

Expected: FAIL，因为 `ToolExecutionContext.currentTurnEvents` 尚不存在。

- [ ] **Step 3: 给 ToolExecutionContext 增加只读 currentTurnEvents 字段**

在 `lib/tools/core/tool_execution_context.dart` 中：

- import `ChatEvent`
- 新增 public final `List<ChatEvent> currentTurnEvents`
- 构造函数默认 `const <ChatEvent>[]`
- 使用 `List<ChatEvent>.unmodifiable`
- 注释说明这是当前 turn transcript facts，供 tool 做执行期 guard，不是 UI timeline

- [ ] **Step 4: 在 ToolOrchestratorService 传入当前 turn transcript**

查看 `ToolOrchestratorService.prepareAndExecuteTool` 当前参数。如果已有 transcript 参数，直接传入；如果没有，先新增可选 `currentTurnEvents` 参数，默认空列表，调用点逐步接入。

要求：

- 不让 tool handler 自己查数据库
- 不把 UI `messages` 当作同 turn ledger 事实
- 现有调用点不破坏，默认空列表保持兼容

- [ ] **Step 5: 重新运行测试**

Run:

```bash
fvm flutter test test/tools/handlers/skill_tool_handler_test.dart
```

Expected: PASS 当前新增字段测试。

## Task 2: 实现同 turn skill 重复调用保护

**Files:**
- Create: `lib/services/skills/skill_invocation_guard.dart`
- Modify: `lib/tools/handlers/skill_tool_handler.dart`
- Test: `test/services/skills/skill_invocation_guard_test.dart`
- Test: `test/tools/handlers/skill_tool_handler_test.dart`

- [ ] **Step 1: 写 SkillInvocationGuard 失败测试**

创建 `test/services/skills/skill_invocation_guard_test.dart`，覆盖：

- 当前 turn 中已有 `toolResult`，payload `toolName == skill`，`status == success`，`data.skillId == edge-to-edge`，则返回已调用。
- skill tool failure 不算已调用。
- 不同 `skillId` 不算重复。
- 只匹配 name 但 payload 没有 `skillId` 时，使用 normalized name 回退匹配。

- [ ] **Step 2: 运行测试并确认失败**

Run:

```bash
fvm flutter test test/services/skills/skill_invocation_guard_test.dart
```

Expected: FAIL，因为 guard 文件不存在。

- [ ] **Step 3: 实现 SkillInvocationGuard**

在 `lib/services/skills/skill_invocation_guard.dart` 中实现：

- public method `bool wasSkillInvoked({required List<ChatEvent> events, required String skillId, required String skillName})`
- 只消费 `ChatEventType.toolResult`
- 只接受 payload 中 `toolName == 'skill'`
- 只接受 `status == 'success'`
- 优先匹配 `data.skillId`
- fallback 匹配 normalized `data.name`
- normalization 与 `SkillRuntimeService` 的 lookup 风格一致，但不要把该私有方法跨文件暴露

- [ ] **Step 4: 运行 guard 测试**

Run:

```bash
fvm flutter test test/services/skills/skill_invocation_guard_test.dart
```

Expected: PASS。

- [ ] **Step 5: 写 SkillToolHandler 重复调用失败测试**

在 `test/tools/handlers/skill_tool_handler_test.dart` 增加：

- 第一次已有当前 turn skill success event
- 再执行 `handler.execute(context)`
- 期望 `ToolExecutionStatus.failure` 或 no-op success 二选一

推荐选择 failure，便于 planner 明确知道重复调用无效：

```dart
expect(result.status, ToolExecutionStatus.failure);
expect(result.errorMessage, 'skill_already_invoked');
expect(result.data['skillId'], 'edge-to-edge');
```

- [ ] **Step 6: 运行测试并确认失败**

Run:

```bash
fvm flutter test test/tools/handlers/skill_tool_handler_test.dart
```

Expected: FAIL，因为 handler 尚未调用 guard。

- [ ] **Step 7: 修改 SkillToolHandler 接入 guard**

在 `lib/tools/handlers/skill_tool_handler.dart`：

- 构造函数注入 `SkillInvocationGuard`，默认新实例
- 成功读取 descriptor 后，先用 descriptor id/name 检查当前 turn events
- 重复时返回 failure result：
  - `toolName: 'skill'`
  - `status: ToolExecutionStatus.failure`
  - `summary: 'Skill failed: skill already invoked in this turn'`
  - `errorMessage: 'skill_already_invoked'`
  - `data: {'skillId': descriptor.id, 'name': descriptor.name}`

- [ ] **Step 8: 运行相关测试**

Run:

```bash
fvm flutter test test/services/skills/skill_invocation_guard_test.dart
fvm flutter test test/tools/handlers/skill_tool_handler_test.dart
```

Expected: PASS。

## Task 3: 增加 skill context formatter 与稳定裁剪

**Files:**
- Create: `lib/services/skills/skill_context_formatter.dart`
- Modify: `lib/services/skills/invoked_skill_reminder_builder.dart`
- Modify: `lib/services/tool_result_context_projector.dart`
- Modify: `lib/services/prompt/runtime_user_context_service.dart`
- Modify: `lib/models/skill/invoked_skill_context.dart`
- Test: `test/services/skills/skill_context_formatter_test.dart`
- Test: `test/services/prompt/runtime_user_context_service_skills_test.dart`
- Test: `test/services/session_context_service_skills_test.dart`

- [ ] **Step 1: 写 formatter 失败测试**

创建 `test/services/skills/skill_context_formatter_test.dart`，覆盖：

- `formatCatalogReminder` 按 `name` 稳定排序。
- 超过 `maxCatalogItems` 时只展示前 N 个，并增加 `... 2 more skills omitted.` 提示。
- `formatInvokedReminder` 超过 `maxInstructionCharacters` 时裁剪 body，并包含 `[truncated]` 提示。
- 裁剪后仍包含 skill name、qualified path、base directory。
- 原始 `InvokedSkillContext.instructionBody` 不被修改。

- [ ] **Step 2: 运行测试并确认失败**

Run:

```bash
fvm flutter test test/services/skills/skill_context_formatter_test.dart
```

Expected: FAIL，因为 formatter 文件不存在。

- [ ] **Step 3: 扩展 InvokedSkillContext 字段**

在 `lib/models/skill/invoked_skill_context.dart` 增加：

- `final bool instructionBodyTruncated`
- `final int? originalInstructionLength`

默认值：

```dart
this.instructionBodyTruncated = false,
this.originalInstructionLength,
```

`toJson()` 只在值有意义时写入：

- `instructionBodyTruncated == true` 时写入
- `originalInstructionLength != null` 时写入

字段注释必须说明它们描述 planner-visible reminder 中的正文裁剪状态。

- [ ] **Step 4: 实现 SkillContextFormatter**

建议 API：

```dart
class SkillContextFormatter {
  const SkillContextFormatter({
    this.maxCatalogItems = 20,
    this.maxInstructionCharacters = 6000,
  });

  String formatCatalogReminder(List<SkillCatalogEntry> skills) { ... }

  InvokedSkillContext prepareInvokedContext(InvokedSkillContext context) { ... }

  String formatInvokedReminder(InvokedSkillContext context) { ... }
}
```

要求：

- catalog 空列表返回空字符串
- disabled skills 不出现在 catalog reminder
- 排序稳定
- body 裁剪优先保留前段
- 裁剪提示写入 reminder 文本
- 不读取文件系统

- [ ] **Step 5: 运行 formatter 测试**

Run:

```bash
fvm flutter test test/services/skills/skill_context_formatter_test.dart
```

Expected: PASS。

- [ ] **Step 6: 改造 InvokedSkillReminderBuilder 委托 formatter**

在 `lib/services/skills/invoked_skill_reminder_builder.dart`：

- 构造函数注入 `SkillContextFormatter`
- `build` 调用 `formatter.formatInvokedReminder(context)`
- 保持原有默认文本结构兼容现有测试

- [ ] **Step 7: 改造 RuntimeUserContextService catalog reminder**

在 `lib/services/prompt/runtime_user_context_service.dart`：

- 注入 `SkillContextFormatter`
- `_buildSkillsListSection` 改为 formatter 方法
- 保持无 enabled skills 时不注入 skills reminder
- 保持现有文案核心句：
  `The following skills are available for use with the Skill tool:`

- [ ] **Step 8: 增加 runtime catalog 裁剪测试**

在 `test/services/prompt/runtime_user_context_service_skills_test.dart` 增加超过上限的 skills list，断言：

- planner context 中只出现前 N 个
- 出现 omitted 提示
- 不出现第 N+1 个 skill 名称

- [ ] **Step 9: 增加 session context 长 body 裁剪测试**

在 `test/services/session_context_service_skills_test.dart` 增加一个 tool result payload，`instructionBody` 超长，断言 planner messages 合并文本：

- 包含 skill name/path/base directory
- 包含 `[truncated]`
- 不包含超长尾部 sentinel

- [ ] **Step 10: 运行相关测试**

Run:

```bash
fvm flutter test test/services/skills/skill_context_formatter_test.dart
fvm flutter test test/services/prompt/runtime_user_context_service_skills_test.dart
fvm flutter test test/services/session_context_service_skills_test.dart
```

Expected: PASS。

## Task 4: 让 SkillToolHandler 返回裁剪后的 invoked payload

**Files:**
- Modify: `lib/tools/handlers/skill_tool_handler.dart`
- Modify: `lib/services/tool_result_context_projector.dart`
- Test: `test/tools/handlers/skill_tool_handler_test.dart`

- [ ] **Step 1: 写失败测试**

在 `test/tools/handlers/skill_tool_handler_test.dart` 增加长 skill body：

- handler 使用 `SkillContextFormatter(maxInstructionCharacters: 80)`
- 执行成功后 result.data：
  - `instructionBodyTruncated == true`
  - `originalInstructionLength` 大于 `instructionBody.length`
  - `instructionBody` 不包含尾部 sentinel

- [ ] **Step 2: 运行测试并确认失败**

Run:

```bash
fvm flutter test test/tools/handlers/skill_tool_handler_test.dart
```

Expected: FAIL，因为 handler 还返回完整正文。

- [ ] **Step 3: 修改 SkillToolHandler 构造 invoked payload 前先 prepare**

在 `lib/tools/handlers/skill_tool_handler.dart`：

- 构造函数注入 `SkillContextFormatter`
- 创建 `InvokedSkillContext` 后调用 `prepareInvokedContext`
- `ToolResult.data` 使用裁剪后的 context `toJson()`

注意：

- 文件系统中的 `SKILL.md` 不修改
- failure result 不需要裁剪字段

- [ ] **Step 4: 确认 ToolResultContextProjector 消费裁剪字段**

在 `_projectSkillResult` 中读取：

- `instructionBodyTruncated`
- `originalInstructionLength`

构造 `InvokedSkillContext` 时传入，保证投影文本能显示裁剪状态。

- [ ] **Step 5: 运行测试**

Run:

```bash
fvm flutter test test/tools/handlers/skill_tool_handler_test.dart
fvm flutter test test/services/session_context_service_skills_test.dart
```

Expected: PASS。

## Task 5: Debug Turn Inspector 增加 Skills context section

**Files:**
- Modify: `lib/services/debug/debug_turn_inspector_projection_service.dart`
- Test: `test/services/debug/debug_turn_inspector_projection_service_test.dart`
- Test: `test/widgets/debug/debug_turn_inspector_sheet_test.dart`

- [ ] **Step 1: 写 projection 失败测试**

在 `test/services/debug/debug_turn_inspector_projection_service_test.dart`：

- 创建 turn
- append 一个 `skill` tool result event，payload data 包含 `skillId/name/instructionBodyTruncated/originalInstructionLength`
- 构建 projection
- 断言 contextSections 包含 title `Skills`
- rawJson 包含：
  - `invokedSkills`
  - `skillId`
  - `name`
  - `projected`
  - `instructionBodyTruncated`

- [ ] **Step 2: 运行测试并确认失败**

Run:

```bash
fvm flutter test test/services/debug/debug_turn_inspector_projection_service_test.dart
```

Expected: FAIL，因为 Skills section 尚不存在。

- [ ] **Step 3: 实现 Skills section builder**

在 `lib/services/debug/debug_turn_inspector_projection_service.dart`：

- 新增 private `_buildSkillsSection`
- 从 `plannerMessages` 中解析 available skills reminder 的文本摘要即可，不要扫描 UI messages
- 从 `transcript` 中筛选 `toolResult` payload `toolName == 'skill'`
- 对每个 success result 输出：
  - `skillId`
  - `name`
  - `status`
  - `qualifiedPath`
  - `baseDirectory`
  - `instructionBodyTruncated`
  - `originalInstructionLength`
  - `projected: true` 如果 `ToolResultContextProjector.projectToContextText` 非空
- failure result 输出 `errorMessage`

- [ ] **Step 4: 把 Skills section 插入 contextSections**

建议放在 `Planner Messages` 之后、`Transcript Events` 之前。

summary 示例：

- `2 available, 1 invoked`
- `0 available, 0 invoked`

默认折叠。

- [ ] **Step 5: 更新现有 Debug projection 测试数量断言**

现有测试可能断言 `contextSections hasLength(7)`。新增 section 后改为 8，或改成 contains-based 断言，减少未来脆弱性。

- [ ] **Step 6: 检查 widget 测试**

运行 widget 测试，如果 `DebugTurnInspectorSheet` 对 section 数量或标题有断言，同步更新。

Run:

```bash
fvm flutter test test/widgets/debug/debug_turn_inspector_sheet_test.dart
```

- [ ] **Step 7: 运行 Debug 相关测试**

Run:

```bash
fvm flutter test test/services/debug/debug_turn_inspector_projection_service_test.dart
fvm flutter test test/widgets/debug/debug_turn_inspector_sheet_test.dart
```

Expected: PASS。

## Task 6: 增加 skill tool simulated integration 回归

**Files:**
- Modify: `test/services/simulated_turn_projection_integration_test.dart`
- Possibly Modify: test helper classes in same file

- [ ] **Step 1: 写失败集成测试**

在 `test/services/simulated_turn_projection_integration_test.dart` 新增测试：

场景：

1. fake planner 第一次返回 `ModelToolCall(toolName: 'skill', arguments: {'skill': 'edge-to-edge'})`
2. fake tool call service 或 real skill handler 返回 success `ToolResult`
3. harness 继续下一次 planner decision
4. fake planner 记录第二次收到的 planner messages
5. 第二次 planner 返回 final answer

断言：

- tool result event 中存在 `toolName == skill`
- 第二次 planner messages 合并文本包含 `### Skill: edge-to-edge`
- 包含 `Base directory for this skill`
- final answer 被写入 timeline

- [ ] **Step 2: 运行测试并确认失败**

Run:

```bash
fvm flutter test test/services/simulated_turn_projection_integration_test.dart
```

Expected: FAIL，直到 test helper 支持捕获 planner messages 或 skill tool result 投影链路。

- [ ] **Step 3: 扩展 fake planner 记录每次 planTurnDecision 输入**

在该测试文件内扩展 `_QueuedDecisionLLM`：

- 新增 `List<List<ChatMessage>> capturedMessages`
- 每次 `planTurnDecision` append unmodifiable copy
- 不影响既有测试

- [ ] **Step 4: 接入 skill tool result**

优先使用已有 `_QueuedToolCallService` 返回一个 `ToolPreparationResult`：

- `toolInvocation.toolName: skill`
- `toolResult.status: success`
- `toolResult.data` 为 `InvokedSkillContext(...).toJson()`

如果当前 harness 需要 tool definition，提供 `SkillToolHandler(...).definition` 或 minimal `ToolDefinition`。

- [ ] **Step 5: 运行集成测试**

Run:

```bash
fvm flutter test test/services/simulated_turn_projection_integration_test.dart
```

Expected: PASS。

## Task 7: 更新文档与最终验证

**Files:**
- Modify: `docs/superpowers/specs/2026-05-15-skills-subsystem-hardening-design.md` if implementation changes design details
- Possibly Modify: `README.md` only if user-facing capabilities change

- [ ] **Step 1: 检查设计是否需要同步**

如果实现选择与 spec 不同，例如重复调用采用 no-op success 而不是 failure，更新：

`docs/superpowers/specs/2026-05-15-skills-subsystem-hardening-design.md`

- [ ] **Step 2: 运行 skills / session / debug / integration 测试集合**

Run:

```bash
fvm flutter test test/services/skills/skill_invocation_guard_test.dart
fvm flutter test test/services/skills/skill_context_formatter_test.dart
fvm flutter test test/tools/handlers/skill_tool_handler_test.dart
fvm flutter test test/services/prompt/runtime_user_context_service_skills_test.dart
fvm flutter test test/services/session_context_service_skills_test.dart
fvm flutter test test/services/debug/debug_turn_inspector_projection_service_test.dart
fvm flutter test test/widgets/debug/debug_turn_inspector_sheet_test.dart
fvm flutter test test/services/simulated_turn_projection_integration_test.dart
```

Expected: PASS。

- [ ] **Step 3: 运行 analyze**

Run:

```bash
fvm flutter analyze
```

Expected: PASS 或仅剩本任务无关的既有 warning，并在交付说明中列出。

- [ ] **Step 4: 可选运行全量测试**

如果时间允许：

```bash
fvm flutter test
```

Expected: PASS。

## 注意事项

- 不要新增绕过 `skill` tool 的自动激活路径。
- 不要把 skill 选择实现成 keyword-to-skill 路由表。
- 不要让 `SkillRuntimeService` 保存 turn 级状态。
- 不要让 Debug 面板扫描 UI timeline 文本反推 skill 状态。
- 不要自动执行 `scripts/`。
- 新增公共字段必须写简洁注释，说明语义和用途。
