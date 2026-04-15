# Message Display Optimization Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the chat message list default to the latest message, keep new turns anchored near the composer, and stop forced follow-scroll once the user manually browses history.

**Architecture:** Keep message persistence and turn assembly in chronological order, but render the chat viewport as a reversed list so the latest message becomes the natural anchor. Consolidate scroll intent ownership inside the message list widget, then adapt pagination and tests to the reversed semantics without introducing new history UI states.

**Tech Stack:** Flutter 3.29.2 / Riverpod / Flutter widget tests

---

## File Map

### Existing files to modify

- `lib/widgets/chat_message_list.dart`
  - Reverse the list, centralize scroll intent handling, and update loading / follow-bottom behavior.
- `lib/controllers/chat_controller.dart`
  - Remove duplicate scroll listener ownership so the widget is the single scroll authority.
- `lib/providers/chat_ui_providers.dart`
  - Clarify scroll-intent provider semantics and add any minimal viewport bootstrap state if still needed after reversal.
- `lib/controllers/chat_session_coordinator.dart`
  - Adjust pagination coordination if the current insert/load behavior conflicts with reversed rendering.
- `test/widgets/chat_message_list_test.dart`
  - Add rendering and reversed-scroll behavior coverage.
- `test/widgets/chat_message_list_interaction_test.dart`
  - Add interaction coverage for follow-bottom opt-out / resume behavior.
- `test/pages/chat_page_test.dart`
  - Update or extend page-level assertions if reversed list behavior changes initial viewport expectations.
- `README.md`
  - Update message display behavior if the current docs mention startup positioning or scrolling semantics.

### Existing files to inspect during implementation

- `lib/providers/chat_collection_providers.dart`
  - Verify message insertion order assumptions stay compatible with reversed rendering.
- `test/providers/chat_ui_providers_test.dart`
  - Extend if provider semantics change.

## Task 1: Lock Down Reversed Viewport Expectations with Tests

**Files:**
- Modify: `test/widgets/chat_message_list_test.dart`
- Modify: `test/widgets/chat_message_list_interaction_test.dart`
- Inspect: `lib/widgets/chat_message_list.dart`

- [ ] **Step 1: Add a failing widget test that asserts the message list uses reversed scrolling**

```dart
testWidgets('message list renders with reversed viewport semantics', (
  tester,
) async {
  await _pumpMessageList(
    tester,
    messages: [
      _buildMessage(text: 'older', role: MessageRole.user),
      _buildMessage(text: 'newer', role: MessageRole.assistant),
    ],
  );

  final listView = tester.widget<ListView>(find.byType(ListView));
  expect(listView.reverse, isTrue);
});
```

- [ ] **Step 2: Run the targeted widget test and verify it fails**

Run: `fvm flutter test test/widgets/chat_message_list_test.dart --plain-name "message list renders with reversed viewport semantics"`
Expected: FAIL because `ListView.reverse` is currently `false`

- [ ] **Step 3: Add a failing interaction test for follow-bottom opt-out during streaming**

```dart
testWidgets('manual upward browse disables auto follow until resume button tap', (
  tester,
) async {
  final controller = ScrollController(initialScrollOffset: 0);
  // Pump the widget with generating state true and enough messages to scroll.
  // Drag away from the bottom anchor.
  // Assert autoScrollToBottomProvider becomes false.
  // Tap the arrow button and assert the provider becomes true again.
});
```

- [ ] **Step 4: Run the targeted interaction test and verify it fails**

Run: `fvm flutter test test/widgets/chat_message_list_interaction_test.dart --plain-name "manual upward browse disables auto follow until resume button tap"`
Expected: FAIL because the current widget does not use reversed semantics and does not own the full resume flow

- [ ] **Step 5: Commit the red tests**

```bash
git add test/widgets/chat_message_list_test.dart test/widgets/chat_message_list_interaction_test.dart
git commit -m "test: add reversed chat viewport coverage"
```

## Task 2: Reverse the Message List and Centralize Scroll Intent

**Files:**
- Modify: `lib/widgets/chat_message_list.dart`
- Modify: `lib/providers/chat_ui_providers.dart`
- Test: `test/widgets/chat_message_list_test.dart`
- Test: `test/widgets/chat_message_list_interaction_test.dart`

- [ ] **Step 1: Update provider comments and any lightweight state needed for reversed viewport bootstrapping**

