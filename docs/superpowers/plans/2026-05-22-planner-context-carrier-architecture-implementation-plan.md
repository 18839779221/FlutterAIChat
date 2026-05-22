# Planner 上下文 Carrier 架构实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 把 provider wire 格式边界下沉到 `ApiStyleAdapter`，引入 `PlannerContextCarrier` sealed 类型替代 `List<ChatMessage>` 作为 planner 请求构造的输入。

**Architecture:** 入站时各 adapter 把 provider 响应原样存为 `assistantTurnSnapshot` event；出站时 `SessionContextService` 输出 `List<PlannerContextCarrier>`，adapter 把 raw carrier 逐字节回放、把 synthetic carrier 物化成 wire 形状。一次性切换，不留兼容路径。

**Tech Stack:** Dart 3.9, Flutter 3.35.7, sqflite, openai_dart 5.0.0, sealed classes + pattern matching。

**Spec：** `docs/superpowers/specs/2026-05-22-planner-context-carrier-architecture-design.md`

---

## 文件结构

### 新建
| 路径 | 职责 |
|---|---|
| `lib/models/context/planner_context_carrier.dart` | sealed 类型 + 三个子类 + estimatedTokens |
| `lib/models/llm/raw_assistant_token_estimator.dart` | 从 raw JSON 抽 content/reasoning/tool_args 字符并估 token |
| `lib/models/llm/planner_invariant_validator.dart` | 调用 adapter 前的预检 |
| `test/models/context/planner_context_carrier_test.dart` | carrier 序列化 + estimatedTokens 单测 |
| `test/models/llm/raw_assistant_token_estimator_test.dart` | 估算器单测 |
| `test/models/llm/planner_invariant_validator_test.dart` | 不变量校验单测 |
| `test/models/llm/adapters/sdk_chat_completions_roundtrip_test.dart` | SDK adapter 入/出站 round-trip 测试 |
| `test/models/llm/adapters/anthropic_messages_roundtrip_test.dart` | Anthropic adapter round-trip |
| `test/models/llm/adapters/responses_roundtrip_test.dart` | Responses adapter round-trip |

### 修改
| 路径 | 改动 |
|---|---|
| `lib/models/chat_event.dart` | enum 新增 `assistantTurnSnapshot` |
| `lib/repositories/chat_event_repository.dart` | 新增 `appendAssistantTurnSnapshot` |
| `lib/database/database_helper.dart` | version 13 + drop-recreate migration + `locked_provider_style` 字段 |
| `lib/models/chat_group.dart` | 新增 `lockedProviderStyle` 字段 |
| `lib/repositories/chat_group_repository.dart` | 写入 / 读取 `lockedProviderStyle` |
| `lib/models/llm/adapters/api_style_adapter.dart` | 加 `buildPlannerPayloadFromCarriers` / `extractRawAssistantMessage` / `assembleRawFromStreamingSnapshot` |
| `lib/models/llm/adapters/sdk_chat_completions_adapter.dart` | 实现新方法 |
| `lib/models/llm/adapters/anthropic_messages_adapter.dart` | 实现新方法 |
| `lib/models/llm/adapters/responses_adapter.dart` | 实现新方法 |
| `lib/models/llm/adapters/chat_completions_adapter.dart` (legacy) | 实现新方法 |
| `lib/services/turn_harness.dart` | 调 adapter 提取 raw，append snapshot event |
| `lib/services/session_context_service.dart` | `buildPlannerCarriers` 取代旧 `buildPlannerMessages` |
| `lib/services/session_context_projector.dart` | 删除 assistant 事件分支，泛化 `userInteractionResult` |
| `lib/services/model_context_item_encoder.dart` | 删除 assistantMessage / assistantToolUse 分支 |
| `lib/models/context/model_context_item.dart` | 删除 `assistantMessage` / `assistantToolUse` 工厂 |
| `lib/models/llm/adapters/sdk_message_converter.dart` | 删除合并逻辑 |
| `lib/services/session_token_budget_service.dart` | `estimateMessagesTokens` 加同名 `estimateCarriersTokens` |
| `lib/models/llm/configurable_http_llm.dart` | wire validator + 切到新 build 方法 |
| `lib/pages/settings_page.dart` (或 chat drawer) | 进行中会话禁用 provider 切换 |

### 删除（在 cleanup 阶段进行）
- `ApiStyleAdapter.buildPlannerPayload` 旧方法（接口 + 4 个实现）
- `ModelContextItem.assistantMessage` / `ModelContextItem.assistantToolUse` 工厂
- `SdkMessageConverter` 中 `_isAssistantPlainText` / `_isAssistantToolUse` / `_mergeAssistantWithToolUse`
- `session_context_projector.dart` 中 `assistantPlannerMessage` / `assistantToolCall` / `assistantQuestionPrompt` / `assistantReasoningDelta` / `assistantToolConfirmation` 等所有 assistant 事件分支
- 2026-05-22 给 `assistantQuestionPrompt` 加的 skip 分支

---

## Phase 1：类型骨架（Task 1-3）

### Task 1：`PlannerContextCarrier` sealed 类型

**Files:**
- Create: `lib/models/context/planner_context_carrier.dart`
- Test: `test/models/context/planner_context_carrier_test.dart`

- [ ] **Step 1.1：写失败测试**

```dart
// test/models/context/planner_context_carrier_test.dart
import 'package:ai_chat/models/chat_turn.dart';
import 'package:ai_chat/models/context/planner_context_carrier.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('SyntheticCarrier', () {
    test('system role 不带 toolCallId', () {
      const c = SyntheticCarrier.system('You are an agent.');
      expect(c.role, SyntheticRole.system);
      expect(c.content, 'You are an agent.');
      expect(c.toolCallId, isNull);
    });

    test('toolResult 必须带 toolCallId', () {
      const c = SyntheticCarrier.toolResult(
        toolCallId: 'call_1',
        content: 'OK',
      );
      expect(c.role, SyntheticRole.toolResult);
      expect(c.toolCallId, 'call_1');
    });

    test('estimatedTokens 是 content 字符数 / 4 取整', () {
      const c = SyntheticCarrier.user('hello world');
      expect(c.estimatedTokens, 'hello world'.length ~/ 4);
    });
  });

  group('RawAssistantCarrier', () {
    test('保留 apiStyle + rawJson', () {
      final c = RawAssistantCarrier(
        apiStyle: ChatTurnProviderStyle.openaiChatCompletions,
        rawJson: const {'role': 'assistant', 'content': 'hi'},
      );
      expect(c.apiStyle, ChatTurnProviderStyle.openaiChatCompletions);
      expect(c.rawJson['content'], 'hi');
    });
  });
}
```

- [ ] **Step 1.2：跑测试确认失败**

```bash
fvm flutter test test/models/context/planner_context_carrier_test.dart
```
Expected: 编译失败 / `Target of URI doesn't exist`

- [ ] **Step 1.3：写最小实现**

```dart
// lib/models/context/planner_context_carrier.dart
import '../chat_turn.dart';

enum SyntheticRole { system, user, toolResult }

sealed class PlannerContextCarrier {
  const PlannerContextCarrier();
  int get estimatedTokens;
}

class SyntheticCarrier extends PlannerContextCarrier {
  final SyntheticRole role;
  final String content;
  final String? toolCallId;

  const SyntheticCarrier._({
    required this.role,
    required this.content,
    this.toolCallId,
  });

  const SyntheticCarrier.system(String content)
      : this._(role: SyntheticRole.system, content: content);
  const SyntheticCarrier.user(String content)
      : this._(role: SyntheticRole.user, content: content);
  const SyntheticCarrier.toolResult({
    required String toolCallId,
    required String content,
  }) : this._(
          role: SyntheticRole.toolResult,
          content: content,
          toolCallId: toolCallId,
        );

  @override
  int get estimatedTokens => content.length ~/ 4;
}

class RawAssistantCarrier extends PlannerContextCarrier {
  final ChatTurnProviderStyle apiStyle;
  final Map<String, dynamic> rawJson;

  const RawAssistantCarrier({
    required this.apiStyle,
    required this.rawJson,
  });

  @override
  int get estimatedTokens {
    // 占位：Task 2 完成后切到 RawAssistantTokenEstimator
    final encoded = rawJson.toString();
    return encoded.length ~/ 4;
  }
}
```

- [ ] **Step 1.4：跑测试确认通过**

```bash
fvm flutter test test/models/context/planner_context_carrier_test.dart
```
Expected: All tests passed

- [ ] **Step 1.5：commit**

```bash
git add lib/models/context/planner_context_carrier.dart \
        test/models/context/planner_context_carrier_test.dart
git commit -m "feat(planner): add PlannerContextCarrier sealed type"
```

---

### Task 2：`RawAssistantTokenEstimator`

**Files:**
- Create: `lib/models/llm/raw_assistant_token_estimator.dart`
- Test: `test/models/llm/raw_assistant_token_estimator_test.dart`
- Modify: `lib/models/context/planner_context_carrier.dart`（让 `RawAssistantCarrier.estimatedTokens` 走估算器）

- [ ] **Step 2.1：写失败测试**

```dart
// test/models/llm/raw_assistant_token_estimator_test.dart
import 'package:ai_chat/models/llm/raw_assistant_token_estimator.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const estimator = RawAssistantTokenEstimator();

  test('累加 content 字符数', () {
    final tokens = estimator.estimate(const {
      'role': 'assistant',
      'content': 'hello world',
    });
    expect(tokens, 'hello world'.length ~/ 4);
  });

  test('累加 reasoning_content', () {
    final tokens = estimator.estimate(const {
      'role': 'assistant',
      'content': 'final answer',
      'reasoning_content': 'think hard',
    });
    expect(tokens, ('final answer'.length + 'think hard'.length) ~/ 4);
  });

  test('累加 tool_calls function.arguments', () {
    final tokens = estimator.estimate(const {
      'role': 'assistant',
      'content': null,
      'tool_calls': [
        {
          'id': 'c1',
          'function': {'name': 'search', 'arguments': '{"q":"x"}'},
        },
      ],
    });
    expect(tokens, '{"q":"x"}'.length ~/ 4);
  });

  test('未知字段忽略，不报错', () {
    final tokens = estimator.estimate(const {
      'role': 'assistant',
      'content': 'hi',
      'future_provider_field': 'whatever',
    });
    expect(tokens, 'hi'.length ~/ 4);
  });
}
```

- [ ] **Step 2.2：跑测试确认失败**

```bash
fvm flutter test test/models/llm/raw_assistant_token_estimator_test.dart
```
Expected: FAIL（文件不存在）

- [ ] **Step 2.3：实现估算器**

```dart
// lib/models/llm/raw_assistant_token_estimator.dart

/// 从 provider 原样 assistant message JSON 中抽出文本字段累加估 token。
///
/// 故意只认 OpenAI/DeepSeek/Anthropic 都常见的字段，未知字段忽略——
/// 偏差几个 token 可接受，但不要因为新字段崩溃。
class RawAssistantTokenEstimator {
  const RawAssistantTokenEstimator();

  int estimate(Map<String, dynamic> rawJson) {
    var chars = 0;

    final content = rawJson['content'];
    if (content is String) chars += content.length;
    if (content is List) {
      for (final part in content) {
        if (part is Map) {
          final text = part['text'];
          if (text is String) chars += text.length;
        }
      }
    }

    final reasoning = rawJson['reasoning_content'];
    if (reasoning is String) chars += reasoning.length;

    final toolCalls = rawJson['tool_calls'];
    if (toolCalls is List) {
      for (final tc in toolCalls) {
        if (tc is Map) {
          final fn = tc['function'];
          if (fn is Map) {
            final args = fn['arguments'];
            if (args is String) chars += args.length;
          }
        }
      }
    }

    return chars ~/ 4;
  }
}
```

