# Create Artifact Render Observability Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add session-based observability and anomaly detection for inline `create_artifact` rendering, and replace the current loading skeleton with a static shell plus fixed-rate diagonal sweep overlay.

**Architecture:** Keep the existing runtime-preview versus final-takeover rendering split intact, and add a runtime-only `ArtifactRenderSessionRecorder` that aggregates render signals emitted by `ArtifactPreviewSurface`. The widget remains the render owner, but it now emits structured session events, computes a first-successful-render milestone, logs high-signal trace summaries, and swaps the skeleton placeholder for a Flutter-owned sweep overlay that is decoupled from WebView update cadence.

**Tech Stack:** Flutter, Riverpod-adjacent state patterns already used in the repo, `webview_flutter`, existing `Logger.trace` / `Logger.temp`, widget tests, plain Dart unit tests.

---

## File Structure

### New files

- `lib/models/artifact/artifact_render_session_snapshot.dart`
  - Runtime-only session read model for one inline artifact render lifecycle, including counters, timestamps, anomaly codes, and height-pattern classification helpers.
- `lib/services/artifact/artifact_render_session_recorder.dart`
  - Aggregates session events, computes anomaly verdicts, produces `session_done` summaries, and emits formal trace logs.
- `test/services/artifact/artifact_render_session_recorder_test.dart`
  - Unit tests for anomaly detection, `firstSuccessfulRender`, and `heightPattern` classification.

### Modified files

- `lib/widgets/chat_blocks/artifact_preview_surface.dart`
  - Emits structured render-session events, injects `dom_commit` back-channel support, wires recorder lifecycle, and replaces skeleton placeholder with static shell + sweep overlay.
- `lib/widgets/tool_renderers/tool_running_effects.dart`
  - Reuse or extract a low-noise diagonal sweep primitive suitable for inline artifact loading instead of creating a second animation idiom from scratch.
- `test/widgets/chat_blocks/artifact_preview_surface_debouncing_test.dart`
  - Extend existing widget coverage for waiting/loading state changes, overlay visibility, and skeleton removal.
- `test/widgets/chat_blocks/artifact_preview_surface_test.dart`
  - Add focused widget assertions around static shell behavior and stable runtime preview rendering entry conditions.
- `docs/architecture/logging.md`
  - Add a short section clarifying that artifact render-session anomaly summaries live in the existing trace lane and do not form a second observability system.

### Existing files to inspect while implementing

- `docs/superpowers/specs/2026-06-06-create-artifact-render-observability-design.md`
- `lib/widgets/chat_blocks/artifact_preview_surface.dart`
- `lib/widgets/tool_renderers/tool_running_effects.dart`
- `lib/models/debug/streaming_trace_snapshot.dart`
- `lib/services/debug/streaming_trace_recorder.dart`
- `test/widgets/chat_blocks/artifact_preview_surface_debouncing_test.dart`
- `test/widgets/chat_blocks/artifact_preview_surface_test.dart`

## Task 1: Add Render Session Domain Model

**Files:**
- Create: `lib/models/artifact/artifact_render_session_snapshot.dart`
- Test: `test/services/artifact/artifact_render_session_recorder_test.dart`

- [x] **Step 1: Write the failing recorder-domain test for height-drop anomaly**

```dart
test('marks session anomalous when applied height drops by more than 30px', () {
  final recorder = ArtifactRenderSessionRecorder();
  final sessionId = 'turn_1:artifact_1:0';

  recorder.startSession(
    sessionId: sessionId,
    turnId: 'turn_1',
    artifactId: 'artifact_1',
    providerCallId: 'call_1',
    sourcePath: 'runtime://artifact_1',
    phase: ArtifactRenderPhase.runtime,
    isRuntimePreview: true,
    timestamp: DateTime(2026, 6, 6, 10, 0, 0),
  );
  recorder.recordHeightApplied(
    sessionId: sessionId,
    appliedHeight: 280,
    isPreviewTruncated: false,
    timestamp: DateTime(2026, 6, 6, 10, 0, 1),
  );
  recorder.recordHeightApplied(
    sessionId: sessionId,
    appliedHeight: 240,
    isPreviewTruncated: false,
    timestamp: DateTime(2026, 6, 6, 10, 0, 2),
  );

  final snapshot = recorder.finishSession(
    sessionId: sessionId,
    timestamp: DateTime(2026, 6, 6, 10, 0, 3),
  );

  expect(snapshot.verdict, ArtifactRenderSessionVerdict.anomalous);
  expect(snapshot.anomalyCodes, contains('artifact_height_drop_over_30px'));
  expect(snapshot.largestDropPx, 40);
});
```

