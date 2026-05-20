# Multi-Theme System & Claude Theme Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a multi-theme system (AppThemeSpec + ThemeController) with Claude as the first built-in theme; migrate typography from builders to named roles; unify Markdown reader theming; convert Assistant blocks from bubble to document-stream; and corral the highest-frequency hardcoded color/size literals.

**Architecture:** Introduce a `AppThemeSpec` abstract class with 9 dimensions (surfaces, accents, text tones, borders, typography, spacing, radius, motion, reader sub-theme). The legacy `AppColors` ThemeExtension stays as a compatibility layer that derives all 13 fields from the active spec, so the ~50 existing call sites need no edits. A new `AppThemeController` (Riverpod) holds the active spec, persists the user choice via `SharedPreferences`, and is wired into `MaterialApp` from `main.dart`. Claude theme is implemented as `ClaudeTheme` under `lib/theme/themes/`. The Settings page gains an "Appearance" section that lists installed themes with a selected indicator. Assistant chat blocks drop their surface container and adopt the reader typography role; user bubble keeps current shape but pulls colors from the new tokens.

**Tech Stack:** Flutter (Material 3), Riverpod, `SharedPreferences`, `flutter_test`. Charter serif font shipped as an asset to assure render fidelity across platforms.

**Spec:** `docs/superpowers/specs/2026-05-19-multi-theme-system-and-claude-theme-design.md`

---

## File Structure

**Create:**
- `lib/theme/tokens/surface_palette.dart` — Dimension 1 (immutable value class)
- `lib/theme/tokens/workflow_accents.dart` — Dimension 2
- `lib/theme/tokens/text_tones.dart` — Dimension 3
- `lib/theme/tokens/borders.dart` — Dimension 4
- `lib/theme/tokens/app_typography_spec.dart` — Dimension 5 (named roles)
- `lib/theme/tokens/reader_sub_theme.dart` — Dimension 9
- `lib/theme/app_theme_spec.dart` — Abstract base bundling all 9 dimensions
- `lib/theme/themes/claude_theme.dart` — First concrete theme
- `lib/theme/themes/theme_registry.dart` — Static list of installed themes
- `lib/theme/app_theme_controller.dart` — Riverpod state + persistence
- `lib/widgets/settings/settings_appearance_section.dart` — Appearance UI
- `assets/fonts/Charter-Regular.ttf` / `Charter-Italic.ttf` / `Charter-Bold.ttf` / `Charter-BoldItalic.ttf` — Bundled font assets (downloaded by hand per Task 0)
- `test/theme/app_theme_spec_test.dart`
- `test/theme/claude_theme_test.dart`
- `test/theme/app_theme_controller_test.dart`
- `test/widgets/settings/settings_appearance_section_test.dart`
- `test/widgets/chat_blocks/assistant_doc_block_document_flow_test.dart`

**Modify:**
- `lib/theme/app_colors.dart` — Add `.fromSpec()` factory; keep existing fields
- `lib/theme/app_typography.dart` — Builders now resolve font family from active spec
- `lib/theme/app_radius.dart` — Add `xs`, `card` alias
- `lib/theme/app_motion.dart` — Add `streamingPulse`, `confirmationSnap` semantic getters
- `lib/theme/app_component_theme.dart` — Read border color from `Borders.strongBorder` not `workflowRunning`
- `lib/theme/app_theme.dart` — Add `.fromSpec(spec)` factory; keep `.light()` thin wrapper
- `lib/main.dart` — Wire `AppThemeController`, override providers, drive `MaterialApp.theme` from controller
- `lib/widgets/markdown/flutter_markdown_reader_tokens.dart` — Source styles from `ReaderSubTheme`
- `lib/widgets/markdown/markdown_widget_impl.dart` — Drop all hardcoded `fontSize`/`height`; consume `ReaderSubTheme`
- `lib/widgets/markdown/code_widget.dart` — Surface + colors from spec
- `lib/widgets/chat_input.dart` — Strip hardcoded colors → tokens
- `lib/widgets/chat_drawer.dart` — Strip hardcoded colors → tokens
- `lib/widgets/interaction/ask_user_question_card.dart` — Strip hardcoded colors + font sizes → tokens
- `lib/widgets/tool_renderers/tool_running_effects.dart` — Pull shimmer/glow from `accents` + `motion`
- `lib/widgets/debug/debug_test_case_sheet.dart` — Strip hardcoded font sizes + radii
- `lib/widgets/chat_blocks/user_anchor_bubble.dart` — Switch to `bodyChat` typography role
- `lib/widgets/chat_blocks/assistant_doc_block.dart` — Document-flow rendering (no surface, meta header)
- `lib/widgets/chat_blocks/streaming_response_block.dart` — Same document-flow rules
- `lib/widgets/chat_blocks/final_response_block.dart` — Same document-flow rules
- `lib/widgets/chat_blocks/tool_workflow_card.dart` — Status line + `cardSurface`
- `lib/widgets/chat_blocks/tool_outcome_card.dart` — Status line + `cardSurface`
- `lib/widgets/chat_blocks/tool_exception_card.dart` — Status line + `cardSurface`, danger accent
- `lib/pages/settings_page.dart` — Insert `SettingsAppearanceSection`
- `pubspec.yaml` — Register Charter font family
- `test/theme/app_theme_test.dart` — Update legacy expectations to Claude defaults

**No-op:** `lib/theme/app_spacing.dart` (sufficient as-is)

---

## Task 0: Bundle Charter font assets

**Files:**
- Create: `assets/fonts/Charter-Regular.ttf`
- Create: `assets/fonts/Charter-Italic.ttf`
- Create: `assets/fonts/Charter-Bold.ttf`
- Create: `assets/fonts/Charter-BoldItalic.ttf`
- Modify: `pubspec.yaml`

This task is **manual** — the implementer must download Charter (Bitstream Charter is free) or commit a similarly-licensed serif (e.g. `Charis SIL`, `Source Serif 4`). If substituting, replace every occurrence of `Charter` in later tasks with the chosen family name.

- [ ] **Step 1: Place font files**

Place the four `.ttf` files under `assets/fonts/`. Verify with `ls assets/fonts/Charter-*.ttf` → 4 lines.

- [ ] **Step 2: Register family in `pubspec.yaml`**

Under the existing `flutter:` → `fonts:` list, add:

```yaml
    - family: Charter
      fonts:
        - asset: assets/fonts/Charter-Regular.ttf
        - asset: assets/fonts/Charter-Italic.ttf
          style: italic
        - asset: assets/fonts/Charter-Bold.ttf
          weight: 700
        - asset: assets/fonts/Charter-BoldItalic.ttf
          weight: 700
          style: italic
```

- [ ] **Step 3: Refresh deps**

Run: `flutter pub get`
Expected: `Got dependencies!`

- [ ] **Step 4: Commit**

```bash
git add assets/fonts/Charter-*.ttf pubspec.yaml pubspec.lock
git commit -m "chore(fonts): bundle Charter for document reading surface"
```

---

## Task 1: Surface palette token

**Files:**
- Create: `lib/theme/tokens/surface_palette.dart`

- [ ] **Step 1: Write the file**

```dart
import 'package:flutter/material.dart';

/// Surface palette — one of the 9 theme dimensions.
///
/// Carries every fill color the product uses. Themes implement this by
/// returning a const instance from their factory.
@immutable
class SurfacePalette {
  final Color chatBackground;
  final Color contentSurface;
  final Color cardSurface;
  final Color userBubbleSurface;
  final Color settingsPanelBackground;
  final Color assistantSurface;
  final Color toolWorkflowSurface;
  final Color structuredSurface;
  final Color toolOutcomeSurface;
  final Color toolExceptionSurface;
  final Color artifactSurface;
  final Color calloutNoteSurface;
  final Color calloutWarnSurface;
  final Color codeBlockSurface;
  final Color accent;

  const SurfacePalette({
    required this.chatBackground,
    required this.contentSurface,
    required this.cardSurface,
    required this.userBubbleSurface,
    required this.settingsPanelBackground,
    required this.assistantSurface,
    required this.toolWorkflowSurface,
    required this.structuredSurface,
    required this.toolOutcomeSurface,
    required this.toolExceptionSurface,
    required this.artifactSurface,
    required this.calloutNoteSurface,
    required this.calloutWarnSurface,
    required this.codeBlockSurface,
    required this.accent,
  });
}
```

- [ ] **Step 2: Run analyzer**

Run: `flutter analyze lib/theme/tokens/surface_palette.dart`
Expected: `No issues found!`