```dart
/// Whether the viewport is allowed to keep following the latest-message anchor.
final autoScrollToBottomProvider = StateProvider<bool>((ref) => true);
```

- [ ] **Step 2: Change `ChatMessageList` to render a reversed `ListView.builder`**

```dart
ListView.builder(
  reverse: true,
  controller: scrollController,
  // ...
)
```

- [ ] **Step 3: Re-map loading item placement and timeline indexing for reversed rendering**

```dart
final visualIndex = hasMoreMessages ? index - 1 : index;
final item = timelineItems[visualIndex];
```

Implementation note: after setting `reverse: true`, verify whether `timelineItems` itself should stay chronological or be reversed once before binding. Keep only one reversal in the entire pipeline.

- [ ] **Step 4: Move all follow-bottom state transitions into `_scrollListener()` inside `ChatMessageList`**

```dart
if (_isAtLatestAnchor(scrollController)) {
  ref.read(autoScrollToBottomProvider.notifier).state = true;
}

if (_userBrowsedHistory(scrollController.position)) {
  ref.read(autoScrollToBottomProvider.notifier).state = false;
}
```

- [ ] **Step 5: Update the floating resume button to both scroll to the latest anchor and restore follow-bottom**

```dart
void _scrollToBottom() {
  ref.read(autoScrollToBottomProvider.notifier).state = true;
  scrollController.animateTo(
    scrollController.position.minScrollExtent,
    duration: const Duration(milliseconds: 300),
    curve: Curves.easeOut,
  );
}
```

- [ ] **Step 6: Run focused widget tests until they pass**

Run:
- `fvm flutter test test/widgets/chat_message_list_test.dart`
- `fvm flutter test test/widgets/chat_message_list_interaction_test.dart`

Expected: PASS

- [ ] **Step 7: Commit the viewport implementation**

```bash
git add lib/widgets/chat_message_list.dart lib/providers/chat_ui_providers.dart test/widgets/chat_message_list_test.dart test/widgets/chat_message_list_interaction_test.dart
git commit -m "feat: reverse chat message viewport"
```

## Task 3: Remove Duplicate Scroll Ownership from the Controller Layer

**Files:**
- Modify: `lib/controllers/chat_controller.dart`
- Test: `test/controllers/chat_controller_test.dart`
- Test: `test/providers/chat_controller_tool_flow_test.dart`

- [ ] **Step 1: Add or update a failing controller test that no longer depends on controller-installed scroll listeners**

```dart
test('chat controller delegates loading without owning scroll updates', () async {
  await container.read(chatControllerProvider).loadMoreMessages();
  expect(sessionCoordinator.loadMoreMessagesCalls, 1);
});
```

Implementation note: if an existing test already covers this boundary, tighten it instead of creating a duplicate.

- [ ] **Step 2: Run the targeted controller tests to confirm the current expectations**

Run:
- `fvm flutter test test/controllers/chat_controller_test.dart`
- `fvm flutter test test/providers/chat_controller_tool_flow_test.dart`

Expected: At least one assertion needs updating once `_initScrollListener()` is removed

- [ ] **Step 3: Remove `_initScrollListener()` and any duplicate auto-follow state writes from `ChatController`**

```dart
ChatController(
  this._ref, {
  // ...
});
```

- [ ] **Step 4: Keep business-triggered resets explicit where they still belong**

Implementation note: sending a message may still set `autoScrollToBottomProvider = true` in the send coordinator, because that reflects intent at send time rather than scroll observation.

- [ ] **Step 5: Re-run the controller-focused tests and make them pass**

Run:
- `fvm flutter test test/controllers/chat_controller_test.dart`
- `fvm flutter test test/providers/chat_controller_tool_flow_test.dart`

Expected: PASS

- [ ] **Step 6: Commit the controller cleanup**

```bash
git add lib/controllers/chat_controller.dart test/controllers/chat_controller_test.dart test/providers/chat_controller_tool_flow_test.dart
git commit -m "refactor: centralize chat scroll ownership"
```

## Task 4: Make Reversed Pagination Keep the Reading Anchor Stable

**Files:**
- Modify: `lib/widgets/chat_message_list.dart`
- Modify: `lib/controllers/chat_session_coordinator.dart`
- Inspect: `lib/providers/chat_collection_providers.dart`
- Test: `test/widgets/chat_message_list_interaction_test.dart`

