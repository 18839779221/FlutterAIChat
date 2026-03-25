# Task 2 Structured Output Debug Entry Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a debug-only structured-output entry point that lets developers long-press a completed assistant plain-text message, generate a structured summary card for it, and safely fall back to plain text on any failure.

**Architecture:** Keep the normal streaming chat flow unchanged. Add a separate non-streaming structured-output path where `ChatController` orchestrates the action, `ChatService` owns the LLM call plus parser invocation, `ResponseParserService` validates the raw model output, and `ChatMessageList` exposes a `kDebugMode`-only long-press menu entry plus structured-card rendering.

**Tech Stack:** Flutter, Dart, flutter_test, Riverpod, existing typed-message infrastructure from task 1, DeepSeek-compatible LLM abstraction, TDD.

---

## File Responsibility Map

### Create

- `lib/models/response/structured_summary_card.dart`
  Defines the single schema used in task 2 and its JSON serialization helpers.
- `lib/services/response_parser_service.dart`
  Parses raw model output into either a valid `StructuredSummaryCard` result or a plain-text fallback result.
- `test/services/chat_service_structured_output_test.dart`
  Covers the structured-output service path, including request-level failure fallback.
- `lib/widgets/structured_message/structured_summary_card_widget.dart`
  Renders a `StructuredSummaryCard` without parsing logic.
- `test/services/response_parser_service_test.dart`
  Covers parser success and failure behavior.
- `test/widgets/structured_summary_card_widget_test.dart`
  Covers structured card rendering.
- `test/providers/chat_controller_structured_output_test.dart`
  Covers at least one happy-path and one fallback-path orchestration test for the debug action.

### Modify

- `lib/models/llm/base_llm.dart`
  Adds the non-streaming structured-output contract.
- `lib/models/llm/deepseek_llm.dart`
  Implements the new contract with a fixed prompt for the summary-card schema.
- `lib/database/database_helper.dart`
  Adds or extends a message update API so finalized structured-output messages persist `text`, `status`, `contentType`, and `payloadJson`.
- `lib/services/chat_service.dart`
  Adds the dedicated debug structured-output method and delegates parsing to `ResponseParserService`.
- `lib/providers/chat_providers.dart`
  Adds controller orchestration for the debug action and provider wiring for the parser service.
- `lib/widgets/chat_message_list.dart`
  Adds the debug-only long-press action and real `structuredCard` rendering dispatch.
- `test/database/database_helper_test.dart`
  Extends database coverage for structured-output message persistence.

### Reuse As-Is

- `lib/models/chat_message.dart`
  Already carries `contentType` and `payloadJson` from task 1; do not add new message-envelope abstractions.
- `lib/models/response/message_content_type.dart`
  Already defines `plainText` and `structuredCard`.

## Verification Commands

- Parser tests:
  `flutter test test/services/response_parser_service_test.dart`
- Service tests:
  `flutter test test/services/chat_service_structured_output_test.dart`
- Database tests:
  `flutter test test/database/database_helper_test.dart`
- Widget tests:
  `flutter test test/widgets/structured_summary_card_widget_test.dart`
- Controller orchestration tests:
  `flutter test test/providers/chat_controller_structured_output_test.dart`
- Focused task-2 suite:
  `flutter test test/services/response_parser_service_test.dart test/services/chat_service_structured_output_test.dart test/database/database_helper_test.dart test/widgets/structured_summary_card_widget_test.dart test/providers/chat_controller_structured_output_test.dart`
- Static analysis:
  `flutter analyze`

## Task 1: Define the Structured Summary Schema and Parser Result Contract

**Files:**
- Create: `lib/models/response/structured_summary_card.dart`
- Create: `lib/services/response_parser_service.dart`
- Test: `test/services/response_parser_service_test.dart`

- [ ] **Step 1: Write the failing parser tests**

Create `test/services/response_parser_service_test.dart` and add tests for:

- valid JSON with all required fields returns a structured-card success result
- invalid JSON returns a plain-text fallback result
- missing required fields returns a plain-text fallback result
- wrong field types return a plain-text fallback result

