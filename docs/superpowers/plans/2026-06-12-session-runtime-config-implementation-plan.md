# Session Runtime Config Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace global active provider/model selection with a session-scoped runtime config layer, delete `lockedProviderStyle`, and make send/context/runtime flows read from the current session binding while keeping global defaults only for new-session initialization.

**Architecture:** Add a dedicated `SessionRuntimeConfig` model + repository/service as the single source of truth for each session's active provider/model/style. Keep `AppSettingsRepository` focused on provider catalog plus global defaults, bridge draft sessions through an in-memory runtime config, then switch send/UI/context consumers to the new resolver before deleting `lockedProviderStyle` and its repair patches.

**Tech Stack:** Flutter, Riverpod, sqflite/shared_preferences storage, existing chat/session coordinators, targeted Flutter tests

---

## File Structure

| Path | Responsibility |
| --- | --- |
| `lib/models/session/session_runtime_config.dart` | New persisted session runtime binding model |
| `lib/repositories/session_runtime_config_repository.dart` | CRUD/upsert access for `SessionRuntimeConfig` |
| `lib/services/session_runtime_config_service.dart` | Current-session runtime orchestration, including draft-session binding |
| `lib/services/session_llm_config_resolver.dart` | Builds `LLMConfig` from session runtime config + provider catalog |
| `lib/providers/chat_dependency_providers.dart` | Wire new repository/service/resolver providers |
| `lib/providers/chat_collection_providers.dart` or new provider file | Hold current draft runtime state if needed |
| `lib/models/chat_group.dart` | Remove `lockedProviderStyle` from group model |
| `lib/database/database_helper.dart` | Add `session_runtime_configs`, remove `locked_provider_style`, bump schema, hard-cut upgrade path |
| `lib/storage/chat_storage.dart` | Add storage APIs for session runtime configs and remove old group-style assumptions |
| `lib/storage/web_chat_storage.dart` | Mirror new session runtime config storage for web |
| `lib/controllers/chat_session_coordinator.dart` | Initialize draft runtime, restore session runtime on session switch, remove old provider-style sync patch |
| `lib/controllers/chat_send_coordinator.dart` | Use session runtime resolver when creating groups, validating attachments, and starting turns |
| `lib/widgets/chat_input.dart` | Display and mutate current session runtime selection rather than global selection |
| `lib/services/session_context_service.dart` | Resolve runtime config from current session before budget/context assembly |
| `lib/services/turn_harness.dart` | Stop reading `group.lockedProviderStyle`; use turn/session runtime style |
| `lib/models/llm/configurable_http_llm.dart` | Accept resolved session `LLMConfig` path instead of implicit global active config where necessary |
| `README.md` | Update architecture summary if runtime-selection ownership is described there |
| `AGENTS.md` | Update repo guidance if session runtime rules replace old provider-lock assumptions |
| `test/...` | Add focused unit/widget/integration tests and remove old `lockedProviderStyle` expectations |

## Task 1: Add `SessionRuntimeConfig` domain model and repository

**Files:**
- Create: `lib/models/session/session_runtime_config.dart`
- Create: `lib/repositories/session_runtime_config_repository.dart`
- Modify: `lib/storage/chat_storage.dart`
- Modify: `lib/providers/chat_dependency_providers.dart`
- Test: `test/repositories/session_runtime_config_repository_test.dart`

- [ ] **Step 1: Write the failing repository test for upsert and read**

```dart
test('upserts and reloads runtime config by group', () async {
  final storage = DatabaseHelper(databaseName: 'session_runtime_config_repo.db');
  final repo = SessionRuntimeConfigRepository(storage);
  final groupId = await storage.insertGroup(ChatGroup(title: 'g'));

  await repo.upsert(
    const SessionRuntimeConfig(
      groupId: groupId,
      providerId: 'openai',
      modelId: 'gpt-5.4',
      providerStyle: ChatTurnProviderStyle.openaiResponses,
    ),
  );

  final config = await repo.getByGroup(groupId);
  expect(config?.providerId, 'openai');
  expect(config?.modelId, 'gpt-5.4');
});
```

