# Provider Think Visibility Cleanup Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:test-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 清理旧“深度思考开关”残留，并让 provider 返回的 tool-use think 与 final-answer think 在当前 Agent loop 中进入事件账本和时间线展示。

**Architecture:** 不恢复 `useReasoning` 入口；think 是 provider 输出的一部分，由各协议 adapter 解析为 `ModelTurnDecision` 的可展示 reasoning 字段。`TurnHarness` 根据当前 decision 是否包含工具调用，将 think 标记为 tool-use 或 final-answer scope，再由 `AgentEventProcessor` 投影到对应 assistant 消息，UI 以弱层级折叠区展示。

**Tech Stack:** Flutter 3.29.2, Riverpod, SQLite/Web storage, existing Agent loop and chat block renderer.

---

### Task 1: 锁定 adapter 可展示 think 解析

**Files:**
- Modify: `test/models/llm/openai_tool_loop_adapter_test.dart`
- Modify: `test/models/llm/adapters/anthropic_messages_adapter_test.dart`
- Modify: `lib/models/agent/model_turn_decision.dart`
- Modify: `lib/models/llm/tool_loop/openai_chat_completions_tool_loop_adapter.dart`
- Modify: `lib/models/llm/tool_loop/openai_responses_tool_loop_adapter.dart`
- Modify: `lib/models/llm/tool_loop/anthropic_messages_tool_loop_adapter.dart`

- [ ] **Step 1: Write failing tests for Chat Completions, Responses, and Anthropic think extraction**
- [ ] **Step 2: Run the focused adapter tests and verify RED**
- [ ] **Step 3: Add a normalized visible reasoning field to `ModelTurnDecision`**
- [ ] **Step 4: Parse provider-visible reasoning without using `ChatConfig.useReasoning`**
- [ ] **Step 5: Run focused adapter tests and verify GREEN**

### Task 2: 写入 Agent loop 事件账本

**Files:**
- Modify: `test/services/turn_harness_test.dart`
- Modify: `lib/models/chat_event.dart`
- Modify: `lib/repositories/chat_event_repository.dart`
- Modify: `lib/services/turn_harness.dart`

- [ ] **Step 1: Write failing tests for tool-use think and final-answer think events**
- [ ] **Step 2: Run focused turn harness tests and verify RED**
- [ ] **Step 3: Add scoped reasoning event payloads**
- [ ] **Step 4: Emit tool-use scope before tool execution and final-answer scope before final answer**
- [ ] **Step 5: Run focused turn harness tests and verify GREEN**

### Task 3: 投影到当前消息与 UI block

**Files:**
- Modify: `test/providers/chat_controller_tool_flow_test.dart`
- Modify: `test/widgets/chat_message_list_test.dart`
- Modify: `lib/controllers/agent_event_processor.dart`
- Modify: `lib/services/chat_block_builder.dart`
- Modify: `lib/models/chat/assistant_turn_block.dart`
- Modify: `lib/widgets/chat_timeline/chat_timeline_row.dart`
- Modify: `lib/widgets/chat_blocks/final_response_block.dart`
- Modify: `lib/widgets/chat_blocks/assistant_doc_block.dart`
- Create: `lib/widgets/chat_blocks/reasoning_section.dart` if duplication becomes meaningful.

- [ ] **Step 1: Write failing projection/widget tests**
- [ ] **Step 2: Run focused tests and verify RED**
- [ ] **Step 3: Append scoped reasoning to the active assistant message**
- [ ] **Step 4: Carry reasoning through `AssistantTurnBlock`**
- [ ] **Step 5: Render compact reasoning sections for analysis/tool-use and final-answer blocks**
- [ ] **Step 6: Run focused tests and verify GREEN**

### Task 4: 清理旧 reasoning 开关残留

**Files:**
- Modify: `lib/services/chat_service.dart`
- Modify: `lib/services/agent_planner_service.dart`
- Modify: `lib/controllers/chat_send_coordinator.dart`
- Modify: `lib/models/llm/configurable_http_llm.dart`
- Modify: `lib/models/llm/adapters/responses_adapter.dart`
- Modify: affected tests under `test/`
- Modify: `README.md`
- Modify: `AGENTS.md`

- [ ] **Step 1: Remove `ChatService.streamFinalAnswer()` and its tests if unused**
- [ ] **Step 2: Remove `ChatConfig.useReasoning` from production code and update constructor call sites**
- [ ] **Step 3: Remove active request shaping tied to the old deep-thinking toggle**
- [ ] **Step 4: Update docs to describe provider-returned think visibility**
- [ ] **Step 5: Run affected analyzer/tests**
