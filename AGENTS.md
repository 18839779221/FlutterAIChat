# AGENTS.md

This file provides guidance to Codex (Codex.ai/code) when working with code in this repository.

## Project Overview

This is a Flutter-based AI chat application with multi-group conversations, local storage, and intelligent context management. The app supports streaming AI responses and deep thinking mode.

## Development Commands

### Flutter Version
- Prefer Flutter `3.35.7` in this repository
- If the locally active `flutter` is not `3.35.7`, use `fvm flutter` for all Flutter commands
- Recommended command forms:
  - `fvm flutter pub get`
  - `fvm flutter test`
  - `fvm flutter analyze`
  - `fvm flutter run`

### Running the App
```bash
# If active flutter == 3.35.7
flutter run

# Otherwise
fvm flutter run
```

- Unless explicitly requested otherwise, prefer debug builds/runs for local development and device installation
- On Android real devices, default to debug package install/run; only use `--release` or `--profile` when the user specifically asks for it
- Prefer Android real devices for end-to-end verification when available, unless the task explicitly requires another platform
- **CRITICAL: For Android debug installation, ALWAYS use `bash scripts/android_install_debug.sh [device_id]`**
  - **NEVER use `flutter install` or any uninstall/reinstall approach**
  - The script ensures debug APK is built and installed correctly with proper flags
  - This prevents issues like installing release builds which lack debug logging
  - Example: `bash scripts/android_install_debug.sh AUUNW22B08000071`
- Before installing a debug package to a real device, rebuild it first so the installed APK matches the latest workspace code
  - Prefer `bash scripts/android_install_debug.sh`
  - The script builds the latest debug APK, then installs with `adb install -r -t` only
  - It must not fall back to uninstall/reinstall automatically; if overwrite install fails, preserve the failure and inspect it
  - If you need to run the steps manually, prefer `flutter build apk --debug` then `adb install -r -t build/app/outputs/flutter-apk/app-debug.apk`
  - If the active flutter is not `3.35.7`, prefer the same build step with `fvm flutter`
- When reinstalling on an Android real device, prefer overwrite install over uninstall/reinstall so app state is preserved unless a clean install is explicitly needed

### Installing Dependencies
```bash
# If active flutter == 3.35.7
flutter pub get

# Otherwise
fvm flutter pub get
```

### Linting
```bash
# If active flutter == 3.35.7
flutter analyze

# Otherwise
fvm flutter analyze
```

### Testing
```bash
# If active flutter == 3.35.7
flutter test

# Otherwise
fvm flutter test
```

- For `ConfigurableHttpLLM`, provider-adapter, request-payload, or API-style compatibility changes, do not stop at mocked unit tests
- First run the fast local contract suite:
  - `fvm flutter test test/models/llm/configurable_http_llm_test.dart`
- Then run opt-in live provider contract tests against real upstream APIs:
  - `bash scripts/run_live_llm_contract_tests.sh minimax-openai`
  - `bash scripts/run_live_llm_contract_tests.sh minimax-openai minimax-anthropic`
  - `HEADLESS_LIVE_PROVIDER_CHAT_COMPLETIONS=minimax-openai flutter test --tags live-headless-agent test/integration/chat_send_live/chat_send_live_chat_completions_test.dart`
  - `HEADLESS_LIVE_PROVIDER_ANTHROPIC=minimax-anthropic flutter test --tags live-headless-agent test/integration/chat_send_live/chat_send_live_anthropic_test.dart`
  - `HEADLESS_LIVE_PROVIDER_RESPONSES=<provider-id> flutter test --tags live-headless-agent test/integration/chat_send_live/chat_send_live_responses_test.dart`
  - if the current workspace does not contain your local defaults file, inject it explicitly:
    `LIVE_LLM_LOCAL_DEFAULTS_PATH=/abs/path/config/local_defaults.json ...`
- Prefer validating at least one real provider for each still-supported API style you touched
  - current examples in local defaults include `responses`, `chat completions`, and `anthropic messages`
- The live suite should cover both first-round planner parsing and append-only transcript tool round-trip compatibility
  - do not treat a provider as verified if it only passes plain text / summary smoke paths