- [ ] **Step 2: Run the new repository test to confirm missing types/APIs**

Run: `fvm flutter test test/repositories/session_runtime_config_repository_test.dart`
Expected: FAIL with missing `SessionRuntimeConfig` / repository / storage methods

- [ ] **Step 3: Implement the minimal model and repository**

```dart
class SessionRuntimeConfig {
  final int? id;
  final int groupId;
  final String providerId;
  final String modelId;
  final ChatTurnProviderStyle providerStyle;
  final DateTime updatedAt;
}
```

```dart
abstract class ChatStorage {
  Future<int> insertSessionRuntimeConfig(SessionRuntimeConfig config);
  Future<SessionRuntimeConfig?> getSessionRuntimeConfigByGroup(int groupId);
  Future<void> updateSessionRuntimeConfig(SessionRuntimeConfig config);
}
```

- [ ] **Step 4: Re-run the repository test**

Run: `fvm flutter test test/repositories/session_runtime_config_repository_test.dart`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add lib/models/session/session_runtime_config.dart lib/repositories/session_runtime_config_repository.dart lib/storage/chat_storage.dart lib/providers/chat_dependency_providers.dart test/repositories/session_runtime_config_repository_test.dart
git commit -m "feat: add session runtime config repository"
```

## Task 2: Add storage schema for `session_runtime_configs` and hard-cut upgrade path

**Files:**
- Modify: `lib/database/database_helper.dart`
- Modify: `lib/storage/web_chat_storage.dart`
- Test: `test/database/database_helper_test.dart`
- Test: `test/storage/web_chat_storage_test.dart`

- [ ] **Step 1: Write failing storage/schema assertions**

```dart
expect(source, contains(RegExp(r'CREATE TABLE IF NOT EXISTS session_runtime_configs \(')));
expect(source, isNot(contains('locked_provider_style')));
```

```dart
final configId = await helper.insertSessionRuntimeConfig(
  SessionRuntimeConfig(
    groupId: groupId,
    providerId: 'openai',
    modelId: 'gpt-5.4',
    providerStyle: ChatTurnProviderStyle.openaiResponses,
  ),
);
expect((await helper.getSessionRuntimeConfigByGroup(groupId))?.id, configId);
```

- [ ] **Step 2: Run targeted storage tests**

Run: `fvm flutter test test/database/database_helper_test.dart test/storage/web_chat_storage_test.dart`
Expected: FAIL because new table/APIs do not exist and old schema still mentions `locked_provider_style`

- [ ] **Step 3: Implement schema changes with a hard-cut upgrade**

```dart
version: 17,
```

```sql
CREATE TABLE IF NOT EXISTS session_runtime_configs (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  group_id INTEGER NOT NULL UNIQUE,
  provider_id TEXT NOT NULL,
  model_id TEXT NOT NULL,
  provider_style TEXT NOT NULL,
  updated_at INTEGER NOT NULL,
  FOREIGN KEY (group_id) REFERENCES chat_groups (id) ON DELETE CASCADE
)
```

For old versions, prefer hard reset of session tables rather than compatibility migration:

```dart
if (oldVersion < 17) {
  await db.execute('DROP TABLE IF EXISTS session_runtime_configs');
  await db.execute('DROP TABLE IF EXISTS session_runtime_markers');
  await db.execute('DROP TABLE IF EXISTS session_context_snapshots');
  await db.execute('DROP TABLE IF EXISTS chat_events');
  await db.execute('DROP TABLE IF EXISTS chat_turn_steps');
  await db.execute('DROP TABLE IF EXISTS chat_turns');
  await db.execute('DROP TABLE IF EXISTS messages');
  await db.execute('DROP TABLE IF EXISTS chat_groups');
  await _createAllTables(db);
}
```

- [ ] **Step 4: Re-run the storage tests**

Run: `fvm flutter test test/database/database_helper_test.dart test/storage/web_chat_storage_test.dart`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add lib/database/database_helper.dart lib/storage/web_chat_storage.dart test/database/database_helper_test.dart test/storage/web_chat_storage_test.dart
git commit -m "feat(db): add session runtime config storage"
```