Example seed test:

```dart
test('returns structured card when json is valid', () {
  final service = ResponseParserService();

  final result = service.parseStructuredSummaryCard(
    '{"title":"Weekly Summary","summary":"A short summary","keyPoints":["A"],"actionItems":["B"],"risks":["C"]}',
  );

  expect(result.isStructuredCard, isTrue);
  expect(result.card?.title, 'Weekly Summary');
});
```

- [ ] **Step 2: Run the parser tests and confirm they fail**

Run: `flutter test test/services/response_parser_service_test.dart`

Expected: FAIL because neither the schema model nor parser service exists yet.

- [ ] **Step 3: Implement the schema model**

Create `lib/models/response/structured_summary_card.dart` with:

- immutable fields: `title`, `summary`, `keyPoints`, `actionItems`, `risks`
- `fromJson(Map<String, dynamic>)`
- `toJson()`

Keep field names exactly aligned with the spec and payload JSON keys.

- [ ] **Step 4: Implement the parser service with a minimal result type**

Create `lib/services/response_parser_service.dart` with:

- a parser method dedicated to task 2, for example `parseStructuredSummaryCard(String rawOutput)`
- a small result contract that exposes either:
  - a `StructuredSummaryCard`, or
  - a fixed fallback text such as `结构化整理失败，请重试。`

Do not leak raw JSON back to the caller on failure.

- [ ] **Step 5: Re-run the parser tests and confirm they pass**

Run: `flutter test test/services/response_parser_service_test.dart`

Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add lib/models/response/structured_summary_card.dart lib/services/response_parser_service.dart test/services/response_parser_service_test.dart
git commit -m "feat: add structured summary parser"
```

## Task 2: Add the Non-Streaming Structured Output Contract and Service-Level Fallbacks

**Files:**
- Modify: `lib/models/llm/base_llm.dart`
- Modify: `lib/models/llm/deepseek_llm.dart`
- Modify: `lib/services/chat_service.dart`
- Create: `test/services/chat_service_structured_output_test.dart`

- [ ] **Step 1: Write the failing service tests**

Create `test/services/chat_service_structured_output_test.dart` and cover:

- success path: `ChatService` returns a parsed structured-card result, not raw model JSON
- request failure path: if the LLM throws, `ChatService` returns the same fixed plain-text fallback result required by the spec

The important contract is that `ChatService` never leaks raw JSON and never propagates request failures for this debug feature.

- [ ] **Step 2: Run the service tests and confirm they fail**

Run: `flutter test test/services/chat_service_structured_output_test.dart`

Expected: FAIL because the LLM and service contract do not yet expose the structured-output path or uniform fallback handling.

- [ ] **Step 3: Update the base LLM contract**

Modify `lib/models/llm/base_llm.dart` to add a dedicated non-streaming method, for example:

```dart
Future<String> structureSummaryCard(String sourceText);
```

Do not reuse `chatStream()` for this path.

- [ ] **Step 4: Implement the DeepSeek method**

Modify `lib/models/llm/deepseek_llm.dart` to:

- send a non-streaming request
- use a fixed prompt that requests only the task-2 schema
- return raw response text for the parser service

Keep it intentionally narrow: one schema, one method, one response shape.

- [ ] **Step 5: Add the dedicated ChatService method**

Modify `lib/services/chat_service.dart` to add a method such as:

```dart
Future<StructuredSummaryParseResult> structureMessageForDebug(String sourceText)
```

This method must:

- call the new LLM method
- pass raw output to `ResponseParserService`
- return only the parsed success-or-fallback result
- catch request-level failures from the LLM and convert them into the same fixed plain-text fallback result

Inject or construct `ResponseParserService` in a way consistent with the current codebase, but keep ownership in `ChatService`, not `ChatController`.

- [ ] **Step 6: Re-run the service tests**

Run: `flutter test test/services/chat_service_structured_output_test.dart`

Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add lib/models/llm/base_llm.dart lib/models/llm/deepseek_llm.dart lib/services/chat_service.dart test/services/chat_service_structured_output_test.dart
git commit -m "feat: add structured output service contract"
```

