# API Config And Web Storage Quick Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make API key/base URL editable in settings and make the app run normally in Chrome with browser-backed persistence.

**Architecture:** Add a small settings repository for LLM config, inject that config into a configurable HTTP LLM implementation, and introduce a platform-selected chat storage abstraction so desktop keeps SQLite while web uses browser local storage. Keep existing chat behavior intact and avoid broad refactors.

**Tech Stack:** Flutter, Dart, Riverpod, `shared_preferences`, `sqflite`, browser local persistence, manual smoke verification

---

## File Responsibility Map

### Create

- `lib/repositories/app_settings_repository.dart`
  - Persist and load `apiKey` and `baseUrl`
- `lib/storage/chat_storage.dart`
  - Shared storage interface for groups and messages
- `lib/storage/web_chat_storage.dart`
  - Browser-backed storage implementation for Chrome/web

### Modify

- `lib/models/llm/configurable_http_llm.dart`
  - Remove hardcoded config and accept injected values
- `lib/models/llm/llm_factory.dart`
  - Build LLM instances from app settings
- `lib/main.dart`
  - Initialize settings repository and platform-specific storage
- `lib/providers/chat_providers.dart`
  - Depend on storage abstraction instead of directly instantiating `DatabaseHelper`
- `lib/database/database_helper.dart`
  - Implement shared storage interface for non-web platforms
- `lib/pages/settings_page.dart`
  - Add editable API key/base URL fields and save action
- `pubspec.yaml`
  - Add any browser-safe persistence dependency needed for shared settings/storage

## Task 1: App Settings For API Config

**Files:**
- Create: `lib/repositories/app_settings_repository.dart`
- Modify: `lib/pages/settings_page.dart`
- Modify: `pubspec.yaml`

- [ ] Create `AppSettingsRepository` with `getApiKey()`, `getBaseUrl()`, and `saveLlmConfig(...)`
- [ ] Back the repository with shared local persistence available on desktop and web
- [ ] Add API key and base URL fields to settings UI
- [ ] Validate base URL with `Uri.tryParse` before saving
- [ ] Show a clear save success or error message in settings
- [ ] Run: `flutter analyze`

## Task 2: Inject API Config Into LLM Construction

**Files:**
- Modify: `lib/models/llm/configurable_http_llm.dart`
- Modify: `lib/models/llm/llm_factory.dart`
- Modify: `lib/main.dart`

- [ ] Update the configurable HTTP LLM constructor to accept runtime config instead of hardcoded values
- [ ] Remove the embedded secret and embedded base URL from the configurable HTTP LLM implementation
- [ ] Update factory/bootstrap code to read config from `AppSettingsRepository`
- [ ] Keep request-time error handling clear when config is empty or invalid
- [ ] Run: `flutter analyze`

## Task 3: Platform Storage Abstraction

**Files:**
- Create: `lib/storage/chat_storage.dart`
- Modify: `lib/database/database_helper.dart`
- Modify: `lib/providers/chat_providers.dart`

- [ ] Define the minimum storage interface needed by current chat/group flows
- [ ] Make the existing SQLite helper satisfy that interface on non-web platforms
- [ ] Change provider wiring to depend on the storage interface instead of concrete SQLite creation
- [ ] Keep existing desktop behavior unchanged
- [ ] Run: `flutter analyze`

## Task 4: Web Storage Implementation

**Files:**
- Create: `lib/storage/web_chat_storage.dart`
- Modify: `lib/main.dart`
- Modify: `lib/providers/chat_providers.dart`

- [ ] Implement browser-backed persistence for groups and messages using JSON serialization
- [ ] Select `WebChatStorage` when `kIsWeb` is true
- [ ] Ensure startup no longer touches `sqflite` on Chrome
- [ ] Verify load/save/update paths used by chat history still work on web
- [ ] Run: `flutter run -d chrome`

## Task 5: Quick End-To-End Verification

**Files:**
- Modify: `docs/superpowers/plans/2026-03-26-api-config-and-web-storage-quick-implementation-plan.md`

- [ ] Save a real API key and base URL from settings
- [ ] Launch desktop target and verify a real request can be sent
- [ ] Launch Chrome target and verify the app starts without database initialization failure
- [ ] Send one message in Chrome and verify local browser-backed persistence keeps the conversation after refresh
- [ ] Update the checklist in this plan with actual progress notes
