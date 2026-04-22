# Streaming Response Buffer Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Introduce a lightweight stream output buffer so long assistant replies render and persist smoothly without changing the existing LLM streaming protocol.

**Architecture:** Keep `ChatService` and the LLM protocol unchanged, but insert a focused `AssistantStreamOutputBuffer` between streamed text deltas and downstream consumers. `ChatSendCoordinator` remains the turn projection facade while the buffer owns coalescing, timed UI flushes, timed persistence flushes, and final synchronization on finish or cancel.

**Tech Stack:** Flutter, Riverpod, Dart async timers, sqflite/web chat storage, Flutter widget tests.

---

## File Map

- Create: `lib/services/assistant_stream_output_buffer.dart`
- Modify: `lib/controllers/chat_send_coordinator.dart`
- Modify: `lib/widgets/chat_message_list.dart`
- Create: `lib/widgets/chat_blocks/streaming_response_block.dart`
- Create: `test/services/assistant_stream_output_buffer_test.dart`
- Modify: `test/controllers/chat_controller_test.dart`
- Modify: `test/widgets/chat_message_list_test.dart`

## Task 1: Add the failing buffer tests

**Files:**
- Create: `test/services/assistant_stream_output_buffer_test.dart`
- Modify: `lib/services/assistant_stream_output_buffer.dart`

- [ ] **Step 1: Write the failing tests for buffered UI and persistence flushes**

Add tests that cover:
- high-frequency `onDelta()` calls collapse into fewer UI flushes
- persistence flushes happen less often than UI flushes
- `finish()` flushes the complete final text
- `cancel()` preserves accumulated text before closing

- [ ] **Step 2: Run the targeted test file to verify RED**

Run: `fvm flutter test test/services/assistant_stream_output_buffer_test.dart`
Expected: FAIL because `AssistantStreamOutputBuffer` does not exist yet.

- [ ] **Step 3: Write the minimal buffer implementation**

Implement:
- a `StringBuffer` for accumulated text
- separate timers for UI and persistence flush cadence
- explicit `finish()`, `cancel()`, and `dispose()` paths
- protection against post-dispose flushes

- [ ] **Step 4: Run the targeted test file to verify GREEN**

Run: `fvm flutter test test/services/assistant_stream_output_buffer_test.dart`
Expected: PASS.

## Task 2: Route assistant text deltas through the buffer

**Files:**
- Modify: `lib/controllers/chat_send_coordinator.dart`
- Modify: `test/controllers/chat_controller_test.dart`

- [ ] **Step 1: Write the failing coordinator tests**

Add tests that prove:
- streamed assistant deltas no longer require per-delta persistence writes
- final assistant text is still complete and status becomes `completed`
- interrupt/cancel paths keep the last visible text

- [ ] **Step 2: Run the focused coordinator test selection to verify RED**

Run: `fvm flutter test test/controllers/chat_controller_test.dart`
Expected: FAIL because the coordinator still appends and persists every delta directly.

- [ ] **Step 3: Implement minimal coordinator integration**

Update `ChatSendCoordinator` to:
- create one active `AssistantStreamOutputBuffer` per active assistant placeholder
- send `assistantTextDelta` content into `buffer.onDelta(...)`
- call `finish()` before marking completed
- call `cancel()` or final flush on interruption / error paths
- dispose active buffers when the stream ends

- [ ] **Step 4: Run the focused coordinator tests to verify GREEN**

Run: `fvm flutter test test/controllers/chat_controller_test.dart`
Expected: PASS.

## Task 3: Add generating-state lightweight rendering

**Files:**
- Create: `lib/widgets/chat_blocks/streaming_response_block.dart`
- Modify: `lib/widgets/chat_message_list.dart`
- Modify: `test/widgets/chat_message_list_test.dart`

- [ ] **Step 1: Write the failing widget tests**

Add tests that prove:
- assistant messages in `MessageStatus.generating` render with the lightweight streaming block
- completed assistant messages still render with the existing Markdown-backed block

- [ ] **Step 2: Run the focused widget tests to verify RED**

Run: `fvm flutter test test/widgets/chat_message_list_test.dart`
Expected: FAIL because generating messages currently go through the standard assistant rendering path.

- [ ] **Step 3: Implement the minimal rendering split**

Add a lightweight `StreamingResponseBlock` and update message-list rendering so:
- `generating` assistant plain-text/final-answer content uses the lightweight block
- completed content still uses `FinalResponseBlock`

- [ ] **Step 4: Run the focused widget tests to verify GREEN**

Run: `fvm flutter test test/widgets/chat_message_list_test.dart`
Expected: PASS.

## Task 4: Verify the integrated flow

**Files:**
- Modify: `README.md` if the architecture notes for streaming output need to be mentioned
- Modify: `AGENTS.md` only if new implementation constraints or maintenance rules are introduced

- [ ] **Step 1: Run the combined targeted test suite**

Run: `fvm flutter test test/services/assistant_stream_output_buffer_test.dart test/controllers/chat_controller_test.dart test/widgets/chat_message_list_test.dart`
Expected: PASS.

- [ ] **Step 2: Run static analysis**

Run: `fvm flutter analyze`
Expected: PASS with no new diagnostics from the changed files.

- [ ] **Step 3: Do a manual sanity pass if needed**

If a local run is practical, verify:
- long replies begin streaming quickly
- mid-stream updates feel smoother than before
- cancelling a stream keeps the partial text visible

- [ ] **Step 4: Update docs only if the final implementation changes architecture expectations**

If the implementation introduces a new durable architectural concept, update:
- `README.md`
- `AGENTS.md`