## Task 3: Add Persistence Support for Finalized Structured Output Messages

**Files:**
- Modify: `lib/database/database_helper.dart`
- Modify: `test/database/database_helper_test.dart`

- [ ] **Step 1: Write the failing database test**

Extend `test/database/database_helper_test.dart` to verify that a previously inserted assistant message can be updated to persist:

- final `text`
- final `status`
- final `contentType`
- final `payloadJson`

Use the task-1 message schema as the base.

- [ ] **Step 2: Run the database test and confirm it fails**

Run: `flutter test test/database/database_helper_test.dart`

Expected: FAIL because the current helper does not expose an API to update typed payload fields after placeholder creation.

- [ ] **Step 3: Add the database helper update method**

Modify `lib/database/database_helper.dart` to add a focused update API for structured-output completion, for example:

```dart
Future<void> updateStructuredMessage(
  int id, {
  required String text,
  required MessageStatus status,
  required MessageContentType contentType,
  String? payloadJson,
});
```

Keep it narrow and reuse the existing columns from task 1.

- [ ] **Step 4: Re-run the database test and confirm it passes**

Run: `flutter test test/database/database_helper_test.dart`

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/database/database_helper.dart test/database/database_helper_test.dart
git commit -m "feat: persist structured output message updates"
```

## Task 4: Add Controller Orchestration for the Debug Action

**Files:**
- Modify: `lib/providers/chat_providers.dart`
- Test: `test/providers/chat_controller_structured_output_test.dart`

- [ ] **Step 1: Write the failing controller orchestration tests**

Create `test/providers/chat_controller_structured_output_test.dart` and cover:

- happy path: a completed assistant plain-text message creates a new structured-card assistant message
- fallback path: a parsing failure creates a new completed plain-text fallback assistant message
- guard path: unsupported messages are ignored

Use fake or stub services instead of hitting the real network.

Example assertions to include:

```dart
expect(newMessage.contentType, MessageContentType.structuredCard);
expect(newMessage.payloadJson, isNotNull);
```

and

```dart
expect(newMessage.contentType, MessageContentType.plainText);
expect(newMessage.status, MessageStatus.completed);
expect(newMessage.text, '结构化整理失败，请重试。');
```

- [ ] **Step 2: Run the controller tests and confirm they fail**

Run: `flutter test test/providers/chat_controller_structured_output_test.dart`

Expected: FAIL because the controller action and wiring do not exist yet.

- [ ] **Step 3: Add parser-service wiring if needed**

If the codebase benefits from a provider for the parser service, add it in `lib/providers/chat_providers.dart`, but keep it lightweight and task-specific.

- [ ] **Step 4: Implement the controller action**

Modify `lib/providers/chat_providers.dart` to add a method such as:

```dart
Future<void> structureMessageForDebug(ChatMessage message)
```

The action should:

- return immediately for unsupported messages
- create a new assistant placeholder message
- call `ChatService.structureMessageForDebug(...)`
- use the new `DatabaseHelper` update method to persist the finalized placeholder message
- on success:
  - set `contentType = structuredCard`
  - serialize the card into `payloadJson`
  - set `status = completed`
- on fallback:
  - set `contentType = plainText`
  - set fixed fallback text
  - set `status = completed`

Do not mutate the original message.

- [ ] **Step 5: Re-run the controller tests and confirm they pass**

Run: `flutter test test/providers/chat_controller_structured_output_test.dart`

Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add lib/providers/chat_providers.dart test/providers/chat_controller_structured_output_test.dart
git commit -m "feat: orchestrate debug structured output flow"
```

## Task 5: Add the Debug-Only UI Entry and Real Structured Card Rendering

**Files:**
- Modify: `lib/widgets/chat_message_list.dart`
- Create: `lib/widgets/structured_message/structured_summary_card_widget.dart`
- Test: `test/widgets/structured_summary_card_widget_test.dart`
- Modify: `test/widgets/chat_message_list_test.dart`

- [ ] **Step 1: Write the failing widget tests for the card component**

