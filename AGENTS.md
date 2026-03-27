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
The app uses **flutter_riverpod** for state management with a centralized controller pattern:

- `ChatController` (in `lib/providers/chat_providers.dart`) is the main business logic controller that handles all chat operations
- State is managed through various providers: `messagesProvider`, `groupsProvider`, `currentGroupProvider`, etc.
- The controller pattern centralizes logic and prevents state management code from spreading across UI components

### Data Flow Architecture

1. **UI Layer** (`lib/pages/`, `lib/widgets/`) - Consumes providers and displays data
2. **Controller Layer** (`ChatController` in `lib/providers/chat_providers.dart`) - Orchestrates business logic
3. **Service Layer** (`lib/services/chat_service.dart`) - Handles AI communication with context strategy
4. **Data Layer** (`lib/database/database_helper.dart`) - SQLite operations for persistence

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
- This logic is in `ChatController.loadCurrentGroup()` in `lib/providers/chat_providers.dart`

### Concise Mode Implementation

When concise mode is toggled:
1. Current system prompt is cached in `cachedSystemPromptProvider`
2. System prompt is replaced with a concise instruction (30 characters max)
3. When disabled, the cached prompt is restored
4. This is handled in `ChatController.setUseConciseMode()`

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
- When timer fires, `_checkAndTriggerAutoSummary()` validates all conditions
- If conditions pass, calls `summarizeAndUpdateTitle()` to generate summary via LLM
- Summary updates both database and UI state
- `isSummarized` flag prevents re-summarization of the same conversation
- Fails silently if summarization errors occur (doesn't interrupt user experience)

**Key Methods:**
- `_scheduleAutoSummary()` - Schedules the 30-second timer after message completion
- `_checkAndTriggerAutoSummary()` - Validates conditions and triggers summarization
- `_isDefaultTitle()` - Checks if title is still default/generic
- `summarizeAndUpdateTitle()` - Generates summary and updates group title

### Database Schema

SQLite database with two main tables:
- `chat_groups` - Conversation groups with system prompts and `is_summarized` flag
- `chat_messages` - Individual messages with role, status, and optional reasoning content

Messages are loaded with pagination (20 messages per page) to optimize performance.

Database version: 5 (includes `is_summarized` field for automatic summarization tracking)

## Key Files

- `lib/main.dart` - App entry point, configures ChatService with context strategy and LLM
- `lib/providers/chat_providers.dart` - All Riverpod providers and ChatController business logic
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