- Keep live tests opt-in
  - do not make default `flutter test` depend on external network access or provider credentials
  - use `HEADLESS_LIVE_PROVIDER_CHAT_COMPLETIONS` / `HEADLESS_LIVE_PROVIDER_RESPONSES` / `HEADLESS_LIVE_PROVIDER_ANTHROPIC` to explicitly select provider ids from `config/local_defaults.json`
  - when an AI agent is running tests, default preference is to use `minimax` / `deepseek` provider entries and their configured base URLs when available
  - for headless live integration tests, prefer environment-variable injection over editing test source:
    `HEADLESS_LIVE_PROVIDER_CHAT_COMPLETIONS`
    `HEADLESS_LIVE_PROVIDER_ANTHROPIC`
    `HEADLESS_LIVE_PROVIDER_RESPONSES`
    `LIVE_LLM_LOCAL_DEFAULTS_PATH`
- Treat live-test failures as first-class signal
  - mocked tests passing does not prove real provider compatibility
  - handshake, timeout, undocumented validation, and real response-shape issues must be investigated rather than waived away

### Web Automation
- For Flutter Web automation, prefer `fvm flutter run -d web-server` over ad-hoc local servers
- Keep the host and port stable so browser storage stays reusable:
  - `fvm flutter run -d web-server --release --web-hostname 127.0.0.1 --web-port 7357`
- Reuse the same origin for repeated tests:
  - `http://127.0.0.1:7357`
  - Do not switch freely between `localhost` and `127.0.0.1`
  - Do not change ports unless necessary
- Web persistence depends on browser profile plus origin (`scheme + host + port`)
  - If the origin changes, `localStorage` / `IndexedDB` / `shared_preferences` may appear empty
  - If the browser profile changes, saved settings and chat history may also appear empty
- Chrome standalone app mode can help manual regression testing, but it does not replace fixed origin/profile rules
  - It does not guarantee a fixed port
  - It does not by itself preserve data if host/port/profile changes
  - For browser automation, a normal Chrome page is usually easier to control than a standalone app window
- When testing real chat flows in Chrome/web, verify whether API settings already exist before assuming network features will work
  - Required runtime fields are typically `API Key`, `Model`, and `Base URL`

### Android Real-Device Automation
- Prefer Android real-device end-to-end validation over Web/Desktop substitutes when the required scenario can be exercised on the connected device
- Prefer rebuilding and installing the latest debug APK with `bash scripts/android_install_debug.sh [device_id]` before manual validation on a connected device
- For Android send-flow regressions, default to manual real-device verification plus existing Flutter / integration / live-provider tests instead of external mobile-control automation

### Android Repro Logging Workflow
- For Android/native repro debugging, default to the app-private file log instead of `logcat`
- The stable log source is `app.log` created by `Logger` under the native application support directory
- On Android, `getApplicationSupportDirectory()` maps to the app-private app-data root, and the expected log path is `/data/user/0/<package>/files/logs/app.log`
- Before each new repro, clear the existing `app.log` so the file contains only the current run's logs
- After the repro completes, read `app.log` directly for analysis; treat `logcat` as supplemental only when file-log evidence is insufficient
- When accessing the file from a connected Android device, prefer `adb shell run-as <package> ...` against the app-private `files/logs/app.log` path rather than long-running `logcat` capture
- Current Android debug package is `com.example.ai_chat`, so the default commands are:
  - clear: `adb -s <device_id> shell run-as com.example.ai_chat sh -c ': > /data/user/0/com.example.ai_chat/files/logs/app.log'`
  - inspect: `adb -s <device_id> shell run-as com.example.ai_chat sh -c 'cat /data/user/0/com.example.ai_chat/files/logs/app.log'`
  - export: `adb -s <device_id> shell run-as com.example.ai_chat sh -c 'cat /data/user/0/com.example.ai_chat/files/logs/app.log' > build/artifact-debug/<name>.log`
- Prefer the project helper script for this workflow:
  - `bash scripts/android_capture_app_log.sh clear [device_id]`
  - `bash scripts/android_capture_app_log.sh show [device_id]`
  - `bash scripts/android_capture_app_log.sh export <name> [device_id]`
- Keep detailed logging architecture, log taxonomy, and cleanup policy in `docs/architecture/logging.md`; use this section only as the default repro workflow

### Building
```bash
# Android
# If active flutter == 3.35.7
flutter build apk

# Otherwise
fvm flutter build apk

# iOS
# If active flutter == 3.35.7
flutter build ios

# Otherwise
fvm flutter build ios
```

