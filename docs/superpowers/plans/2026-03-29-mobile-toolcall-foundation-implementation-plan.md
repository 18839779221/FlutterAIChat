# Mobile ToolCall Foundation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the first production-grade mobile ToolCall foundation for FlutterAIChat, including typed tool messages, policy-driven confirmation, tool-name whitelist support, two auto-run tools, four confirm-first tools, and settings-based whitelist management.

**Architecture:** Extend the existing typed-message chat flow with a dedicated ToolCall pipeline rather than bolting tool execution onto plain text responses. Keep the first version single-step: model decision, policy check, confirmation if required, execution, tool result write-back, optional final assistant reply. Reuse the current `BaseLLM.decideToolCall()` entry point and the existing minimal tool files, but upgrade them into explicit registry, policy, orchestration, and rendering units.

**Tech Stack:** Flutter, Riverpod, SharedPreferences, existing configurable HTTP LLM, typed chat messages, widget tests, service unit tests

---

## File Structure

### Existing files to modify

- `lib/models/response/message_content_type.dart`
  Purpose: extend message types for ToolCall-specific states.
- `lib/models/chat_message.dart`
  Purpose: keep typed payload persistence compatible with new tool payload shapes.
- `lib/models/llm/base_llm.dart`
  Purpose: preserve and document the tool decision entry point used by the new orchestration layer.
- `lib/services/chat_service.dart`
  Purpose: delegate tool preparation/orchestration cleanly instead of embedding ad hoc logic.
- `lib/providers/chat_providers.dart`
  Purpose: insert tool-related messages into the chat flow, handle confirmation actions, and preserve existing send behavior.
- `lib/widgets/chat_message_list.dart`
  Purpose: route new message content types to dedicated widgets and expose confirmation actions.
- `lib/pages/settings_page.dart`
  Purpose: add tool execution mode and whitelist management UI.
- `lib/repositories/app_settings_repository.dart`
  Purpose: persist tool mode and tool-name whitelist alongside existing runtime settings.
- `lib/models/tool/tool_call.dart`
  Purpose: evolve current raw decision model into stricter invocation parsing.
- `lib/models/tool/tool_definition.dart`
  Purpose: expand current minimal tool definition metadata.
- `lib/models/tool/tool_result.dart`
  Purpose: support richer execution status and renderer-friendly result fields.
- `lib/services/tool_call_service.dart`
  Purpose: either refactor into a compatibility wrapper or retire responsibilities into more focused services.
- `lib/services/tool_registry.dart`
  Purpose: upgrade the current one-tool registry into the first formal tool catalog.
- `lib/services/tool_executor.dart`
  Purpose: keep existing search execution, then extend execution entry points for first-wave tools.

### New files to create

- `lib/models/tool/tool_invocation.dart`
  Purpose: typed payload for invocation and confirmation messages.
- `lib/models/tool/tool_policy.dart`
  Purpose: tool execution mode, whitelist data, and policy decisions.
- `lib/services/tool_policy_service.dart`
  Purpose: decide `auto_run`, `require_confirmation`, or `blocked`.
- `lib/services/tool_decision_service.dart`
  Purpose: call the LLM, parse strict JSON, validate tool names and argument shape.
- `lib/services/tool_orchestrator_service.dart`
  Purpose: coordinate decision, policy, execution, result message creation, and follow-up assistant context.
- `lib/widgets/tool_call/tool_confirmation_card_widget.dart`
  Purpose: render `继续` / `取消` / `继续，以后不再确认`.
- `lib/widgets/tool_call/tool_invocation_card_widget.dart`
  Purpose: render planned/running tool state.
- `lib/widgets/tool_call/tool_result_card_widget.dart`
  Purpose: render tool success and failure states.
- `test/models/tool/tool_invocation_test.dart`
  Purpose: validate invocation parsing and serialization.
- `test/services/tool_policy_service_test.dart`
  Purpose: validate mode + whitelist policy behavior.
- `test/services/tool_decision_service_test.dart`
  Purpose: validate strict decision parsing and invalid tool rejection.
- `test/services/tool_executor_test.dart`
  Purpose: cover search + first-wave non-search executors with focused service tests.
- `test/services/tool_orchestrator_service_test.dart`
  Purpose: validate single-step orchestration branches.
