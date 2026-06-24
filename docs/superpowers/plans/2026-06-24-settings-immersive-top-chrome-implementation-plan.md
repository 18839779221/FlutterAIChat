# Settings Immersive Top Chrome Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a shared immersive top chrome scaffold for the settings domain so level-1, level-2, and level-3 settings pages use the same fixed floating header pattern as the homepage.

**Architecture:** Introduce a settings-domain-specific scaffold that owns the top veil, floating header, and body top inset, then migrate the three existing settings-domain entry pages away from page-local `AppBar` builders to the shared structure. Keep the body content logic of each page intact and scope this rollout to top chrome only.

**Tech Stack:** Flutter 3.35.7 via `fvm flutter`, Material 3, Riverpod, shared app theme extensions (`AppThemeSpec`, `AppSpacing`, `AppRadius`, `AppMotion`), Flutter widget tests

## Global Constraints

- Use `fvm flutter` for Flutter commands in this repository.
- Do not implement a generic app-wide top chrome in this rollout; build a settings-domain-specific scaffold only.
- Do not copy the homepage header widget tree directly into settings pages; align semantics and structure while keeping the implementation decoupled.
- Do not redesign settings page body content in this rollout; only replace the top chrome structure and required body top inset handling.
- Replace page-local `_buildTintedHeader(...)` usage in `lib/pages/settings_page.dart`, `lib/pages/model_management_page.dart`, and `lib/pages/provider_form_page.dart`.
- Keep title fixed and floating while page content scrolls beneath it.
- Avoid page-local magic numbers for header spacing; the shared scaffold must own top inset calculation.

---

## File Structure

### New files

- `lib/widgets/settings/immersive_settings_scaffold.dart`
  - Shared settings-domain scaffold for top veil, floating header, top inset, and constrained body content.
- `test/widgets/settings/immersive_settings_scaffold_test.dart`
  - Widget tests for fixed header structure, title centering contract, and body inset behavior.

### Modified files

- `lib/pages/settings_page.dart`
  - Replace `Scaffold.appBar` with the shared scaffold and remove the local tinted header helper.
- `lib/pages/model_management_page.dart`
  - Replace `Scaffold.appBar` with the shared scaffold and remove the local tinted header helper.
- `lib/pages/provider_form_page.dart`
  - Replace `Scaffold.appBar` with the shared scaffold and remove the local tinted header helper.
- `test/pages/settings_page_test.dart`
  - Update expectations from plain `AppBar` structure to immersive scaffold structure.
- `test/pages/model_management_page_test.dart`
  - Add or update page-level assertions that the model-management page uses the shared immersive header.
- `test/pages/provider_form_page_test.dart`
  - Add or update page-level assertions that the provider form page uses the shared immersive header.

### Existing references to inspect before coding

- `lib/pages/chat_page.dart`
  - Source of existing homepage top veil / ghost header spatial language.
- `lib/widgets/home_header_button.dart`
  - Existing header button visual language that may be reused or adapted.
- `docs/superpowers/specs/2026-06-24-settings-immersive-top-chrome-design.md`
  - Approved design constraints for this rollout.

## Task 1: Build the Shared Settings Immersive Scaffold

**Files:**
- Create: `lib/widgets/settings/immersive_settings_scaffold.dart`
- Test: `test/widgets/settings/immersive_settings_scaffold_test.dart`

**Interfaces:**
- Consumes: `AppThemeSpec`, `AppSpacing`, `AppRadius`, `AppMotion`, `Navigator.maybePop`, standard Flutter layout primitives
- Produces:
  - `enum SettingsHeaderStyle { root, nested, editor }`
  - `class ImmersiveSettingsScaffold extends StatelessWidget`
  - constructor:
    `ImmersiveSettingsScaffold({super.key, required String title, required Widget body, SettingsHeaderStyle headerStyle = SettingsHeaderStyle.root, Widget? leading, Widget? trailing, EdgeInsetsGeometry? bodyPadding, double maxContentWidth = 760, ScrollController? scrollController, bool centerTitle = true})`

- [ ] **Step 1: Write the failing scaffold structure test**

