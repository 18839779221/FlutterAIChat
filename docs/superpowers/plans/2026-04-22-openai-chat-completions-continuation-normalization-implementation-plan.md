# OpenAI Chat Completions 续跑规范化 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 将 `openaiChatCompletions` 的工具续跑从“仅依赖 transcript 语义投影”升级为“普通工具优先使用原生 continuation，`ask_user_question` 保留用户语义特例”，提升 OpenAI 兼容提供方的协议稳定性。

**Architecture:** 保留现有 `AgentPlannerService -> ConfigurableHttpLLM -> provider adapter` 的边界，不改数据库结构。`AgentPlannerService` 继续负责从 transcript/step ledger 中提炼 planner 上下文，但会额外为 `openaiChatCompletions` 构建 provider-native continuation items；`ConfigurableHttpLLM` 负责把这些 continuation items 组装成 `assistant(tool_calls) + tool` 风格消息，`ask_user_question` 则继续投影为真实 `user` 回答，避免把内部状态事件重新塞回上游。

**Tech Stack:** Flutter, Dart, flutter_test, 现有 native planner loop、OpenAI Chat Completions 兼容层、MiniMax OpenAI-compatible endpoint

---

## 文件地图

**续跑构造**

- 修改：`lib/services/agent_planner_service.dart`
- 修改：`lib/models/llm/configurable_http_llm.dart`
- 参考：`lib/models/llm/tool_loop/openai_chat_completions_tool_loop_adapter.dart`

**运行时与持久化模型**

- 参考：`lib/models/agent/chat_turn_step.dart`
- 参考：`lib/models/agent/model_tool_call.dart`
- 参考：`lib/models/chat_turn.dart`

**测试**

- 修改：`test/services/agent_planner_service_test.dart`
- 修改：`test/models/llm/configurable_http_llm_test.dart`

**文档**

- 修改：`README.md`

### Task 1: 固化 chat completions 续跑协议回归测试

**Files:**
- Modify: `test/services/agent_planner_service_test.dart`
- Modify: `test/models/llm/configurable_http_llm_test.dart`

- [ ] **Step 1: 先写 `AgentPlannerService` 失败测试**

覆盖 `openaiChatCompletions` 场景下的 transcript 投影边界：
- `turnStatus`、`toolExecutionStarted` 不得进入 planner messages
- `userInteractionResult` 必须投影为 `user`
- `toolResult` / `toolError` 必须投影为 `assistant`

- [ ] **Step 2: 先写 `ConfigurableHttpLLM` 失败测试**

覆盖 `chat/completions` native planner 请求体：
- 普通工具续跑时必须包含一条 `assistant` 消息，其 `tool_calls` 对应 step ledger 中的 `providerCallId + toolArgsJson`
- 紧随其后必须包含 `tool` role 消息，且 `tool_call_id` 与上面的 call id 一致
- `ask_user_question` 续跑时不得出现内部 `system` role

- [ ] **Step 3: 运行聚焦测试，确认当前实现仍缺少原生 continuation**

Run: `flutter test test/services/agent_planner_service_test.dart test/models/llm/configurable_http_llm_test.dart`
Expected: FAIL，且失败点集中在 chat completions 第二轮续跑 payload 与 role 投影断言

- [ ] **Step 4: 提交测试基线**

```bash
git add test/services/agent_planner_service_test.dart test/models/llm/configurable_http_llm_test.dart
git commit -m "test: cover chat completions continuation payloads"
```

### Task 2: 为 openaiChatCompletions 提供 provider-native continuation items

**Files:**
- Modify: `lib/services/agent_planner_service.dart`
- Modify: `test/services/agent_planner_service_test.dart`

- [ ] **Step 1: 扩展 continuation item 构造分支**

在 `AgentPlannerService._buildProviderContinuationItems()` 中为 `ChatTurnProviderStyle.openaiChatCompletions` 增加专用分支，按 step ledger 提炼 continuation items。建议输出结构：

```dart
{
  'type': 'assistant_tool_call',
  'toolCallId': 'call_123',
  'toolName': 'web_search',
  'arguments': {'query': 'MiniMax API'},
}
```

以及：

```dart
{
  'type': 'tool_result',
  'toolCallId': 'call_123',
  'toolName': 'web_search',
  'output': '{"status":"success","summary":"..."}',
}
```

- [ ] **Step 2: 为 `ask_user_question` 增加特例 continuation item**

当 step 的 `toolName == 'ask_user_question'` 时，不生成普通 `tool_result` 续跑项，而是生成显式的用户回答项，避免把“用户补充信息”错误降级为工具摘要。

建议结构：