## Documentation Map

- Global architecture overview: `docs/architecture/project-architecture-overview.md`
- Agent loop boundaries: `docs/architecture/agent-loop-boundaries-and-decoupling.md`
- Append-only transcript rules: `docs/architecture/append-only-transcript.md`
- Session context architecture: `docs/architecture/session-context-management.md`
- Provider adapter/runtime boundaries: `docs/architecture/provider-adapter-runtime-and-live-matrix.md`
- Streaming preview pipeline: `docs/architecture/streaming-message-preview-and-projection-pipeline.md`
- Tool presentation boundary: `docs/architecture/tool-presentation-event-boundary.md`
- Logging and trace rules: `docs/architecture/logging.md`

## Architecture Overview

### Core Structure

- The app uses `flutter_riverpod` with split provider/controller boundaries.
- `lib/providers/chat_providers.dart` is the composition entry; UI should consume providers and controller facades instead of embedding orchestration logic in widgets.
- Keep `ChatController` thin. Prefer adding narrow coordinators/services instead of growing a god object.
- Core layering is:
  1. UI (`lib/pages/`, `lib/widgets/`)
  2. Providers / Controllers (`lib/providers/`, `lib/controllers/`)
  3. Agent loop / session context / tool runtime (`lib/services/`, `lib/models/`)
  4. Persistence (`lib/database/`, repositories, storage)

### Controller and Prompt Boundaries

- `ChatSendCoordinator` owns send transaction lifecycle and streaming terminal handling.
- `ChatInteractionCoordinator` owns ask-user-question draft handoff and answer submission.
- `ChatSessionCoordinator` owns group load/select/delete and pagination.
- `ChatSummaryController` owns auto-summary scheduling and title updates.
- `ChatPreferencesController` owns system prompt persistence.
- Prompt management lives under `lib/services/prompt/`.
- User-authored system prompts are additive runtime sections, not overrides of core rules.
- Default prompt locale is English; Chinese copies must stay structurally aligned with English.

### Agent / Planner Guardrails

- `TurnHarness` is the only main entry for turn-loop execution.
- `planNextDecision()` remains the only execution entry for planner/tool loops.
- `ToolDefinition.descriptionForModel` is the only planner-facing tool description source; new tools must provide `descriptionForModel` and structured `argumentSchema`.
- Do not reintroduce hard-coded planner routing, keyword-trigger tool rules, prompt-only safety patches, or legacy JSON planner compatibility.
- Prefer execution-time safeguards such as confirmation, policy checks, verifier rules, and availability filtering over decision-time heuristics.
- Preserve transcript semantics in model-visible context: keep tool calls, tool results, interaction results, and final answers distinguishable.
- Persist pre-tool assistant text as `assistantPlannerMessage`; do not flatten it into generic summaries.
- `AskUserQuestion` is an interaction-style tool: persist structured results in `ChatTurnStep.resultJson` and replay them through transcript/context, but do not route it through generic tool execution.

### Session Context and Prompt Assembly

- Planner-visible context is composed from:
  - runtime user context
  - latest snapshot summary
  - recent completed turns after the snapshot boundary
  - current turn transcript
- Keep `history summary`, `recent completed turns`, and `current turn transcript` mutually exclusive.
- Do not treat UI `messages` as the direct model input source.
- Do not persist compression summaries into UI timeline messages.
- Compression boundaries should prefer completed turns / interactions, not arbitrary event slices.
- Date reminders belong to runtime user-context messages, not persisted timeline facts.
- Keep prompt composition limited to:
  - `base prompt`
  - `stage delta`
  - `runtime sections`
  - `user context messages`
  - `session context messages`
- Workspace V1 follows the same rule: current workspace belongs in runtime user context and per-turn runtime reminders, not in persisted summaries or snapshots

### LLM Integration

- `ConfigurableHttpLLM` remains a high-level orchestrator only.
- Protocol semantic mapping belongs in `lib/models/llm/adapters/`.
- Transport / SDK execution belongs in `lib/models/llm/runtime/`.
- Provider-specific streaming adaptation must stay inside the runtime boundary.
- Prefer extending the unified protocol runtime architecture instead of adding provider-specific branches to planner/controller/UI layers.

