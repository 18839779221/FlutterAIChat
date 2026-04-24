# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is a Flutter-based AI chat application with multi-group conversations, local storage, and intelligent context management. The app supports streaming AI responses, deep thinking mode, and concise mode.

## Development Commands

### Running the App
```bash
flutter run
```

### Installing Dependencies
```bash
flutter pub get
```

### Linting
```bash
flutter analyze
```

### Testing
```bash
flutter test
```

### Building
```bash
# Android
flutter build apk

# iOS
flutter build ios
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
2. Current group title is default/generic (matches `新对话 <digits>`, equals "AI Chat" or "默认对话")
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