- [ ] **Step 1: Add a failing test for loading older history without jumping the current reading position**

```dart
testWidgets('loading older history preserves viewport anchor in reversed list', (
  tester,
) async {
  // Pump enough content to scroll.
  // Move away from the latest anchor.
  // Simulate more-history insertion.
  // Assert the visible region does not jump back to the latest anchor.
});
```

- [ ] **Step 2: Run the targeted test and verify it fails**

Run: `fvm flutter test test/widgets/chat_message_list_interaction_test.dart --plain-name "loading older history preserves viewport anchor in reversed list"`
Expected: FAIL because reversed pagination anchor restoration is not implemented yet

- [ ] **Step 3: Update the pagination trigger to the reversed-history edge**

```dart
if (_isNearOlderHistoryEdge(scrollController.position) &&
    !_ref.read(isLoadingMoreProvider)) {
  ref.read(chatControllerProvider).loadMoreMessages();
}
```

- [ ] **Step 4: Preserve the reading anchor across older-history insertion**

```dart
final beforeExtent = scrollController.position.maxScrollExtent;
await ref.read(chatControllerProvider).loadMoreMessages();
final extentDelta = scrollController.position.maxScrollExtent - beforeExtent;
scrollController.jumpTo(scrollController.offset + extentDelta);
```

Implementation note: validate against reversed semantics; the exact extent and sign may need to use `minScrollExtent` / `maxScrollExtent` depending on the final anchor math.

- [ ] **Step 5: Verify `MessagesNotifier.insertMessages()` still inserts older history at the correct chronological edge**

Implementation note: if provider insertion order remains chronological, prefer keeping it unchanged and adapting only the widget index mapping.

- [ ] **Step 6: Run the message-list tests again**

Run:
- `fvm flutter test test/widgets/chat_message_list_test.dart`
- `fvm flutter test test/widgets/chat_message_list_interaction_test.dart`

Expected: PASS

- [ ] **Step 7: Commit the pagination fix**

```bash
git add lib/widgets/chat_message_list.dart lib/controllers/chat_session_coordinator.dart test/widgets/chat_message_list_interaction_test.dart
git commit -m "fix: preserve anchor when loading older chat history"
```

## Task 5: Verify App-Level Behavior and Update Docs

**Files:**
- Modify: `test/pages/chat_page_test.dart`
- Modify: `README.md`
- Inspect: `docs/feature_todo.md`

- [ ] **Step 1: Add or update a page-level test for the latest-message-first landing behavior**

```dart
testWidgets('chat page lands on the latest message viewport', (tester) async {
  // Pump ChatPage with seeded messages and assert the chat list uses
  // the latest-message anchor semantics.
});
```

- [ ] **Step 2: Run the page test to verify the new expectation**

Run: `fvm flutter test test/pages/chat_page_test.dart`
Expected: PASS after any required fixture updates

- [ ] **Step 3: Update README messaging if it describes older scroll behavior**

```md
- Chat conversations open at the latest message, while users can scroll up to browse earlier turns without losing their reading position during streaming.
```

- [ ] **Step 4: Run the targeted verification suite**

Run:
- `fvm flutter test test/widgets/chat_message_list_test.dart`
- `fvm flutter test test/widgets/chat_message_list_interaction_test.dart`
- `fvm flutter test test/controllers/chat_controller_test.dart`
- `fvm flutter test test/providers/chat_controller_tool_flow_test.dart`
- `fvm flutter test test/pages/chat_page_test.dart`

Expected: PASS

- [ ] **Step 5: Run analyzer on the touched surface**

Run: `fvm flutter analyze`
Expected: PASS

- [ ] **Step 6: Commit the final verification + docs updates**

```bash
git add test/pages/chat_page_test.dart README.md
git commit -m "docs: record reversed chat scrolling behavior"
```

## Manual Regression Checklist

- [ ] Open an existing long conversation and confirm the newest turn is visible on entry.
- [ ] Send a new message and confirm the previous history is pushed out of the visible viewport.
- [ ] While the assistant is streaming, drag upward and confirm the viewport stays where it is.
- [ ] Tap the floating “回到底部” button and confirm the viewport returns to the newest turn and resumes follow mode.
- [ ] Scroll toward older history until pagination triggers and confirm the viewport does not jump.
- [ ] Switch between two groups and confirm each group opens at its own latest turn.
