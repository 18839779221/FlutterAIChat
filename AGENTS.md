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
- Prefer the deterministic Droidrun driver smoke test for chat send regression:
  - `bash scripts/android_droidrun_driver_smoke.sh`
- The driver smoke test uses Droidrun's low-level `AndroidDriver` directly instead of an LLM agent
- Use the agent-driven smoke test only when you specifically want to validate natural-language mobile control behavior:
  - `bash scripts/android_droidrun_chat_smoke.sh`
- Prefer the project wrapper script for Droidrun-based Android smoke tests:
  - `bash scripts/android_droidrun_chat_smoke.sh`
- The smoke script reads model settings from `config/local_defaults.json` at runtime and generates a temporary Droidrun config under `build/droidrun/`
- The script pre-wakes the phone, dismisses keyguard, launches the app via ADB, then hands control to Droidrun
- If the device is still locked and `ai_chat` is not the foreground app after prewarm, the script should fail fast instead of spending agent steps on a broken precondition
- Trajectories are saved under `build/droidrun/trajectories`
- Prefer a unique smoke message per run to avoid false positives from old chat history
- The deterministic driver smoke saves screenshots under `build/droidrun/driver-smoke`

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

## Architecture Overview

### State Management
The app uses **flutter_riverpod** with a split provider/controller architecture:

- `lib/providers/chat_providers.dart` is the composition entry that wires controllers and re-exports chat providers
- Collection, dependency, send-state, and UI-state providers are split into dedicated files under `lib/providers/`
- Chat business logic is split across dedicated controllers under `lib/controllers/`
- UI should consume providers and controller facades rather than embedding orchestration logic in widgets

### Data Flow Architecture

1. **UI Layer** (`lib/pages/`, `lib/widgets/`) - Consumes providers and displays data
2. **Controller Layer** (`lib/controllers/`) - Coordinates chat, session, summary, debug, and preference flows
3. **Service Layer** (`lib/services/chat_service.dart`) - Handles AI communication with context strategy
  - Session context orchestration now lives in dedicated `SessionContext*` services
4. **Data Layer** (`lib/database/database_helper.dart`) - SQLite operations for persistence

### Controller Boundaries

- `ChatController` is the page-facing facade and should stay thin
- `ChatSendCoordinator` owns send transaction lifecycle, tool confirmation/cancel, ask-user-question resume event projection, and streaming terminal handling
- `ChatInteractionCoordinator` owns ask-user-question draft state handoff and structured answer submission
- `ChatSessionCoordinator` owns group load/select/delete and message pagination
- `ChatSummaryController` owns auto-summary scheduling and summary title updates
- `ChatPreferencesController` owns system prompt persistence
- Prompt management lives under `lib/services/prompt/`
  - `PromptCatalog` owns bilingual prompt text blocks
  - `PromptBuilderService` assembles stage-specific prompts
  - `PromptRuntimeContextBuilder` wraps user system prompt and runtime extras into additive sections
  - `RuntimeUserContextService` builds runtime `userContext` data such as current date and AGENTS-derived context
  - `UserContextMessageBuilder` wraps runtime user context into a synthetic reminder message
  - default prompt locale is English; Chinese copies must stay structurally aligned with English
  - user-authored system prompts are additive runtime sections, not full overrides of core rules

### Agent Planner Tooling

- `ToolDefinition` is not only runtime metadata; it is also planner-facing schema metadata
- New tools must provide:
  - `descriptionForModel`
  - structured `argumentSchema`
- `descriptionForModel` is the only planner-facing tool description source
- Do not reintroduce `PlannerPromptBuilder` or any duplicate external tool-description prompt layer
- Prefer exposing tools to the planner dynamically from the runtime registry instead of maintaining separate hard-coded planner allowlists
- Keep tool-selection heuristics weak and generic:
  - do not hard-code tool-name routing or large keyword-to-tool rule tables as the primary decision mechanism
  - do not use prompt shaping as the primary safety mechanism for tool misuse
  - prefer runtime metadata plus lightweight policy filtering over per-tool dead rules
- Put safety and correctness in execution-time guards, not decision-time heuristics:
  - confirmation, write-before-read, policy enforcement, and availability checks should be enforced by architecture, not only by model instructions
  - decision-time filtering should behave like a lightweight availability filter, not a handwritten tool router
