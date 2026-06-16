# Codex 风格 Steer / Queue 与中断半截回复恢复 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 支持运行中追加输入的 `Steer` / `Queue` 双模式，并把中断时的半截 assistant 输出稳定进入后续 context。

**Architecture:** 在 `ChatController` / `ChatSendCoordinator` 前面增加一层运行期输入调度，先把追加输入作为未持久化的 pending follow-up 管理，真正消费时才写入 transcript。`TurnHarness` 与 `SessionContextService` 仍保留各自职责，但 transcript 需要扩展 `userMessage` 语义与 partial assistant 恢复投影，保证下一轮 planner 能看到中断点。

**Tech Stack:** Flutter Riverpod, SQLite via existing repositories, append-only `chat_events`, `chat_turns`, `SessionContextService`, `TurnHarness`, `AgentEventProcessor`, widget/service tests.

---

### Task 1: Extend the input request and scheduler-facing contract

**Files:**
- Modify: `lib/models/chat/send_message_request.dart`
- Modify: `lib/controllers/chat_controller.dart`
- Modify: `lib/widgets/chat_input.dart`
- Test: `test/controllers/chat_controller_test.dart`
- Test: `test/widgets/chat_input_test.dart`

- [ ] **Step 1: Write the failing test**

Add tests that prove the send request can carry a dispatch mode, defaulting to `steer`, and that chat input can surface the choice without changing the message text itself.

- [ ] **Step 2: Run test to verify it fails**

Run: `fvm flutter test test/controllers/chat_controller_test.dart test/widgets/chat_input_test.dart`
Expected: fail because dispatch mode is not yet modeled or wired through.

- [ ] **Step 3: Write minimal implementation**

Add a `dispatchMode` field to `SendMessageRequest`, keep `steer` as the default, and thread it through `ChatController.sendMessageRequest(...)` and `chat_input.dart` call sites.

- [ ] **Step 4: Run test to verify it passes**

Run: `fvm flutter test test/controllers/chat_controller_test.dart test/widgets/chat_input_test.dart`
Expected: pass.

- [ ] **Step 5: Commit**

```bash
git add lib/models/chat/send_message_request.dart lib/controllers/chat_controller.dart lib/widgets/chat_input.dart test/controllers/chat_controller_test.dart test/widgets/chat_input_test.dart
git commit -m "feat: add follow-up dispatch mode to sends"
```

### Task 2: Add runtime follow-up queue and steer consumption boundary

**Files:**
- Create: `lib/services/follow_up_dispatch_queue.dart`
- Modify: `lib/controllers/chat_send_coordinator.dart`
- Modify: `lib/providers/chat_send_state_providers.dart`
- Modify: `lib/controllers/chat_controller.dart`
- Test: `test/controllers/chat_send_coordinator_test.dart`
- Test: `test/controllers/chat_controller_test.dart`

- [ ] **Step 1: Write the failing test**

Add tests for:
- default `Steer` behavior
- `Queue` staying out of the current turn until the current turn finishes
- `Steer` and `Queue` both staying in memory until consumption
- `Steer` draining all queued follow-ups at the next planner boundary instead of inserting immediately

- [ ] **Step 2: Run test to verify it fails**

Run: `fvm flutter test test/controllers/chat_send_coordinator_test.dart test/controllers/chat_controller_test.dart`
Expected: fail because there is no runtime queue / steer boundary yet.

- [ ] **Step 3: Write minimal implementation**

Introduce a small runtime queue service owned by the app layer, keep pending follow-ups in memory only, and teach `ChatSendCoordinator` to consume them in one place:
- `Steer` drains immediately before the next planner request
- `Queue` drains after the current turn ends, when creating the next turn

- [ ] **Step 4: Run test to verify it passes**

Run: `fvm flutter test test/controllers/chat_send_coordinator_test.dart test/controllers/chat_controller_test.dart`
Expected: pass.

- [ ] **Step 5: Commit**

```bash
git add lib/services/follow_up_dispatch_queue.dart lib/controllers/chat_send_coordinator.dart lib/providers/chat_send_state_providers.dart lib/controllers/chat_controller.dart test/controllers/chat_send_coordinator_test.dart test/controllers/chat_controller_test.dart
git commit -m "feat: add steer and queue follow-up dispatch"
```

### Task 3: Extend transcript semantics for start, follow_up, and system_reminder

**Files:**
- Modify: `lib/models/chat_event.dart`
- Modify: `lib/repositories/chat_event_repository.dart`
- Modify: `lib/services/session_context_projector.dart`
- Modify: `lib/services/session_context_service.dart`
- Modify: `lib/services/turn_harness.dart`
- Test: `test/services/session_context_projector_test.dart`
- Test: `test/services/session_context_service_test.dart`
- Test: `test/services/turn_harness_test.dart`