- [ ] **Step 2.4：切 `RawAssistantCarrier.estimatedTokens` 走估算器**

```dart
// lib/models/context/planner_context_carrier.dart 修改 RawAssistantCarrier
import '../llm/raw_assistant_token_estimator.dart';   // 加 import

// ... RawAssistantCarrier 类内：
  static const _estimator = RawAssistantTokenEstimator();

  @override
  int get estimatedTokens => _estimator.estimate(rawJson);
```

- [ ] **Step 2.5：跑测试**

```bash
fvm flutter test test/models/llm/raw_assistant_token_estimator_test.dart \
                 test/models/context/planner_context_carrier_test.dart
```
Expected: All tests passed

- [ ] **Step 2.6：commit**

```bash
git add lib/models/llm/raw_assistant_token_estimator.dart \
        lib/models/context/planner_context_carrier.dart \
        test/models/llm/raw_assistant_token_estimator_test.dart
git commit -m "feat(planner): add RawAssistantTokenEstimator"
```

---

### Task 3：`PlannerInvariantValidator`

**Files:**
- Create: `lib/models/llm/planner_invariant_validator.dart`
- Test: `test/models/llm/planner_invariant_validator_test.dart`

- [ ] **Step 3.1：写失败测试**

```dart
// test/models/llm/planner_invariant_validator_test.dart
import 'package:ai_chat/models/chat_turn.dart';
import 'package:ai_chat/models/context/planner_context_carrier.dart';
import 'package:ai_chat/models/llm/planner_invariant_validator.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const validator = PlannerInvariantValidator();
  const active = ChatTurnProviderStyle.openaiChatCompletions;

  test('全 synthetic 列表通过', () {
    validator.validate(
      carriers: const [
        SyntheticCarrier.system('sys'),
        SyntheticCarrier.user('hi'),
      ],
      activeApiStyle: active,
      currentTurnRunning: false,
    );
    // 不抛即通过
  });

  test('raw apiStyle 不匹配抛 InconsistentProviderStateError', () {
    expect(
      () => validator.validate(
        carriers: [
          const SyntheticCarrier.user('hi'),
          RawAssistantCarrier(
            apiStyle: ChatTurnProviderStyle.anthropicMessages,
            rawJson: const {'role': 'assistant'},
          ),
        ],
        activeApiStyle: active,
        currentTurnRunning: false,
      ),
      throwsA(isA<InconsistentProviderStateError>()),
    );
  });

  test('completed turn 中 tool_call 必须有配对 toolResult', () {
    expect(
      () => validator.validate(
        carriers: [
          const SyntheticCarrier.user('hi'),
          RawAssistantCarrier(
            apiStyle: active,
            rawJson: const {
              'role': 'assistant',
              'tool_calls': [
                {'id': 'call_1', 'function': {'name': 's', 'arguments': '{}'}},
              ],
            },
          ),
          // 没有 toolResult 配对
        ],
        activeApiStyle: active,
        currentTurnRunning: false,
      ),
      throwsA(isA<ToolCallPairingError>()),
    );
  });

  test('running turn 允许 tool_call 暂未配对', () {
    validator.validate(
      carriers: [
        const SyntheticCarrier.user('hi'),
        RawAssistantCarrier(
          apiStyle: active,
          rawJson: const {
            'role': 'assistant',
            'tool_calls': [
              {'id': 'call_1', 'function': {'name': 's', 'arguments': '{}'}},
            ],
          },
        ),
      ],
      activeApiStyle: active,
      currentTurnRunning: true,
    );
    // 不抛即通过
  });

  test('多 tool_calls 全部配对通过', () {
    validator.validate(
      carriers: [
        const SyntheticCarrier.user('hi'),
        RawAssistantCarrier(
          apiStyle: active,
          rawJson: const {
            'role': 'assistant',
            'tool_calls': [
              {'id': 'c1', 'function': {'name': 's', 'arguments': '{}'}},
              {'id': 'c2', 'function': {'name': 's', 'arguments': '{}'}},
            ],
          },
        ),
        const SyntheticCarrier.toolResult(toolCallId: 'c1', content: 'r1'),
        const SyntheticCarrier.toolResult(toolCallId: 'c2', content: 'r2'),
      ],
      activeApiStyle: active,
      currentTurnRunning: false,
    );
  });
}
```

- [ ] **Step 3.2：跑测试确认失败**

```bash
fvm flutter test test/models/llm/planner_invariant_validator_test.dart
```
Expected: FAIL（文件不存在）

- [ ] **Step 3.3：实现 validator**

```dart
// lib/models/llm/planner_invariant_validator.dart
import '../chat_turn.dart';
import '../context/planner_context_carrier.dart';

class InconsistentProviderStateError extends StateError {
  InconsistentProviderStateError(super.message);
}

class ToolCallPairingError extends StateError {
  ToolCallPairingError(super.message);
}

class PlannerInvariantValidator {
  const PlannerInvariantValidator();

  void validate({
    required List<PlannerContextCarrier> carriers,
    required ChatTurnProviderStyle activeApiStyle,
    required bool currentTurnRunning,
  }) {
    final pendingToolCallIds = <String>{};

    for (var i = 0; i < carriers.length; i++) {
      final carrier = carriers[i];

      switch (carrier) {
        case RawAssistantCarrier(:final apiStyle, :final rawJson):
          if (apiStyle != activeApiStyle) {
            throw InconsistentProviderStateError(
              'carriers[$i] apiStyle=$apiStyle but active=$activeApiStyle',
            );
          }
          final ids = _extractToolCallIds(rawJson);
          pendingToolCallIds.addAll(ids);

        case SyntheticCarrier(role: SyntheticRole.toolResult, :final toolCallId):
          if (toolCallId != null) {
            pendingToolCallIds.remove(toolCallId);
          }

        case SyntheticCarrier():
          break;
      }
    }

    if (!currentTurnRunning && pendingToolCallIds.isNotEmpty) {
      throw ToolCallPairingError(
        'unpaired tool_call_ids: ${pendingToolCallIds.toList()}',
      );
    }
  }

  List<String> _extractToolCallIds(Map<String, dynamic> rawJson) {
    final toolCalls = rawJson['tool_calls'];
    if (toolCalls is! List) return const [];
    return [
      for (final tc in toolCalls)
        if (tc is Map && tc['id'] is String) tc['id'] as String,
    ];
  }
}
```

- [ ] **Step 3.4：跑测试**

```bash
fvm flutter test test/models/llm/planner_invariant_validator_test.dart
```
Expected: All tests passed

- [ ] **Step 3.5：commit**

```bash
git add lib/models/llm/planner_invariant_validator.dart \
        test/models/llm/planner_invariant_validator_test.dart
git commit -m "feat(planner): add PlannerInvariantValidator"
```

---

## Phase 2：DB & 事件 schema（Task 4-5）

### Task 4：DB v13 迁移 + `chat_events.event_type` 接受 `assistantTurnSnapshot` + `chat_groups.locked_provider_style`

**Files:**
- Modify: `lib/database/database_helper.dart`
- Modify: `lib/models/chat_event.dart`
- Modify: `lib/models/chat_group.dart`

- [ ] **Step 4.1：在 `ChatEventType` enum 加 `assistantTurnSnapshot`**

```dart
// lib/models/chat_event.dart 修改 enum
enum ChatEventType {
  userMessage,
  assistantPlannerMessage,
  assistantReasoningDelta,
  assistantTextDelta,
  assistantTextFinal,
  assistantToolCall,
  assistantToolConfirmation,
  assistantQuestionPrompt,
  assistantTurnSnapshot,    // ← 新增
  toolExecutionStarted,
  toolResult,
  userInteractionResult,
  toolError,
  turnStatus,
  finalAnswer,
  error,
}
```

确认 `ChatEvent` 类的 `toJson` / `fromJson` 使用 `enum.name` 自动覆盖，无需额外改动。如果有 hardcoded switch 用 grep 找一遍：

```bash
grep -rn 'ChatEventType\.' lib/ | grep -v 'assistantTurnSnapshot' | wc -l
```

- [ ] **Step 4.2：升 DB version 至 13，写 onUpgrade 分支（drop-recreate 会话表）**

修改 `lib/database/database_helper.dart`：

```dart
// 第 48 行附近
        version: 13,   // 从 12 升到 13

// 在 onUpgrade 内 oldVersion < 12 之后追加：
          if (oldVersion < 13) {
            Logger.i(_tag, 'v13 migration: drop conversation tables');
            await db.execute('DROP TABLE IF EXISTS chat_events');
            await db.execute('DROP TABLE IF EXISTS chat_turn_steps');
            await db.execute('DROP TABLE IF EXISTS chat_turns');
            await db.execute('DROP TABLE IF EXISTS messages');
            await db.execute('DROP TABLE IF EXISTS session_context_snapshots');
            await db.execute('DROP TABLE IF EXISTS chat_groups');

            // 按新 schema 重建 chat_groups（含 locked_provider_style）
            await db.execute('''
              CREATE TABLE chat_groups (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                title TEXT NOT NULL,
                created_at INTEGER NOT NULL,
                last_message_at INTEGER NOT NULL,
                system_prompt TEXT,
                is_summarized INTEGER NOT NULL DEFAULT 0,
                locked_provider_style TEXT NOT NULL
              )
            ''');
            // messages 表保留兼容已删除 v3 数据迁移路径
            await db.execute('''
              CREATE TABLE messages (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                group_id INTEGER NOT NULL,
                text TEXT NOT NULL,
                role TEXT NOT NULL,
                timestamp INTEGER NOT NULL,
                status TEXT NOT NULL DEFAULT 'initial',
                reasoning_content TEXT,
                tool_call_id TEXT,
                payload_json TEXT,
                reference_json TEXT,
                FOREIGN KEY (group_id) REFERENCES chat_groups (id) ON DELETE CASCADE
              )
            ''');
            await _createAgentLoopTables(db);
            await _createSessionContextSnapshotTable(db);
          }
```

并在 `onCreate` 内的 `chat_groups` 建表语句也加上 `locked_provider_style TEXT NOT NULL`。

- [ ] **Step 4.3：`ChatGroup` 模型加字段**

```dart
// lib/models/chat_group.dart
class ChatGroup {
  // ... 已有字段 ...
  final String lockedProviderStyle;   // 新增

  ChatGroup({
    // ... 已有 ...
    required this.lockedProviderStyle,
  });

  factory ChatGroup.fromMap(Map<String, dynamic> map) => ChatGroup(
        // ... 已有 ...
        lockedProviderStyle: map['locked_provider_style'] as String,
      );

  Map<String, dynamic> toMap() => {
        // ... 已有 ...
        'locked_provider_style': lockedProviderStyle,
      };
}
```

`ChatGroupRepository.create` / `insert` 调用处同步加 `lockedProviderStyle` 参数（默认值由调用方传，Task 21 在 UI 接入）。临时让默认值为 `'openaiChatCompletions'` 保证本步骤能跑通。

- [ ] **Step 4.4：跑测试确认 schema 改动不破坏既有测试**

```bash
fvm flutter test test/database/database_helper_test.dart
```
Expected: schema 相关测试可能失败——预期，因为我们故意 drop。修测试断言（`v11` 测试 → 改成 `v13` 行为预期）。

- [ ] **Step 4.5：commit**