- `test/widgets/tool_confirmation_card_widget_test.dart`
  Purpose: validate three-button confirmation behavior.
- `test/widgets/tool_result_card_widget_test.dart`
  Purpose: validate success/failure card rendering.

### Notes on decomposition

- Keep model parsing, policy, execution, and orchestration in separate files. Do not grow `tool_call_service.dart` into a god object.
- Keep tool UI widgets separate from `chat_message_list.dart`. The list should route, not own tool-specific layout logic.
- Keep the first implementation single-step. Do not introduce multi-step tool planning or queueing in this plan.

## Task 1: Expand Tool Message Types And Payload Models

**Files:**
- Modify: `lib/models/response/message_content_type.dart`
- Modify: `lib/models/chat_message.dart`
- Modify: `lib/models/tool/tool_call.dart`
- Modify: `lib/models/tool/tool_definition.dart`
- Modify: `lib/models/tool/tool_result.dart`
- Create: `lib/models/tool/tool_invocation.dart`
- Create: `lib/models/tool/tool_policy.dart`
- Test: `test/models/tool/tool_invocation_test.dart`

- [ ] **Step 1: Write the failing model tests**

Add tests for:
- parsing a valid tool invocation payload with `toolName`, `arguments`, `status`, `summary`, and `requiresConfirmation`
- rejecting invalid `toolName`
- serializing/deserializing richer tool result payload
- preserving new message content types

- [ ] **Step 2: Run the targeted tests to verify they fail**

Run: `flutter test test/models/tool/tool_invocation_test.dart`
Expected: FAIL because the new model and/or enum values do not exist yet.

- [ ] **Step 3: Add the new message content types**

Update `lib/models/response/message_content_type.dart` to add:
- `toolInvocation`
- `actionConfirmation`

Keep existing values:
- `plainText`
- `structuredCard`
- `toolResult`

- [ ] **Step 4: Implement the new tool payload models**

Add `tool_invocation.dart` and `tool_policy.dart`, and upgrade:
- `ToolCall` to remain the raw LLM decision object
- `ToolDefinition` to include title, schema, confirmation requirement, supported platforms, and risk
- `ToolResult` to carry a renderer-friendly summary, status, error, and payload

- [ ] **Step 5: Make sure `ChatMessage` payload handling still supports new JSON payloads**

Verify `payloadJson` and `referenceJson` continue to accept/return JSON maps without changing existing message persistence behavior.

- [ ] **Step 6: Run the targeted tests to verify they pass**

Run: `flutter test test/models/tool/tool_invocation_test.dart`
Expected: PASS

- [ ] **Step 7: Commit**

```bash
git add lib/models/response/message_content_type.dart lib/models/chat_message.dart lib/models/tool/tool_call.dart lib/models/tool/tool_definition.dart lib/models/tool/tool_result.dart lib/models/tool/tool_invocation.dart lib/models/tool/tool_policy.dart test/models/tool/tool_invocation_test.dart
git commit -m "feat: add typed tool message models"
```

## Task 2: Add Tool Policy Storage And Decision Logic

**Files:**
- Modify: `lib/repositories/app_settings_repository.dart`
- Create: `lib/services/tool_policy_service.dart`
- Test: `test/services/tool_policy_service_test.dart`

- [ ] **Step 1: Write the failing policy tests**

Cover:
- balanced mode auto-runs `search_chat_history` and `fetch_webpage`
- balanced mode requires confirmation for `save_note`, `create_reminder`, `create_calendar_event`, and `share_result`
- adding a tool to the whitelist changes it to `auto_run`
- removing a tool from the whitelist restores confirmation

- [ ] **Step 2: Run the targeted tests to verify they fail**

Run: `flutter test test/services/tool_policy_service_test.dart`
Expected: FAIL because the policy service and settings storage keys do not exist yet.

- [ ] **Step 3: Extend settings storage for tool mode and whitelist**

Add repository methods for:
- reading default tool execution mode
- saving default tool execution mode
- reading tool-name whitelist
- adding/removing a whitelisted tool name

- [ ] **Step 4: Implement `ToolPolicyService`**

Implement a focused service that:
- reads the configured mode and whitelist
- inspects tool metadata
- returns `auto_run`, `require_confirmation`, or `blocked`
- exposes helpers for “trust this tool” and “untrust this tool”