```dart
testWidgets('immersive settings scaffold renders fixed veil and floating header',
    (tester) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light(),
      home: const ImmersiveSettingsScaffold(
        title: '设置',
        body: SizedBox(height: 600, child: Text('body')),
      ),
    ),
  );

  expect(find.byKey(const ValueKey('settings-top-overlay-veil')), findsOneWidget);
  expect(find.byKey(const ValueKey('settings-floating-header')), findsOneWidget);
  expect(find.text('设置'), findsOneWidget);
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `fvm flutter test test/widgets/settings/immersive_settings_scaffold_test.dart`

Expected: FAIL because `ImmersiveSettingsScaffold` does not exist yet.

- [ ] **Step 3: Write the minimal scaffold implementation**

```dart
enum SettingsHeaderStyle { root, nested, editor }

class ImmersiveSettingsScaffold extends StatelessWidget {
  const ImmersiveSettingsScaffold({
    super.key,
    required this.title,
    required this.body,
    this.headerStyle = SettingsHeaderStyle.root,
    this.leading,
    this.trailing,
    this.bodyPadding,
    this.maxContentWidth = 760,
    this.scrollController,
    this.centerTitle = true,
  });

  final String title;
  final Widget body;
  final SettingsHeaderStyle headerStyle;
  final Widget? leading;
  final Widget? trailing;
  final EdgeInsetsGeometry? bodyPadding;
  final double maxContentWidth;
  final ScrollController? scrollController;
  final bool centerTitle;

  static const double _headerHeight = 56;

  @override
  Widget build(BuildContext context) {
    final spacing = Theme.of(context).extension<AppSpacing>()!;
    final topInset = MediaQuery.of(context).padding.top + _headerHeight + spacing.sm;

    return Scaffold(
      body: Stack(
        children: [
          Positioned.fill(
            child: SingleChildScrollView(
              controller: scrollController,
              padding: EdgeInsets.only(top: topInset),
              child: Align(
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: maxContentWidth),
                  child: Padding(
                    padding: bodyPadding ?? EdgeInsets.fromLTRB(spacing.lg, 0, spacing.lg, spacing.xl),
                    child: body,
                  ),
                ),
              ),
            ),
          ),
          const _SettingsTopOverlayVeil(),
          _SettingsFloatingHeader(
            title: title,
            leading: leading,
            trailing: trailing,
            centerTitle: centerTitle,
            headerStyle: headerStyle,
          ),
        ],
      ),
    );
  }
}
```

- [ ] **Step 4: Add behavior-focused tests for inset and title centering**

```dart
testWidgets('immersive settings scaffold offsets body beneath header',
    (tester) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light(),
      home: const ImmersiveSettingsScaffold(
        title: '设置',
        body: Text('body'),
      ),
    ),
  );

  final bodyTop = tester.getTopLeft(find.text('body')).dy;
  final headerBottom =
      tester.getBottomLeft(find.byKey(const ValueKey('settings-floating-header'))).dy;

  expect(bodyTop, greaterThan(headerBottom));
});
```

- [ ] **Step 5: Run widget test file to verify it passes**

Run: `fvm flutter test test/widgets/settings/immersive_settings_scaffold_test.dart`

Expected: PASS

- [ ] **Step 6: Commit**

```bash
git add lib/widgets/settings/immersive_settings_scaffold.dart test/widgets/settings/immersive_settings_scaffold_test.dart
git commit -m "feat: add immersive settings scaffold"
```

## Task 2: Migrate the Level-1 Settings Page

**Files:**
- Modify: `lib/pages/settings_page.dart`
- Test: `test/pages/settings_page_test.dart`

**Interfaces:**
- Consumes:
  - `ImmersiveSettingsScaffold`
  - `SettingsHeaderStyle.root`
- Produces:
  - `SettingsPage` rendered with shared immersive top chrome
  - page-level structure keyed by:
    - `ValueKey('settings-top-overlay-veil')`
    - `ValueKey('settings-floating-header')`

- [ ] **Step 1: Write the failing page-level assertion**

```dart
testWidgets('settings page uses immersive floating header shell', (tester) async {
  final repository = await _buildRepository();
  await _pumpSettingsPage(tester, repository: repository);

  expect(find.byKey(const ValueKey('settings-top-overlay-veil')), findsOneWidget);
  expect(find.byKey(const ValueKey('settings-floating-header')), findsOneWidget);
});
```

- [ ] **Step 2: Run the page test to verify it fails**

Run: `fvm flutter test test/pages/settings_page_test.dart`

Expected: FAIL because the page still renders the old `AppBar`.

- [ ] **Step 3: Replace the page-local app bar with the shared scaffold**

```dart
return ImmersiveSettingsScaffold(
  title: '设置',
  headerStyle: SettingsHeaderStyle.root,
  body: _isLoading
      ? const Center(child: CircularProgressIndicator())
      : Align(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: Column(
              children: [
                // existing settings groups remain unchanged
              ],
            ),
          ),
        ),
);
```

- [ ] **Step 4: Remove the page-local `_buildTintedHeader(...)` helper**

```dart
// Delete the old helper entirely once no longer referenced:
// PreferredSizeWidget _buildTintedHeader(BuildContext context, String title) { ... }
```

- [ ] **Step 5: Run the page test to verify it passes**

Run: `fvm flutter test test/pages/settings_page_test.dart`

Expected: PASS

- [ ] **Step 6: Commit**

```bash
git add lib/pages/settings_page.dart test/pages/settings_page_test.dart
git commit -m "refactor: move settings page to immersive top chrome"
```

## Task 3: Migrate the Model Management Page

**Files:**
- Modify: `lib/pages/model_management_page.dart`
- Test: `test/pages/model_management_page_test.dart`

**Interfaces:**
- Consumes:
  - `ImmersiveSettingsScaffold`
  - `SettingsHeaderStyle.nested`
- Produces:
  - `ModelManagementPage` using the shared floating header structure

- [ ] **Step 1: Write the failing model-management page test**

```dart
testWidgets('model management page uses immersive nested header', (tester) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light(),
      home: ModelManagementPage(repository: repository),
    ),
  );

  expect(find.byKey(const ValueKey('settings-floating-header')), findsOneWidget);
  expect(find.text('模型配置'), findsOneWidget);
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `fvm flutter test test/pages/model_management_page_test.dart`