```bash
git add lib/database/database_helper.dart lib/models/chat_event.dart \
        lib/models/chat_group.dart test/database/database_helper_test.dart
git commit -m "feat(db): bump schema v13 — add lockedProviderStyle, assistantTurnSnapshot event"
```

---

### Task 5：`ChatEventRepository.appendAssistantTurnSnapshot`

**Files:**
- Modify: `lib/repositories/chat_event_repository.dart`
- Test: `test/repositories/chat_event_repository_test.dart`

- [ ] **Step 5.1：写失败测试**

把以下用例追加到 `chat_event_repository_test.dart`：

```dart
test('appendAssistantTurnSnapshot 写入正确字段', () async {
  final repo = await _setupTestRepo();
  final event = await repo.appendAssistantTurnSnapshot(
    turnId: 1,
    groupId: 1,
    apiStyle: ChatTurnProviderStyle.openaiChatCompletions,
    rawAssistantMessageJson: const {
      'role': 'assistant',
      'content': 'hi',
      'tool_calls': [
        {'id': 'c1', 'function': {'name': 's', 'arguments': '{}'}},
      ],
    },
  );
  expect(event.eventType, ChatEventType.assistantTurnSnapshot);
  expect(event.role, MessageRole.assistant);
  expect(event.payloadJson?['apiStyle'], 'openaiChatCompletions');
  expect(event.payloadJson?['rawAssistantMessage'], isA<Map>());
});
```

- [ ] **Step 5.2：跑测试确认失败**

```bash
fvm flutter test test/repositories/chat_event_repository_test.dart \
  --plain-name 'appendAssistantTurnSnapshot'
```
Expected: FAIL（方法不存在）

- [ ] **Step 5.3：实现 append 方法**

```dart
// lib/repositories/chat_event_repository.dart 在 appendAssistantTextFinal 之后追加：
Future<ChatEvent> appendAssistantTurnSnapshot({
  required int turnId,
  required int groupId,
  required ChatTurnProviderStyle apiStyle,
  required Map<String, dynamic> rawAssistantMessageJson,
}) {
  return _appendEvent(
    turnId: turnId,
    groupId: groupId,
    eventType: ChatEventType.assistantTurnSnapshot,
    role: MessageRole.assistant,
    content: '',
    payloadJson: {
      'apiStyle': apiStyle.name,
      'rawAssistantMessage': rawAssistantMessageJson,
    },
  );
}
```

`ChatTurnProviderStyle` 已在 `lib/models/chat_turn.dart` 定义，加 import。

- [ ] **Step 5.4：跑测试**

```bash
fvm flutter test test/repositories/chat_event_repository_test.dart
```
Expected: All tests passed

- [ ] **Step 5.5：commit**

```bash
git add lib/repositories/chat_event_repository.dart \
        test/repositories/chat_event_repository_test.dart
git commit -m "feat(repo): add appendAssistantTurnSnapshot"
```

---

## Phase 3：入站捕获（Task 6-10）

### Task 6：`ApiStyleAdapter` 契约新增三个方法（默认抛 `UnimplementedError`）

**Files:**
- Modify: `lib/models/llm/adapters/api_style_adapter.dart`

不写测试——纯抽象签名变化，后续 Task 7-9 各 adapter 实现时再覆盖具体测试。

- [ ] **Step 6.1：在 abstract class 中追加方法签名**

```dart
// lib/models/llm/adapters/api_style_adapter.dart 在 extractNonStreamText 之后追加：

  /// 从非流式 planner 响应 body 中提取原样 assistant message JSON。
  /// 返回 null 表示响应里没有 assistant 内容可保存（例如空 choices）。
  Map<String, dynamic>? extractRawAssistantMessage(
    Map<String, dynamic> responsePayload,
  );

  /// 从流式累积器拼出 provider 原样 assistant message JSON。
  /// 流式场景 provider 不会一次发完整 message，由 adapter 把
  /// 已累积的 text/reasoning/tool_calls 合成符合 provider wire 形状的 map。
  Map<String, dynamic>? assembleRawFromStreamingSnapshot(
    StreamingDecisionAccumulatorSnapshot snapshot,
  );

  /// 从一组 PlannerContextCarrier 构造完整 planner 请求 payload。
  /// 入参顺序就是 wire 上 messages 的顺序。
  Map<String, dynamic> buildPlannerPayloadFromCarriers({
    required List<PlannerContextCarrier> carriers,
    required ChatConfig config,
    required String modelName,
    required List<PlannerToolOption> availableTools,
    required bool parallelToolCalls,
    LlmRequestOptions requestOptions,
  });
```

加 imports：

```dart
import '../../context/planner_context_carrier.dart';
import '../streaming_decision_accumulator.dart';
```

如果 `StreamingDecisionAccumulator` 没有暴露 `Snapshot` 类型，先在 `streaming_decision_accumulator.dart` 加：

```dart
class StreamingDecisionAccumulatorSnapshot {
  final String? text;
  final String? reasoning;
  final List<StreamingToolCallDraft> toolCalls;
  final Map<String, dynamic> providerState;
  const StreamingDecisionAccumulatorSnapshot({
    required this.text,
    required this.reasoning,
    required this.toolCalls,
    required this.providerState,
  });
}

class StreamingToolCallDraft {
  final String? id;
  final String? toolName;
  final String argumentsBuffer;
  final int sequence;
  final bool isDone;
  const StreamingToolCallDraft({
    required this.id,
    required this.toolName,
    required this.argumentsBuffer,
    required this.sequence,
    required this.isDone,
  });
}
```

并在 `StreamingDecisionAccumulator` 加 `currentSnapshot()` 返回上面的快照（复用现有累积字段）。

- [ ] **Step 6.2：四个实现类临时抛 `UnimplementedError`**

```dart
// 在每个 adapter 实现里加：
@override
Map<String, dynamic>? extractRawAssistantMessage(
  Map<String, dynamic> responsePayload,
) => throw UnimplementedError('Task 7-9 will implement this');

@override
Map<String, dynamic>? assembleRawFromStreamingSnapshot(
  StreamingDecisionAccumulatorSnapshot snapshot,
) => throw UnimplementedError('Task 7-9 will implement this');

@override
Map<String, dynamic> buildPlannerPayloadFromCarriers({...}) =>
    throw UnimplementedError('Task 12-14 will implement this');
```

4 个实现类：
- `lib/models/llm/adapters/sdk_chat_completions_adapter.dart`
- `lib/models/llm/adapters/chat_completions_adapter.dart`（legacy）
- `lib/models/llm/adapters/anthropic_messages_adapter.dart`
- `lib/models/llm/adapters/responses_adapter.dart`

- [ ] **Step 6.3：dart analyze 跑通**

```bash
fvm flutter analyze 2>&1 | grep -E 'error' | head -10
```
Expected: 0 errors

- [ ] **Step 6.4：commit**

```bash
git add lib/models/llm/adapters/ lib/models/llm/streaming_decision_accumulator.dart
git commit -m "feat(adapter): extend ApiStyleAdapter with carrier-aware methods"
```

---

### Task 7：`SdkChatCompletionsAdapter.extractRawAssistantMessage` + `assembleRawFromStreamingSnapshot`

**Files:**
- Modify: `lib/models/llm/adapters/sdk_chat_completions_adapter.dart`
- Create: `test/models/llm/adapters/sdk_chat_completions_roundtrip_test.dart`

- [ ] **Step 7.1：写失败测试**

```dart
// test/models/llm/adapters/sdk_chat_completions_roundtrip_test.dart
import 'package:ai_chat/models/llm/adapters/sdk_chat_completions_adapter.dart';
import 'package:ai_chat/models/llm/streaming_decision_accumulator.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('SdkChatCompletionsAdapter.extractRawAssistantMessage', () {
    const adapter = SdkChatCompletionsAdapter();

    test('保留 content + tool_calls + reasoning_content 三类字段', () {
      final raw = adapter.extractRawAssistantMessage(const {
        'id': 'resp_1',
        'choices': [
          {
            'index': 0,
            'message': {
              'role': 'assistant',
              'content': 'Let me search',
              'reasoning_content': 'think first',
              'tool_calls': [
                {
                  'id': 'call_1',
                  'type': 'function',
                  'function': {'name': 'search', 'arguments': '{"q":"x"}'},
                },
              ],
            },
          },
        ],
      });
      expect(raw, isNotNull);
      expect(raw!['role'], 'assistant');
      expect(raw['content'], 'Let me search');
      expect(raw['reasoning_content'], 'think first');
      expect((raw['tool_calls'] as List).first['id'], 'call_1');
    });

    test('空 choices 返回 null', () {
      final raw = adapter.extractRawAssistantMessage(const {'choices': []});
      expect(raw, isNull);
    });
  });

  group('SdkChatCompletionsAdapter.assembleRawFromStreamingSnapshot', () {
    const adapter = SdkChatCompletionsAdapter();

    test('累积 text + reasoning + 一条 tool_call 拼成完整 message', () {
      final snapshot = StreamingDecisionAccumulatorSnapshot(
        text: 'final',
        reasoning: 'why',
        toolCalls: const [
          StreamingToolCallDraft(
            id: 'c1',
            toolName: 's',
            argumentsBuffer: '{"q":"x"}',
            sequence: 0,
            isDone: true,
          ),
        ],
        providerState: const {},
      );
      final raw = adapter.assembleRawFromStreamingSnapshot(snapshot);
      expect(raw!['role'], 'assistant');
      expect(raw['content'], 'final');
      expect(raw['reasoning_content'], 'why');
      final tc = (raw['tool_calls'] as List).first as Map;
      expect(tc['id'], 'c1');
      expect(tc['type'], 'function');
      expect((tc['function'] as Map)['arguments'], '{"q":"x"}');
    });

    test('流式与非流式同等内容的 raw 字段相等', () {
      final fromStream = adapter.assembleRawFromStreamingSnapshot(
        const StreamingDecisionAccumulatorSnapshot(
          text: 'hi',
          reasoning: null,
          toolCalls: [],
          providerState: {},
        ),
      );
      final fromNonStream = adapter.extractRawAssistantMessage(const {
        'choices': [
          {'message': {'role': 'assistant', 'content': 'hi'}},
        ],
      });
      expect(fromStream, fromNonStream);
    });
  });
}
```

- [ ] **Step 7.2：跑测试确认失败**

```bash
fvm flutter test test/models/llm/adapters/sdk_chat_completions_roundtrip_test.dart
```
Expected: FAIL（`UnimplementedError`）

- [ ] **Step 7.3：实现两个方法**

```dart
// lib/models/llm/adapters/sdk_chat_completions_adapter.dart

@override
Map<String, dynamic>? extractRawAssistantMessage(
  Map<String, dynamic> responsePayload,
) {
  final choices = responsePayload['choices'];
  if (choices is! List || choices.isEmpty) return null;
  final first = choices.first;
  if (first is! Map) return null;
  final message = first['message'];
  if (message is! Map) return null;
  // 不动 provider 给的字段，原样返回（cast 一次保证类型）
  return Map<String, dynamic>.from(message);
}

@override
Map<String, dynamic>? assembleRawFromStreamingSnapshot(
  StreamingDecisionAccumulatorSnapshot snapshot,
) {
  final hasContent = (snapshot.text ?? '').isNotEmpty;
  final hasReasoning = (snapshot.reasoning ?? '').isNotEmpty;
  final hasToolCalls = snapshot.toolCalls.isNotEmpty;
  if (!hasContent && !hasReasoning && !hasToolCalls) return null;

  return <String, dynamic>{
    'role': 'assistant',
    if (hasContent) 'content': snapshot.text else 'content': null,
    if (hasReasoning) 'reasoning_content': snapshot.reasoning,
    if (hasToolCalls)
      'tool_calls': [
        for (final tc in snapshot.toolCalls)
          {
            if (tc.id != null) 'id': tc.id,
            'type': 'function',
            'function': {
              'name': tc.toolName ?? '',
              'arguments': tc.argumentsBuffer,
            },
          },
      ],
  };
}
```