- [ ] **Step 5: Run the targeted tests to verify they pass**

Run: `flutter test test/services/tool_policy_service_test.dart`
Expected: PASS

- [ ] **Step 6: Commit**

```bash
git add lib/repositories/app_settings_repository.dart lib/services/tool_policy_service.dart test/services/tool_policy_service_test.dart
git commit -m "feat: add tool policy and whitelist storage"
```

## Task 3: Upgrade Tool Registry And Strict Tool Decision Parsing

**Files:**
- Modify: `lib/services/tool_registry.dart`
- Create: `lib/services/tool_decision_service.dart`
- Modify: `lib/models/llm/base_llm.dart`
- Test: `test/services/tool_decision_service_test.dart`

- [ ] **Step 1: Write the failing decision tests**

Cover:
- valid decision JSON resolves to a known tool
- `{"toolName":"none"}` returns no tool
- unknown tool names are rejected
- malformed JSON is rejected
- missing required argument structure is rejected

- [ ] **Step 2: Run the targeted tests to verify they fail**

Run: `flutter test test/services/tool_decision_service_test.dart`
Expected: FAIL because the decision service does not exist yet.

- [ ] **Step 3: Expand the tool registry to include the first-wave six tools**

Register:
- `search_chat_history`
- `fetch_webpage`
- `save_note`
- `create_reminder`
- `create_calendar_event`
- `share_result`

Include confirmation requirements and simple parameter schemas in the registry.

- [ ] **Step 4: Implement `ToolDecisionService`**

Responsibilities:
- call `BaseLLM.decideToolCall()`
- parse raw JSON using the upgraded `ToolCall`
- reject unknown tools
- reject malformed arguments
- normalize `none`

- [ ] **Step 5: Keep `BaseLLM.decideToolCall()` but update any comments/docs needed**

Do not widen this interface yet. Keep the LLM boundary simple.

- [ ] **Step 6: Run the targeted tests to verify they pass**

Run: `flutter test test/services/tool_decision_service_test.dart`
Expected: PASS

- [ ] **Step 7: Commit**

```bash
git add lib/services/tool_registry.dart lib/services/tool_decision_service.dart lib/models/llm/base_llm.dart test/services/tool_decision_service_test.dart
git commit -m "feat: add strict tool decision service"
```

## Task 4: Expand Tool Executor For First-Wave Tools

**Files:**
- Modify: `lib/services/tool_executor.dart`
- Modify: `lib/storage/chat_storage.dart` only if note storage needs a minimal interface addition
- Test: `test/services/tool_executor_test.dart`

- [ ] **Step 1: Write the failing executor tests**

Cover:
- successful `search_chat_history`
- successful `fetch_webpage` with a stubbed fetcher
- successful `save_note` in the chosen first-pass storage strategy
- confirmation-only tools returning structured success/failure payloads from stubbed platform adapters

- [ ] **Step 2: Run the targeted tests to verify they fail**

Run: `flutter test test/services/tool_executor_test.dart`
Expected: FAIL because the new executor entry points are not implemented.

- [ ] **Step 3: Decide the minimal first-pass storage/adaptor seams**

Use small injected interfaces for anything not already available locally, for example:
- webpage fetcher
- reminder adapter
- calendar adapter
- share adapter
- optional note storage adapter

Do not bind the executor directly to Flutter widget APIs.

- [ ] **Step 4: Implement executor entry points**

Implement methods for:
- `executeSearchChatHistory`
- `executeFetchWebpage`
- `executeSaveNote`
- `executeCreateReminder`
- `executeCreateCalendarEvent`
- `executeShareResult`

Use typed `ToolResult` objects with clear summaries and failure messages.

- [ ] **Step 5: Run the targeted tests to verify they pass**

Run: `flutter test test/services/tool_executor_test.dart`
Expected: PASS

- [ ] **Step 6: Commit**

```bash
git add lib/services/tool_executor.dart lib/storage/chat_storage.dart test/services/tool_executor_test.dart
git commit -m "feat: expand tool executor for first-wave tools"
```

## Task 5: Build Single-Step Tool Orchestration

**Files:**
- Create: `lib/services/tool_orchestrator_service.dart`
- Modify: `lib/services/tool_call_service.dart`
- Modify: `lib/services/chat_service.dart`
- Test: `test/services/tool_orchestrator_service_test.dart`