- [ ] **Step 3: Commit**

```bash
git add lib/theme/tokens/surface_palette.dart
git commit -m "feat(theme): add SurfacePalette token"
```

---

## Task 2: Workflow accents, text tones, borders tokens

**Files:**
- Create: `lib/theme/tokens/workflow_accents.dart`
- Create: `lib/theme/tokens/text_tones.dart`
- Create: `lib/theme/tokens/borders.dart`

- [ ] **Step 1: Create `workflow_accents.dart`**

```dart
import 'package:flutter/material.dart';

/// Workflow accent triad + destructive accent.
@immutable
class WorkflowAccents {
  final Color running;
  final Color success;
  final Color warning;
  final Color danger;

  const WorkflowAccents({
    required this.running,
    required this.success,
    required this.warning,
    required this.danger,
  });
}
```

- [ ] **Step 2: Create `text_tones.dart`**

```dart
import 'package:flutter/material.dart';

/// Text color tones.
@immutable
class TextTones {
  final Color primary;
  final Color secondary;
  final Color muted;
  final Color onAccent;

  const TextTones({
    required this.primary,
    required this.secondary,
    required this.muted,
    required this.onAccent,
  });
}
```

- [ ] **Step 3: Create `borders.dart`**

```dart
import 'package:flutter/material.dart';

/// Borders / divider tones.
@immutable
class Borders {
  final Color divider;
  final Color strongBorder;

  const Borders({
    required this.divider,
    required this.strongBorder,
  });
}
```

- [ ] **Step 4: Run analyzer**

Run: `flutter analyze lib/theme/tokens/`
Expected: `No issues found!`

- [ ] **Step 5: Commit**

```bash
git add lib/theme/tokens/workflow_accents.dart lib/theme/tokens/text_tones.dart lib/theme/tokens/borders.dart
git commit -m "feat(theme): add accents/text-tones/borders tokens"
```

---

## Task 3: Typography spec with named roles

**Files:**
- Create: `lib/theme/tokens/app_typography_spec.dart`

- [ ] **Step 1: Write the spec class**

```dart
import 'package:flutter/material.dart';

/// Named typography roles + font family triple.
///
/// Replaces the freeform `AppTypography.uiStyle(...)` builders by exposing
/// concrete TextStyles. Call sites should consume these roles directly when
/// possible; the legacy builders remain for one-off adjustments.
@immutable
class AppTypographySpec {
  final String uiFontFamily;
  final String documentFontFamily;
  final String codeFontFamily;
  final List<String> documentFontFallback;

  final TextStyle bodyChat;
  final TextStyle bodyReader;
  final TextStyle caption;
  final TextStyle metaLabel;
  final TextStyle h1;
  final TextStyle h2;
  final TextStyle h3;
  final TextStyle codeInline;
  final TextStyle codeBlock;

  const AppTypographySpec({
    required this.uiFontFamily,
    required this.documentFontFamily,
    required this.codeFontFamily,
    required this.documentFontFallback,
    required this.bodyChat,
    required this.bodyReader,
    required this.caption,
    required this.metaLabel,
    required this.h1,
    required this.h2,
    required this.h3,
    required this.codeInline,
    required this.codeBlock,
  });
}
```

- [ ] **Step 2: Run analyzer**

Run: `flutter analyze lib/theme/tokens/app_typography_spec.dart`
Expected: `No issues found!`

- [ ] **Step 3: Commit**

```bash
git add lib/theme/tokens/app_typography_spec.dart
git commit -m "feat(theme): add AppTypographySpec named roles"
```

---

## Task 4: Reader sub-theme token

**Files:**
- Create: `lib/theme/tokens/reader_sub_theme.dart`

- [ ] **Step 1: Write the file**

```dart
import 'package:flutter/material.dart';

/// Markdown reader styles shared by both renderer impls.
@immutable
class ReaderSubTheme {
  final TextStyle body;
  final TextStyle secondaryBody;
  final TextStyle h1;
  final TextStyle h2;
  final TextStyle h3;
  final Color quoteBackground;
  final Color quoteBorder;
  final Color codeBlockSurface;
  final Color calloutNoteSurface;
  final Color calloutNoteBorder;
  final Color calloutWarnSurface;
  final Color calloutWarnBorder;
  final Color mathAccent;

  const ReaderSubTheme({
    required this.body,
    required this.secondaryBody,
    required this.h1,
    required this.h2,
    required this.h3,
    required this.quoteBackground,
    required this.quoteBorder,
    required this.codeBlockSurface,
    required this.calloutNoteSurface,
    required this.calloutNoteBorder,
    required this.calloutWarnSurface,
    required this.calloutWarnBorder,
    required this.mathAccent,
  });
}
```

- [ ] **Step 2: Run analyzer**

Run: `flutter analyze lib/theme/tokens/reader_sub_theme.dart`
Expected: `No issues found!`

- [ ] **Step 3: Commit**

```bash
git add lib/theme/tokens/reader_sub_theme.dart
git commit -m "feat(theme): add ReaderSubTheme token"
```

---

## Task 5: Extend AppRadius with `xs` and `card` alias

**Files:**
- Modify: `lib/theme/app_radius.dart`

- [ ] **Step 1: Add `xs` and `card` getters**

Replace the entire class body with:

```dart
import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';

@immutable
class AppRadius extends ThemeExtension<AppRadius> {
  final double xs;
  final double sm;
  final double md;
  final double lg;
  final double pill;

  double get card => md;

  const AppRadius({
    required this.xs,
    required this.sm,
    required this.md,
    required this.lg,
    required this.pill,
  });

  factory AppRadius.base() {
    return const AppRadius(
      xs: 6,
      sm: 10,
      md: 12,
      lg: 16,
      pill: 999,
    );
  }

  @override
  ThemeExtension<AppRadius> copyWith({
    double? xs,
    double? sm,
    double? md,
    double? lg,
    double? pill,
  }) {
    return AppRadius(
      xs: xs ?? this.xs,
      sm: sm ?? this.sm,
      md: md ?? this.md,
      lg: lg ?? this.lg,
      pill: pill ?? this.pill,
    );
  }

  @override
  ThemeExtension<AppRadius> lerp(
    covariant ThemeExtension<AppRadius>? other,
    double t,
  ) {
    if (other is! AppRadius) return this;
    return AppRadius(
      xs: lerpDouble(xs, other.xs, t)!,
      sm: lerpDouble(sm, other.sm, t)!,
      md: lerpDouble(md, other.md, t)!,
      lg: lerpDouble(lg, other.lg, t)!,
      pill: lerpDouble(pill, other.pill, t)!,
    );
  }
}
```

- [ ] **Step 2: Run analyzer**

Run: `flutter analyze lib/theme/app_radius.dart`
Expected: `No issues found!`

- [ ] **Step 3: Commit**

```bash
git add lib/theme/app_radius.dart
git commit -m "feat(theme): add radius.xs and radius.card alias"
```

---

## Task 6: AppMotion semantic aliases

**Files:**
- Modify: `lib/theme/app_motion.dart`

- [ ] **Step 1: Add semantic getters near top of class (after existing fields, before constructor)**

Locate the line `const AppMotion({` in `lib/theme/app_motion.dart`. Immediately above it (after the last `final Curve gentleCurve;` line) insert:

```dart
  // Semantic aliases — give frequently-reused combinations a name so widgets
  // stop hand-rolling their own constants (see tool_running_effects.dart).
  Duration get streamingPulse => pulse;
  Curve get streamingPulseCurve => breathing;
  Duration get confirmationSnap => quick;
  Curve get confirmationSnapCurve => easeOut;

```

- [ ] **Step 2: Run analyzer**

Run: `flutter analyze lib/theme/app_motion.dart`
Expected: `No issues found!`

- [ ] **Step 3: Commit**

```bash
git add lib/theme/app_motion.dart
git commit -m "feat(theme): add motion semantic aliases (streamingPulse, confirmationSnap)"
```

---

## Task 7: AppThemeSpec abstract base

**Files:**
- Create: `lib/theme/app_theme_spec.dart`

- [ ] **Step 1: Write the abstract class**