- Important: when solving model / agent reliability problems, do not default to hard-coded rules, keyword triggers, brittle text matching, or per-case prompt patching as the primary fix
  - prefer fixing the contract between planner, orchestrator, executor, ledger, and UI through structured state, typed outputs, capability boundaries, verification gates, and execution-time safeguards
  - treat heuristic patches as a last resort only when they are narrowly scoped, well-justified, and cannot be replaced by a more general architectural constraint
  - do not "repair" model behavior by teaching the system an ever-growing list of special phrases, special cases, or hand-maintained if/else policies
- Planner context should include structured summaries of prior tool attempts, latest tool results, and latest tool errors when available
- Preserve tool transcript semantics in model-visible context:
  - do not flatten tool-use history into summary-style assistant replies such as "已写入文件 ..."
  - keep tool initiation and tool result distinguishable when projecting recent turns / current turn for the model
  - if a tool result needs truncation for budget reasons, prefer a tool-specific context transform over replacing it with a generic assistant summary
- `AgentTurnOrchestrator` should treat `planNextDecision()` as the only execution entry for tool loops
- Legacy JSON planner compatibility has been removed; do not add fallback planner formats back in
- Do not re-inject raw `additionalContextMessages` / search hit details verbatim into the next planner or final-answer prompt; persist tool outcomes into turn-step ledger summaries and feed the model with compact structured summaries instead
- A single provider decision may contain both assistant text and tool calls; do not force a tool-or-text-only split
- Provider streaming for planner/tool-call assembly must remain an LLM-adapter-internal capability:
  - provider runtime / stream adapter must emit unified `StreamingMessageEvent` internally for preview projection and decision accumulation
  - `ConfigurableHttpLLM` / accumulator may consume streaming deltas internally, but legacy parallel streaming contracts must not be reintroduced
  - upper layers must still consume one final `ModelTurnDecision`
  - do not make `TurnHarness`、`AgentPlannerService`、projection providers, or widgets depend on planner mid-stream delta events unless the architecture is explicitly revised
- Streaming planner timeout policy should distinguish `idle timeout` from `overall timeout`:
  - idle timeout means no provider delta arrives for a sustained period
  - overall timeout is a coarse upper bound for one streaming attempt
  - do not regress to a single "whole request must fully close within one fixed timeout" rule for streaming planner paths
- Persist intermediate assistant text emitted before tool execution as `assistantPlannerMessage` so transcript, UI projection, and step ledger stay aligned
- Keep assistant reasoning stage-scoped in the timeline:
  - `tool_use` reasoning should render as a normal analysis block in chronological order before the corresponding tool workflow/result
  - only final-answer / response reasoning may be folded into the final response block
  - do not let final answer fallback logic absorb earlier `tool_use` reasoning into the final response message
- Treat `AskUserQuestion` as an interaction-style tool:
  - do not route it through `ToolOrchestratorService.executeToolInvocation()`
  - do persist its structured result into `ChatTurnStep.resultJson`
  - do append the interaction result into transcript and let planner-visible context replay it from append-only transcript
  - do keep the human-readable transcript text and structured payload in sync
- Tool-use UI should keep status semantics shared but allow per-tool presentation overrides:
  - preserve existing lifecycle enums and structured payload models instead of inventing a second UI-only state machine
  - allow custom tool cards to read `ToolWorkflowStep.details` and `ToolResult.data` directly when richer explanation is needed
  - keep `ToolWorkflowCard` and other generic cards as fallback renderers for tools without dedicated UI
  - keep confirmation controls outside tool-specific timeline cards when possible; prefer a shared bottom confirmation surface over embedding action buttons into every tool card
- Inline artifact / visualizer work should remain a small local capability:
  - `create_artifact` is the only tool that explicitly understands artifact semantics
  - `Write` / `Edit` must remain generic file tools; do not add artifact-specific arguments or return fields to them
  - artifact/file linking should stay in registry / resolver / timeline projection / renderer layers, not in `TurnHarness`, `ToolOrchestratorService`, or planner keyword heuristics
  - same-turn edits to the same artifact should refresh one inline card as part of the answer body
  - cross-turn edits should render a new card in the new turn while older cards remain visible and show a stale/updated hint
  - app restart, group switch, and group reload must invalidate artifact runtime cache and rebuild from persistent truth instead of relying on in-memory linkage

