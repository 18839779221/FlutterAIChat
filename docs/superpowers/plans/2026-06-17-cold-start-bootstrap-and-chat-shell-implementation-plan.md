# Cold Start Bootstrap And Chat Shell Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Shrink cold-start white-screen time by moving heavy app initialization behind the first Flutter frame while rendering the real chat page in a bootstrap state with an editable composer and disabled send.

**Architecture:** Introduce a dedicated bootstrap layer that owns runtime assembly after `runApp()`, keep `main.dart` as a minimal entrypoint, and teach the existing chat page / chat input to render a startup state until the runtime-backed providers are ready. The implementation keeps one real chat UI, uses skeleton content instead of fake data, and gates send availability separately from text editing.

**Tech Stack:** Flutter, Riverpod, existing chat providers/controllers, Flutter widget tests

---

## File Structure

### New files

- `lib/bootstrap/app_bootstrap_state.dart`
  - Bootstrap state model and minimal readiness semantics used by UI and startup orchestration.
- `lib/bootstrap/app_runtime.dart`
  - Runtime dependency aggregate created after delayed initialization completes.
- `lib/bootstrap/app_bootstrap_controller.dart`
  - Async bootstrap orchestrator that performs delayed initialization and exposes state transitions.
- `lib/bootstrap/app_bootstrap_scope.dart`
  - Root scope that starts bootstrap after first frame and hosts the app with bootstrap-aware provider overrides.
- `lib/widgets/chat_message_list_skeleton.dart`
  - Skeleton message area used by `ChatPage` during bootstrap.
- `test/bootstrap/app_bootstrap_controller_test.dart`
  - Unit tests for bootstrap state transitions and delayed initialization behavior.

### Existing files to modify

- `lib/main.dart`
  - Reduce pre-`runApp()` work to minimal entry setup and hand off runtime assembly to bootstrap code.
- `lib/pages/chat_page.dart`
  - Render bootstrap-aware message content and defer `loadGroups()` until bootstrap ready.
- `lib/widgets/chat_input.dart`
  - Separate composer editability from send availability and surface a lightweight preparing state.
- `lib/providers/chat_ui_providers.dart`
  - Add bootstrap UI state providers and any lightweight startup flags used by the page and input.
- `lib/providers/chat_dependency_providers.dart`
  - Add bootstrap-state provider entrypoints and adjust runtime-facing providers so the app can render before full runtime injection.
- `lib/providers/chat_providers.dart`
  - Wire any new provider exports used by the page/input.
- `README.md`
  - Note the bootstrap startup split so the documented architecture matches the code.
- `test/pages/chat_page_test.dart`
  - Add bootstrap chat page coverage.
- `test/widgets/chat_input_test.dart`
  - Add composer-editable / send-disabled startup coverage.

### Existing files to inspect during implementation

- `lib/providers/chat_collection_providers.dart`
  - Existing chat state containers used by page gating.
- `lib/storage/chat_storage.dart`
  - Runtime storage interface needed by delayed initialization.
- `lib/storage/chat_storage_factory.dart`
  - Storage creation path currently invoked before `runApp()`.

---

### Task 1: Add bootstrap state model and controller tests first

**Files:**
- Create: `lib/bootstrap/app_bootstrap_state.dart`
- Create: `test/bootstrap/app_bootstrap_controller_test.dart`
- Modify: `pubspec.yaml` only if test support needs an already-approved dependency

- [ ] **Step 1: Write the failing bootstrap controller tests**

Add tests that describe the intended behavior before any production bootstrap code exists:

- `booting` is the default state
- successful delayed initialization transitions to `ready`
- failed delayed initialization transitions to `failed`
- bootstrap readiness exposes `composer editable = true` while `booting`
- bootstrap readiness exposes `send available = false` while `booting`

Representative test shape:

```dart
test('bootstrap starts in booting state and becomes ready after init', () async {
  final controller = AppBootstrapController(
    initializeRuntime: () async => _FakeRuntime(),
  );

  expect(controller.state.phase, AppBootstrapPhase.booting);
  expect(controller.state.isComposerEditable, isTrue);
  expect(controller.state.isSendAvailable, isFalse);

  await controller.start();

  expect(controller.state.phase, AppBootstrapPhase.ready);
  expect(controller.state.isSendAvailable, isTrue);
});
```

- [ ] **Step 2: Run the bootstrap tests and verify they fail for the missing types**