- [x] **Step 2: Run test to verify it fails**

Run: `fvm flutter test test/services/artifact/artifact_render_session_recorder_test.dart`

Expected: FAIL because `ArtifactRenderSessionRecorder` and related models do not exist yet.

- [x] **Step 3: Implement the minimal session snapshot model**

Create `lib/models/artifact/artifact_render_session_snapshot.dart` with focused enums and DTOs:

```dart
enum ArtifactRenderPhase { runtime, finalTakeover }

enum ArtifactRenderSessionVerdict { normal, anomalous }

enum ArtifactRenderHeightPattern {
  monotonicGrowth,
  overshootThenDrop,
  sawtooth,
  finalTakeoverDrop,
  noHeightSignal,
}

class ArtifactRenderSessionSnapshot {
  const ArtifactRenderSessionSnapshot({
    required this.sessionId,
    required this.turnId,
    required this.artifactId,
    required this.sourcePath,
    required this.verdict,
    required this.anomalyCodes,
    required this.heightPattern,
    required this.maxAppliedHeight,
    required this.finalAppliedHeight,
    required this.largestDropPx,
    required this.totalStreamingDurationMs,
    required this.firstSuccessfulRenderAtMs,
    required this.sourceProgressCount,
    required this.applyCount,
    required this.domCommitCount,
    required this.heightSampleCount,
    required this.heightAppliedCount,
    required this.phaseSummary,
  });

  final String sessionId;
  final String turnId;
  final String artifactId;
  final String sourcePath;
  final ArtifactRenderSessionVerdict verdict;
  final List<String> anomalyCodes;
  final ArtifactRenderHeightPattern heightPattern;
  final double? maxAppliedHeight;
  final double? finalAppliedHeight;
  final double largestDropPx;
  final int totalStreamingDurationMs;
  final int? firstSuccessfulRenderAtMs;
  final int sourceProgressCount;
  final int applyCount;
  final int domCommitCount;
  final int heightSampleCount;
  final int heightAppliedCount;
  final String phaseSummary;
}
```

- [x] **Step 4: Run test to verify model-only progress still fails for missing recorder behavior**

Run: `fvm flutter test test/services/artifact/artifact_render_session_recorder_test.dart`

Expected: FAIL because the recorder and anomaly logic are not implemented yet.

- [ ] **Step 5: Commit**

```bash
git add lib/models/artifact/artifact_render_session_snapshot.dart \
  test/services/artifact/artifact_render_session_recorder_test.dart
git commit -m "feat: add artifact render session model"
```

## Task 2: Implement Recorder Logic and Trace Summaries

**Files:**
- Create: `lib/services/artifact/artifact_render_session_recorder.dart`
- Modify: `lib/models/artifact/artifact_render_session_snapshot.dart`
- Test: `test/services/artifact/artifact_render_session_recorder_test.dart`
- Modify: `docs/architecture/logging.md`

- [x] **Step 1: Extend tests for first-successful-render and final-second anomaly**

Add failing tests covering:

```dart
test('flags first render in final second when stream lasts longer than 3s', () {
  final recorder = ArtifactRenderSessionRecorder();
  final sessionId = 'turn_1:artifact_1:0';
  final startedAt = DateTime(2026, 6, 6, 10, 0, 0);

  recorder.startSession(
    sessionId: sessionId,
    turnId: 'turn_1',
    artifactId: 'artifact_1',
    sourcePath: 'runtime://artifact_1',
    phase: ArtifactRenderPhase.runtime,
    isRuntimePreview: true,
    timestamp: startedAt,
  );
  recorder.recordSourceProgressed(
    sessionId: sessionId,
    sourceLength: 120,
    deltaLength: 120,
    timestamp: startedAt.add(const Duration(milliseconds: 300)),
  );
  recorder.recordRuntimeApplyCompleted(
    sessionId: sessionId,
    sourceLength: 600,
    result: 'success',
    timestamp: startedAt.add(const Duration(milliseconds: 2600)),
  );
  recorder.recordDomCommit(
    sessionId: sessionId,
    sourceLength: 600,
    artifactRectHeight: 180,
    timestamp: startedAt.add(const Duration(milliseconds: 3200)),
  );
  recorder.recordHeightApplied(
    sessionId: sessionId,
    appliedHeight: 200,
    isPreviewTruncated: false,
    timestamp: startedAt.add(const Duration(milliseconds: 3250)),
  );

  final snapshot = recorder.finishSession(
    sessionId: sessionId,
    timestamp: startedAt.add(const Duration(milliseconds: 3600)),
  );

  expect(
    snapshot.anomalyCodes,
    contains('artifact_first_render_in_final_second'),
  );
  expect(snapshot.firstSuccessfulRenderAtMs, 3250);
});
```