When adding a feature, prefer extending an existing bounded controller or creating a new narrow controller instead of growing `ChatController` back into a god object.

### Context Management System

The app now uses a **Session Context** architecture for conversation context:

- `SessionContextService` builds planner-visible context for one `group`/Session
- `SessionRuntimeMarkerService` tracks the latest injected date per session and decides whether a date-change reminder is needed before the current turn
- `SessionContextProjector` converts prior messages, tool results, and interaction results into compact model-visible messages
- `ModelBudgetRegistry` resolves model budget profiles from runtime provider/model overrides, built-in defaults, and conservative fallback values
- `SessionTokenBudgetService` decides whether compression is needed based on token budget pressure
- `SessionSummaryService` generates stable historical summaries
- `session_context_snapshots` stores the latest persisted summary boundary for each Session

The planner-visible context should be composed from:

- runtime user context
- latest snapshot summary
- recent completed turns after the snapshot boundary
- current turn transcript

Important rules:

- Do not reintroduce `context_strategies.dart` or `MessageContextStrategy`
- Do not treat UI `messages` as the direct model input source
- Do not persist compression summaries into UI timeline messages
- Compression boundaries should prefer completed turn / completed interaction units, not arbitrary single-event slicing
- The primary compression trigger is token budget pressure near the current model limit, not a fixed message count
- planner-visible context must keep `history summary`、`recent completed turns`、`current turn transcript` mutually exclusive
- runtime date reminders should be injected as runtime context messages, not persisted timeline facts
- `recent completed turns` should be selected by both default count and budget ratio limits, with at least the previous completed turn retained when available
- older history that exits the recent working set must roll into snapshot summary instead of being dropped directly

### Agent Loop Boundary Guardrails

- Treat `TurnHarness` as the only main entry for turn-loop execution; do not move planner-loop, waiting-state, or stop-condition logic back into controllers, providers, or widgets
- Treat provider/API request-response compatibility as a `Model Gateway / Provider Adapter` concern, not as part of the Agent Loop Core
- Treat prompt assembly, runtime markers, and session-context composition as `Planner Input Assembly`, not as loop-state rules
- Treat repositories/DB writes as persistence adapters; do not make UI message storage shape the primary source of loop semantics
- Treat UI waiting-state / workflow rendering as projection concerns; do not rely on `ChatMessage.payloadJson` scanning as the long-term single source of truth for pending tool or interaction state
- See `docs/architecture/agent-loop-boundaries-and-decoupling.md` for the current decoupling target and testing rationale

### LLM Integration

- `ConfigurableHttpLLM` should remain a high-level orchestrator only
  - protocol semantic mapping belongs in `lib/models/llm/adapters/`
  - protocol transport / SDK execution belongs in `lib/models/llm/runtime/`
  - protocol-specific streaming event adaptation should stay inside the runtime boundary instead of leaking into planner / controller layers
- Prefer extending the unified protocol runtime architecture before adding new provider-specific branches
  - `ProtocolRequestSpec` carries typed or JSON protocol request objects
  - `ProtocolExecutionRuntime` owns request execution and raw response capture
  - `ProtocolRuntimeRegistry` selects the runtime by `ApiStyle`
  - upcoming anthropic SDK/native refactors should plug into this boundary instead of restoring inline HTTP logic inside `ConfigurableHttpLLM`
 
To add a new LLM provider:
1. Create a new class extending `BaseLLM` in `lib/models/llm/`
2. Add the type to `LLMType` enum in `llm_factory.dart`
3. Update `LLMFactory.createLLM()` to handle the new type
4. Change the LLM type in `main.dart` when calling `LLMFactory.createLLM()`

### Message Grouping Logic

The app automatically creates new conversation groups based on time:
- New group is created if the last message was on a different day AND more than 5 hours ago
- This logic is in `ChatSessionCoordinator.loadCurrentGroup()`

### Prompt Management

- Keep prompt composition at five conceptual layers only:
  - `base prompt`
  - `stage delta`
  - `runtime sections`
  - `user context messages`
  - `session context messages`