Expected: FAIL because the page still uses `appBar`.

- [ ] **Step 3: Swap the page shell to the shared scaffold**

```dart
return ImmersiveSettingsScaffold(
  title: '模型配置',
  headerStyle: SettingsHeaderStyle.nested,
  body: _isLoading
      ? const Center(child: CircularProgressIndicator())
      : ListView(
          padding: EdgeInsets.all(spacing.lg),
          children: [
            // existing content preserved
          ],
        ),
);
```

- [ ] **Step 4: Delete the page-local `_buildTintedHeader(...)` helper**

```dart
// Remove obsolete local header builder once migration compiles.
```

- [ ] **Step 5: Run the page test to verify it passes**

Run: `fvm flutter test test/pages/model_management_page_test.dart`

Expected: PASS

- [ ] **Step 6: Commit**

```bash
git add lib/pages/model_management_page.dart test/pages/model_management_page_test.dart
git commit -m "refactor: migrate model management header shell"
```

## Task 4: Migrate the Provider Form Page

**Files:**
- Modify: `lib/pages/provider_form_page.dart`
- Test: `test/pages/provider_form_page_test.dart`

**Interfaces:**
- Consumes:
  - `ImmersiveSettingsScaffold`
  - `SettingsHeaderStyle.editor`
- Produces:
  - `ProviderFormPage` using the shared floating header structure

- [ ] **Step 1: Write the failing provider-form page test**