Run:

```bash
fvm flutter test test/bootstrap/app_bootstrap_controller_test.dart
```

Expected:

- FAIL with missing `AppBootstrapController`, `AppBootstrapPhase`, or equivalent bootstrap model symbols

- [ ] **Step 3: Implement the minimal bootstrap state model**

Create `app_bootstrap_state.dart` with:

- a small `AppBootstrapPhase` enum: `booting`, `ready`, `failed`
- an immutable `AppBootstrapState`
- derived getters or helpers for:
  - `isReady`
  - `isComposerEditable`
  - `isSendAvailable`

Keep this file free of UI dependencies except where a lightweight error payload type is strictly needed.

- [ ] **Step 4: Implement the minimal bootstrap controller to satisfy the tests**

Create a controller that:

- starts in `booting`
- accepts an injected async initializer
- moves to `ready` with a runtime payload on success
- moves to `failed` on error

Do not assemble the real app runtime yet; keep this task focused on the tested state machine.

- [ ] **Step 5: Re-run the bootstrap tests**

Run:

```bash
fvm flutter test test/bootstrap/app_bootstrap_controller_test.dart
```

Expected:

- PASS

- [ ] **Step 6: Commit**

```bash
git add lib/bootstrap/app_bootstrap_state.dart lib/bootstrap/app_bootstrap_controller.dart test/bootstrap/app_bootstrap_controller_test.dart
git commit -m "test: add bootstrap state controller coverage"
```

---

### Task 2: Refactor the app entrypoint to bootstrap after `runApp()`

**Files:**
- Create: `lib/bootstrap/app_runtime.dart`
- Create: `lib/bootstrap/app_bootstrap_scope.dart`
- Modify: `lib/main.dart`
- Modify: `lib/providers/chat_dependency_providers.dart`

- [ ] **Step 1: Write the failing root-scope test or extend bootstrap tests to cover delayed runtime assembly**

Add one test that proves the root bootstrap scope can render an app shell before the runtime future completes.

Representative test shape:

```dart
testWidgets('bootstrap scope renders child while runtime is still loading', (tester) async {
  await tester.pumpWidget(
    AppBootstrapScope(
      initializeRuntime: () async {
        await Future<void>.delayed(const Duration(seconds: 1));
        return _FakeRuntime();
      },
      child: const _FakeApp(),
    ),
  );

  expect(find.byType(_FakeApp), findsOneWidget);
});
```

- [ ] **Step 2: Run the targeted tests and verify they fail**

Run:

```bash
fvm flutter test test/bootstrap/app_bootstrap_controller_test.dart
```

Expected:

- FAIL because `AppBootstrapScope` / `AppRuntime` wiring does not exist yet

- [ ] **Step 3: Implement the runtime aggregate and bootstrap scope**

Create:

- `AppRuntime` to hold the delayed-initialized objects currently built in `main.dart`
- `AppBootstrapScope` to:
  - create/bootstrap the controller
  - schedule startup after first frame
  - expose bootstrap state to descendants

Use explicit constructor dependencies where possible so unit tests can fake runtime assembly.

- [ ] **Step 4: Move heavy initialization logic out of `main.dart`**

Refactor `main.dart` so it only does:

- `WidgetsFlutterBinding.ensureInitialized()`
- `SystemChrome` setup
- `runApp(...)`

Move the existing heavy initialization sequence into a bootstrap runtime builder used by `AppBootstrapScope`.

Keep initialization order functionally equivalent for the ready path; this task changes timing, not runtime semantics.

- [ ] **Step 5: Add bootstrap-aware provider entrypoints**

Update `chat_dependency_providers.dart` so startup-aware widgets can safely read bootstrap state before runtime overrides are ready.

The provider layer should:

- expose bootstrap state/readiness
- avoid throwing during first-frame shell rendering
- keep runtime-dependent providers on the ready path only

- [ ] **Step 6: Re-run the targeted bootstrap tests**

Run:

```bash
fvm flutter test test/bootstrap/app_bootstrap_controller_test.dart
```

Expected:

- PASS

- [ ] **Step 7: Commit**

```bash
git add lib/main.dart lib/bootstrap/app_runtime.dart lib/bootstrap/app_bootstrap_scope.dart lib/providers/chat_dependency_providers.dart test/bootstrap/app_bootstrap_controller_test.dart
git commit -m "refactor: move runtime assembly behind bootstrap scope"
```