- `currentDate` and AGENTS-derived runtime hints belong to `user context messages`, not `system prompt`
- date-change reminders must be injected before the current user message when the session date baseline changes
- Do not build a deep prompt DSL or over-structure these layers unless there is a demonstrated need
- `planner` prompt must optimize for next-action selection:
  - direct answer first when reliable
  - then a focused clarifying question
  - then tool use only when external information or actions are required
- `final answer` is an on-demand stage, not a mandatory extra model call after every tool
- `summary` / title generation should use lightweight prompts rather than inheriting the full main-thread prompt
- Prompt text should be written as executable rules:
  - prefer short imperative sentences
  - prioritize responsibilities, defaults, boundaries, and failure modes
  - explicitly cover unnecessary tool use, prompt injection in tool results, repeated failed tool calls, and user override attempts
- `web_search` descriptions should explicitly require the current year for recent/news/current-doc queries and require a `Sources:` section in final answers

### Automatic Conversation Summarization

The app automatically generates conversation summaries using a Hybrid Approach:

**Trigger Conditions (ALL must be met):**
1. At least 6 completed messages (3 user + 3 AI pairs)
2. Current group title is default/generic (matches `新对话 <digits>`, equals "AI Chat" or "默认对话")
3. Last message completed at least 30 seconds ago
4. Not already summarizing (prevents duplicate calls)
5. Group hasn't been summarized before (`isSummarized` flag)