Add at least one failing classification test for `finalTakeoverDrop`.

- [x] **Step 2: Run recorder tests to verify they fail**

Run: `fvm flutter test test/services/artifact/artifact_render_session_recorder_test.dart`

Expected: FAIL because recorder methods and classification rules are incomplete.

- [x] **Step 3: Implement the recorder with the smallest viable state machine**

Create `lib/services/artifact/artifact_render_session_recorder.dart` with one in-memory active-session map keyed by `sessionId`.

Implementation outline:

```dart
class ArtifactRenderSessionRecorder {
  ArtifactRenderSessionRecorder({
    void Function(String tag, String message,
        {Map<String, dynamic>? data})? traceEmitter,
  }) : _traceEmitter = traceEmitter ?? _defaultTraceEmitter;

  final Map<String, _ActiveArtifactRenderSession> _sessions = {};
  final void Function(String tag, String message, {Map<String, dynamic>? data})
      _traceEmitter;

  void startSession({ ... }) { ... }
  void recordSourceProgressed({ ... }) { ... }
  void recordRuntimeApplyStarted({ ... }) { ... }
  void recordRuntimeApplyCompleted({ ... }) { ... }
  void recordDomCommit({ ... }) { ... }
  void recordHeightSampled({ ... }) { ... }
  void recordHeightApplied({ ... }) { ... }
  void recordFinalControllerPrepared({ ... }) { ... }
  void recordFinalTakeover({ ... }) { ... }
  ArtifactRenderSessionSnapshot finishSession({ ... }) { ... }
}
```

Rules to implement exactly:

- `artifact_height_drop_over_30px`
  - Trigger when `maxAppliedHeight - appliedHeight > 30`
- `firstSuccessfulRender`
  - First time after at least one `runtimeApplyCompleted`, one `domCommit`, and one `heightApplied`
- `artifact_first_render_in_final_second`
  - Trigger when `totalStreamingDurationMs > 3000`
  - And `firstSuccessfulRenderAtMs >= totalStreamingDurationMs - 1000`
- `heightPattern`
  - Respect the priority from the spec:
    1. `noHeightSignal`
    2. `finalTakeoverDrop`
    3. `sawtooth`
    4. `overshootThenDrop`
    5. `monotonicGrowth`

Trace output requirements:

- Emit `artifact.preview.anomaly` via `Logger.trace`
- Emit `artifact.preview.session_done` via `Logger.trace`
- Keep raw per-event emission opt-in and low-noise; avoid exploding trace volume unnecessarily

- [x] **Step 4: Update logging docs**

Append a concise note to `docs/architecture/logging.md` that artifact render-session anomalies and summaries are formal `trace` entries inside `logs/app.log`, not a second observability lane.

- [x] **Step 5: Run tests to verify recorder behavior passes**

Run: `fvm flutter test test/services/artifact/artifact_render_session_recorder_test.dart`

Expected: PASS

- [ ] **Step 6: Commit**

```bash
git add lib/models/artifact/artifact_render_session_snapshot.dart \
  lib/services/artifact/artifact_render_session_recorder.dart \
  test/services/artifact/artifact_render_session_recorder_test.dart \
  docs/architecture/logging.md
git commit -m "feat: add artifact render session recorder"
```

## Task 3: Wire Recorder Into ArtifactPreviewSurface

**Files:**
- Modify: `lib/widgets/chat_blocks/artifact_preview_surface.dart`
- Test: `test/widgets/chat_blocks/artifact_preview_surface_debouncing_test.dart`