```dart
import 'package:flutter/foundation.dart';

import 'app_motion.dart';
import 'app_radius.dart';
import 'app_spacing.dart';
import 'tokens/app_typography_spec.dart';
import 'tokens/borders.dart';
import 'tokens/reader_sub_theme.dart';
import 'tokens/surface_palette.dart';
import 'tokens/text_tones.dart';
import 'tokens/workflow_accents.dart';

/// A complete visual theme — covers all 9 dimensions.
///
/// Concrete themes (e.g. ClaudeTheme) extend this and return their token
/// bundle. The active spec drives both `AppColors.fromSpec(...)` (legacy
/// compatibility) and direct token consumers (new code).
@immutable
abstract class AppThemeSpec {
  const AppThemeSpec();

  String get id;
  String get displayName;

  SurfacePalette get surfaces;
  WorkflowAccents get accents;
  TextTones get text;
  Borders get borders;
  AppTypographySpec get typography;
  AppSpacing get spacing;
  AppRadius get radius;
  AppMotion get motion;
  ReaderSubTheme get reader;
}
```

- [ ] **Step 2: Run analyzer**

Run: `flutter analyze lib/theme/app_theme_spec.dart`
Expected: `No issues found!`

- [ ] **Step 3: Commit**

```bash
git add lib/theme/app_theme_spec.dart
git commit -m "feat(theme): add AppThemeSpec abstract base"
```

---

## Task 8: AppColors compatibility layer — `.fromSpec()`

**Files:**
- Modify: `lib/theme/app_colors.dart`
- Create: `test/theme/app_colors_from_spec_test.dart`

- [ ] **Step 1: Write failing test**

```dart
import 'package:ai_chat/theme/app_colors.dart';
import 'package:ai_chat/theme/themes/claude_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('AppColors.fromSpec derives all legacy fields from ClaudeTheme', () {
    const spec = ClaudeTheme();
    final colors = AppColors.fromSpec(spec);

    expect(colors.chatBackground, const Color(0xFFF5F4EE));
    expect(colors.assistantSurface, const Color(0xFFFAF9F5));
    expect(colors.userBubbleSurface, const Color(0xFFEDEAE0));
    expect(colors.primaryText, const Color(0xFF1F1F1E));
    expect(colors.secondaryText, const Color(0xFF3D3D3A));
    expect(colors.divider, const Color(0xFFE8E6DC));
    expect(colors.workflowRunning, const Color(0xFF9A6C37));
    expect(colors.workflowSuccess, const Color(0xFF2F6A4F));
    expect(colors.workflowWarning, const Color(0xFFB45309));
  });
}
```

- [ ] **Step 2: Run test — expect FAIL because ClaudeTheme doesn't exist yet**

Run: `flutter test test/theme/app_colors_from_spec_test.dart`
Expected: compilation error on `import 'package:ai_chat/theme/themes/claude_theme.dart';`

(Keep this failing test in place — Task 9 will satisfy the import; this task only adds the `.fromSpec` factory.)

- [ ] **Step 3: Add `.fromSpec` to `AppColors`**

Inside `lib/theme/app_colors.dart`, **after** the existing `factory AppColors.dark() { ... }` block and before `@override`, insert:

```dart
  factory AppColors.fromSpec(AppThemeSpec spec) {
    return AppColors(
      chatBackground: spec.surfaces.chatBackground,
      settingsPanelBackground: spec.surfaces.settingsPanelBackground,
      assistantSurface: spec.surfaces.assistantSurface,
      userBubbleSurface: spec.surfaces.userBubbleSurface,
      toolWorkflowSurface: spec.surfaces.toolWorkflowSurface,
      structuredSurface: spec.surfaces.structuredSurface,
      toolOutcomeSurface: spec.surfaces.toolOutcomeSurface,
      toolExceptionSurface: spec.surfaces.toolExceptionSurface,
      primaryText: spec.text.primary,
      secondaryText: spec.text.secondary,
      divider: spec.borders.divider,
      workflowRunning: spec.accents.running,
      workflowSuccess: spec.accents.success,
      workflowWarning: spec.accents.warning,
    );
  }
```

Also add at the top of the file (next to the other imports):

```dart
import 'app_theme_spec.dart';
```

- [ ] **Step 4: Run analyzer**