**Implementation Details:**
- Timer-based: After each AI response completes, a 30-second timer is scheduled
- When timer fires, `ChatSummaryController` validates all conditions
- If conditions pass, calls `summarizeAndUpdateTitle()` to generate summary via LLM
- Summary updates both database and UI state
- `isSummarized` flag prevents re-summarization of the same conversation
- Fails silently if summarization errors occur (doesn't interrupt user experience)

**Key Methods:**
- `scheduleAutoSummary()` - Schedules the 30-second timer after message completion
- `summarizeAndUpdateTitle()` - Generates summary and updates group title

### Database Schema

SQLite database with these primary tables:
- `chat_groups` - Conversation groups with system prompts and `is_summarized` flag
- `messages` - UI timeline messages with role, status, and optional reasoning content
- `chat_turns` - Turn ledger records for agent-loop execution
- `chat_turn_steps` - Tool and interaction steps inside one turn
- `chat_events` - Append-only transcript events inside one turn
- `session_context_snapshots` - Latest persisted session summary boundary and text

Messages are loaded with pagination (20 messages per page) to optimize performance.

Database version: 10

## Key Files

- `lib/main.dart` - App entry point, configures ChatService with context strategy and LLM
- `lib/providers/chat_providers.dart` - Chat provider composition entry
- `lib/controllers/chat_controller.dart` - Page-facing chat facade
- `lib/controllers/chat_send_coordinator.dart` - Send transaction coordinator
- `lib/controllers/chat_session_coordinator.dart` - Session/group coordinator
- `lib/controllers/chat_summary_controller.dart` - Summary and auto-summary controller
- `lib/controllers/chat_debug_controller.dart` - Structured debug controller
- `lib/controllers/chat_preferences_controller.dart` - Prompt/mode preference controller
- `lib/services/chat_service.dart` - Handles AI streaming and model-name lookup for runtime services
- `lib/services/session_context_service.dart` - Session-level planner context orchestrator
- `lib/services/session_context_projector.dart` - Session history to model-visible context projector
- `lib/services/session_token_budget_service.dart` - Token budget evaluation for context compression
- `lib/services/session_summary_service.dart` - Snapshot summary generation service
- `lib/models/llm/llm_factory.dart` - LLM factory for creating model instances
- `lib/database/database_helper.dart` - SQLite database operations
- `assets/debug/test_cases.json` - Debug 测试案例的唯一结构化数据源，供空状态精选案例、Debug `Cases` 面板和未来自动化共用
- `config/local_defaults.json` - 本地运行与自动化默认配置来源，供 LLM 默认参数与 Droidrun 等脚本在运行时读取

## Important Notes

- The app uses streaming responses from the LLM, handled via `Stream<String>` in `BaseLLM.chatStream()`
- Messages are stored in reverse chronological order in the UI (newest first)
- History messages are filtered to only include completed AI-user message pairs before sending to the LLM
- Auto-scrolling behavior pauses when user manually scrolls up during generation
- The app supports Shorebird code push for over-the-air updates
- The app is currently in an internal-development stage with no external users
  - Unless a task explicitly requires it, do not add backward-compatibility layers, migration shims, fallback parsing for retired schemas, or legacy-preservation code
  - Prefer direct refactors toward the target structure and update local docs/scripts/tests in the same change
- `assets/debug/test_cases.json` is the single source of truth for debug/e2e manual test cases
  - Do not reintroduce a second primary case list in Markdown, widget constants, or automation-only fixtures
  - When adding or changing debug cases, consider whether empty-state featured entries, Debug `Cases` grouping, and related tests also need updates
- `config/local_defaults.json` is a runtime-facing local defaults file
  - Changes to its schema or semantics must consider app boot-time config loading, settings fallback behavior, and Android/Web automation scripts that read it directly
  - When adding or changing LLM providers, consider whether the headless live suites under `test/integration/chat_send_live/` should also be exercised against the new provider
- When generating or modifying code, add necessary comments for public interfaces, payload models, and important fields
  - This is especially required for interface fields, schema fields, DTO/model fields, and tool/message payload fields
  - Comments should explain the meaning and usage of the field, not restate the field name mechanically
  - Keep comments concise, but do not omit them for externally consumed structures just to save lines
- When architecture changes, update `README.md` to reflect the current structure rather than the historical structure
- When project requirements, implementation rules, or team conventions change, update `AGENTS.md`
- Any newly added or updated spec/design/plan documentation in this repository must be written in Chinese
  - This applies to files under `docs/superpowers/specs/`, `docs/superpowers/plans/`, and similar implementation/design docs
  - Do not default to English for newly generated spec or implementation plan content
- When adding a new feature, explicitly consider whether the following also need updates:
  - logging coverage defined in `docs/architecture/logging.md`
  - automated tests
  - README capability/architecture docs
  - AGENTS implementation constraints
  - backlog/todo docs if the feature changes future priorities
- For LLM integration, adapter, or provider-compatibility work:
  - update mocked contract tests first
  - then run real-provider contract tests for the touched API styles before considering the work complete
- For agent-loop regression coverage, prefer adding simulated integration tests before reaching for heavier e2e flows
  - the preferred shape is: fake planner / fake tool call service / real `TurnHarness` / real `AgentEventProcessor` / real projection providers
  - these tests should cover multi-iteration loop, waiting states, resume paths, and projection consumption together
  - keep real-environment tests focused on provider wire compatibility, real devices, platform timing, and other issues that simulation cannot expose
- For any trace/log changes, keep detailed rules only in `docs/architecture/logging.md` and let other docs reference it instead of duplicating fields, categories, or cleanup policy
- For new interaction checkpoints in the agent loop:
  - prefer message-card interactions over modal-only state
  - keep turn status, event payload, message payload, and step ledger aligned
  - update `TurnVerifier` whenever a new waiting state or resumable step type is introduced
- New feature work should stay visually and architecturally consistent with the current project direction
  - Avoid one-off UI patterns or isolated architectural shortcuts that bypass the current controller/provider boundaries
  - Tool-use UI should prefer semantic presentation variants over raw message-type mirroring
  - Context-gathering tool steps should stay compact and collapse by default; external-action results should remain explicit in the timeline
  - Completed Markdown timeline rows should preserve stable row identity; avoid rebuilding the full assistant widget list in `ChatMessageList` when only one message changes
  - The chat timeline should keep a single vertical scroll owner; new timeline cards should avoid adding nested vertical `ScrollView` / `ListView` containers by default
  - `ask_user_question` cards should expand with the timeline instead of owning an inner vertical scroll surface
  - Inline artifact previews should not own vertical scrolling inside the chat timeline; full scrolling artifact reading belongs to the detail page
- Session context changes should preserve the current layered boundary:
  - UI `messages` for timeline
  - `chat_turns/chat_turn_steps/chat_events` for turn ledger and transcript
  - `SessionContextService` for model-visible session context