- [ ] **Step 1: Write the failing orchestration tests**

Cover:
- no-tool path returns control to the normal chat flow
- auto-run tool path produces invocation context and tool result
- confirmation-required path returns an awaiting-confirmation payload instead of executing
- whitelist trust path marks future calls as `auto_run`

- [ ] **Step 2: Run the targeted tests to verify they fail**

Run: `flutter test test/services/tool_orchestrator_service_test.dart`
Expected: FAIL because the orchestrator service does not exist yet.

- [ ] **Step 3: Implement `ToolOrchestratorService`**

It should:
- ask `ToolDecisionService` for a decision
- ask `ToolPolicyService` for the execution mode
- build a `ToolInvocation` payload
- either return confirmation state or execute through `ToolExecutor`
- package result/context for the chat layer

- [ ] **Step 4: Refactor existing `tool_call_service.dart` responsibilities**

Choose one of these and keep the result clean:
- convert it into a compatibility façade that delegates to the orchestrator
- or trim it down and move real orchestration into the new service

Do not leave overlapping orchestration logic in both places.

- [ ] **Step 5: Update `ChatService` to consume the orchestrator**

Keep `ChatService` as the chat-facing boundary, but stop letting it own ad hoc tool logic.

- [ ] **Step 6: Run the targeted tests to verify they pass**

Run: `flutter test test/services/tool_orchestrator_service_test.dart`
Expected: PASS

- [ ] **Step 7: Commit**

```bash
git add lib/services/tool_orchestrator_service.dart lib/services/tool_call_service.dart lib/services/chat_service.dart test/services/tool_orchestrator_service_test.dart
git commit -m "feat: add single-step tool orchestration"
```

## Task 6: Add Tool Confirmation And Result Widgets

**Files:**
- Create: `lib/widgets/tool_call/tool_confirmation_card_widget.dart`
- Create: `lib/widgets/tool_call/tool_invocation_card_widget.dart`
- Create: `lib/widgets/tool_call/tool_result_card_widget.dart`
- Modify: `lib/widgets/chat_message_list.dart`
- Test: `test/widgets/tool_confirmation_card_widget_test.dart`
- Test: `test/widgets/tool_result_card_widget_test.dart`

- [ ] **Step 1: Write the failing widget tests**

Cover:
- confirmation card renders the three actions
- clicking the third action calls the trust callback
- result card renders success and failure summaries
- invocation card renders running state without crashing

- [ ] **Step 2: Run the targeted tests to verify they fail**

Run: `flutter test test/widgets/tool_confirmation_card_widget_test.dart test/widgets/tool_result_card_widget_test.dart`
Expected: FAIL because the widgets and render routes do not exist yet.

- [ ] **Step 3: Implement tool widgets**

Build focused widgets for:
- confirmation
- invocation/running
- result

Keep raw JSON hidden. Render human-readable summaries and an optional compact details section.

- [ ] **Step 4: Update `chat_message_list.dart` routing**

Route the new `contentType` values to the new widgets.

- [ ] **Step 5: Run the targeted tests to verify they pass**

Run: `flutter test test/widgets/tool_confirmation_card_widget_test.dart test/widgets/tool_result_card_widget_test.dart`
Expected: PASS

- [ ] **Step 6: Commit**

```bash
git add lib/widgets/tool_call/tool_confirmation_card_widget.dart lib/widgets/tool_call/tool_invocation_card_widget.dart lib/widgets/tool_call/tool_result_card_widget.dart lib/widgets/chat_message_list.dart test/widgets/tool_confirmation_card_widget_test.dart test/widgets/tool_result_card_widget_test.dart
git commit -m "feat: add tool confirmation and result cards"
```

## Task 7: Integrate Tool Flow Into ChatController

**Files:**
- Modify: `lib/providers/chat_providers.dart`
- Test: `test/providers/chat_controller_toolcall_test.dart`

- [ ] **Step 1: Write the failing controller tests**

Cover:
- send message with no tool still behaves as before
- auto-run tool inserts tool invocation/result messages
- confirmation-required tool inserts an awaiting-confirmation message
- tapping trust action both executes and updates whitelist