```dart
{
  'type': 'user_interaction_answer',
  'toolCallId': 'call_ask_1',
  'content': 'User answered AskUserQuestion:\\n- Storage: SQLite',
}
```

- [ ] **Step 3: 收紧 transcript 投影逻辑**

保持当前已修复的规则：
- 内部状态事件继续过滤
- `userInteractionResult -> user`
- `toolResult` / `toolError` -> assistant

同时避免 continuation items 与 transcript 语义重复拼装。

- [ ] **Step 4: 运行 service 聚焦测试**

Run: `flutter test test/services/agent_planner_service_test.dart`
Expected: PASS

- [ ] **Step 5: 提交**

```bash
git add lib/services/agent_planner_service.dart test/services/agent_planner_service_test.dart
git commit -m "feat: add chat completions continuation items"
```

### Task 3: 在 ConfigurableHttpLLM 中组装原生 chat completions 续跑消息

**Files:**
- Modify: `lib/models/llm/configurable_http_llm.dart`
- Modify: `test/models/llm/configurable_http_llm_test.dart`

- [ ] **Step 1: 新增 chat completions continuation payload 组装函数**

在 `ConfigurableHttpLLM` 中为 planner payload 增加专用组装逻辑，将 `providerContinuationItems` 转换为兼容消息：

普通工具续跑：

```json
{
  "role": "assistant",
  "content": "",
  "tool_calls": [
    {
      "id": "call_123",
      "type": "function",
      "function": {
        "name": "web_search",
        "arguments": "{\"query\":\"MiniMax API\"}"
      }
    }
  ]
}
```

```json
{
  "role": "tool",
  "tool_call_id": "call_123",
  "content": "{\"status\":\"success\",\"summary\":\"已完成\"}"
}
```

- [ ] **Step 2: 对 `ask_user_question` 保留 user 语义续跑**

当 continuation item 是 `user_interaction_answer` 时，组装成：

```json
{
  "role": "user",
  "content": "User answered AskUserQuestion:\n- Storage: SQLite"
}
```

不要再拼入 `planner_action_call_tools:*` 或其他内部状态文本。

- [ ] **Step 3: 限制 message role 集合**

确保 chat completions 路径最终只会发送兼容角色：
- `system`
- `user`
- `assistant`
- `tool`

若 continuation item 无法映射到这四类之一，应直接丢弃并打 debug log，而不是继续透传到上游。

- [ ] **Step 4: 运行 LLM 聚焦测试**

Run: `flutter test test/models/llm/configurable_http_llm_test.dart`
Expected: PASS

- [ ] **Step 5: 提交**

```bash
git add lib/models/llm/configurable_http_llm.dart test/models/llm/configurable_http_llm_test.dart
git commit -m "feat: normalize chat completions continuation payloads"
```

### Task 4: 回归 MiniMax 双协议链路并更新文档

**Files:**
- Modify: `README.md`

- [ ] **Step 1: 运行关键单测**

Run: `flutter test test/services/agent_planner_service_test.dart test/models/llm/configurable_http_llm_test.dart`
Expected: PASS

- [ ] **Step 2: 构建 Android debug APK**

Run: `flutter build apk --debug`
Expected: PASS，产物输出到 `build/app/outputs/flutter-apk/app-debug.apk`

- [ ] **Step 3: 真机验证两条 provider 链路**

手动验证：
- `MiniMax-M2.7 + Anthropic` 的 tool loop 不回退
- `MiniMax-M2.5 + OpenAI` 在普通工具和 `ask_user_question` 两条路径都能完成第二轮续跑

预期：
- 不再出现 `invalid message role: system (2013)`
- UI 若失败仍能显示 planner request error

- [ ] **Step 4: 更新 README 的 provider 兼容说明**

补充说明：
- `responses`、`chat/completions`、`anthropic/messages` 的运行时推断方式
- `chat/completions` 对内部事件与续跑 role 的约束
- `ask_user_question` 在 OpenAI-compatible provider 中按用户补充信息处理

- [ ] **Step 5: 提交**

```bash
git add README.md
git commit -m "docs: document chat completions continuation behavior"
```

### Final Verification

**Files:**
- Verify only

- [ ] **Step 1: 运行聚焦回归**

Run: `flutter test test/services/agent_planner_service_test.dart test/models/llm/configurable_http_llm_test.dart`
Expected: PASS

- [ ] **Step 2: 运行静态检查**

Run: `flutter analyze`
Expected: PASS，或仅存在与本计划无关的历史问题

- [ ] **Step 3: 进行真机 smoke**

Run: `adb install -r build/app/outputs/flutter-apk/app-debug.apk`
Expected: 安装成功，且最新 debug 包可在 Android 设备上复现通过