## Task 3: Remove `lockedProviderStyle` from `ChatGroup` and test fixtures

**Files:**
- Modify: `lib/models/chat_group.dart`
- Modify: all direct `ChatGroup(...)` call sites in touched test files
- Test: `test/models/chat_group_test.dart`
- Test: `test/controllers/chat_controller_test.dart`

- [ ] **Step 1: Write/adjust failing `ChatGroup` model tests for the field removal**

```dart
final group = ChatGroup(title: 'Session');
expect(group.toMap().containsKey('locked_provider_style'), isFalse);
```

- [ ] **Step 2: Run focused model/controller tests**

Run: `fvm flutter test test/models/chat_group_test.dart test/controllers/chat_controller_test.dart`
Expected: FAIL because constructors and expectations still require `lockedProviderStyle`

- [ ] **Step 3: Remove the field from the model and fix the narrowest affected tests**

```dart
class ChatGroup {
  // remove lockedProviderStyle
}
```

- [ ] **Step 4: Re-run the focused tests**

Run: `fvm flutter test test/models/chat_group_test.dart test/controllers/chat_controller_test.dart`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add lib/models/chat_group.dart test/models/chat_group_test.dart test/controllers/chat_controller_test.dart
git commit -m "refactor: remove locked provider style from chat groups"
```

## Task 4: Add `SessionRuntimeConfigService` for draft and persisted session runtime state

**Files:**
- Create: `lib/services/session_runtime_config_service.dart`
- Modify: `lib/providers/chat_dependency_providers.dart`
- Modify: `lib/providers/chat_collection_providers.dart` or create a dedicated state provider file
- Test: `test/services/session_runtime_config_service_test.dart`

- [ ] **Step 1: Write failing service tests for draft-state initialization and restore**

```dart
test('initializes draft runtime from global defaults', () async {
  final service = SessionRuntimeConfigService(...);
  final draft = await service.createDraftRuntime();
  expect(draft.providerId, 'openai');
  expect(draft.modelId, 'gpt-5.4');
});

test('restores persisted runtime when selecting existing group', () async {
  final restored = await service.loadForGroup(groupId);
  expect(restored.providerId, 'anthropic');
});
```

- [ ] **Step 2: Run the service test**

Run: `fvm flutter test test/services/session_runtime_config_service_test.dart`
Expected: FAIL because the service and provider state do not exist

- [ ] **Step 3: Implement the service with explicit draft-session state**

```dart
class SessionRuntimeConfigService {
  Future<SessionRuntimeConfigDraft> initializeDraftFromDefaults();
  Future<void> updateDraft(...);
  Future<SessionRuntimeConfig?> loadPersisted(int groupId);
  Future<void> saveForGroup(SessionRuntimeConfig config);
}
```

Use a dedicated provider for current draft runtime instead of smuggling state into `ChatGroup`.

- [ ] **Step 4: Re-run the service test**

Run: `fvm flutter test test/services/session_runtime_config_service_test.dart`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add lib/services/session_runtime_config_service.dart lib/providers/chat_dependency_providers.dart lib/providers/chat_collection_providers.dart test/services/session_runtime_config_service_test.dart
git commit -m "feat: add session runtime config service"
```

## Task 5: Add `SessionLlmConfigResolver` and stop using global active selection as the runtime source

**Files:**
- Create: `lib/services/session_llm_config_resolver.dart`
- Modify: `lib/providers/chat_dependency_providers.dart`
- Modify: `lib/repositories/app_settings_repository.dart`
- Test: `test/services/session_llm_config_resolver_test.dart`
- Test: `test/repositories/app_settings_repository_test.dart`

- [ ] **Step 1: Write failing resolver tests**