- [ ] **Step 7.4：跑测试**

```bash
fvm flutter test test/models/llm/adapters/sdk_chat_completions_roundtrip_test.dart
```
Expected: All tests passed

- [ ] **Step 7.5：commit**

```bash
git add lib/models/llm/adapters/sdk_chat_completions_adapter.dart \
        test/models/llm/adapters/sdk_chat_completions_roundtrip_test.dart
git commit -m "feat(adapter): SdkChatCompletionsAdapter extract/assemble raw"
```

---

### Task 8：`AnthropicMessagesAdapter.extractRawAssistantMessage` + `assembleRawFromStreamingSnapshot`

**Files:**
- Modify: `lib/models/llm/adapters/anthropic_messages_adapter.dart`
- Create: `test/models/llm/adapters/anthropic_messages_roundtrip_test.dart`

Anthropic wire 形状：assistant message 的 `content` 是 `List<ContentBlock>`，每个 block 是 `{type:'text', text:...}` 或 `{type:'tool_use', id, name, input}` 或 `{type:'thinking', thinking:..., signature:...}`。

- [ ] **Step 8.1：写失败测试**

```dart
// test/models/llm/adapters/anthropic_messages_roundtrip_test.dart
import 'package:ai_chat/models/llm/adapters/anthropic_messages_adapter.dart';
import 'package:ai_chat/models/llm/streaming_decision_accumulator.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AnthropicMessagesAdapter.extractRawAssistantMessage', () {
    const adapter = AnthropicMessagesAdapter();

    test('保留 content 列表（text + tool_use + thinking）', () {
      final raw = adapter.extractRawAssistantMessage(const {
        'id': 'msg_1',
        'role': 'assistant',
        'content': [
          {'type': 'thinking', 'thinking': 'plan', 'signature': 'sig_xyz'},
          {'type': 'text', 'text': 'Let me search'},
          {
            'type': 'tool_use',
            'id': 'toolu_1',
            'name': 'search',
            'input': {'q': 'x'},
          },
        ],
      });
      expect(raw, isNotNull);
      expect(raw!['role'], 'assistant');
      final blocks = raw['content'] as List;
      expect(blocks.length, 3);
      expect(blocks[0]['signature'], 'sig_xyz');
      expect(blocks[2]['id'], 'toolu_1');
    });

    test('content 空列表返回 null', () {
      final raw = adapter.extractRawAssistantMessage(const {
        'role': 'assistant',
        'content': [],
      });
      expect(raw, isNull);
    });
  });

  group('AnthropicMessagesAdapter.assembleRawFromStreamingSnapshot', () {
    const adapter = AnthropicMessagesAdapter();

    test('text + tool_use 拼成 content blocks 列表', () {
      final raw = adapter.assembleRawFromStreamingSnapshot(
        const StreamingDecisionAccumulatorSnapshot(
          text: 'searching',
          reasoning: null,
          toolCalls: [
            StreamingToolCallDraft(
              id: 'toolu_1',
              toolName: 'search',
              argumentsBuffer: '{"q":"x"}',
              sequence: 0,
              isDone: true,
            ),
          ],
          providerState: {},
        ),
      );
      expect(raw!['role'], 'assistant');
      final blocks = raw['content'] as List;
      // 顺序：text 在前，tool_use 在后
      expect(blocks[0]['type'], 'text');
      expect(blocks[0]['text'], 'searching');
      expect(blocks[1]['type'], 'tool_use');
      expect(blocks[1]['id'], 'toolu_1');
      expect(blocks[1]['name'], 'search');
      expect(blocks[1]['input'], {'q': 'x'});
    });

    test('reasoning 累积成 thinking block（保留 signature 占位）', () {
      // signature 在流式时由 provider state 给出；snapshot 没有就空字符串
      final raw = adapter.assembleRawFromStreamingSnapshot(
        const StreamingDecisionAccumulatorSnapshot(
          text: 'hi',
          reasoning: 'think',
          toolCalls: [],
          providerState: {'anthropic_thinking_signature': 'sig_z'},
        ),
      );
      final blocks = raw!['content'] as List;
      expect(blocks[0]['type'], 'thinking');
      expect(blocks[0]['thinking'], 'think');
      expect(blocks[0]['signature'], 'sig_z');
    });
  });
}
```

- [ ] **Step 8.2：跑测试确认失败**

```bash
fvm flutter test test/models/llm/adapters/anthropic_messages_roundtrip_test.dart
```
Expected: FAIL

- [ ] **Step 8.3：实现两个方法**

```dart
// lib/models/llm/adapters/anthropic_messages_adapter.dart

@override
Map<String, dynamic>? extractRawAssistantMessage(
  Map<String, dynamic> responsePayload,
) {
  // Anthropic Messages 响应顶层就是 assistant message
  final role = responsePayload['role'];
  if (role != 'assistant') return null;
  final content = responsePayload['content'];
  if (content is! List || content.isEmpty) return null;
  return <String, dynamic>{
    'role': 'assistant',
    'content': List<dynamic>.from(content),
  };
}

@override
Map<String, dynamic>? assembleRawFromStreamingSnapshot(
  StreamingDecisionAccumulatorSnapshot snapshot,
) {
  final blocks = <Map<String, dynamic>>[];

  final reasoning = snapshot.reasoning;
  if (reasoning != null && reasoning.isNotEmpty) {
    final signature =
        snapshot.providerState['anthropic_thinking_signature']?.toString() ?? '';
    blocks.add({
      'type': 'thinking',
      'thinking': reasoning,
      'signature': signature,
    });
  }

  final text = snapshot.text;
  if (text != null && text.isNotEmpty) {
    blocks.add({'type': 'text', 'text': text});
  }

  for (final tc in snapshot.toolCalls) {
    if (tc.id == null || tc.toolName == null) continue;
    final input = _safeDecodeArgs(tc.argumentsBuffer);
    blocks.add({
      'type': 'tool_use',
      'id': tc.id,
      'name': tc.toolName,
      'input': input,
    });
  }

  if (blocks.isEmpty) return null;
  return {'role': 'assistant', 'content': blocks};
}

Map<String, dynamic> _safeDecodeArgs(String raw) {
  try {
    final decoded = jsonDecode(raw);
    if (decoded is Map) return Map<String, dynamic>.from(decoded);
  } catch (_) {}
  return const {};
}
```

Imports：`dart:convert` 已在文件顶部。

- [ ] **Step 8.4：跑测试 + commit**

```bash
fvm flutter test test/models/llm/adapters/anthropic_messages_roundtrip_test.dart
git add lib/models/llm/adapters/anthropic_messages_adapter.dart \
        test/models/llm/adapters/anthropic_messages_roundtrip_test.dart
git commit -m "feat(adapter): AnthropicMessagesAdapter extract/assemble raw"
```

---

### Task 9：`ResponsesAdapter.extractRawAssistantMessage` + `assembleRawFromStreamingSnapshot`

**Files:**
- Modify: `lib/models/llm/adapters/responses_adapter.dart`
- Create: `test/models/llm/adapters/responses_roundtrip_test.dart`

Responses API wire 形状：响应 `output` 是 list，包含 type=`message` 的 assistant 输出和 type=`function_call` / `reasoning` 等。

- [ ] **Step 9.1：写失败测试**

```dart
// test/models/llm/adapters/responses_roundtrip_test.dart
import 'package:ai_chat/models/llm/adapters/responses_adapter.dart';
import 'package:ai_chat/models/llm/streaming_decision_accumulator.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ResponsesAdapter.extractRawAssistantMessage', () {
    const adapter = ResponsesAdapter();

    test('保留 output 数组完整（message + function_call + reasoning）', () {
      final raw = adapter.extractRawAssistantMessage(const {
        'id': 'resp_1',
        'output': [
          {'type': 'reasoning', 'id': 'rs_1', 'summary': []},
          {
            'type': 'message',
            'id': 'msg_1',
            'role': 'assistant',
            'content': [
              {'type': 'output_text', 'text': 'Let me search'},
            ],
          },
          {
            'type': 'function_call',
            'id': 'fc_1',
            'call_id': 'call_1',
            'name': 'search',
            'arguments': '{"q":"x"}',
          },
        ],
      });
      expect(raw, isNotNull);
      // Responses 的 raw 我们存整个 output 列表，回放时作为一组 items 注入
      expect(raw!['output'], isA<List>());
      expect((raw['output'] as List).length, 3);
    });

    test('空 output 返回 null', () {
      final raw = adapter.extractRawAssistantMessage(const {'output': []});
      expect(raw, isNull);
    });
  });

  group('ResponsesAdapter.assembleRawFromStreamingSnapshot', () {
    const adapter = ResponsesAdapter();

    test('从 snapshot 拼出 output 列表', () {
      final raw = adapter.assembleRawFromStreamingSnapshot(
        const StreamingDecisionAccumulatorSnapshot(
          text: 'final',
          reasoning: 'think',
          toolCalls: [
            StreamingToolCallDraft(
              id: 'fc_1',
              toolName: 'search',
              argumentsBuffer: '{"q":"x"}',
              sequence: 0,
              isDone: true,
            ),
          ],
          providerState: {'response_id': 'resp_1'},
        ),
      );
      final items = raw!['output'] as List;
      // 期望顺序：reasoning -> message(text) -> function_call
      expect(items[0]['type'], 'reasoning');
      expect(items[1]['type'], 'message');
      expect(((items[1]['content'] as List).first as Map)['text'], 'final');
      expect(items[2]['type'], 'function_call');
      expect((items[2] as Map)['call_id'], 'fc_1');
    });
  });
}
```

- [ ] **Step 9.2：跑测试确认失败**

```bash
fvm flutter test test/models/llm/adapters/responses_roundtrip_test.dart
```
Expected: FAIL

- [ ] **Step 9.3：实现两个方法**

```dart
// lib/models/llm/adapters/responses_adapter.dart

@override
Map<String, dynamic>? extractRawAssistantMessage(
  Map<String, dynamic> responsePayload,
) {
  final output = responsePayload['output'];
  if (output is! List || output.isEmpty) return null;
  return {'output': List<dynamic>.from(output)};
}

@override
Map<String, dynamic>? assembleRawFromStreamingSnapshot(
  StreamingDecisionAccumulatorSnapshot snapshot,
) {
  final items = <Map<String, dynamic>>[];

  if ((snapshot.reasoning ?? '').isNotEmpty) {
    items.add({
      'type': 'reasoning',
      'summary': [
        {'type': 'summary_text', 'text': snapshot.reasoning},
      ],
    });
  }

  final text = snapshot.text;
  if (text != null && text.isNotEmpty) {
    items.add({
      'type': 'message',
      'role': 'assistant',
      'content': [
        {'type': 'output_text', 'text': text},
      ],
    });
  }

  for (final tc in snapshot.toolCalls) {
    if (tc.id == null || tc.toolName == null) continue;
    items.add({
      'type': 'function_call',
      'call_id': tc.id,
      'name': tc.toolName,
      'arguments': tc.argumentsBuffer,
    });
  }

  if (items.isEmpty) return null;
  return {'output': items};
}
```

- [ ] **Step 9.4：跑测试 + commit**