- [x] **Step 1: Add the first failing widget-level observability test**

Add a focused test that simulates a runtime preview staying empty initially, then updating, and asserts the widget emits a session summary through an injected fake recorder.

Example test shape:

```dart
testWidgets('runtime preview reports session lifecycle to recorder', (tester) async {
  final recorder = FakeArtifactRenderSessionRecorder();

  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: ArtifactPreviewSurface(
          artifactId: 'artifact-1',
          source: null,
          sourcePath: 'runtime://artifact',
          isRuntimePreview: true,
          sessionRecorder: recorder,
        ),
      ),
    ),
  );

  await tester.pump();
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: ArtifactPreviewSurface(
          artifactId: 'artifact-1',
          source: '<div>Updated</div>',
          sourcePath: 'runtime://artifact',
          isRuntimePreview: true,
          sessionRecorder: recorder,
        ),
      ),
    ),
  );

  expect(recorder.startedSessionIds, hasLength(1));
  expect(recorder.sourceProgressLengths, contains('<div>Updated</div>'.length));
});
```

- [x] **Step 2: Run the widget test to verify it fails**

Run: `fvm flutter test test/widgets/chat_blocks/artifact_preview_surface_debouncing_test.dart`

Expected: FAIL because `ArtifactPreviewSurface` has no recorder injection or event emission yet.

- [x] **Step 3: Inject recorder dependency and session lifecycle**

Modify `ArtifactPreviewSurface` constructor to accept an optional recorder:

```dart
const ArtifactPreviewSurface({
  super.key,
  required this.artifactId,
  required this.source,
  required this.sourcePath,
  this.isRuntimePreview = false,
  this.enableInternalScroll = false,
  this.sessionRecorder,
  this.turnId,
  this.providerCallId,
});
```

Inside `_ArtifactPreviewSurfaceState`:

- derive one stable `sessionId` in `initState`
- call `startSession(...)` once
- emit `recordSourceProgressed(...)` when source length increases
- emit `recordRuntimeApplyStarted/Completed(...)`
- emit `recordHeightSampled(...)`
- emit `recordHeightApplied(...)`
- emit `recordFinalControllerPrepared(...)`
- emit `recordFinalTakeover(...)`
- call `finishSession(...)` on completion/dispose when appropriate

Do not move responsibility into `TurnHarness` or timeline projection.

- [x] **Step 4: Add WebView `dom_commit` back-channel**

Extend the injected HTML/JS in `artifact_preview_surface.dart`:

```javascript
window.__artifactDomCommit__ = function(meta) {
  if (window.ArtifactRenderState &&
      typeof window.ArtifactRenderState.postMessage === 'function') {
    window.ArtifactRenderState.postMessage(JSON.stringify({
      event: 'dom_commit',
      sourceLength: meta && meta.sourceLength,
      artifactRectHeight: meta && meta.artifactRectHeight
    }));
  }
};
```

After a successful `__applyArtifactPayload__`, trigger `__artifactDomCommit__`.

Register a second JS channel in Flutter and forward `dom_commit` into the recorder.

- [x] **Step 5: Run the widget tests to verify they pass**

Run: `fvm flutter test test/widgets/chat_blocks/artifact_preview_surface_debouncing_test.dart test/widgets/chat_blocks/artifact_preview_surface_test.dart`

Expected: PASS

- [ ] **Step 6: Commit**

```bash
git add lib/widgets/chat_blocks/artifact_preview_surface.dart \
  test/widgets/chat_blocks/artifact_preview_surface_debouncing_test.dart \
  test/widgets/chat_blocks/artifact_preview_surface_test.dart
git commit -m "feat: instrument artifact preview sessions"
```

## Task 4: Replace Skeleton Loading With Static Shell and Sweep Overlay

**Files:**
- Modify: `lib/widgets/chat_blocks/artifact_preview_surface.dart`
- Modify: `lib/widgets/tool_renderers/tool_running_effects.dart`
- Test: `test/widgets/chat_blocks/artifact_preview_surface_debouncing_test.dart`
- Test: `test/widgets/chat_blocks/artifact_preview_surface_test.dart`

- [x] **Step 1: Add the failing UI-state tests**

Write widget tests that assert:

```dart
testWidgets('waiting runtime preview shows sweep shell instead of skeleton lines',
    (tester) async {
  await tester.pumpWidget(
    const MaterialApp(
      home: Scaffold(
        body: ArtifactPreviewSurface(
          artifactId: 'artifact-1',
          source: null,
          sourcePath: 'runtime://artifact',
          isRuntimePreview: true,
        ),
      ),
    ),
  );

  expect(find.textContaining('正在准备预览'), findsNothing);
  expect(find.byKey(const Key('artifact-preview-sweep-shell')), findsOneWidget);
  expect(find.byKey(const Key('artifact-preview-skeleton-line-1')), findsNothing);
});
```

Add a second failing test asserting the sweep overlay remains present while runtime updates are in flight.

- [x] **Step 2: Run widget tests to verify they fail**

Run: `fvm flutter test test/widgets/chat_blocks/artifact_preview_surface_debouncing_test.dart test/widgets/chat_blocks/artifact_preview_surface_test.dart`

Expected: FAIL because the old placeholder still renders skeleton rows and no sweep shell key exists.

- [x] **Step 3: Extract or reuse a low-noise sweep primitive**

Inspect `lib/widgets/tool_renderers/tool_running_effects.dart` and either:

- reuse the existing diagonal sweep widget with tuned opacity/duration, or
- extract a smaller `ArtifactPreviewSweepOverlay` helper inside `artifact_preview_surface.dart` if direct reuse becomes awkward

Constraints to preserve:

- Flutter-owned animation
- fixed-rate loop independent of WebView updates
- diagonal travel from upper-right to lower-left
- lower visual intensity than large running workflow cards

- [x] **Step 4: Replace placeholder rendering**

Update `_buildPreviewPlaceholder(...)` in `artifact_preview_surface.dart` so it no longer renders fake text bars.

Target replacement shape:

```dart
Widget _buildPreviewShell(BuildContext context) {
  return Container(
    key: const Key('artifact-preview-sweep-shell'),
    width: double.infinity,
    height: _previewHeight,
    decoration: BoxDecoration(
      color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.45),
      borderRadius: BorderRadius.circular(12),
    ),
    child: const ArtifactPreviewSweepOverlay(),
  );
}
```

UI rules:

- before first successful render: static shell + sweep overlay
- during runtime update or pending final takeover: show sweep overlay above content
- do not reintroduce fake line skeletons

- [x] **Step 5: Run widget tests to verify the new UI passes**

Run: `fvm flutter test test/widgets/chat_blocks/artifact_preview_surface_debouncing_test.dart test/widgets/chat_blocks/artifact_preview_surface_test.dart`

Expected: PASS

- [ ] **Step 6: Commit**

```bash
git add lib/widgets/chat_blocks/artifact_preview_surface.dart \
  lib/widgets/tool_renderers/tool_running_effects.dart \
  test/widgets/chat_blocks/artifact_preview_surface_debouncing_test.dart \
  test/widgets/chat_blocks/artifact_preview_surface_test.dart
git commit -m "feat: add artifact preview sweep loading state"
```

## Task 5: Run Focused Verification and Update the Plan State

**Files:**
- Modify: `docs/superpowers/plans/2026-06-06-create-artifact-render-observability-implementation-plan.md`

- [x] **Step 1: Run the focused verification suite**

Run:

```bash
fvm flutter test test/services/artifact/artifact_render_session_recorder_test.dart
fvm flutter test test/widgets/chat_blocks/artifact_preview_surface_debouncing_test.dart
fvm flutter test test/widgets/chat_blocks/artifact_preview_surface_test.dart
fvm flutter analyze
```

Expected:

- all three targeted test files PASS
- `flutter analyze` PASS with no new diagnostics from touched files

- [x] **Step 2: If a verification command fails, fix only the revealed issue and rerun that command**

Do not batch speculative fixes. Return to the exact failing test or analyzer output, correct it, and rerun the smallest relevant command first.

- [x] **Step 3: Mark completed steps in this plan**

Update this plan document so every completed checkbox is checked before handoff or merge.

- [ ] **Step 4: Commit final verification-state updates if needed**

```bash
git add docs/superpowers/plans/2026-06-06-create-artifact-render-observability-implementation-plan.md
git commit -m "docs: update artifact render observability plan progress"
```

Only create this commit if the plan document itself changed during execution.
