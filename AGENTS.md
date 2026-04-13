# AGENTS.md

This file provides guidance to Codex (Codex.ai/code) when working with code in this repository.

## Project Overview

This is a Flutter-based AI chat application with multi-group conversations, local storage, and intelligent context management. The app supports streaming AI responses, deep thinking mode, and concise mode.

## Development Commands

### Flutter Version
- Prefer Flutter `3.29.2` in this repository
- If the locally active `flutter` is not `3.29.2`, use `fvm flutter` for all Flutter commands
- Recommended command forms:
  - `fvm flutter pub get`
  - `fvm flutter test`
  - `fvm flutter analyze`
  - `fvm flutter run`

### Running the App
```bash
# If active flutter == 3.29.2
flutter run

# Otherwise
fvm flutter run
```

### Installing Dependencies
```bash
# If active flutter == 3.29.2
flutter pub get

# Otherwise
fvm flutter pub get
```

### Linting
```bash
# If active flutter == 3.29.2
flutter analyze

# Otherwise
fvm flutter analyze
```

### Testing
```bash
# If active flutter == 3.29.2
flutter test

# Otherwise
fvm flutter test
```

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
# If active flutter == 3.29.2
flutter build apk

# Otherwise
fvm flutter build apk

# iOS
# If active flutter == 3.29.2
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
4. **Data Layer** (`lib/database/database_helper.dart`) - SQLite operations for persistence

### Controller Boundaries

- `ChatController` is the page-facing facade and should stay thin
- `ChatSendCoordinator` owns send transaction lifecycle, tool confirmation/cancel, and streaming terminal handling
- `ChatSessionCoordinator` owns group load/select/delete and message pagination
- `ChatSummaryController` owns auto-summary scheduling and summary title updates
- `ChatDebugController` owns `structureMessageForDebug` lifecycle
- `ChatPreferencesController` owns system prompt, reasoning mode, and concise mode

### Agent Planner Tooling

- `ToolDefinition` is not only runtime metadata; it is also planner-facing schema metadata
- New tools must provide:
  - `descriptionForModel`
  - `whenToUse`
  - `whenNotToUse`
  - structured `argumentSchema`
- Prefer exposing tools to the planner dynamically from the runtime registry instead of maintaining separate hard-coded planner allowlists
- Prefer intent-based tool exposure:
  - retrieval turns should default to retrieval tools
  - high-risk write tools should not be exposed unless the user intent is clearly actionable
- Keep tool-selection heuristics weak and generic:
  - do not hard-code tool-name routing or large keyword-to-tool rule tables as the primary decision mechanism
  - do not use prompt shaping as the primary safety mechanism for tool misuse
  - prefer broad intent/actionability gating plus runtime metadata over per-tool dead rules
- Put safety and correctness in execution-time guards, not decision-time heuristics:
  - confirmation, write-before-read, policy enforcement, and availability checks should be enforced by architecture, not only by model instructions
  - decision-time filtering should behave like a lightweight availability filter, not a handwritten tool router
- Planner context should include structured summaries of prior tool attempts, latest tool results, and latest tool errors when available
- When evolving the planner path, preserve backward compatibility if the current LLM backend does not yet support native structured tool-calling
- `AgentTurnOrchestrator` should treat `planNextDecision()` as the only execution entry for tool loops; any fallback from native provider decisions to legacy planner formats must happen inside `AgentPlannerService`
- Do not re-inject raw `additionalContextMessages` / search hit details verbatim into the next planner or final-answer prompt; persist tool outcomes into turn-step ledger summaries and feed the model with compact structured summaries instead
- Legacy fallback must inspect the latest persisted turn step before issuing another retrieval call; if the most recent completed retrieval already used the same arguments and returned an empty result, terminate with a user-facing clarification request instead of repeating the same tool call

When adding a feature, prefer extending an existing bounded controller or creating a new narrow controller instead of growing `ChatController` back into a god object.

### Context Management System

The app uses a **Strategy Pattern** for managing conversation context:

- `MessageContextStrategy` (base class) - Defines the interface for context selection
- `TokenBasedStrategy` - Selects messages based on token limits
- `SmartSelectionStrategy` - Selects messages based on relevance and time
- `HybridStrategy` - Combines multiple strategies with weighted scoring

Context strategies are configured in `main.dart` when creating the `ChatService`. The default is a hybrid of 70% token-based and 30% smart selection.

### LLM Integration

 
To add a new LLM provider:
1. Create a new class extending `BaseLLM` in `lib/models/llm/`
2. Add the type to `LLMType` enum in `llm_factory.dart`
3. Update `LLMFactory.createLLM()` to handle the new type
4. Change the LLM type in `main.dart` when calling `LLMFactory.createLLM()`

### Message Grouping Logic

The app automatically creates new conversation groups based on time:
- New group is created if the last message was on a different day AND more than 5 hours ago
- This logic is in `ChatSessionCoordinator.loadCurrentGroup()`

### Concise Mode Implementation

When concise mode is toggled:
1. Current system prompt is cached in `cachedSystemPromptProvider`
2. System prompt is replaced with a concise instruction (30 characters max)
3. When disabled, the cached prompt is restored
4. This is handled in `ChatPreferencesController.setUseConciseMode()`

### Automatic Conversation Summarization

The app automatically generates conversation summaries using a Hybrid Approach:

**Trigger Conditions (ALL must be met):**
1. At least 6 completed messages (3 user + 3 AI pairs)
2. Current group title is default/generic (starts with "新对话", equals "AI Chat" or "默认对话")
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

SQLite database with two main tables:
- `chat_groups` - Conversation groups with system prompts and `is_summarized` flag
- `chat_messages` - Individual messages with role, status, and optional reasoning content

Messages are loaded with pagination (20 messages per page) to optimize performance.

Database version: 5 (includes `is_summarized` field for automatic summarization tracking)

## Key Files

- `lib/main.dart` - App entry point, configures ChatService with context strategy and LLM
- `lib/providers/chat_providers.dart` - Chat provider composition entry
- `lib/controllers/chat_controller.dart` - Page-facing chat facade
- `lib/controllers/chat_send_coordinator.dart` - Send transaction coordinator
- `lib/controllers/chat_session_coordinator.dart` - Session/group coordinator
- `lib/controllers/chat_summary_controller.dart` - Summary and auto-summary controller
- `lib/controllers/chat_debug_controller.dart` - Structured debug controller
- `lib/controllers/chat_preferences_controller.dart` - Prompt/mode preference controller
- `lib/services/chat_service.dart` - Handles AI streaming with context selection
- `lib/models/context/context_strategies.dart` - Context selection strategy implementations
- `lib/models/llm/llm_factory.dart` - LLM factory for creating model instances
- `lib/database/database_helper.dart` - SQLite database operations

## Important Notes

- The app uses streaming responses from the LLM, handled via `Stream<String>` in `ChatService.sendMessageStream()`
- Messages are stored in reverse chronological order in the UI (newest first)
- History messages are filtered to only include completed AI-user message pairs before sending to the LLM
- Auto-scrolling behavior pauses when user manually scrolls up during generation
- The app supports Shorebird code push for over-the-air updates
- When generating or modifying code, add necessary comments for public interfaces, payload models, and important fields
  - This is especially required for interface fields, schema fields, DTO/model fields, and tool/message payload fields
  - Comments should explain the meaning and usage of the field, not restate the field name mechanically
  - Keep comments concise, but do not omit them for externally consumed structures just to save lines
- When architecture changes, update `README.md` to reflect the current structure rather than the historical structure
- When project requirements, implementation rules, or team conventions change, update `AGENTS.md`
- When adding a new feature, explicitly consider whether the following also need updates:
  - trace/log coverage
  - automated tests
  - README capability/architecture docs
  - AGENTS implementation constraints
  - backlog/todo docs if the feature changes future priorities
- New feature work should stay visually and architecturally consistent with the current project direction
  - Avoid one-off UI patterns or isolated architectural shortcuts that bypass the current controller/provider boundaries