```dart
testWidgets('provider form page uses immersive editor header', (tester) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light(),
      home: ProviderFormPage(repository: repository),
    ),
  );

  expect(find.byKey(const ValueKey('settings-floating-header')), findsOneWidget);
  expect(find.text('新增 Provider'), findsOneWidget);
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `fvm flutter test test/pages/provider_form_page_test.dart`

Expected: FAIL because the page still uses `appBar`.

- [ ] **Step 3: Replace the page shell with the immersive scaffold**

```dart
return ImmersiveSettingsScaffold(
  title: _isEdit ? '编辑 Provider' : '新增 Provider',
  headerStyle: SettingsHeaderStyle.editor,
  body: Form(
    key: _formKey,
    child: ListView(
      padding: EdgeInsets.all(spacing.lg),
      children: [
        // existing form content preserved
      ],
    ),
  ),
);
```

- [ ] **Step 4: Delete the page-local `_buildTintedHeader(...)` helper**

```dart
// Remove obsolete local header helper after migration.
```

- [ ] **Step 5: Run the provider-form page test to verify it passes**

Run: `fvm flutter test test/pages/provider_form_page_test.dart`

Expected: PASS

- [ ] **Step 6: Commit**

```bash
git add lib/pages/provider_form_page.dart test/pages/provider_form_page_test.dart
git commit -m "refactor: migrate provider form top chrome"
```

## Task 5: Final Verification and Cleanup

**Files:**
- Modify: `lib/widgets/settings/immersive_settings_scaffold.dart`
- Modify: `lib/pages/settings_page.dart`
- Modify: `lib/pages/model_management_page.dart`
- Modify: `lib/pages/provider_form_page.dart`
- Test: `test/widgets/settings/immersive_settings_scaffold_test.dart`
- Test: `test/pages/settings_page_test.dart`
- Test: `test/pages/model_management_page_test.dart`
- Test: `test/pages/provider_form_page_test.dart`

**Interfaces:**
- Consumes: outputs from Tasks 1-4
- Produces: validated immersive top chrome rollout ready for review

- [ ] **Step 1: Run the focused widget and page tests**

Run:

```bash
fvm flutter test \
  test/widgets/settings/immersive_settings_scaffold_test.dart \
  test/pages/settings_page_test.dart \
  test/pages/model_management_page_test.dart \
  test/pages/provider_form_page_test.dart
```

Expected: PASS

- [ ] **Step 2: Run targeted analysis on touched files**

Run:

```bash
fvm flutter analyze \
  lib/widgets/settings/immersive_settings_scaffold.dart \
  lib/pages/settings_page.dart \
  lib/pages/model_management_page.dart \
  lib/pages/provider_form_page.dart \
  test/widgets/settings/immersive_settings_scaffold_test.dart \
  test/pages/settings_page_test.dart \
  test/pages/model_management_page_test.dart \
  test/pages/provider_form_page_test.dart
```

Expected: `No issues found!`

- [ ] **Step 3: Manually verify the three target pages**

Run one of:

```bash
fvm flutter run
```

or, if validating on Android real device:

```bash
bash scripts/android_install_debug.sh <device_id>
```

Check:

- `设置` 页 header 固定悬浮
- `模型配置` 页 header 固定悬浮
- `新增/编辑 Provider` 页 header 固定悬浮
- 内容都从 header 下方滚动经过
- 返回按钮和标题在 claude / olive-paper 主题下可读

- [ ] **Step 4: Commit final polish if any verification-driven fixes were needed**

```bash
git add lib/widgets/settings/immersive_settings_scaffold.dart \
  lib/pages/settings_page.dart \
  lib/pages/model_management_page.dart \
  lib/pages/provider_form_page.dart \
  test/widgets/settings/immersive_settings_scaffold_test.dart \
  test/pages/settings_page_test.dart \
  test/pages/model_management_page_test.dart \
  test/pages/provider_form_page_test.dart
git commit -m "test: verify settings immersive chrome rollout"
```

## Self-Review

### Spec coverage

- Shared settings-domain scaffold: covered by Task 1
- Level-1, level-2, level-3 page migration: covered by Tasks 2-4
- Removal of repeated page-local header builders: covered by Tasks 2-4
- Fixed floating title with body scrolling beneath: covered by Tasks 1-5
- Keep rollout scoped to top chrome only: enforced by Global Constraints and task scopes

### Placeholder scan

- No `TODO`, `TBD`, or “similar to previous task” placeholders remain.
- Every code-changing task contains concrete file paths, code snippets, and commands.

### Type consistency

- `ImmersiveSettingsScaffold` and `SettingsHeaderStyle` are defined once in Task 1 and referenced consistently in Tasks 2-4.
- Shared keys `settings-top-overlay-veil` and `settings-floating-header` are introduced in Task 1 and reused consistently in page tests.

## Execution Handoff

Plan complete and saved to `docs/superpowers/plans/2026-06-24-settings-immersive-top-chrome-implementation-plan.md`. Two execution options:

**1. Subagent-Driven (recommended)** - I dispatch a fresh subagent per task, review between tasks, fast iteration

**2. Inline Execution** - Execute tasks in this session using executing-plans, batch execution with checkpoints

Which approach?