```dart
test('builds LLMConfig from session runtime config and provider catalog', () async {
  final config = await resolver.resolveForGroup(groupId);
  expect(config.model, 'claude-sonnet');
  expect(config.additionalConfig['llm.selected_provider_id'], 'anthropic');
});
```

- [ ] **Step 2: Run the resolver and repository tests**

Run: `fvm flutter test test/services/session_llm_config_resolver_test.dart test/repositories/app_settings_repository_test.dart`
Expected: FAIL because there is no session-scoped resolver and repository still owns active runtime resolution

- [ ] **Step 3: Implement the resolver and shrink repository responsibility**

Keep in `AppSettingsRepository`:

- provider catalog CRUD
- global default selection CRUD

Move session runtime resolution out:

```dart
class SessionLlmConfigResolver {
  Future<LLMConfig> resolveCurrentSessionConfig();
  Future<LLMConfig> resolveForGroup(int? groupId);
}
```

- [ ] **Step 4: Re-run the resolver and repository tests**

Run: `fvm flutter test test/services/session_llm_config_resolver_test.dart test/repositories/app_settings_repository_test.dart`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add lib/services/session_llm_config_resolver.dart lib/providers/chat_dependency_providers.dart lib/repositories/app_settings_repository.dart test/services/session_llm_config_resolver_test.dart test/repositories/app_settings_repository_test.dart
git commit -m "refactor: resolve llm config from session runtime"
```

## Task 6: Update `ChatSessionCoordinator` to own session runtime switching and remove the old draft provider-style patch

**Files:**
- Modify: `lib/controllers/chat_session_coordinator.dart`
- Modify: `lib/controllers/chat_controller.dart`
- Test: `test/controllers/chat_controller_test.dart`

- [ ] **Step 1: Replace old coordinator tests with failing session-runtime tests**

```dart
test('createNewGroup initializes draft runtime from defaults', () async { ... });
test('selectGroup restores that groups runtime config', () async { ... });
test('switching groups swaps current runtime state', () async { ... });
```

- [ ] **Step 2: Run the controller/coordinator tests**

Run: `fvm flutter test test/controllers/chat_controller_test.dart`
Expected: FAIL because `createNewGroup()` and `selectGroup()` do not manage runtime config yet

- [ ] **Step 3: Implement coordinator changes**

Key changes:

- `createNewGroup()` initializes draft runtime via `SessionRuntimeConfigService`
- `selectGroup()` loads persisted runtime for the target group
- delete `syncDraftGroupProviderStyle()`
- remove old `_resolveCurrentProviderStyle()` helper

- [ ] **Step 4: Re-run the controller/coordinator tests**

Run: `fvm flutter test test/controllers/chat_controller_test.dart`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add lib/controllers/chat_session_coordinator.dart lib/controllers/chat_controller.dart test/controllers/chat_controller_test.dart
git commit -m "refactor: make session coordinator manage runtime configs"
```

## Task 7: Update `ChatSendCoordinator` to create/persist session runtime bindings and write correct turn runtime facts

**Files:**
- Modify: `lib/controllers/chat_send_coordinator.dart`
- Test: `test/controllers/chat_send_coordinator_test.dart`

- [ ] **Step 1: Write failing send-coordinator tests**

```dart
test('first send persists draft runtime config for the new group', () async { ... });
test('new turn stores providerStyle/modelName from session runtime', () async { ... });
test('attachment capability checks use current session runtime', () async { ... });
```

- [ ] **Step 2: Run the send coordinator tests**

Run: `fvm flutter test test/controllers/chat_send_coordinator_test.dart`
Expected: FAIL because send flow still derives provider style and config from global settings or `ChatGroup`

- [ ] **Step 3: Implement the send flow changes**

Key changes:

- when `currentGroup == null`, create a draft group without provider-style fields
- persist draft runtime config immediately after group insert
- use `SessionLlmConfigResolver` / `SessionRuntimeConfigService` for runtime lookups
- record `ChatTurn.providerStyle` and `ChatTurn.modelName` from the resolved session runtime

- [ ] **Step 4: Re-run the send coordinator tests**