```bash
fvm flutter test test/models/llm/adapters/responses_roundtrip_test.dart
git add lib/models/llm/adapters/responses_adapter.dart \
        test/models/llm/adapters/responses_roundtrip_test.dart
git commit -m "feat(adapter): ResponsesAdapter extract/assemble raw"
```

---

### Task 10：`TurnHarness` 写 `assistantTurnSnapshot`

**Files:**
- Modify: `lib/services/turn_harness.dart`
- Modify: `test/services/turn_harness_test.dart`

- [ ] **Step 10.1：在已存在的 `appendAssistantPlannerMessage` / 多 toolCall 分支后追加 snapshot 写入**

定位 `turn_harness.dart` 中处理 `ModelTurnDecision` 的位置（spec 中提到的 line 372 附近），在写完 fragmented events 之后追加：

```dart
// 取 raw（流式 vs 非流式 由 decision 是否携带 rawAssistantMessage 决定）
// 1) 非流式路径：ConfigurableHttpLLM 解析时已经把 raw 塞进
//    decision.providerState['raw_assistant_message']
// 2) 流式路径：同上，由 _planTurnDecisionStreaming 调
//    adapter.assembleRawFromStreamingSnapshot 后写入 providerState
final raw = decision.providerState['raw_assistant_message'];
if (raw is Map<String, dynamic> &&
    decision.providerStyle != null) {
  yield await _eventRepository.appendAssistantTurnSnapshot(
    turnId: turnId,
    groupId: runtimeTurn.groupId,
    apiStyle: decision.providerStyle!,
    rawAssistantMessageJson: raw,
  );
}
```

- [ ] **Step 10.2：在 `ConfigurableHttpLLM.planTurnDecision` 解析后塞 raw 进 providerState**

非流式分支（约 line 396 附近 `_parseTurnDecisionForStyle` 之后）：

```dart
final decision = _parseTurnDecisionForStyle(apiStyle, decoded);
if (decision != null) {
  final raw = adapter.extractRawAssistantMessage(decoded);
  if (raw != null) {
    final mergedState = Map<String, dynamic>.from(decision.providerState)
      ..['raw_assistant_message'] = raw;
    return decision.copyWith(providerState: mergedState);
  }
}
```

流式分支：在 `StreamingDecisionAccumulator.toDecision` 调用之后：

```dart
final decision = accumulator.toDecision(...);
final snapshot = accumulator.currentSnapshot();
final raw = adapter.assembleRawFromStreamingSnapshot(snapshot);
if (raw != null) {
  final mergedState = Map<String, dynamic>.from(decision.providerState)
    ..['raw_assistant_message'] = raw;
  return decision.copyWith(providerState: mergedState);
}
```

- [ ] **Step 10.3：补 `turn_harness_test.dart` 用例**

```dart
test('runTurn 在 non-empty decision 后写 assistantTurnSnapshot', () async {
  final harness = await _setupHarness(/* ... */);
  final fakeDecision = ModelTurnDecision(
    toolCalls: const [],
    assistantMessage: 'hello',
    visibleReasoning: null,
    providerState: const {
      'raw_assistant_message': {'role': 'assistant', 'content': 'hello'},
    },
    providerStyle: ChatTurnProviderStyle.openaiChatCompletions,
    isTerminal: true,
  );
  // ... 触发流程 ...
  final events = await eventRepo.listEventsByTurn(turnId);
  final snapshots = events
      .where((e) => e.eventType == ChatEventType.assistantTurnSnapshot)
      .toList();
  expect(snapshots, hasLength(1));
  expect(
    snapshots.single.payloadJson?['rawAssistantMessage'],
    {'role': 'assistant', 'content': 'hello'},
  );
});
```

- [ ] **Step 10.4：跑测试 + analyze + commit**

```bash
fvm flutter test test/services/turn_harness_test.dart
fvm flutter analyze 2>&1 | grep error | head -5
git add lib/services/turn_harness.dart lib/models/llm/configurable_http_llm.dart \
        test/services/turn_harness_test.dart
git commit -m "feat(harness): append assistantTurnSnapshot from raw provider message"
```

---

## Phase 4：出站编排（Task 11-15）

### Task 11：`SessionContextService.buildPlannerCarriers`

**Files:**
- Modify: `lib/services/session_context_service.dart`
- Modify: `lib/services/session_token_budget_service.dart`
- Modify: `test/services/session_context_service_test.dart`

- [ ] **Step 11.1：`SessionTokenBudgetService.estimateCarriersTokens`**

在 `lib/services/session_token_budget_service.dart` 加方法：

```dart
import '../models/context/planner_context_carrier.dart';

int estimateCarriersTokens(List<PlannerContextCarrier> carriers) {
  return carriers.fold(0, (sum, c) => sum + c.estimatedTokens);
}
```

- [ ] **Step 11.2：在 service 上加新方法 `buildPlannerCarriers`**

在 `SessionContextService` 类内追加（**不动**旧 `buildPlannerMessages`，Task 15 切流量后由 cleanup 阶段删除）：

```dart
Future<List<PlannerContextCarrier>> buildPlannerCarriers({
  required int groupId,
  required int currentTurnId,
  required List<ChatEvent> currentTurnTranscript,
  required ChatConfig config,
}) async {
  // 复用 buildPlannerContextState 已有的取数 + compaction 逻辑
  // 但产出 carrier 列表而不是 ChatMessage 列表
  final state = await buildPlannerContextState(
    groupId: groupId,
    currentTurnId: currentTurnId,
    currentTurnTranscript: currentTurnTranscript,
    config: config,
  );

  final carriers = <PlannerContextCarrier>[];

  // 1) system prompt（来自 config 解析）
  if (state.resolvedSystemPrompt.isNotEmpty) {
    carriers.add(SyntheticCarrier.system(state.resolvedSystemPrompt));
  }

  // 2) runtime user context messages（已是 ChatMessage[]，需转成 carrier）
  for (final m in state.runtimeUserContextMessages) {
    carriers.add(_chatMessageToSyntheticCarrier(m));
  }

  // 3) compaction snapshot summary
  if (state.activeSnapshot != null) {
    carriers.add(SyntheticCarrier.system(state.activeSnapshot!.summaryText));
  }

  // 4) recent history segments 按 turn 顺序展开
  for (final segment in state.recentSegments) {
    carriers.addAll(_segmentToCarriers(segment));
  }

  // 5) 当前 turn transcript
  carriers.addAll(_eventsToCarriers(currentTurnTranscript));

  return carriers;
}

SyntheticCarrier _chatMessageToSyntheticCarrier(ChatMessage m) {
  switch (m.role) {
    case MessageRole.system:
      return SyntheticCarrier.system(m.text);
    case MessageRole.user:
      return SyntheticCarrier.user(m.text);
    case MessageRole.assistant:
      // 不该发生——runtime user context 只产 system / user
      throw StateError('assistant ChatMessage in runtimeUserContext');
  }
}

List<PlannerContextCarrier> _segmentToCarriers(SessionContextTurnSegment seg) {
  // Task 11.3 实装
  throw UnimplementedError('see Step 11.3');
}

List<PlannerContextCarrier> _eventsToCarriers(List<ChatEvent> events) {
  // Task 11.3 实装
  throw UnimplementedError('see Step 11.3');
}
```

- [ ] **Step 11.3：实装 `_eventsToCarriers`（核心：识别 `assistantTurnSnapshot`）**

```dart
List<PlannerContextCarrier> _eventsToCarriers(List<ChatEvent> events) {
  final carriers = <PlannerContextCarrier>[];
  for (final event in events) {
    switch (event.eventType) {
      case ChatEventType.userMessage:
        final t = (event.content ?? '').trim();
        if (t.isNotEmpty) carriers.add(SyntheticCarrier.user(t));

      case ChatEventType.assistantTurnSnapshot:
        final payload = event.payloadJson;
        if (payload == null) break;
        final apiStyleName = payload['apiStyle']?.toString();
        final raw = payload['rawAssistantMessage'];
        if (apiStyleName == null || raw is! Map) break;
        final style = ChatTurnProviderStyle.values.firstWhere(
          (e) => e.name == apiStyleName,
          orElse: () => throw StateError('unknown apiStyle=$apiStyleName'),
        );
        carriers.add(RawAssistantCarrier(
          apiStyle: style,
          rawJson: Map<String, dynamic>.from(raw),
        ));

      case ChatEventType.toolResult:
      case ChatEventType.toolError:
      case ChatEventType.userInteractionResult:
        final providerCallId =
            event.payloadJson?['providerCallId']?.toString().trim();
        final content = (event.content ?? '').trim();
        if (providerCallId == null || providerCallId.isEmpty || content.isEmpty) {
          break;
        }
        carriers.add(SyntheticCarrier.toolResult(
          toolCallId: providerCallId,
          content: content,
        ));

      // 所有 UI-only 事件：完全跳过
      case ChatEventType.assistantPlannerMessage:
      case ChatEventType.assistantTextDelta:
      case ChatEventType.assistantTextFinal:
      case ChatEventType.assistantReasoningDelta:
      case ChatEventType.assistantToolCall:
      case ChatEventType.assistantToolConfirmation:
      case ChatEventType.assistantQuestionPrompt:
      case ChatEventType.toolExecutionStarted:
      case ChatEventType.turnStatus:
      case ChatEventType.finalAnswer:
      case ChatEventType.error:
        break;
    }
  }
  return carriers;
}

List<PlannerContextCarrier> _segmentToCarriers(SessionContextTurnSegment seg) {
  // segment 内部目前只暴露 messages，无原始 events——需要让 segment 改成
  // 直接持有 events 或在 _buildHistorySegments 里同时构造 carrier。
  // 简化方案：把 _buildHistorySegments 改成直接产出 carrier，segment 多带一份。
  return seg.carriers;   // 新字段，见 Step 11.4
}
```

- [ ] **Step 11.4：`SessionContextTurnSegment` 加 `carriers` 字段，`_buildHistorySegments` 同步产出**

```dart
class SessionContextTurnSegment {
  final int turnId;
  final List<ChatMessage> messages;   // 暂保留，Phase 5 清理时移除
  final List<PlannerContextCarrier> carriers;   // 新增
  final int estimatedTokens;

  const SessionContextTurnSegment({
    required this.turnId,
    required this.messages,
    required this.carriers,
    required this.estimatedTokens,
  });
}
```

`_buildHistorySegments` 内构造每个 segment 时增量调用 `_eventsToCarriers(events)` 写入。`estimatedTokens` 按 carriers 估：

```dart
final carriers = _eventsToCarriers(events);
final estimated = _tokenBudgetService.estimateCarriersTokens(carriers);
```

- [ ] **Step 11.5：写测试**

在 `test/services/session_context_service_test.dart` 加：

```dart
test('buildPlannerCarriers 把 assistantTurnSnapshot 投影为 RawAssistantCarrier', () async {
  final service = await _setupService();
  // 准备一个 turn 含 user / assistantTurnSnapshot / toolResult 三种 events
  // ...
  final carriers = await service.buildPlannerCarriers(
    groupId: groupId,
    currentTurnId: currentTurnId,
    currentTurnTranscript: transcript,
    config: config,
  );
  expect(carriers.whereType<RawAssistantCarrier>(), hasLength(1));
  expect(
    carriers.whereType<RawAssistantCarrier>().single.rawJson['content'],
    'hello from snapshot',
  );
});

test('buildPlannerCarriers 跳过 UI-only 细粒度 events', () async {
  // 准备含 assistantPlannerMessage / assistantReasoningDelta 但无 snapshot 的 turn
  final carriers = await service.buildPlannerCarriers(...);
  expect(carriers.whereType<RawAssistantCarrier>(), isEmpty);
});

test('buildPlannerCarriers 把 userInteractionResult 投影为 toolResult carrier', () async {
  // ...
  final result = carriers.whereType<SyntheticCarrier>().firstWhere(
    (c) => c.role == SyntheticRole.toolResult,
  );
  expect(result.toolCallId, 'call_ask_1');
});
```