---

### Task 3: Add chat-page bootstrap shell behavior

**Files:**
- Create: `lib/widgets/chat_message_list_skeleton.dart`
- Modify: `lib/pages/chat_page.dart`
- Modify: `test/pages/chat_page_test.dart`

- [ ] **Step 1: Write the failing chat page widget tests**

Add tests that verify:

- booting state renders the real chat page chrome plus a message skeleton instead of `ChatMessageList`
- booting state does not call `loadGroups()`
- ready state renders `ChatMessageList`
- ready transition triggers `loadGroups()` exactly once

Representative test shape:

```dart
testWidgets('chat page shows skeleton and defers group load while booting', (tester) async {
  final coordinator = _StubSessionCoordinator();
  final container = ProviderContainer(
    overrides: [
      chatSessionCoordinatorProvider.overrideWith((ref) => coordinator),
      appBootstrapStateProvider.overrideWithValue(AppBootstrapState.booting()),
    ],
  );

  await tester.pumpWidget(_buildChatPage(container));

  expect(find.byType(ChatMessageListSkeleton), findsOneWidget);
  expect(find.byType(ChatMessageList), findsNothing);
  expect(coordinator.loadGroupsCallCount, 0);
});
```

- [ ] **Step 2: Run the chat page tests and verify they fail**

Run:

```bash
fvm flutter test test/pages/chat_page_test.dart
```

Expected:

- FAIL because no bootstrap-aware skeleton behavior exists yet

- [ ] **Step 3: Implement the skeleton widget**

Create a lightweight `ChatMessageListSkeleton` that:

- matches the chat page spacing and tone
- renders placeholder rows without fake content
- stays visually subordinate to the real composer

Keep it intentionally small and testable.

- [ ] **Step 4: Teach `ChatPage` to switch on bootstrap readiness**

Update `ChatPage` so that:

- booting uses `ChatMessageListSkeleton`
- ready uses `ChatMessageList`
- `loadGroups()` is triggered only when bootstrap becomes ready

Avoid duplicate `loadGroups()` calls on rebuilds by tracking whether the ready-path load has already been scheduled.

- [ ] **Step 5: Re-run the chat page tests**

Run:

```bash
fvm flutter test test/pages/chat_page_test.dart
```

Expected:

- PASS

- [ ] **Step 6: Commit**

```bash
git add lib/pages/chat_page.dart lib/widgets/chat_message_list_skeleton.dart test/pages/chat_page_test.dart
git commit -m "feat: add bootstrap chat page shell state"
```

---

### Task 4: Separate composer editing from send availability

**Files:**
- Modify: `lib/providers/chat_ui_providers.dart`
- Modify: `lib/widgets/chat_input.dart`
- Modify: `test/widgets/chat_input_test.dart`

- [ ] **Step 1: Write the failing chat input widget tests**

Add tests that verify:

- during bootstrap booting, the text field is enabled
- during bootstrap booting, the send button is disabled
- ready state restores send availability without changing idle editing behavior
- existing send-phase locking behavior still works once a send starts

Representative test shape:

```dart
testWidgets('chat input stays editable but disables send while booting', (tester) async {
  final container = ProviderContainer(
    overrides: [
      appBootstrapStateProvider.overrideWithValue(AppBootstrapState.booting()),
    ],
  );

  await tester.pumpWidget(_buildChatInput(container));

  expect(
    tester.widget<TextField>(find.byKey(const ValueKey('chat-input-field'))).enabled,
    isTrue,
  );
  expect(
    tester.widget<IconButton>(find.byKey(const ValueKey('chat-input-send-button'))).onPressed,
    isNull,
  );
});
```

- [ ] **Step 2: Run the chat input tests and verify they fail**

Run:

```bash
fvm flutter test test/widgets/chat_input_test.dart
```

Expected:

- FAIL because composer editability and send availability are still coupled

- [ ] **Step 3: Add bootstrap-derived UI gating providers**

Update `chat_ui_providers.dart` with thin providers that derive:

- composer editability
- send availability
- optional startup helper text

These should combine bootstrap state with the existing `sendPhase` / voice session rules rather than replace them.

- [ ] **Step 4: Update `ChatInput` to use the new gating**

Refactor the widget so that:

- `TextField.enabled` is controlled by editability, not directly by `sendPhase != idle`
- send button enablement requires bootstrap readiness plus the existing idle/cancel semantics
- booting can show a subtle “preparing” hint without changing the page structure

Do not change actual send flow logic in the coordinator during this task; only gate UI availability.

- [ ] **Step 5: Re-run the chat input tests**

Run:

```bash
fvm flutter test test/widgets/chat_input_test.dart
```

Expected:

- PASS

- [ ] **Step 6: Commit**

```bash
git add lib/providers/chat_ui_providers.dart lib/widgets/chat_input.dart test/widgets/chat_input_test.dart
git commit -m "feat: decouple composer editing from send readiness"
```

---

### Task 5: Integrate real runtime assembly and startup instrumentation

**Files:**
- Modify: `lib/main.dart`
- Modify: `lib/bootstrap/app_bootstrap_controller.dart`
- Modify: `lib/bootstrap/app_runtime.dart`
- Modify: `README.md`

- [ ] **Step 1: Write or extend tests for the production bootstrap builder**

Add focused coverage for the runtime builder path that asserts:

- heavy initialization is invoked from the delayed bootstrap callback, not before scope creation
- bootstrap controller records failed initialization as `failed`

Use injected fakes instead of touching real filesystem/database services in tests.

- [ ] **Step 2: Run the bootstrap-focused tests and verify they fail if the production builder still does eager work**

Run:

```bash
fvm flutter test test/bootstrap/app_bootstrap_controller_test.dart
```

Expected:

- FAIL until production wiring is using the delayed builder path

- [ ] **Step 3: Finish wiring the real runtime builder**

Move the current `main.dart` startup sequence into a dedicated runtime builder method/class that assembles:

- `SharedPreferences`
- `AppSettingsRepository`
- `ChatStorage`
- file/artifact/skill services
- `ChatService`
- `TurnHarness`
- runtime-backed provider overrides

Keep ordering explicit and add concise startup logs/timestamps around:

- bootstrap start
- first-frame callback bootstrap dispatch
- runtime ready

These logs provide verification data without adding a new recovery flow.

- [ ] **Step 4: Update `README.md`**

Document the new startup shape at a high level:

- minimal `main.dart`
- first-frame bootstrap scope
- chat page startup shell

- [ ] **Step 5: Re-run the bootstrap-focused tests**

Run:

```bash
fvm flutter test test/bootstrap/app_bootstrap_controller_test.dart
```

Expected:

- PASS

- [ ] **Step 6: Commit**

```bash
git add lib/main.dart lib/bootstrap/app_bootstrap_controller.dart lib/bootstrap/app_runtime.dart README.md test/bootstrap/app_bootstrap_controller_test.dart
git commit -m "feat: wire delayed runtime bootstrap"
```

---

### Task 6: Run regression verification on the touched surfaces

**Files:**
- No new files required unless test fixes uncover missing coverage helpers

- [ ] **Step 1: Run the bootstrap unit tests**

Run:

```bash
fvm flutter test test/bootstrap/app_bootstrap_controller_test.dart
```

Expected:

- PASS

- [ ] **Step 2: Run the chat page widget tests**

Run:

```bash
fvm flutter test test/pages/chat_page_test.dart
```

Expected:

- PASS

- [ ] **Step 3: Run the chat input widget tests**

Run:

```bash
fvm flutter test test/widgets/chat_input_test.dart
```

Expected:

- PASS

- [ ] **Step 4: Run targeted analysis on touched files**

Run:

```bash
fvm flutter analyze lib/main.dart lib/bootstrap lib/pages/chat_page.dart lib/widgets/chat_input.dart lib/providers/chat_ui_providers.dart lib/providers/chat_dependency_providers.dart
```

Expected:

- PASS with no new analyzer errors

- [ ] **Step 5: Perform manual runtime verification**

Preferred Android-first verification:

```bash
bash scripts/android_install_debug.sh <device_id>
```

Then manually confirm:

- cold launch shows the chat page sooner than before
- message area shows skeleton during bootstrap
- input field is editable before send becomes available
- send becomes available when runtime initialization finishes
- no page jump from fake screen to real screen

Secondary iOS/manual verification if available:

```bash
fvm flutter run
```

Confirm the same startup behavior on iOS simulator/device.

- [ ] **Step 6: Commit**

```bash
git add .
git commit -m "test: verify bootstrap cold start flow"
```