Run: `fvm flutter test test/controllers/chat_send_coordinator_test.dart`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add lib/controllers/chat_send_coordinator.dart test/controllers/chat_send_coordinator_test.dart
git commit -m "refactor: drive send flow from session runtime config"
```

## Task 8: Update `ChatInput` model picker to read and write the current session runtime config

**Files:**
- Modify: `lib/widgets/chat_input.dart`
- Test: `test/widgets/chat_input_test.dart`

- [ ] **Step 1: Replace old chip-label tests with session-runtime expectations**

```dart
testWidgets('model chip shows the current sessions model', (tester) async { ... });
testWidgets('switching model updates only the current session runtime', (tester) async { ... });
```

- [ ] **Step 2: Run the widget test file**

Run: `fvm flutter test test/widgets/chat_input_test.dart`
Expected: FAIL because the widget still reads `AppSettingsRepository.getSelectionState()`

- [ ] **Step 3: Implement widget updates**

Key changes:

- chip label resolves from current session runtime config
- picker writes to `SessionRuntimeConfigService`
- global default selection is not mutated by session-local switches

- [ ] **Step 4: Re-run the widget test file**

Run: `fvm flutter test test/widgets/chat_input_test.dart`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add lib/widgets/chat_input.dart test/widgets/chat_input_test.dart
git commit -m "feat: scope chat input model picker to current session"
```

## Task 9: Move session-context, budget, and runtime capability reads onto the session runtime resolver

**Files:**
- Modify: `lib/services/session_context_service.dart`
- Modify: `lib/services/model_capability_resolver.dart`
- Modify: `lib/services/session_token_budget_service.dart` if call sites require plumbing updates
- Test: `test/services/session_context_service_test.dart`
- Test: `test/services/model_capability_resolver_test.dart`
- Test: `test/services/session_token_budget_service_test.dart`

- [ ] **Step 1: Add failing tests proving session runtime drives context/budget**

```dart
test('session context uses runtime config from current group instead of global selection', () async { ... });
test('capability resolver receives provider/model from session runtime config', () async { ... });
```

- [ ] **Step 2: Run the focused service tests**

Run: `fvm flutter test test/services/session_context_service_test.dart test/services/model_capability_resolver_test.dart test/services/session_token_budget_service_test.dart`
Expected: FAIL because services still depend on global active `LLMConfig`

- [ ] **Step 3: Implement session-scoped runtime plumbing**

Ensure upstream runtime resolution feeds all these services from `SessionLlmConfigResolver`.

- [ ] **Step 4: Re-run the focused service tests**

Run: `fvm flutter test test/services/session_context_service_test.dart test/services/model_capability_resolver_test.dart test/services/session_token_budget_service_test.dart`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add lib/services/session_context_service.dart lib/services/model_capability_resolver.dart lib/services/session_token_budget_service.dart test/services/session_context_service_test.dart test/services/model_capability_resolver_test.dart test/services/session_token_budget_service_test.dart
git commit -m "refactor: resolve context and capability from session runtime"
```

## Task 10: Update `TurnHarness` and runtime execution to stop reading `group.lockedProviderStyle`

**Files:**
- Modify: `lib/services/turn_harness.dart`
- Modify: `lib/models/llm/configurable_http_llm.dart`
- Test: `test/services/turn_harness_test.dart`

- [ ] **Step 1: Add failing tests for active API style resolution**

```dart
test('planner uses the turns provider style instead of group metadata', () async { ... });
```

- [ ] **Step 2: Run the harness test**

Run: `fvm flutter test test/services/turn_harness_test.dart`
Expected: FAIL because `activeApiStyle` still comes from `group.lockedProviderStyle`

- [ ] **Step 3: Implement the execution-path fix**

Replace:

```dart
activeApiStyle: group.lockedProviderStyle,
```

with runtime derived from:

- current turn provider style when present
- otherwise resolved current session runtime style

- [ ] **Step 4: Re-run the harness test**

Run: `fvm flutter test test/services/turn_harness_test.dart`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add lib/services/turn_harness.dart lib/models/llm/configurable_http_llm.dart test/services/turn_harness_test.dart
git commit -m "refactor: remove group provider-style runtime dependency"
```