- [ ] **Step 11.6：跑测试 + commit**

```bash
fvm flutter test test/services/session_context_service_test.dart
git add lib/services/session_context_service.dart \
        lib/services/session_token_budget_service.dart \
        test/services/session_context_service_test.dart
git commit -m "feat(session): SessionContextService.buildPlannerCarriers"
```

---

### Task 12：`SdkChatCompletionsAdapter.buildPlannerPayloadFromCarriers`

**Files:**
- Modify: `lib/models/llm/adapters/sdk_chat_completions_adapter.dart`
- Modify: `test/models/llm/adapters/sdk_chat_completions_roundtrip_test.dart`

- [ ] **Step 12.1：写 byte-identical round-trip 测试**

```dart
test('buildPlannerPayloadFromCarriers: raw assistant 字段在 messages 中逐字节相等', () {
  const adapter = SdkChatCompletionsAdapter();
  final raw = {
    'role': 'assistant',
    'content': 'Let me search',
    'reasoning_content': 'think first',
    'tool_calls': [
      {
        'id': 'call_1',
        'type': 'function',
        'function': {'name': 'search', 'arguments': '{"q":"x"}'},
      },
    ],
  };
  final payload = adapter.buildPlannerPayloadFromCarriers(
    carriers: [
      const SyntheticCarrier.system('You are an agent.'),
      const SyntheticCarrier.user('please search x'),
      RawAssistantCarrier(
        apiStyle: ChatTurnProviderStyle.openaiChatCompletions,
        rawJson: raw,
      ),
      const SyntheticCarrier.toolResult(toolCallId: 'call_1', content: 'OK'),
    ],
    config: ChatConfig(systemPrompt: ''),
    modelName: 'deepseek-chat',
    availableTools: const [],
    parallelToolCalls: false,
  );
  final messages = payload['messages'] as List;
  expect(messages, hasLength(4));
  expect(messages[2], raw);   // 关键：等号
  expect(messages[3]['role'], 'tool');
  expect(messages[3]['tool_call_id'], 'call_1');
});

test('deepseek 模型仍不带 parallel_tool_calls 字段', () {
  const adapter = SdkChatCompletionsAdapter();
  final payload = adapter.buildPlannerPayloadFromCarriers(
    carriers: [const SyntheticCarrier.user('hi')],
    config: ChatConfig(systemPrompt: ''),
    modelName: 'deepseek-chat',
    availableTools: const [
      PlannerToolOption(name: 'search', description: 's', inputSchema: {'type': 'object'}),
    ],
    parallelToolCalls: true,
  );
  expect(payload.containsKey('parallel_tool_calls'), isFalse);
});
```

- [ ] **Step 12.2：跑测试确认失败**

```bash
fvm flutter test test/models/llm/adapters/sdk_chat_completions_roundtrip_test.dart
```
Expected: FAIL（`UnimplementedError`）

- [ ] **Step 12.3：实现 `buildPlannerPayloadFromCarriers`**

```dart
// lib/models/llm/adapters/sdk_chat_completions_adapter.dart
import 'package:openai_dart/openai_dart.dart' as oai;

@override
Map<String, dynamic> buildPlannerPayloadFromCarriers({
  required List<PlannerContextCarrier> carriers,
  required ChatConfig config,
  required String modelName,
  required List<PlannerToolOption> availableTools,
  required bool parallelToolCalls,
  LlmRequestOptions requestOptions = const LlmRequestOptions(),
}) {
  final messages = <Map<String, dynamic>>[];

  for (final carrier in carriers) {
    switch (carrier) {
      case SyntheticCarrier(role: SyntheticRole.system, :final content):
        messages.add({'role': 'system', 'content': content});

      case SyntheticCarrier(role: SyntheticRole.user, :final content):
        messages.add({'role': 'user', 'content': content});

      case SyntheticCarrier(role: SyntheticRole.toolResult,
            :final toolCallId, :final content):
        messages.add({
          'role': 'tool',
          'tool_call_id': toolCallId,
          'content': content,
        });

      case RawAssistantCarrier(:final rawJson):
        // 逐字节透传——这是这次重构的核心
        messages.add(Map<String, dynamic>.from(rawJson));
    }
  }

  final tools = availableTools
      .map((t) => {
            'type': 'function',
            'function': {
              'name': t.name,
              'description': t.description,
              'parameters': t.inputSchema,
            },
          })
      .toList();

  final includeParallel = tools.isNotEmpty && !_isDeepSeekModel(modelName);
  final payload = <String, dynamic>{
    'model': modelName,
    'messages': messages,
    if (requestOptions.maxOutputTokens != null)
      'max_completion_tokens': requestOptions.maxOutputTokens,
    if (tools.isNotEmpty) ...{
      'tools': tools,
      'tool_choice': 'auto',
    },
    if (includeParallel) 'parallel_tool_calls': parallelToolCalls,
  };

  return payload;
}
```

注意：这里我们**绕过** `oai.ChatCompletionCreateRequest`，直接构造 map，因为 raw 透传需要逐字节相同（走 `oai.ChatMessage.fromJson` 再 `toJson` 可能丢未知字段）。后续 SDK 升级如果验证更严格，再切回 `oai.*` 类型。

- [ ] **Step 12.4：跑测试 + commit**

```bash
fvm flutter test test/models/llm/adapters/sdk_chat_completions_roundtrip_test.dart
git add lib/models/llm/adapters/sdk_chat_completions_adapter.dart \
        test/models/llm/adapters/sdk_chat_completions_roundtrip_test.dart
git commit -m "feat(adapter): SdkChatCompletionsAdapter buildPlannerPayloadFromCarriers"
```

---

### Task 13：`AnthropicMessagesAdapter.buildPlannerPayloadFromCarriers`

**Files:**
- Modify: `lib/models/llm/adapters/anthropic_messages_adapter.dart`
- Modify: `test/models/llm/adapters/anthropic_messages_roundtrip_test.dart`

Anthropic 的 messages 数组里 assistant 消息 `content` 必须是 list of content blocks，user 消息 `content` 可以是字符串或 block list。tool_result 是 user 角色 + content block type=`tool_result` + tool_use_id。

- [ ] **Step 13.1：写测试**

```dart
test('buildPlannerPayloadFromCarriers: 拼出合法 Anthropic messages 数组', () {
  const adapter = AnthropicMessagesAdapter();
  final raw = {
    'role': 'assistant',
    'content': [
      {'type': 'text', 'text': 'Let me search'},
      {'type': 'tool_use', 'id': 'toolu_1', 'name': 'search', 'input': {'q': 'x'}},
    ],
  };
  final payload = adapter.buildPlannerPayloadFromCarriers(
    carriers: [
      const SyntheticCarrier.system('agent'),
      const SyntheticCarrier.user('please'),
      RawAssistantCarrier(
        apiStyle: ChatTurnProviderStyle.anthropicMessages,
        rawJson: raw,
      ),
      const SyntheticCarrier.toolResult(toolCallId: 'toolu_1', content: 'OK'),
    ],
    config: ChatConfig(systemPrompt: ''),
    modelName: 'claude-3-5-sonnet',
    availableTools: const [],
    parallelToolCalls: false,
  );
  expect(payload['system'], 'agent');
  final messages = payload['messages'] as List;
  expect(messages[0]['role'], 'user');
  expect(messages[1], raw);   // 字段相等
  expect(messages[2]['role'], 'user');
  final toolResultBlock = (messages[2]['content'] as List).first as Map;
  expect(toolResultBlock['type'], 'tool_result');
  expect(toolResultBlock['tool_use_id'], 'toolu_1');
  expect(toolResultBlock['content'], 'OK');
});
```

- [ ] **Step 13.2：实现**

```dart
@override
Map<String, dynamic> buildPlannerPayloadFromCarriers({
  required List<PlannerContextCarrier> carriers,
  required ChatConfig config,
  required String modelName,
  required List<PlannerToolOption> availableTools,
  required bool parallelToolCalls,
  LlmRequestOptions requestOptions = const LlmRequestOptions(),
}) {
  String? systemText;
  final messages = <Map<String, dynamic>>[];

  for (final carrier in carriers) {
    switch (carrier) {
      case SyntheticCarrier(role: SyntheticRole.system, :final content):
        // Anthropic 把 system 提到顶层；多条 system 拼接
        systemText = (systemText == null) ? content : '$systemText\n\n$content';

      case SyntheticCarrier(role: SyntheticRole.user, :final content):
        messages.add({
          'role': 'user',
          'content': [
            {'type': 'text', 'text': content},
          ],
        });

      case SyntheticCarrier(role: SyntheticRole.toolResult,
            :final toolCallId, :final content):
        messages.add({
          'role': 'user',
          'content': [
            {
              'type': 'tool_result',
              'tool_use_id': toolCallId,
              'content': content,
            },
          ],
        });

      case RawAssistantCarrier(:final rawJson):
        messages.add(Map<String, dynamic>.from(rawJson));
    }
  }

  final tools = availableTools
      .map((t) => {
            'name': t.name,
            'description': t.description,
            'input_schema': t.inputSchema,
          })
      .toList();

  return {
    'model': modelName,
    if (systemText != null) 'system': systemText,
    'messages': messages,
    'max_tokens': requestOptions.maxOutputTokens ?? 4096,
    if (tools.isNotEmpty) 'tools': tools,
  };
}
```

- [ ] **Step 13.3：跑测试 + commit**

```bash
fvm flutter test test/models/llm/adapters/anthropic_messages_roundtrip_test.dart
git add lib/models/llm/adapters/anthropic_messages_adapter.dart \
        test/models/llm/adapters/anthropic_messages_roundtrip_test.dart
git commit -m "feat(adapter): AnthropicMessagesAdapter buildPlannerPayloadFromCarriers"
```

---

### Task 14：`ResponsesAdapter.buildPlannerPayloadFromCarriers`

**Files:**
- Modify: `lib/models/llm/adapters/responses_adapter.dart`
- Modify: `test/models/llm/adapters/responses_roundtrip_test.dart`

Responses API 输入是 `input` 数组（统一为 items list）。RawAssistantCarrier 已经存了 `output` 列表，回放时整个 output 数组作为一组 input items 注入。

- [ ] **Step 14.1：写测试**

```dart
test('buildPlannerPayloadFromCarriers: raw output 数组完整注入 input', () {
  const adapter = ResponsesAdapter();
  final raw = {
    'output': [
      {'type': 'reasoning', 'id': 'rs_1', 'summary': []},
      {
        'type': 'message',
        'id': 'msg_1',
        'role': 'assistant',
        'content': [
          {'type': 'output_text', 'text': 'Let me search'},
        ],
      },
      {
        'type': 'function_call',
        'call_id': 'call_1',
        'name': 'search',
        'arguments': '{"q":"x"}',
      },
    ],
  };
  final payload = adapter.buildPlannerPayloadFromCarriers(
    carriers: [
      const SyntheticCarrier.system('agent'),
      const SyntheticCarrier.user('please'),
      RawAssistantCarrier(
        apiStyle: ChatTurnProviderStyle.openaiResponses,
        rawJson: raw,
      ),
      const SyntheticCarrier.toolResult(toolCallId: 'call_1', content: 'OK'),
    ],
    config: ChatConfig(systemPrompt: ''),
    modelName: 'gpt-5',
    availableTools: const [],
    parallelToolCalls: false,
  );
  expect(payload['instructions'], 'agent');
  final input = payload['input'] as List;
  // user 输入 + raw output 三个 item + function_call_output
  expect(input[0]['role'], 'user');
  expect(input[1], raw['output']![0]);
  expect(input[2], raw['output']![1]);
  expect(input[3], raw['output']![2]);
  expect(input[4]['type'], 'function_call_output');
  expect(input[4]['call_id'], 'call_1');
});
```