Create `test/widgets/structured_summary_card_widget_test.dart` to verify:

- title renders
- summary renders
- list sections render their items
- empty lists do not crash the widget

- [ ] **Step 2: Write the failing ChatMessageList tests for task-2 behavior**

Extend `test/widgets/chat_message_list_test.dart` to cover:

- `structuredCard` messages render the dedicated widget instead of plain fallback text
- in debug mode, eligible assistant messages expose the `结构化整理（调试）` menu item
- unsupported messages do not expose that menu item

Keep the existing task-1 tests intact.

- [ ] **Step 3: Run the widget tests and confirm they fail**

Run:

- `flutter test test/widgets/structured_summary_card_widget_test.dart`
- `flutter test test/widgets/chat_message_list_test.dart`

Expected: FAIL because the widget and debug action are not implemented yet.

- [ ] **Step 4: Implement the structured card widget**

Create `lib/widgets/structured_message/structured_summary_card_widget.dart` with a simple, readable layout:

- title
- summary
- key points
- action items
- risks

Keep it intentionally plain; this is a debug-validation feature, not a polished product surface.

- [ ] **Step 5: Update ChatMessageList rendering**

Modify `lib/widgets/chat_message_list.dart` to:

- render `StructuredSummaryCardWidget` for assistant messages whose `contentType` is `structuredCard`
- deserialize `payloadJson` into `StructuredSummaryCard`
- fall back to `Text(message.text)` if payload parsing fails

- [ ] **Step 6: Add the debug-only long-press action**

Still in `lib/widgets/chat_message_list.dart`:

- gate the menu item behind `kDebugMode`
- only show it for completed assistant `plainText` messages
- route the action to `ChatController.structureMessageForDebug(message)`

Do not expose the entry in release builds.

- [ ] **Step 7: Re-run the widget tests and confirm they pass**

Run:

- `flutter test test/widgets/structured_summary_card_widget_test.dart`
- `flutter test test/widgets/chat_message_list_test.dart`

Expected: PASS.

- [ ] **Step 8: Commit**

```bash
git add lib/widgets/chat_message_list.dart lib/widgets/structured_message/structured_summary_card_widget.dart test/widgets/chat_message_list_test.dart test/widgets/structured_summary_card_widget_test.dart
git commit -m "feat: add debug structured summary ui"
```

## Task 6: Full Task-2 Verification and Manual Debug Validation

**Files:**
- Modify: `docs/superpowers/plans/2026-03-26-task-2-structured-output-debug-entry-implementation-plan.md`

- [ ] **Step 1: Run the focused automated suite**

Run:

```bash
flutter test test/services/response_parser_service_test.dart test/services/chat_service_structured_output_test.dart test/database/database_helper_test.dart test/widgets/structured_summary_card_widget_test.dart test/providers/chat_controller_structured_output_test.dart test/widgets/chat_message_list_test.dart
```

Expected: PASS.

- [ ] **Step 2: Run static analysis**

Run: `flutter analyze`

Expected: PASS, or only pre-existing warnings that are clearly unrelated and documented.

- [ ] **Step 3: Perform manual debug validation**

In a debug build:

- send or load a completed assistant plain-text message
- long-press it and confirm `结构化整理（调试）` is visible
- trigger the action and verify a new structured-card message appears
- force a failure path (for example via invalid mocked response or temporary parser stub) and verify a new plain-text fallback message appears
- verify normal streaming chat still works exactly as before

- [ ] **Step 4: Update the checkboxes in this plan**

- [ ] **Step 5: Commit**

```bash
git add docs/superpowers/plans/2026-03-26-task-2-structured-output-debug-entry-implementation-plan.md
git commit -m "docs: mark task 2 implementation plan progress"
```

## Execution Notes

- Do not turn this into a production feature. Keep the entry debug-only.
- Do not refactor the whole chat architecture while doing task 2.
- Do not leak raw model JSON into UI on any failure path.
- Use the existing typed-message fields from task 1; do not invent a second message envelope.
- Prefer fixed fallback text over clever partial recovery.