- [ ] **Step 1: Write the failing test**

Add tests that prove:
- a turn may contain multiple consecutive `start` user messages
- `follow_up` ordering is based on append order, not timestamps
- `system_reminder` user messages are projected into planner context

- [ ] **Step 2: Run test to verify it fails**

Run: `fvm flutter test test/services/session_context_projector_test.dart test/services/session_context_service_test.dart test/services/turn_harness_test.dart`
Expected: fail because transcript kinds and projection rules are not yet modeled.

- [ ] **Step 3: Write minimal implementation**

Extend `ChatEvent` payload semantics to carry a user-message subtype, keep `sequence` as the only ordering source, and teach the projector/service to preserve multiple start messages plus follow-up/reminder messages in order.

- [ ] **Step 4: Run test to verify it passes**

Run: `fvm flutter test test/services/session_context_projector_test.dart test/services/session_context_service_test.dart test/services/turn_harness_test.dart`
Expected: pass.

- [ ] **Step 5: Commit**

```bash
git add lib/models/chat_event.dart lib/repositories/chat_event_repository.dart lib/services/session_context_projector.dart lib/services/session_context_service.dart lib/services/turn_harness.dart test/services/session_context_projector_test.dart test/services/session_context_service_test.dart test/services/turn_harness_test.dart
git commit -m "feat: expand transcript semantics for follow-ups"
```

### Task 4: Persist interrupted partial assistant output and context reminder

**Files:**
- Modify: `lib/controllers/agent_event_processor.dart`
- Modify: `lib/controllers/chat_send_coordinator.dart`
- Modify: `lib/services/session_context_projector.dart`
- Modify: `lib/services/session_context_service.dart`
- Test: `test/controllers/chat_send_coordinator_test.dart`
- Test: `test/services/session_context_service_test.dart`

- [ ] **Step 1: Write the failing test**

Add tests that prove:
- a streaming response interrupted mid-way keeps the partial assistant content
- the next context includes both the partial assistant text and a light reminder message
- the reminder text stays low-noise and does not replace the partial text

- [ ] **Step 2: Run test to verify it fails**

Run: `fvm flutter test test/controllers/chat_send_coordinator_test.dart test/services/session_context_service_test.dart`
Expected: fail because interrupted partial content is not yet projected as durable context.

- [ ] **Step 3: Write minimal implementation**

Teach the event processor and session context projector to keep a stable partial assistant snapshot and emit a matching reminder user message into planner-visible context.

- [ ] **Step 4: Run test to verify it passes**

Run: `fvm flutter test test/controllers/chat_send_coordinator_test.dart test/services/session_context_service_test.dart`
Expected: pass.

- [ ] **Step 5: Commit**

```bash
git add lib/controllers/agent_event_processor.dart lib/controllers/chat_send_coordinator.dart lib/services/session_context_projector.dart lib/services/session_context_service.dart test/controllers/chat_send_coordinator_test.dart test/services/session_context_service_test.dart
git commit -m "feat: persist interrupted partial assistant context"
```

### Task 5: Verify end-to-end resume behavior and update docs if needed

**Files:**
- Modify: `docs/architecture/append-only-transcript.md`
- Modify: `docs/architecture/session-context-management.md`
- Modify: `docs/architecture/agent-loop-boundaries-and-decoupling.md` (only if a boundary note is needed)
- Test: `test/services/simulated_turn_projection_integration_test.dart`
- Test: `test/controllers/chat_send_coordinator_test.dart`

- [ ] **Step 1: Write the failing test**

Add one integration-style regression that starts a turn, injects a steer follow-up and an interrupted partial, then verifies the next planner-visible context sees the right order and the correct recovery text.

- [ ] **Step 2: Run test to verify it fails**

Run: `fvm flutter test test/services/simulated_turn_projection_integration_test.dart test/controllers/chat_send_coordinator_test.dart`
Expected: fail until the end-to-end contract is fully wired.

- [ ] **Step 3: Write minimal implementation**

Patch any remaining boundary gaps, then update the architecture docs to describe the new follow-up and interruption semantics.

- [ ] **Step 4: Run test to verify it passes**

Run: `fvm flutter test test/services/simulated_turn_projection_integration_test.dart test/controllers/chat_send_coordinator_test.dart && fvm flutter analyze`
Expected: pass.

- [ ] **Step 5: Commit**

```bash
git add docs/architecture/append-only-transcript.md docs/architecture/session-context-management.md docs/architecture/agent-loop-boundaries-and-decoupling.md test/services/simulated_turn_projection_integration_test.dart test/controllers/chat_send_coordinator_test.dart
git commit -m "feat: complete steer queue recovery flow"
```