Run: `flutter analyze lib/theme/app_colors.dart`
Expected: `No issues found!` (the test file will still fail; that's fine until Task 9.)

- [ ] **Step 5: Commit**

```bash
git add lib/theme/app_colors.dart test/theme/app_colors_from_spec_test.dart
git commit -m "feat(theme): add AppColors.fromSpec compatibility factory"
```

---

## Task 9: ClaudeTheme — first concrete theme

**Files:**
- Create: `lib/theme/themes/claude_theme.dart`

- [ ] **Step 1: Write `ClaudeTheme`**

```dart
import 'package:flutter/material.dart';

import '../app_motion.dart';
import '../app_radius.dart';
import '../app_spacing.dart';
import '../app_theme_spec.dart';
import '../tokens/app_typography_spec.dart';
import '../tokens/borders.dart';
import '../tokens/reader_sub_theme.dart';
import '../tokens/surface_palette.dart';
import '../tokens/text_tones.dart';
import '../tokens/workflow_accents.dart';

const _documentFontFallback = <String>[
  'NotoSansCJKSC',
  'Noto Sans SC',
  'PingFang SC',
  'HarmonyOS Sans SC',
  'Hiragino Sans GB',
  'Microsoft YaHei',
  'Noto Sans CJK SC',
  'sans-serif',
];

class ClaudeTheme extends AppThemeSpec {
  const ClaudeTheme();

  @override
  String get id => 'claude';

  @override
  String get displayName => 'Claude';

  @override
  SurfacePalette get surfaces => const SurfacePalette(
        chatBackground: Color(0xFFF5F4EE),
        contentSurface: Color(0xFFFAF9F5),
        cardSurface: Color(0xFFFFFFFF),
        userBubbleSurface: Color(0xFFEDEAE0),
        settingsPanelBackground: Color(0xFFF0EEE6),
        assistantSurface: Color(0xFFFAF9F5),
        toolWorkflowSurface: Color(0xFFF5F2EA),
        structuredSurface: Color(0xFFFAF9F5),
        toolOutcomeSurface: Color(0xFFF2F1EB),
        toolExceptionSurface: Color(0xFFFBF1E8),
        artifactSurface: Color(0xFFFFFFFF),
        calloutNoteSurface: Color(0xFFF5F2EA),
        calloutWarnSurface: Color(0xFFFBF1E8),
        codeBlockSurface: Color(0xFFF5F4EE),
        accent: Color(0xFFC96442),
      );

  @override
  WorkflowAccents get accents => const WorkflowAccents(
        running: Color(0xFF9A6C37),
        success: Color(0xFF2F6A4F),
        warning: Color(0xFFB45309),
        danger: Color(0xFFBE2222),
      );

  @override
  TextTones get text => const TextTones(
        primary: Color(0xFF1F1F1E),
        secondary: Color(0xFF3D3D3A),
        muted: Color(0xFF75726A),
        onAccent: Color(0xFFFFFFFF),
      );

  @override
  Borders get borders => const Borders(
        divider: Color(0xFFE8E6DC),
        strongBorder: Color(0xFFD9D6CC),
      );

  @override
  AppTypographySpec get typography => AppTypographySpec(
        uiFontFamily: 'AnthropicSans',
        documentFontFamily: 'Charter',
        codeFontFamily: 'JetBrainsMono',
        documentFontFallback: _documentFontFallback,
        bodyChat: const TextStyle(
          fontFamily: 'AnthropicSans',
          fontFamilyFallback: _documentFontFallback,
          fontSize: 14,
          height: 1.6,
          color: Color(0xFF1F1F1E),
        ),
        bodyReader: const TextStyle(
          fontFamily: 'Charter',
          fontFamilyFallback: _documentFontFallback,
          fontSize: 15.5,
          height: 1.72,
          color: Color(0xFF1F1F1E),
        ),
        caption: const TextStyle(
          fontFamily: 'AnthropicSans',
          fontFamilyFallback: _documentFontFallback,
          fontSize: 12,
          height: 1.5,
          color: Color(0xFF3D3D3A),
        ),
        metaLabel: const TextStyle(
          fontFamily: 'AnthropicSans',
          fontFamilyFallback: _documentFontFallback,
          fontSize: 11,
          height: 1.4,
          letterSpacing: 0.88, // 0.08em at 11px
          color: Color(0xFF75726A),
        ),
        h1: const TextStyle(
          fontFamily: 'Charter',
          fontFamilyFallback: _documentFontFallback,
          fontSize: 19,
          height: 1.32,
          fontWeight: FontWeight.w600,
          color: Color(0xFF1F1F1E),
        ),
        h2: const TextStyle(
          fontFamily: 'Charter',
          fontFamilyFallback: _documentFontFallback,
          fontSize: 17,
          height: 1.36,
          fontWeight: FontWeight.w600,
          color: Color(0xFF1F1F1E),
        ),
        h3: const TextStyle(
          fontFamily: 'Charter',
          fontFamilyFallback: _documentFontFallback,
          fontSize: 15.5,
          height: 1.4,
          fontWeight: FontWeight.w600,
          color: Color(0xFF1F1F1E),
        ),
        codeInline: const TextStyle(
          fontFamily: 'JetBrainsMono',
          fontSize: 12.5,
          height: 1.18,
          color: Color(0xFF1F1F1E),
        ),
        codeBlock: const TextStyle(
          fontFamily: 'JetBrainsMono',
          fontSize: 12.5,
          height: 1.45,
          color: Color(0xFF1F1F1E),
        ),
      );

  @override
  AppSpacing get spacing => AppSpacing.base();

  @override
  AppRadius get radius => AppRadius.base();

  @override
  AppMotion get motion => AppMotion.base();

  @override
  ReaderSubTheme get reader => ReaderSubTheme(
        body: typography.bodyReader,
        secondaryBody: typography.bodyReader.copyWith(
          fontSize: 15,
          height: 1.7,
          color: const Color(0xFF3D3D3A),
        ),
        h1: typography.h1,
        h2: typography.h2,
        h3: typography.h3,
        quoteBackground: const Color(0xFFF5F2EA),
        quoteBorder: const Color(0xFFC96442).withValues(alpha: 0.3),
        codeBlockSurface: surfaces.codeBlockSurface,
        calloutNoteSurface: surfaces.calloutNoteSurface,
        calloutNoteBorder: borders.divider,
        calloutWarnSurface: surfaces.calloutWarnSurface,
        calloutWarnBorder: const Color(0xFFFED7AA),
        mathAccent: surfaces.accent,
      );
}
```

- [ ] **Step 2: Write a focused theme test**

Create `test/theme/claude_theme_test.dart`:

```dart
import 'package:ai_chat/theme/themes/claude_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ClaudeTheme', () {
    const theme = ClaudeTheme();

    test('id and displayName', () {
      expect(theme.id, 'claude');
      expect(theme.displayName, 'Claude');
    });

    test('Claude warm-neutral surface anchors', () {
      expect(theme.surfaces.chatBackground, const Color(0xFFF5F4EE));
      expect(theme.surfaces.contentSurface, const Color(0xFFFAF9F5));
      expect(theme.surfaces.userBubbleSurface, const Color(0xFFEDEAE0));
      expect(theme.surfaces.accent, const Color(0xFFC96442));
    });

    test('typography roles use Charter for reader body', () {
      expect(theme.typography.bodyReader.fontFamily, 'Charter');
      expect(theme.typography.bodyReader.fontSize, 15.5);
      expect(theme.typography.bodyReader.height, 1.72);
    });

    test('reader sub-theme is wired from surfaces and accents', () {
      expect(theme.reader.body.fontSize, 15.5);
      expect(theme.reader.codeBlockSurface, theme.surfaces.codeBlockSurface);
      expect(theme.reader.mathAccent, theme.surfaces.accent);
    });
  });
}
```

- [ ] **Step 3: Run tests — both `claude_theme_test` and `app_colors_from_spec_test` from Task 8 should now pass**

Run: `flutter test test/theme/claude_theme_test.dart test/theme/app_colors_from_spec_test.dart`
Expected: All pass.

- [ ] **Step 4: Commit**

```bash
git add lib/theme/themes/claude_theme.dart test/theme/claude_theme_test.dart
git commit -m "feat(theme): implement ClaudeTheme as first AppThemeSpec"
```

---

## Task 10: Theme registry

**Files:**
- Create: `lib/theme/themes/theme_registry.dart`

- [ ] **Step 1: Write the registry**

```dart
import '../app_theme_spec.dart';
import 'claude_theme.dart';

/// Installed themes, in display order. ClaudeTheme is the default.
class ThemeRegistry {
  static const List<AppThemeSpec> installed = <AppThemeSpec>[
    ClaudeTheme(),
  ];

  static AppThemeSpec get defaultTheme => installed.first;

  static AppThemeSpec? findById(String id) {
    for (final theme in installed) {
      if (theme.id == id) return theme;
    }
    return null;
  }
}
```

- [ ] **Step 2: Run analyzer**

Run: `flutter analyze lib/theme/themes/theme_registry.dart`
Expected: `No issues found!`

- [ ] **Step 3: Commit**

```bash
git add lib/theme/themes/theme_registry.dart
git commit -m "feat(theme): add ThemeRegistry"
```

---

## Task 11: AppTheme.fromSpec — drive ThemeData from spec

**Files:**
- Modify: `lib/theme/app_theme.dart`
- Modify: `lib/theme/app_component_theme.dart`
- Modify: `test/theme/app_theme_test.dart`

- [ ] **Step 1: Update the legacy theme test to reflect Claude defaults**

Replace `test/theme/app_theme_test.dart` with:

```dart
import 'package:ai_chat/theme/app_colors.dart';
import 'package:ai_chat/theme/app_radius.dart';
import 'package:ai_chat/theme/app_spacing.dart';
import 'package:ai_chat/theme/app_theme.dart';
import 'package:ai_chat/theme/themes/claude_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('fromSpec exposes semantic extensions', () {
    final theme = AppTheme.fromSpec(const ClaudeTheme());

    expect(theme.extension<AppColors>(), isNotNull);
    expect(theme.extension<AppSpacing>(), isNotNull);
    expect(theme.extension<AppRadius>(), isNotNull);
  });

  test('fromSpec(ClaudeTheme) uses warm neutral surfaces', () {
    final theme = AppTheme.fromSpec(const ClaudeTheme());
    final colors = theme.extension<AppColors>()!;

    expect(theme.colorScheme.brightness, Brightness.light);
    expect(theme.scaffoldBackgroundColor, const Color(0xFFF5F4EE));
    expect(colors.chatBackground, const Color(0xFFF5F4EE));
    expect(colors.userBubbleSurface, const Color(0xFFEDEAE0));
    expect(colors.workflowRunning, const Color(0xFF9A6C37));
  });
}
```

- [ ] **Step 2: Run the test — expect FAIL (no `AppTheme.fromSpec` yet)**

Run: `flutter test test/theme/app_theme_test.dart`
Expected: compilation error on `AppTheme.fromSpec`.

- [ ] **Step 3: Update `app_component_theme.dart` to take strong-border color**

Replace `lib/theme/app_component_theme.dart` with:

```dart
import 'package:flutter/material.dart';

import 'app_colors.dart';
import 'app_radius.dart';
import 'app_spacing.dart';

class AppComponentTheme {
  static InputDecorationTheme inputDecorationTheme(
    AppColors colors,
    AppRadius radius,
    AppSpacing spacing, {
    required Color strongBorder,
  }) {
    return InputDecorationTheme(
      filled: true,
      fillColor: colors.assistantSurface,
      contentPadding: EdgeInsets.symmetric(
        horizontal: spacing.md,
        vertical: spacing.sm,
      ),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(radius.lg),
        borderSide: BorderSide(color: colors.divider),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(radius.lg),
        borderSide: BorderSide(color: colors.divider),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(radius.lg),
        borderSide: BorderSide(color: strongBorder, width: 1.2),
      ),
    );
  }

  static CardThemeData cardTheme(AppColors colors, AppRadius radius) {
    return CardThemeData(
      color: colors.assistantSurface,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(radius.md),
        side: BorderSide(color: colors.divider),
      ),
    );
  }
}
```

- [ ] **Step 4: Rewrite `app_theme.dart` to drive ThemeData from a spec**

Replace with:

```dart
import 'package:flutter/material.dart';

import 'app_colors.dart';
import 'app_component_theme.dart';
import 'app_theme_spec.dart';
import 'themes/claude_theme.dart';

class AppTheme {
  static ThemeData fromSpec(AppThemeSpec spec) {
    final colors = AppColors.fromSpec(spec);
    final colorScheme = ColorScheme.light().copyWith(
      primary: spec.accents.running,
      secondary: spec.accents.success,
      surface: spec.surfaces.contentSurface,
      onSurface: spec.text.primary,
      onPrimary: spec.text.onAccent,
      onSecondary: spec.text.onAccent,
      outlineVariant: spec.borders.divider,
    );

    return ThemeData(
      useMaterial3: true,
      fontFamily: spec.typography.uiFontFamily,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: spec.surfaces.chatBackground,
      textTheme: Typography.blackMountainView.apply(
        bodyColor: spec.text.primary,
        displayColor: spec.text.primary,
      ),
      canvasColor: spec.surfaces.settingsPanelBackground,
      splashFactory: NoSplash.splashFactory,
      highlightColor: Colors.transparent,
      hoverColor: Colors.transparent,
      inputDecorationTheme: AppComponentTheme.inputDecorationTheme(
        colors,
        spec.radius,
        spec.spacing,
        strongBorder: spec.borders.strongBorder,
      ),
      cardTheme: AppComponentTheme.cardTheme(colors, spec.radius),
      dividerColor: spec.borders.divider,
      iconTheme: IconThemeData(color: spec.text.primary),
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        foregroundColor: spec.text.primary,
        elevation: 0,
        scrolledUnderElevation: 0,
      ),
      extensions: <ThemeExtension<dynamic>>[
        colors,
        spec.spacing,
        spec.radius,
        spec.motion,
      ],
    );
  }

  /// Legacy entry point; kept for back-compat. Routes through Claude.
  static ThemeData light() => fromSpec(const ClaudeTheme());
}
```

- [ ] **Step 5: Run the test**

Run: `flutter test test/theme/app_theme_test.dart`
Expected: all pass.

- [ ] **Step 6: Run full test suite to detect collateral damage**

Run: `flutter test`
Expected: all green. If any test references the old olive palette (e.g. `chatBackground == #F3F1EC`), update it to Claude values inline.

- [ ] **Step 7: Commit**

```bash
git add lib/theme/app_theme.dart lib/theme/app_component_theme.dart test/theme/app_theme_test.dart
git commit -m "feat(theme): drive ThemeData from AppThemeSpec; default = Claude"
```

---

## Task 12: AppThemeController — Riverpod state + persistence

**Files:**
- Create: `lib/theme/app_theme_controller.dart`
- Create: `test/theme/app_theme_controller_test.dart`

- [ ] **Step 1: Write the test**

```dart
import 'package:ai_chat/theme/app_theme_controller.dart';
import 'package:ai_chat/theme/themes/claude_theme.dart';
import 'package:ai_chat/theme/themes/theme_registry.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('defaults to Claude on first launch', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final container = ProviderContainer(
      overrides: [
        sharedPreferencesProviderForThemeController.overrideWithValue(prefs),
      ],
    );
    addTearDown(container.dispose);

    final spec = container.read(activeThemeSpecProvider);
    expect(spec.id, const ClaudeTheme().id);
  });

  test('restores persisted choice', () async {
    SharedPreferences.setMockInitialValues({'app.theme.id': 'claude'});
    final prefs = await SharedPreferences.getInstance();
    final container = ProviderContainer(
      overrides: [
        sharedPreferencesProviderForThemeController.overrideWithValue(prefs),
      ],
    );
    addTearDown(container.dispose);

    final spec = container.read(activeThemeSpecProvider);
    expect(spec.id, 'claude');
  });

  test('setTheme writes to prefs and updates state', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final container = ProviderContainer(
      overrides: [
        sharedPreferencesProviderForThemeController.overrideWithValue(prefs),
      ],
    );
    addTearDown(container.dispose);

    final controller = container.read(appThemeControllerProvider.notifier);
    await controller.setTheme(ThemeRegistry.installed.first.id);

    expect(prefs.getString('app.theme.id'), 'claude');
    expect(container.read(activeThemeSpecProvider).id, 'claude');
  });
}
```

- [ ] **Step 2: Run test — expect FAIL on missing imports**

Run: `flutter test test/theme/app_theme_controller_test.dart`
Expected: compilation error.

- [ ] **Step 3: Implement the controller**

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app_theme_spec.dart';
import 'themes/theme_registry.dart';

const _kPrefsKey = 'app.theme.id';

/// Lives in this file rather than chat_dependency_providers.dart so the theme
/// layer remains independent of the chat domain.
final sharedPreferencesProviderForThemeController =
    Provider<SharedPreferences>((ref) {
  throw UnimplementedError(
    'override sharedPreferencesProviderForThemeController in main.dart',
  );
});

final appThemeControllerProvider =
    StateNotifierProvider<AppThemeController, AppThemeSpec>((ref) {
  final prefs = ref.watch(sharedPreferencesProviderForThemeController);
  return AppThemeController(prefs);
});

final activeThemeSpecProvider = Provider<AppThemeSpec>((ref) {
  return ref.watch(appThemeControllerProvider);
});

class AppThemeController extends StateNotifier<AppThemeSpec> {
  AppThemeController(this._prefs) : super(_initial(_prefs));

  final SharedPreferences _prefs;

  static AppThemeSpec _initial(SharedPreferences prefs) {
    final id = prefs.getString(_kPrefsKey);
    if (id == null) return ThemeRegistry.defaultTheme;
    return ThemeRegistry.findById(id) ?? ThemeRegistry.defaultTheme;
  }

  Future<void> setTheme(String id) async {
    final next = ThemeRegistry.findById(id);
    if (next == null) return;
    state = next;
    await _prefs.setString(_kPrefsKey, id);
  }
}
```

- [ ] **Step 4: Run the test**

Run: `flutter test test/theme/app_theme_controller_test.dart`
Expected: all pass.

- [ ] **Step 5: Commit**

```bash
git add lib/theme/app_theme_controller.dart test/theme/app_theme_controller_test.dart
git commit -m "feat(theme): add AppThemeController with SharedPreferences persistence"
```

---

## Task 13: Wire MaterialApp to active theme

**Files:**
- Modify: `lib/main.dart`

- [ ] **Step 1: Override `sharedPreferencesProviderForThemeController` in main**

In `lib/main.dart`, inside the `runApp(ProviderScope(overrides: [ ... ]))` list (the `MyApp()` mount point), add the override. Locate the existing `sharedPreferencesProvider.overrideWithValue(preferences)` line and add a sibling:

```dart
sharedPreferencesProviderForThemeController.overrideWithValue(preferences),
```

Add the import at the top of `main.dart`:

```dart
import 'theme/app_theme_controller.dart';
```

If `main.dart` does not currently override `sharedPreferencesProvider`, also add that override (it is already declared in `chat_dependency_providers.dart`). Search `lib/main.dart` for `ProviderScope(` and inspect — if `sharedPreferencesProvider.overrideWithValue` is absent, add both overrides together.

- [ ] **Step 2: Drive `MaterialApp.theme` from the controller**

Replace the `MyApp` widget body with:

```dart
class MyApp extends ConsumerWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final spec = ref.watch(activeThemeSpecProvider);
    return MaterialApp(
      routes: getRouteMap(),
      initialRoute: RouteConstant.chatPage,
      title: 'AI Chat',
      theme: AppTheme.fromSpec(spec),
    );
  }

  Map<String, WidgetBuilder> getRouteMap() {
    return {
      RouteConstant.chatPage: (context) => const ChatPage(title: 'AI Chat'),
      RouteConstant.settingsPage: (context) => const SettingsPage(),
      RouteConstant.testPage: (context) => const TestPage()
    };
  }
}
```

- [ ] **Step 3: Smoke-run analyzer**

Run: `flutter analyze lib/main.dart`
Expected: `No issues found!`

- [ ] **Step 4: Run the app and verify visually**

Run: `flutter run -d <device>` (manual). Confirm chat surface is warm-neutral Claude background, not olive. Quit.

- [ ] **Step 5: Commit**

```bash
git add lib/main.dart
git commit -m "feat(theme): drive MaterialApp from AppThemeController"
```

---

## Task 14: Settings → Appearance section

**Files:**
- Create: `lib/widgets/settings/settings_appearance_section.dart`
- Create: `test/widgets/settings/settings_appearance_section_test.dart`
- Modify: `lib/pages/settings_page.dart`

- [ ] **Step 1: Write the widget test**

```dart
import 'package:ai_chat/theme/app_theme.dart';
import 'package:ai_chat/theme/app_theme_controller.dart';
import 'package:ai_chat/theme/themes/claude_theme.dart';
import 'package:ai_chat/widgets/settings/settings_appearance_section.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('renders Claude card with selected indicator', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProviderForThemeController.overrideWithValue(prefs),
        ],
        child: MaterialApp(
          theme: AppTheme.fromSpec(const ClaudeTheme()),
          home: const Scaffold(body: SettingsAppearanceSection()),
        ),
      ),
    );

    expect(find.text('Claude'), findsOneWidget);
    expect(find.byKey(const Key('theme-card-claude-selected')), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run test — expect FAIL (widget doesn't exist)**

Run: `flutter test test/widgets/settings/settings_appearance_section_test.dart`
Expected: compilation error on `import '.../settings_appearance_section.dart'`.

- [ ] **Step 3: Implement the widget**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../theme/app_radius.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_theme_controller.dart';
import '../../theme/app_theme_spec.dart';
import '../../theme/themes/theme_registry.dart';

class SettingsAppearanceSection extends ConsumerWidget {
  const SettingsAppearanceSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final active = ref.watch(activeThemeSpecProvider);
    final spacing = Theme.of(context).extension<AppSpacing>()!;

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: spacing.lg, vertical: spacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '外观',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          SizedBox(height: spacing.sm),
          Wrap(
            spacing: spacing.sm,
            runSpacing: spacing.sm,
            children: [
              for (final theme in ThemeRegistry.installed)
                _ThemeCard(
                  spec: theme,
                  selected: theme.id == active.id,
                  onTap: () => ref
                      .read(appThemeControllerProvider.notifier)
                      .setTheme(theme.id),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ThemeCard extends StatelessWidget {
  final AppThemeSpec spec;
  final bool selected;
  final VoidCallback onTap;

  const _ThemeCard({
    required this.spec,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final radius = Theme.of(context).extension<AppRadius>()!;
    final spacing = Theme.of(context).extension<AppSpacing>()!;
    return InkWell(
      key: Key('theme-card-${spec.id}${selected ? '-selected' : ''}'),
      borderRadius: BorderRadius.circular(radius.md),
      onTap: onTap,
      child: Container(
        width: 168,
        decoration: BoxDecoration(
          color: spec.surfaces.cardSurface,
          borderRadius: BorderRadius.circular(radius.md),
          border: Border.all(
            color: selected ? spec.surfaces.accent : spec.borders.divider,
            width: selected ? 2 : 1,
          ),
        ),
        padding: EdgeInsets.all(spacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              height: 64,
              decoration: BoxDecoration(
                color: spec.surfaces.contentSurface,
                borderRadius: BorderRadius.circular(radius.sm),
                border: Border.all(color: spec.borders.divider),
              ),
            ),
            SizedBox(height: spacing.sm),
            Text(
              spec.displayName,
              style: spec.typography.bodyChat
                  .copyWith(color: spec.text.primary, fontWeight: FontWeight.w500),
            ),
            if (selected)
              Padding(
                padding: EdgeInsets.only(top: spacing.xxs),
                child: Text(
                  '当前',
                  style: spec.typography.caption
                      .copyWith(color: spec.surfaces.accent),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
```

- [ ] **Step 4: Run the widget test**

Run: `flutter test test/widgets/settings/settings_appearance_section_test.dart`
Expected: pass.

- [ ] **Step 5: Mount the section in `settings_page.dart`**

Find the top of `_SettingsPageState.build`'s body `Column`/`ListView` (the first widget after `AppBar`/`Scaffold`). Insert `const SettingsAppearanceSection(),` as the first child. Also add the import:

```dart
import '../widgets/settings/settings_appearance_section.dart';
```

- [ ] **Step 6: Run the full test suite**

Run: `flutter test`
Expected: all green.

- [ ] **Step 7: Commit**

```bash
git add lib/widgets/settings/settings_appearance_section.dart lib/pages/settings_page.dart test/widgets/settings/settings_appearance_section_test.dart
git commit -m "feat(settings): add Appearance section with theme picker"
```

---

## Task 15: Reader sub-theme wiring for `flutter_markdown_reader_tokens.dart`

**Files:**
- Modify: `lib/widgets/markdown/flutter_markdown_reader_tokens.dart`

- [ ] **Step 1: Switch `build` to read from `ReaderSubTheme` via active spec**

Replace the entire file with:

```dart
import 'package:ai_chat/theme/app_theme_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class FlutterMarkdownReaderTokens {
  /// Builds the document-first styles used by completed assistant answers.
  static MarkdownReaderStyles build(BuildContext context, WidgetRef ref) {
    final reader = ref.watch(activeThemeSpecProvider).reader;
    return MarkdownReaderStyles(
      body: reader.body,
      secondaryBody: reader.secondaryBody,
      h1: reader.h1,
      h2: reader.h2,
      h3: reader.h3,
      quoteBackgroundColor: reader.quoteBackground,
      quoteBorderColor: reader.quoteBorder,
    );
  }
}

class MarkdownReaderStyles {
  final TextStyle body;
  final TextStyle secondaryBody;
  final TextStyle h1;
  final TextStyle h2;
  final TextStyle h3;
  final Color quoteBackgroundColor;
  final Color quoteBorderColor;

  const MarkdownReaderStyles({
    required this.body,
    required this.secondaryBody,
    required this.h1,
    required this.h2,
    required this.h3,
    required this.quoteBackgroundColor,
    required this.quoteBorderColor,
  });
}
```

- [ ] **Step 2: Update every call site to pass `ref`**

Run: `grep -rn "FlutterMarkdownReaderTokens.build(" lib/ --include="*.dart"`
For each hit, ensure the caller is a `ConsumerWidget` / `ConsumerStatefulWidget` (or has a `WidgetRef ref` in scope) and pass `ref`. If a caller is a non-Riverpod widget, wrap the subtree in `Consumer(builder: (context, ref, _) => ...)` at the call site.

- [ ] **Step 3: Run full test suite**

Run: `flutter test`
Expected: all green.

- [ ] **Step 4: Commit**

```bash
git add lib/widgets/markdown/flutter_markdown_reader_tokens.dart $(git diff --name-only | grep -v '^lib/widgets/markdown/flutter_markdown_reader_tokens.dart$')
git commit -m "refactor(markdown): consume ReaderSubTheme from active spec"
```

---

## Task 16: Unify `markdown_widget_impl.dart` with reader tokens

**Files:**
- Modify: `lib/widgets/markdown/markdown_widget_impl.dart`

- [ ] **Step 1: Inspect current state**

Run: `grep -nE "fontSize:|height:|Color\(0x" lib/widgets/markdown/markdown_widget_impl.dart | head -30`

Expected: ~16 lines with hardcoded sizes / heights. Identify which roles they map to (paragraph, h1-h3, list, quote, code, link).

- [ ] **Step 2: Refactor to consume `ReaderSubTheme`**

Convert the widget (if not already) to a `ConsumerWidget` and replace every hardcoded `TextStyle(fontSize: ..., height: ...)` with the corresponding role from `ref.watch(activeThemeSpecProvider).reader`:

- paragraph / body → `reader.body`
- secondary body / list marker → `reader.secondaryBody`
- h1/h2/h3 → `reader.h1/h2/h3`
- quote background / border → `reader.quoteBackground` / `reader.quoteBorder`
- code block surface → `reader.codeBlockSurface`

Where `markdown_widget_impl.dart` uses code/inline styles, prefer `ref.watch(activeThemeSpecProvider).typography.codeInline` / `codeBlock`.

- [ ] **Step 3: Run all tests + analyzer**

Run: `flutter analyze lib/widgets/markdown/markdown_widget_impl.dart && flutter test`
Expected: green.

- [ ] **Step 4: Commit**

```bash
git add lib/widgets/markdown/markdown_widget_impl.dart
git commit -m "refactor(markdown): drop hardcoded sizes; route through ReaderSubTheme"
```

---

## Task 17: Code block surface from spec

**Files:**
- Modify: `lib/widgets/markdown/code_widget.dart`

- [ ] **Step 1: Refactor `_CodeBlockWidgetState.build` and `CodeSegmentWidget.build`**

Convert both classes to `ConsumerStatefulWidget` / `ConsumerWidget`. Replace:

- `_codeCanvasColor` → `ref.watch(activeThemeSpecProvider).reader.codeBlockSurface`
- The hardcoded `Color(0xFF31414A)` / `Color(0xFFE6E6E6)` text colors → `spec.text.primary`
- The hardcoded `Color(0xFF7FBE95)` "copied" icon color → `spec.accents.success`
- `BorderRadius.circular(10)` and `BorderRadius.circular(5)` → `radius.sm` / `radius.xs`
- Font styles → `spec.typography.codeBlock` and `codeInline`

- [ ] **Step 2: Run tests + analyzer**

Run: `flutter analyze lib/widgets/markdown/code_widget.dart && flutter test`
Expected: green.

- [ ] **Step 3: Commit**

```bash
git add lib/widgets/markdown/code_widget.dart
git commit -m "refactor(markdown): drive code widget colors/radius from active spec"
```

---

## Task 18: Tool running effects from spec motion + accents

**Files:**
- Modify: `lib/widgets/tool_renderers/tool_running_effects.dart`

- [ ] **Step 1: Audit hardcoded constants**

Run: `grep -nE "Color\(0x|Duration\(|Curves\." lib/widgets/tool_renderers/tool_running_effects.dart`

Expected: 11 color literals + several duration/curve constants.

- [ ] **Step 2: Refactor**

Convert any widget in this file to a `ConsumerWidget` if needed. Replace:

- Shimmer gradient stops → derived from `spec.surfaces.toolWorkflowSurface` (base) and `spec.accents.running` (highlight), each with explicit `withValues(alpha:)` 0.08–0.24 stops
- Glow color → `spec.accents.running.withValues(alpha: 0.18)`
- Pulse duration → `motion.streamingPulse`
- Pulse curve → `motion.streamingPulseCurve`

- [ ] **Step 3: Run tests + analyzer**

Run: `flutter analyze lib/widgets/tool_renderers/tool_running_effects.dart && flutter test`
Expected: green.

- [ ] **Step 4: Commit**

```bash
git add lib/widgets/tool_renderers/tool_running_effects.dart
git commit -m "refactor(tools): drive running effects from theme motion + accents"
```

---

## Task 19: Corral chat_input, chat_drawer, ask_user_question_card, debug_test_case_sheet

**Files:**
- Modify: `lib/widgets/chat_input.dart`
- Modify: `lib/widgets/chat_drawer.dart`
- Modify: `lib/widgets/interaction/ask_user_question_card.dart`
- Modify: `lib/widgets/debug/debug_test_case_sheet.dart`

- [ ] **Step 1: For each file, list hardcoded literals**

Run:

```bash
grep -nE "Color\(0x|Colors\.[a-z]+|BorderRadius\.circular\(|fontSize:|height:" \
  lib/widgets/chat_input.dart \
  lib/widgets/chat_drawer.dart \
  lib/widgets/interaction/ask_user_question_card.dart \
  lib/widgets/debug/debug_test_case_sheet.dart
```

- [ ] **Step 2: Replace per the following rules**

For every hit:

- `Color(0xFFXXXXXX)` → nearest `spec.surfaces.*` / `spec.text.*` / `spec.accents.*` / `spec.borders.*`, accessed via `Theme.of(context).extension<AppColors>()!` if the existing call site already uses that pattern, or via `ref.watch(activeThemeSpecProvider)` if the widget is a `ConsumerWidget`
- `Colors.red` → `spec.accents.danger`
- `Colors.green` → `spec.accents.success`
- `BorderRadius.circular(N)` → nearest `AppRadius` field (≤ 8 → `xs`, 10 → `sm`, 12 → `md` / `card`, 16 → `lg`)
- `fontSize: N, height: H` → the closest matching role from `spec.typography` (body 13–14 → `bodyChat`, 15+ → `bodyReader`, 11–12 → `caption`, label uppercase → `metaLabel`)

When a one-off variant is required (e.g. `bodyChat` with bold), use `spec.typography.bodyChat.copyWith(fontWeight: FontWeight.w600)`.

- [ ] **Step 3: Run analyzer + tests**

Run: `flutter analyze lib/widgets/chat_input.dart lib/widgets/chat_drawer.dart lib/widgets/interaction/ask_user_question_card.dart lib/widgets/debug/debug_test_case_sheet.dart && flutter test`
Expected: green.

- [ ] **Step 4: Commit**

```bash
git add lib/widgets/chat_input.dart lib/widgets/chat_drawer.dart lib/widgets/interaction/ask_user_question_card.dart lib/widgets/debug/debug_test_case_sheet.dart
git commit -m "refactor: route chrome widgets through theme tokens"
```

---

## Task 20: User bubble — Claude-style low-contrast surface

**Files:**
- Modify: `lib/widgets/chat_blocks/user_anchor_bubble.dart`

- [ ] **Step 1: Replace the build method**

```dart
@override
Widget build(BuildContext context) {
  final colors = Theme.of(context).extension<AppColors>()!;
  final spacing = Theme.of(context).extension<AppSpacing>()!;
  final radius = Theme.of(context).extension<AppRadius>()!;

  final isMostlyLatin = RegExp(r'^[\x00-\x7F\s\p{P}]+$', unicode: true)
      .hasMatch(text);

  return Align(
    alignment: Alignment.centerRight,
    child: Container(
      constraints: const BoxConstraints(maxWidth: 468),
      padding: EdgeInsets.symmetric(
        horizontal: spacing.md,
        vertical: spacing.xs + 1,
      ),
      decoration: BoxDecoration(
        color: colors.userBubbleSurface,
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(radius.lg),
          topRight: Radius.circular(radius.lg),
          bottomLeft: Radius.circular(radius.lg),
          bottomRight: Radius.circular(radius.sm),
        ),
      ),
      child: Text(
        text,
        style: AppTypography.uiStyle(
          color: colors.primaryText,
          fontWeight: FontWeight.w400,
          fontSize: 14,
          height: 1.6,
          letterSpacing: isMostlyLatin ? 0.08 : null,
        ),
      ),
    ),
  );
}
```

Drop the shadow (Claude does not use it) and bump size from 13 / 1.3 → 14 / 1.6 to match `bodyChat`.

- [ ] **Step 2: Run analyzer + tests**

Run: `flutter analyze lib/widgets/chat_blocks/user_anchor_bubble.dart && flutter test`
Expected: green.

- [ ] **Step 3: Commit**

```bash
git add lib/widgets/chat_blocks/user_anchor_bubble.dart
git commit -m "feat(chat): user bubble adopts Claude low-contrast warm-neutral"
```

---

## Task 21: Assistant block — document flow, drop bubble surface

**Files:**
- Modify: `lib/widgets/chat_blocks/assistant_doc_block.dart`
- Modify: `lib/widgets/chat_blocks/streaming_response_block.dart`
- Modify: `lib/widgets/chat_blocks/final_response_block.dart`
- Create: `test/widgets/chat_blocks/assistant_doc_block_document_flow_test.dart`

- [ ] **Step 1: Write the widget test**

```dart
import 'package:ai_chat/theme/app_theme.dart';
import 'package:ai_chat/theme/themes/claude_theme.dart';
import 'package:ai_chat/widgets/chat_blocks/assistant_doc_block.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('assistant doc block does not wrap content in a surface container',
      (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: AppTheme.fromSpec(const ClaudeTheme()),
          home: const Scaffold(
            body: AssistantDocBlock(text: 'hello world'),
          ),
        ),
      ),
    );

    // No DecoratedBox with a non-transparent fill is allowed as an outer
    // wrapper of the document content — Claude-style assistant block must be
    // a bare document.
    final decoratedBoxes = find.byType(DecoratedBox);
    for (final element in decoratedBoxes.evaluate()) {
      final decoration = (element.widget as DecoratedBox).decoration as BoxDecoration;
      expect(decoration.color, anyOf(isNull, Colors.transparent),
          reason: 'AssistantDocBlock must not paint a surface');
    }
  });
}
```

- [ ] **Step 2: Run test — expect FAIL (current widget does not paint a surface but the meta header check below will catch the regression)**

Run: `flutter test test/widgets/chat_blocks/assistant_doc_block_document_flow_test.dart`
Expected: may already pass; that's acceptable. Note the result.

- [ ] **Step 3: Rewrite `assistant_doc_block.dart`**

```dart
import 'package:ai_chat/theme/app_colors.dart';
import 'package:ai_chat/theme/app_motion.dart';
import 'package:ai_chat/theme/app_spacing.dart';
import 'package:ai_chat/theme/app_theme_controller.dart';
import 'package:ai_chat/widgets/chat_blocks/reasoning_section.dart';
import 'package:ai_chat/widgets/chat_timeline/stable_markdown_block.dart';
import 'package:ai_chat/widgets/markdown/flutter_markdown_impl.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class AssistantDocBlock extends ConsumerWidget {
  final String text;
  final String? label;
  final String? reasoningText;
  final String? markdownCacheKey;

  const AssistantDocBlock({
    super.key,
    required this.text,
    this.label,
    this.reasoningText,
    this.markdownCacheKey,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = Theme.of(context).extension<AppColors>()!;
    final motion = Theme.of(context).extension<AppMotion>()!;
    final spacing = Theme.of(context).extension<AppSpacing>()!;
    final spec = ref.watch(activeThemeSpecProvider);

    return AnimatedOpacity(
      duration: motion.quick,
      curve: motion.easeOut,
      opacity: 1,
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          spacing.md - 1,
          0,
          spacing.md - 1,
          spacing.xxs,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Document-flow meta header: small avatar + name. No outer surface.
            Padding(
              padding: EdgeInsets.only(bottom: spacing.xs),
              child: Row(
                children: [
                  Container(
                    width: 22,
                    height: 22,
                    decoration: BoxDecoration(
                      color: spec.surfaces.accent,
                      shape: BoxShape.circle,
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      'C',
                      style: spec.typography.caption.copyWith(
                        color: spec.text.onAccent,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  SizedBox(width: spacing.xs),
                  Text(
                    label ?? 'Claude',
                    style: spec.typography.caption.copyWith(color: spec.text.muted),
                  ),
                ],
              ),
            ),
            if ((reasoningText ?? '').trim().isNotEmpty)
              ReasoningSection(
                text: reasoningText!,
                variant: ReasoningSectionVariant.toolUseInline,
              ),
            StableMarkdownBlock(
              cacheKey:
                  markdownCacheKey ?? 'doc:${label ?? 'analysis'}:${text.hashCode}',
              child: FlutterMarkdownImpl(data: text),
            ),
          ],
        ),
      ),
    );
  }
}
```

- [ ] **Step 4: Apply the same meta-header pattern to `streaming_response_block.dart` and `final_response_block.dart`**

For each file, open and confirm whether it currently wraps content in a `Container` / `DecoratedBox` with a fill color. If so, remove the fill (keep padding) and prepend the same Claude-avatar + 'Claude' meta row used above. If the file already delegates to `AssistantDocBlock`, no change needed.

- [ ] **Step 5: Run the assistant doc test + full suite**

Run: `flutter test test/widgets/chat_blocks/assistant_doc_block_document_flow_test.dart && flutter test`
Expected: green.

- [ ] **Step 6: Commit**

```bash
git add lib/widgets/chat_blocks/assistant_doc_block.dart lib/widgets/chat_blocks/streaming_response_block.dart lib/widgets/chat_blocks/final_response_block.dart test/widgets/chat_blocks/assistant_doc_block_document_flow_test.dart
git commit -m "feat(chat): assistant blocks adopt document flow with Claude meta header"
```

---

## Task 22: Tool cards — `cardSurface` + status line

**Files:**
- Modify: `lib/widgets/chat_blocks/tool_workflow_card.dart`
- Modify: `lib/widgets/chat_blocks/tool_outcome_card.dart`
- Modify: `lib/widgets/chat_blocks/tool_exception_card.dart`

- [ ] **Step 1: For each card, replace surface + add status line**

In each file, locate the outer `Container` / `DecoratedBox` decoration. Replace the existing `color:` with `colors.cardSurface` (Claude `#FFFFFF`), keep the existing `border` using `colors.divider`, and at the top of the inner column insert a 1.5px-tall status indicator strip:

```dart
Container(
  height: 1.5,
  color: _statusColor(colors), // workflow: running; outcome: success; exception: danger
),
SizedBox(height: spacing.xs),
```

Define `_statusColor` per file:
- `tool_workflow_card.dart` → `colors.workflowRunning`
- `tool_outcome_card.dart` → `colors.workflowSuccess`
- `tool_exception_card.dart` → fetch `spec.accents.danger` via `ref.watch(activeThemeSpecProvider)` if widget isn't ConsumerWidget, else convert it.

Note: `AppColors` does not currently expose `cardSurface`. Add a getter to `AppColors`:

```dart
Color get cardSurface => assistantSurface; // legacy fallback
```

…and in `AppColors.fromSpec`, also pass through via the existing `assistantSurface` mapping (already pointing at `spec.surfaces.contentSurface`). For the tool cards specifically, use `spec.surfaces.cardSurface` directly via `ref` (preferred) — that's the Claude pure white.

- [ ] **Step 2: Run analyzer + tests**

Run: `flutter analyze lib/widgets/chat_blocks/tool_workflow_card.dart lib/widgets/chat_blocks/tool_outcome_card.dart lib/widgets/chat_blocks/tool_exception_card.dart && flutter test`
Expected: green.

- [ ] **Step 3: Commit**

```bash
git add lib/widgets/chat_blocks/tool_workflow_card.dart lib/widgets/chat_blocks/tool_outcome_card.dart lib/widgets/chat_blocks/tool_exception_card.dart lib/theme/app_colors.dart
git commit -m "feat(tools): tool cards collapse to cardSurface + status line"
```

---

## Task 23: Final validation & manual screenshot pass

**Files:** none (manual verification)

- [ ] **Step 1: Run full test suite**

Run: `flutter test`
Expected: all green.

- [ ] **Step 2: Run analyzer over the whole project**

Run: `flutter analyze`
Expected: `No issues found!` (or only pre-existing warnings unrelated to this change).

- [ ] **Step 3: Manual visual pass**

Launch the app on a device: `flutter run`. Walk through:

1. First launch → chat surface is warm Claude beige (`#F5F4EE`), not olive.
2. Send a user message → bubble is `#EDEAE0`, no shadow, font 14 / 1.6.
3. Receive an assistant answer → no surface around content, small Claude avatar + name above paragraph, body in Charter serif 15.5 / 1.72.
4. Trigger a tool call → tool card uses white `cardSurface`, narrow top status line in running/success/danger color.
5. Open Settings → "外观" section at top, Claude card selected with accent border + "当前" label.
6. Re-tap the Claude card → no flicker; state persists.

- [ ] **Step 4: Commit any in-pass fixups**

If visual pass exposed a missed surface or font fallback, fix and commit:

```bash
git add <files>
git commit -m "fix(theme): <specific tweak>"
```

- [ ] **Step 5: Final summary commit (optional)**

If multiple in-pass fixes piled up, no final commit is needed — each fix already has its own commit.

---

## Self-Review

### Spec coverage

| Spec section | Tasks |
|--------------|-------|
| §3 Dimension 1 SurfacePalette | Task 1, 9 |
| §3 Dimension 2 WorkflowAccents | Task 2, 9 |
| §3 Dimension 3 TextTones | Task 2, 9 |
| §3 Dimension 4 Borders | Task 2, 9, 11 |
| §3 Dimension 5 Typography roles | Task 3, 9, 16, 17, 19, 20 |
| §3 Dimension 6 Spacing | (unchanged) |
| §3 Dimension 7 Radius (xs + card) | Task 5 |
| §3 Dimension 8 Motion semantic aliases | Task 6, 18 |
| §3 Dimension 9 Reader sub-theme | Task 4, 9, 15, 16 |
| §4.1 File structure | Tasks 1–12 |
| §4.2 AppThemeSpec interface | Task 7 |
| §4.3 ThemeController + persistence | Task 12, 13 |
| §4.4 AppColors compat layer | Task 8 |
| §4.5 AppTypography retains builders | Tasks 9, 19 (use roles where possible) |
| §5 Claude theme values | Task 9 |
| §6.1 User bubble | Task 20 |
| §6.2 Assistant document flow | Task 21 |
| §6.3 Tool card simplification | Task 22 |
| §6.4 Settings Appearance section | Task 14 |
| §6.5 Hardcoded corral (7 files) | Tasks 16 (md), 17 (code), 18 (running effects), 19 (chat_input, chat_drawer, ask_user, debug_test_case) |
| §7 Stages 1–4 | Tasks 1–13 (Stage 1+2), 15–17 (Stage 3), 20–22 (Stage 4) |
| §8 Tests | Tasks 8, 9, 12, 14, 21 |
| §10 Acceptance checklist | Task 23 manual pass |

### Placeholder scan

No `TBD`, `TODO`, "implement later", or stub steps. Every code step has full code blocks.

### Type consistency

- `AppThemeSpec` getter names (`surfaces`, `accents`, `text`, `borders`, `typography`, `spacing`, `radius`, `motion`, `reader`) match across Task 7 (definition), Task 9 (implementation), Tasks 13–22 (consumption).
- `AppTypographySpec` role names (`bodyChat`, `bodyReader`, `caption`, `metaLabel`, `h1`, `h2`, `h3`, `codeInline`, `codeBlock`) consistent across Task 3, 9, 16, 17, 19, 20.
- `WorkflowAccents.danger` consistently named (introduced Task 2, used Task 22 exception card).
- `Borders.strongBorder` introduced Task 2, consumed Task 11 input decoration.
- `motion.streamingPulse` / `streamingPulseCurve` introduced Task 6, consumed Task 18.
- `sharedPreferencesProviderForThemeController` declared Task 12, overridden Task 13, used in tests across Tasks 12 and 14.

All consistent.