- [ ] **Step 2: Run the targeted tests to verify they fail**

Run: `flutter test test/providers/chat_controller_toolcall_test.dart`
Expected: FAIL because controller support for new tool message states does not exist yet.

- [ ] **Step 3: Extend the controller send flow**

Implement the single-step branching:
- user message is stored
- tool orchestrator is consulted
- confirmation messages are inserted when required
- auto-run results are written back before the final assistant reply path

- [ ] **Step 4: Add controller actions for confirmation buttons**

Implement focused handlers for:
- continue
- cancel
- continue and trust tool

These handlers should update messages, invoke policy service where required, and execute or stop the pending tool invocation.

- [ ] **Step 5: Run the targeted tests to verify they pass**

Run: `flutter test test/providers/chat_controller_toolcall_test.dart`
Expected: PASS

- [ ] **Step 6: Commit**

```bash
git add lib/providers/chat_providers.dart test/providers/chat_controller_toolcall_test.dart
git commit -m "feat: integrate tool flow into chat controller"
```

## Task 8: Add Settings UI For Tool Mode And Whitelist

**Files:**
- Modify: `lib/pages/settings_page.dart`
- Optional Test: `test/pages/settings_page_tool_settings_test.dart`

- [ ] **Step 1: Write the failing settings test**

Cover:
- tool mode is displayed
- whitelist entries render
- removing an entry triggers the repository update

If page tests are too brittle in the first pass, capture this as a manual verification checklist and come back once the settings UI stabilizes.

- [ ] **Step 2: Run the targeted test to verify it fails**

Run: `flutter test test/pages/settings_page_tool_settings_test.dart`
Expected: FAIL because the tool settings UI does not exist yet.

- [ ] **Step 3: Add a tool settings section**

Include:
- default tool execution mode selector
- whitelist list tiles
- remove action for whitelisted tools

- [ ] **Step 4: Run the targeted test or manual verification**

If widget test exists:
Run: `flutter test test/pages/settings_page_tool_settings_test.dart`
Expected: PASS

If not practical yet, manually verify:
- mode changes persist
- whitelist removal persists
- trusted tools stop auto-running only after removal

- [ ] **Step 5: Commit**

```bash
git add lib/pages/settings_page.dart test/pages/settings_page_tool_settings_test.dart
git commit -m "feat: add tool settings management"
```

## Task 9: Regression Verification

**Files:**
- Verify only; no new source files expected unless fixes are needed

- [ ] **Step 1: Run focused tooling tests**

Run:
```bash
flutter test test/models/tool/tool_invocation_test.dart test/services/tool_policy_service_test.dart test/services/tool_decision_service_test.dart test/services/tool_executor_test.dart test/services/tool_orchestrator_service_test.dart test/widgets/tool_confirmation_card_widget_test.dart test/widgets/tool_result_card_widget_test.dart test/providers/chat_controller_toolcall_test.dart
```

Expected: PASS

- [ ] **Step 2: Run targeted existing regression tests**

Run:
```bash
flutter test test/services/chat_service_structured_output_test.dart test/providers/chat_controller_structured_output_test.dart test/widgets/chat_message_list_test.dart test/widgets/structured_summary_card_widget_test.dart test/services/response_parser_service_test.dart
```

Expected: PASS

- [ ] **Step 3: Run analyzer**

Run: `flutter analyze`
Expected: no new ToolCall-related errors; if historical warnings remain, document them explicitly.

- [ ] **Step 4: Manual verification**

Verify on a debug build:
- auto-run `search_chat_history`
- auto-run `fetch_webpage`
- confirm-first `save_note`
- confirm-first `create_reminder`
- third button `继续，以后不再确认`
- whitelist removal from settings
- fallback behavior when a tool execution fails

- [ ] **Step 5: Final commit**

```bash
git add .
git commit -m "feat: complete mobile toolcall foundation"
```

## Review Notes

- This plan intentionally upgrades the existing minimal tool prototype rather than deleting it wholesale.
- Keep the first version single-step. Do not add multi-tool planning, looped execution, or autonomous retries during this plan.
- The third confirmation action is a hard requirement, not a stretch goal.
- If a platform-specific tool adapter is too expensive to implement fully during the first pass, keep the seam injectable and ship a stub-backed integration that still exercises the UI and orchestration path.