To add or extend provider support:
1. Add or update an `ApiStyleAdapter` in `lib/models/llm/adapters/` if protocol-level request/response mapping changes.
2. Add or update a `ProtocolExecutionRuntime` in `lib/models/llm/runtime/` if transport or SDK execution changes.
3. Register the runtime in `ProtocolRuntimeRegistry` and wire the adapter/runtime pairing through `ConfigurableHttpLLM`.
4. Keep provider capability differences in tests and runtime metadata, not in `TurnHarness` or UI heuristics.
5. Run mocked contract tests first, then real-provider live tests for every touched API style before considering the work complete.

## Implementation Notes

- The app is still internal-only. Unless a task explicitly requires it, do not add backward-compatibility layers, migration shims, fallback parsing for retired schemas, or legacy-preservation code.
- `assets/debug/test_cases.json` is the single source of truth for debug/e2e manual test cases.
- `config/local_defaults.json` is a runtime-facing local defaults file; schema changes must consider app boot config, settings fallback behavior, and automation scripts that read it directly.
- `ChatGroup.workspaceId` may be `NULL` in storage, but runtime must always resolve `NULL` to `.default`.
- Workspace-scoped files live under `/workspaces/<workspaceId>/...`; file tools should default to the resolved workspace root.
- `Delete` may remove a single file or recursively delete a directory, but it must only operate inside the current resolved workspace.
- `Delete` must never delete the current workspace root directory itself.
- Long-term memory uses `/memories/MEMORY.md` plus topic Markdown files; runtime memory usage belongs in `runtime user context`, with `side`-based recall for a small number of clearly relevant topics.
- `/memories` is the global long-term memory directory, not part of the current workspace; `Write /memories/...` must not trigger workspace auto-promotion.
- `Delete` may delete a concrete memory topic file, but must never delete `/memories` itself or `/memories/MEMORY.md`.
- If a user asks to ignore memory, runtime must proceed as if `/memories/MEMORY.md` were empty for that turn.
- Recalled memory records are context clues, not current truth; if a memory names a file path, function, flag, or repo state, verify the current state before acting on it.
- Workspace is a file container only; do not make it a new session context, transcript, or summary ownership boundary.
- Agent-visible file paths use a file-native `/` root and may include `/workspaces`, `/skills`, `/memories`; host filesystem paths must remain internal-only.
- On each platform, the physical app-private storage root may differ, but it is always mapped behind the same agent path semantics.
- When generating or modifying code, add concise comments for public interfaces, payload models, schema fields, DTO fields, and externally consumed tool/message payloads.
- When architecture changes, update `README.md` to reflect the current structure rather than the historical structure.
- When project requirements, implementation rules, or team conventions change, update `AGENTS.md`.
- Once spec/design/plan documentation is written, implementation may begin immediately unless the user explicitly asks for a pause.
- Prefer continuing on the current `main` branch and in the current workspace unless the user explicitly requests a different branch or a separate worktree.
- New or updated spec/design/plan docs under `docs/superpowers/` must be written in Chinese.
- When adding a new feature, explicitly consider whether logging coverage, automated tests, `README.md`, `AGENTS.md`, and backlog/todo docs also need updates.
- New modal bottom sheet UI should default to the shared `showAppBottomSheet` entry and shared outer shell unless the task explicitly requires a different presentation primitive.
- Settings-domain pages must preserve the approved layering rules:
  - Level-1 settings page is overview-first and should show as much current state as is practical.
  - Level-2 pages are for management and change operations, not decorative overview duplication.
  - Level-3 pages are only for genuinely complex object editing.
- For settings-domain changes, prefer lightweight interactions in the current page (`bottom sheet`, dropdown, segmented control, dialog) before introducing a new page.
- Settings-domain UI should avoid heavy outlined-card / wireframe boundaries; prefer tone, whitespace, typography, and light elevation for grouping.
- Settings-domain motion and lightweight interaction feedback should use shared `AppMotion` tokens and shared shells rather than page-local raw durations or bespoke sheet styling.
- For agent-loop regression coverage, prefer simulated integration tests built around fake planner/tool services plus real `TurnHarness`, `AgentEventProcessor`, and projection providers before reaching for heavier e2e flows.
- For new interaction checkpoints, prefer message-card interactions over modal-only state and keep turn status, event payload, message payload, and step ledger aligned.
- Keep the chat timeline under a single vertical scroll owner; avoid nested vertical scroll containers in timeline cards by default.