- [ ] **Step 14.2：实现**

```dart
@override
Map<String, dynamic> buildPlannerPayloadFromCarriers({
  required List<PlannerContextCarrier> carriers,
  required ChatConfig config,
  required String modelName,
  required List<PlannerToolOption> availableTools,
  required bool parallelToolCalls,
  LlmRequestOptions requestOptions = const LlmRequestOptions(),
}) {
  String? instructions;
  final input = <Map<String, dynamic>>[];

  for (final carrier in carriers) {
    switch (carrier) {
      case SyntheticCarrier(role: SyntheticRole.system, :final content):
        instructions = (instructions == null) ? content : '$instructions\n\n$content';

      case SyntheticCarrier(role: SyntheticRole.user, :final content):
        input.add({
          'type': 'message',
          'role': 'user',
          'content': [
            {'type': 'input_text', 'text': content},
          ],
        });

      case SyntheticCarrier(role: SyntheticRole.toolResult,
            :final toolCallId, :final content):
        input.add({
          'type': 'function_call_output',
          'call_id': toolCallId,
          'output': content,
        });

      case RawAssistantCarrier(:final rawJson):
        final outputs = rawJson['output'];
        if (outputs is List) {
          for (final item in outputs) {
            if (item is Map) {
              input.add(Map<String, dynamic>.from(item));
            }
          }
        }
    }
  }

  final tools = availableTools
      .map((t) => {
            'type': 'function',
            'name': t.name,
            'description': t.description,
            'parameters': t.inputSchema,
          })
      .toList();

  return {
    'model': modelName,
    if (instructions != null) 'instructions': instructions,
    'input': input,
    if (tools.isNotEmpty) 'tools': tools,
  };
}
```

- [ ] **Step 14.3：跑测试 + commit**

```bash
fvm flutter test test/models/llm/adapters/responses_roundtrip_test.dart
git add lib/models/llm/adapters/responses_adapter.dart \
        test/models/llm/adapters/responses_roundtrip_test.dart
git commit -m "feat(adapter): ResponsesAdapter buildPlannerPayloadFromCarriers"
```

---

### Task 15：在 `ConfigurableHttpLLM.planTurnDecision` 切到 carrier 路径

**Files:**
- Modify: `lib/models/llm/configurable_http_llm.dart`
- Modify: `lib/services/turn_harness.dart`（调用方式更新）
- Modify: `lib/controllers/chat_send_coordinator.dart`（如有需要传 lockedProviderStyle）
- Modify: `test/models/llm/configurable_http_llm_test.dart`

- [ ] **Step 15.1：`planTurnDecision` 签名 + 实现切换**

`ConfigurableHttpLLM.planTurnDecision` 既有签名（`messages: List<ChatMessage>`）改为接收 carriers：

```dart
@override
Future<ModelTurnDecision?> planTurnDecision({
  required List<PlannerContextCarrier> carriers,
  required ChatTurnProviderStyle activeApiStyle,
  required bool currentTurnRunning,
  required ChatConfig config,
  required List<PlannerToolOption> availableTools,
  void Function(LlmRetryProgress progress)? onRetryScheduled,
}) async {
  // 入口处守 invariant
  const PlannerInvariantValidator().validate(
    carriers: carriers,
    activeApiStyle: activeApiStyle,
    currentTurnRunning: currentTurnRunning,
  );

  // 现有逻辑：取 runtimeConfig、resolve adapter、build payload
  final runtimeConfig = await _settingsRepository.getLlmConfig();
  _validateRuntimeConfig(runtimeConfig);
  final apiStyle = _protocolResolver.resolveStyle(runtimeConfig.apiUrl);
  if (apiStyle != activeApiStyle) {
    throw InconsistentProviderStateError(
      'active=$activeApiStyle but runtime resolves to $apiStyle',
    );
  }
  final adapter = _adapterFor(apiStyle);
  final modelName = _resolveModelName(runtimeConfig, config);
  final requestOptions = _requestOptionsFor(/* ... */);

  final payload = adapter.buildPlannerPayloadFromCarriers(
    carriers: carriers,
    config: config,
    modelName: modelName,
    availableTools: availableTools,
    parallelToolCalls: true,
    requestOptions: requestOptions,
  );

  // 之后的 streaming / non-streaming 分支保持不变；raw 在解析后被塞进
  // providerState（Task 10 已做）
  // ...
}
```

- [ ] **Step 15.2：上游调用方（`TurnHarness` / `ChatSendCoordinator`）改成传 carriers**

`TurnHarness` 中调 `planTurnDecision` 之前先调 `sessionContextService.buildPlannerCarriers`：

```dart
final carriers = await _sessionContextService.buildPlannerCarriers(
  groupId: turn.groupId,
  currentTurnId: turnId,
  currentTurnTranscript: transcript,
  config: config,
);
final decision = await _planner.planNextDecision(
  carriers: carriers,
  activeApiStyle: turn.providerStyle ?? group.lockedProviderStyle,
  currentTurnRunning: true,
  config: config,
  availableTools: availableTools,
);
```

`AgentPlannerService.planNextDecision` 签名同步改。

- [ ] **Step 15.3：测试**

更新 `test/models/llm/configurable_http_llm_test.dart` 既有用例为新签名；新增：

```dart
test('carrier 中 apiStyle 与 active 不匹配抛 InconsistentProviderStateError', () {
  expect(
    () => llm.planTurnDecision(
      carriers: [
        const SyntheticCarrier.user('hi'),
        RawAssistantCarrier(
          apiStyle: ChatTurnProviderStyle.anthropicMessages,
          rawJson: const {'role': 'assistant'},
        ),
      ],
      activeApiStyle: ChatTurnProviderStyle.openaiChatCompletions,
      currentTurnRunning: false,
      config: ChatConfig(systemPrompt: ''),
      availableTools: const [],
    ),
    throwsA(isA<InconsistentProviderStateError>()),
  );
});
```

- [ ] **Step 15.4：跑测试 + analyze + commit**

```bash
fvm flutter test test/models/llm/configurable_http_llm_test.dart \
                 test/services/turn_harness_test.dart
fvm flutter analyze 2>&1 | grep error
git add lib/models/llm/configurable_http_llm.dart lib/services/turn_harness.dart \
        lib/services/agent_planner_service.dart lib/controllers/ \
        test/models/llm/configurable_http_llm_test.dart \
        test/services/turn_harness_test.dart
git commit -m "feat(planner): wire ConfigurableHttpLLM through carrier pipeline"
```

---

## Phase 5：清理已死代码（Task 16-19）

到这一步新路径已经全跑通。本阶段是纯删除——旧代码已无调用点。每个 task 删完跑 `dart analyze` 0 errors + `flutter test` 全套绿，否则回滚。

### Task 16：删除 `ApiStyleAdapter.buildPlannerPayload` 旧方法

**Files:**
- Modify: `lib/models/llm/adapters/api_style_adapter.dart`
- Modify: `lib/models/llm/adapters/sdk_chat_completions_adapter.dart`
- Modify: `lib/models/llm/adapters/chat_completions_adapter.dart`（legacy）
- Modify: `lib/models/llm/adapters/anthropic_messages_adapter.dart`
- Modify: `lib/models/llm/adapters/responses_adapter.dart`
- Modify: 相关测试文件中 `buildPlannerPayload(messages: ...)` 用例删除

- [ ] **Step 16.1：grep 确认无调用方**

```bash
grep -rn 'buildPlannerPayload(' lib/ test/ | grep -v 'FromCarriers' | head
```
Expected: 只剩测试和 adapter 内部定义，无 production 调用。如有 production 调用，停下来排查。

- [ ] **Step 16.2：删除接口方法 + 各实现 + 相关测试用例**

按上面 5 个文件逐个删除：
- abstract method 在 `api_style_adapter.dart`
- 4 个 `@override Map<String, dynamic> buildPlannerPayload({...}) { ... }` 实现块
- `test/models/llm/adapters/sdk_chat_completions_adapter_test.dart` 中 `buildPlannerPayload includes ...` / `merges adjacent ...` 等 4-5 个用例
- `test/models/llm/adapters/chat_completions_adapter_test.dart` 中 legacy 路径对应用例（如非删除可保留作为兼容样本，但需更新签名）

- [ ] **Step 16.3：跑全套测试 + analyze + commit**

```bash
fvm flutter test
fvm flutter analyze 2>&1 | grep error
git add -A
git commit -m "chore(adapter): remove deprecated ApiStyleAdapter.buildPlannerPayload"
```

---

### Task 17：删除 `SessionContextProjector` 中的 assistant 事件分支

**Files:**
- Modify: `lib/services/session_context_projector.dart`
- Modify: `test/services/session_context_projector_test.dart`

- [ ] **Step 17.1：精简 `projectEventToContextItem`**

只保留 `userMessage`、`userInteractionResult`（必须带 providerCallId）、`toolResult`、`toolError`。删除：
- `assistantPlannerMessage`
- `assistantQuestionPrompt`
- `assistantToolCall`
- `assistantToolConfirmation`
- 默认 `null` 的 UI-only 类型分支（用统一 `null` 处理）

精简后版本：

```dart
ModelContextItem? projectEventToContextItem(ChatEvent event) {
  switch (event.eventType) {
    case ChatEventType.userMessage:
      final content = event.content?.trim() ?? '';
      if (content.isEmpty) return null;
      return ModelContextItem.userMessage(content, timestamp: event.createdAt);

    case ChatEventType.userInteractionResult:
    case ChatEventType.toolResult:
    case ChatEventType.toolError:
      final providerCallId =
          event.payloadJson?['providerCallId']?.toString().trim();
      if (providerCallId == null || providerCallId.isEmpty) return null;
      final payload = event.payloadJson;
      final structured = payload == null
          ? null
          : _toolResultContextProjector
              .projectToContextText(ToolResult.fromJson(payload))
              ?.trim();
      final content = (structured != null && structured.isNotEmpty)
          ? structured
          : (event.content?.trim() ?? '');
      if (content.isEmpty) return null;
      return ModelContextItem.userToolResult(
        text: content,
        toolName: payload?['toolName']?.toString(),
        providerCallId: providerCallId,
        timestamp: event.createdAt,
      );

    case ChatEventType.assistantTurnSnapshot:
    case ChatEventType.assistantPlannerMessage:
    case ChatEventType.assistantQuestionPrompt:
    case ChatEventType.assistantToolCall:
    case ChatEventType.assistantToolConfirmation:
    case ChatEventType.assistantReasoningDelta:
    case ChatEventType.assistantTextDelta:
    case ChatEventType.assistantTextFinal:
    case ChatEventType.toolExecutionStarted:
    case ChatEventType.turnStatus:
    case ChatEventType.finalAnswer:
    case ChatEventType.error:
      return null;
  }
}
```

- [ ] **Step 17.2：删除测试中所有 assistant 事件的 projection 用例**

`test/services/session_context_projector_test.dart`：
- "projects assistant tool call into tagged tool-use context message" → 删
- 2026-05-22 加的 `assistantQuestionPrompt` skip 分支测试 → 删
- 含 `assistantToolCall` 期待变成 `[assistant tool_use]` 的断言用例 → 删