## Task 11: Remove old UI/runtime references to `lockedProviderStyle` and clean up affected tests

**Files:**
- Modify: `lib/widgets/chat_drawer.dart`
- Modify: `lib/pages/chat_page.dart` if session info display depends on group metadata
- Modify: any touched debug/test helpers still constructing `ChatGroup(... lockedProviderStyle: ...)`
- Test: `test/widgets/chat_drawer_test.dart`
- Test: `test/pages/chat_page_test.dart`

- [ ] **Step 1: Write failing UI tests around current runtime display**

```dart
testWidgets('drawer shows provider label from session runtime config', (tester) async { ... });
```

- [ ] **Step 2: Run the focused widget/page tests**

Run: `fvm flutter test test/widgets/chat_drawer_test.dart test/pages/chat_page_test.dart`
Expected: FAIL because display code still reads `currentGroup.lockedProviderStyle`

- [ ] **Step 3: Implement the cleanup**

Remove remaining `lockedProviderStyle` references and replace visible labels with session runtime lookups.

- [ ] **Step 4: Re-run the focused widget/page tests**

Run: `fvm flutter test test/widgets/chat_drawer_test.dart test/pages/chat_page_test.dart`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add lib/widgets/chat_drawer.dart lib/pages/chat_page.dart test/widgets/chat_drawer_test.dart test/pages/chat_page_test.dart
git commit -m "refactor: show session runtime binding in chat surfaces"
```

## Task 12: Update docs and repo guidance for the new session-runtime rule

**Files:**
- Modify: `README.md`
- Modify: `AGENTS.md`
- Modify: `docs/architecture/project-architecture-overview.md` if runtime ownership is documented there

- [ ] **Step 1: Add failing doc-check assertion only if a doc test already exists**

If there is no doc test, skip the failing-test step and make a direct doc edit.

- [ ] **Step 2: Update documentation**

Document:

- global defaults seed new sessions only
- current session runtime config is the source of provider/model/style
- `lockedProviderStyle` is removed

- [ ] **Step 3: Sanity check changed docs**

Run: `rg -n "lockedProviderStyle|global active model|session runtime" README.md AGENTS.md docs/architecture/project-architecture-overview.md`
Expected: only intentional references remain

- [ ] **Step 4: Commit**

```bash
git add README.md AGENTS.md docs/architecture/project-architecture-overview.md
git commit -m "docs: describe session runtime config architecture"
```

## Task 13: Final targeted verification

**Files:**
- Modify: none unless verification uncovers regressions

- [ ] **Step 1: Run storage and repository verification**

Run: `fvm flutter test test/database/database_helper_test.dart test/repositories/session_runtime_config_repository_test.dart test/services/session_runtime_config_service_test.dart`
Expected: PASS

- [ ] **Step 2: Run coordinator and widget verification**

Run: `fvm flutter test test/controllers/chat_controller_test.dart test/controllers/chat_send_coordinator_test.dart test/widgets/chat_input_test.dart test/widgets/chat_drawer_test.dart`
Expected: PASS

- [ ] **Step 3: Run runtime/context verification**

Run: `fvm flutter test test/services/session_context_service_test.dart test/services/model_capability_resolver_test.dart test/services/session_token_budget_service_test.dart test/services/turn_harness_test.dart`
Expected: PASS

- [ ] **Step 4: Run targeted analyze on touched runtime/session files**

Run: `fvm flutter analyze lib/models/session lib/repositories lib/services lib/controllers lib/widgets/chat_input.dart lib/widgets/chat_drawer.dart`
Expected: PASS or only unrelated pre-existing warnings explicitly reviewed

- [ ] **Step 5: Commit any last verification fixes**

```bash
git add <only files changed by verification fixes>
git commit -m "test: finalize session runtime config rollout"
```