保留 `userMessage` / `userInteractionResult`（含 providerCallId 分支）/ `toolResult` / `toolError` / snapshot system message 用例。

- [ ] **Step 17.3：跑 + commit**

```bash
fvm flutter test test/services/session_context_projector_test.dart
fvm flutter analyze 2>&1 | grep error
git add lib/services/session_context_projector.dart test/services/session_context_projector_test.dart
git commit -m "chore(projector): drop assistant event branches; UI-only now"
```

---

### Task 18：删除 `ModelContextItem.assistantMessage` / `assistantToolUse` 工厂 + encoder 分支

**Files:**
- Modify: `lib/models/context/model_context_item.dart`
- Modify: `lib/services/model_context_item_encoder.dart`

- [ ] **Step 18.1：grep 确认无调用方**

```bash
grep -rn 'ModelContextItem\.assistantMessage\|ModelContextItem\.assistantToolUse' lib/ test/
```
Expected: 仅文件本身定义。如有调用，停下来排查（Phase 4 应该已清掉）。

- [ ] **Step 18.2：删除工厂方法**

```dart
// lib/models/context/model_context_item.dart 删除：
//   factory ModelContextItem.assistantMessage(...)
//   factory ModelContextItem.assistantToolUse(...)
// 并把 enum ModelContextItemType 中的 assistantMessage / assistantToolUse 删除
```

- [ ] **Step 18.3：encoder 删除对应 case**

```dart
// lib/services/model_context_item_encoder.dart 中 switch 删除：
//   case ModelContextItemType.assistantMessage: ...
//   case ModelContextItemType.assistantToolUse: ...
// 编译器会强制其余 switch 覆盖剩余 case
```

- [ ] **Step 18.4：跑 + commit**

```bash
fvm flutter test
fvm flutter analyze 2>&1 | grep error
git add lib/models/context/model_context_item.dart lib/services/model_context_item_encoder.dart
git commit -m "chore(context): drop ModelContextItem.assistantMessage / assistantToolUse"
```

---

### Task 19：删除 `SdkMessageConverter` 合并逻辑

**Files:**
- Modify: `lib/models/llm/adapters/sdk_message_converter.dart`
- Modify: `test/models/llm/adapters/sdk_chat_completions_adapter_test.dart`（保留剩余测试）

- [ ] **Step 19.1：grep 确认无调用方**

```bash
grep -rn 'SdkMessageConverter\b' lib/ test/
```
Expected: 文件本身 + 测试。如 `SdkChatCompletionsAdapter` 不再用 converter（Task 12 改成直接构造 map）则可整体删除整个 converter 文件。

- [ ] **Step 19.2：整体删除 `sdk_message_converter.dart` 和它的测试**

```bash
git rm lib/models/llm/adapters/sdk_message_converter.dart
git rm test/models/llm/adapters/sdk_message_converter_test.dart   # 如存在
```

- [ ] **Step 19.3：跑 + commit**

```bash
fvm flutter test
fvm flutter analyze 2>&1 | grep error
git commit -m "chore(adapter): delete SdkMessageConverter — merge logic obsolete"
```

---

## Phase 6：Provider 锁定 UI（Task 20-21）

### Task 20：创建新会话时写入 `lockedProviderStyle`

**Files:**
- Modify: `lib/repositories/chat_group_repository.dart`
- Modify: 调用 `ChatGroupRepository.create` 的位置（grep 找到具体文件）

- [ ] **Step 20.1：`ChatGroupRepository.create` 接受 `lockedProviderStyle` 参数**

```dart
Future<int> create({
  required String title,
  required String lockedProviderStyle,   // 新增
  String? systemPrompt,
}) async {
  return await _db.insert('chat_groups', {
    'title': title,
    'created_at': now,
    'last_message_at': now,
    'system_prompt': systemPrompt,
    'is_summarized': 0,
    'locked_provider_style': lockedProviderStyle,
  });
}
```

- [ ] **Step 20.2：调用方传入当前选中 provider**

```bash
grep -rn 'chatGroupRepository\.create\b\|groupRepository\.create\b\|ChatGroupRepository(\b' lib/
```
找到所有 create 调用点，传入：

```dart
final config = await settingsRepository.getLlmConfig();
final apiStyle = ApiProtocolResolver.resolveStyle(config.apiUrl);
final groupId = await groupRepository.create(
  title: title,
  lockedProviderStyle: apiStyle.toChatTurnProviderStyle().name,
  systemPrompt: systemPrompt,
);
```

如果 `ApiProtocolResolver` 没有 `toChatTurnProviderStyle()` 转换，加：

```dart
extension ApiStyleToProviderStyle on ApiStyle {
  ChatTurnProviderStyle toChatTurnProviderStyle() {
    switch (this) {
      case ApiStyle.chatCompletions:
        return ChatTurnProviderStyle.openaiChatCompletions;
      case ApiStyle.responses:
        return ChatTurnProviderStyle.openaiResponses;
      case ApiStyle.anthropicMessages:
        return ChatTurnProviderStyle.anthropicMessages;
    }
  }
}
```

- [ ] **Step 20.3：写测试**

```dart
test('ChatGroupRepository.create 写入 locked_provider_style', () async {
  final groupId = await repo.create(
    title: 'test',
    lockedProviderStyle: 'openaiChatCompletions',
  );
  final row = await db.query('chat_groups', where: 'id = ?', whereArgs: [groupId]);
  expect(row.first['locked_provider_style'], 'openaiChatCompletions');
});
```

- [ ] **Step 20.4：跑 + commit**

```bash
fvm flutter test test/repositories/chat_group_repository_test.dart
git add lib/repositories/chat_group_repository.dart \
        lib/models/llm/api_protocol_resolver.dart \
        test/repositories/chat_group_repository_test.dart
git commit -m "feat(group): set lockedProviderStyle on group creation"
```

---

### Task 21：进行中会话禁用 provider 切换 UI

**Files:**
- Modify: `lib/pages/settings_page.dart`（或 chat drawer 中 provider 选择控件）
- Modify: 相关 widget 测试

- [ ] **Step 21.1：在 settings page 加状态联动**

```bash
grep -rn 'selectedProviderId\|providerSelector\|providerSwitcher' lib/pages/settings_page.dart lib/widgets/
```

找到 provider 切换控件后加：

```dart
final currentGroup = ref.watch(currentChatGroupProvider);
final isProviderLocked = currentGroup?.lockedProviderStyle != null;

ProviderSwitcher(
  enabled: !isProviderLocked,
  helperText: isProviderLocked
      ? '当前会话已锁定 provider，新建会话方可切换'
      : null,
  // ... 原参数
);
```

- [ ] **Step 21.2：在 chat drawer 加锁定标识**

每个 group 列表项显示其 `lockedProviderStyle`（缩写：`DeepSeek` / `Claude` / `GPT`），点击不可改。

- [ ] **Step 21.3：widget 测试**

```dart
testWidgets('当前 group 锁定 provider 时切换控件 disabled', (tester) async {
  await tester.pumpWidget(/* with currentGroup having lockedProviderStyle */);
  final switcher = find.byKey(const Key('provider-switcher'));
  expect(tester.widget<ProviderSwitcher>(switcher).enabled, isFalse);
});
```

- [ ] **Step 21.4：手动 UI 验证 + commit**

```bash
fvm flutter test test/pages/settings_page_test.dart
fvm flutter run -d 37b534c2 --debug
# 操作：开新会话 → 试图改 provider → 应该 disabled
git add lib/pages/settings_page.dart lib/widgets/ test/pages/
git commit -m "feat(ui): disable provider switcher when current group is locked"
```

---

## Phase 7：真机回归（Task 22）

### Task 22：四个 DeepSeek 场景 + 强杀重启验证

**这一阶段不写代码，只验证。** 任何场景失败，回到对应 Task 修复。

- [ ] **Step 22.1：重新构建并安装到设备**

```bash
FLUTTER_STORAGE_BASE_URL=https://storage.flutter-io.cn \
PUB_HOSTED_URL=https://pub.flutter-io.cn \
bash scripts/android_install_debug.sh 37b534c2
```

- [ ] **Step 22.2：场景 1 —— 单工具调用**

操作：
1. 新建会话（确认锁定 provider = DeepSeek）
2. 用户："帮我查一下 site:blog.google 关于 AI 的最近动态"
3. 预期：模型调一次 `web_search` → 拿到结果 → 给出回答

成功判据：logcat 无 `400` 字样；UI 展示工具调用 + 最终答案；turn 进入 completed 状态。

- [ ] **Step 22.3：场景 2 —— AskUserQuestion**

操作：
1. 新建会话
2. 用户："我要做一个 AI Chat 产品，但目标平台、数据存储、是否离线都没定，请一次性问我这些关键问题再给方案"
3. 等待 AskUserQuestion 卡片出现
4. 填答案后提交
5. 预期：模型基于回答继续给出最终方案

成功判据：第二轮请求 logcat 无 `400`；DB 中 `assistantTurnSnapshot` event 写了两条（每个 iteration 一条）；`userInteractionResult` event 的 `providerCallId` 与 snapshot 中的 tool_call_id 匹配。

- [ ] **Step 22.4：场景 3 —— 多轮 tool loop**

操作：
1. 新建会话
2. 用户："先搜 X 再搜 Y，最后总结"
3. 预期：模型连调两次 `web_search`，每次工具结果返回后继续 plan

成功判据：每轮 plan 请求 logcat 无 `400`；每个 iteration 都有 `assistantTurnSnapshot` event；tool_call_id 配对完整。

- [ ] **Step 22.5：场景 4 —— 思考模型多轮**

操作：
1. 切到思考模型（如 deepseek-r1）
2. 新建会话
3. 多轮对话，每轮模型应有可见 reasoning

成功判据：第二轮起请求 body 中包含上一轮的 `reasoning_content` 字段（透传）；logcat 无 `400`。

- [ ] **Step 22.6：场景 5 —— 强杀重启**

操作：
1. 在场景 2 走到 AskUserQuestion 卡片出现
2. 强杀 App（最近任务里滑掉）
3. 重启 App，打开同一会话
4. 填答案提交
5. 预期：能恢复，最终给出方案

成功判据：DB 中 `assistantTurnSnapshot` 在 kill 前已持久化；重启后 carrier 序列正确组装；logcat 无 `400`。

- [ ] **Step 22.7：记录回归结果**

在 `docs/superpowers/specs/2026-05-22-planner-context-carrier-architecture-design.md` 末尾追加：

```markdown
## 真机回归记录（YYYY-MM-DD）

- 场景 1（单工具）：✅ / ❌
- 场景 2（AskUserQuestion）：✅ / ❌
- 场景 3（多轮 tool loop）：✅ / ❌
- 场景 4（思考模型）：✅ / ❌
- 场景 5（强杀重启）：✅ / ❌
```

- [ ] **Step 22.8：commit 文档**

```bash
git add docs/superpowers/specs/2026-05-22-planner-context-carrier-architecture-design.md
git commit -m "docs(specs): planner carrier on-device regression results"
```

---

## 完成判据

实施全部 22 个 Task 后：
- `fvm flutter test` 全套绿（spec 中标注允许保留的 25 个 pre-existing live-integration 失败外）
- `fvm flutter analyze` 0 errors
- 真机 5 个回归场景全部 pass
- `grep -rn 'buildPlannerPayload\b' lib/` 找不到旧方法（确认清理彻底）
- `grep -rn 'ModelContextItem\.assistantMessage\|ModelContextItem\.assistantToolUse' lib/` 找不到（确认 demote 彻底）
