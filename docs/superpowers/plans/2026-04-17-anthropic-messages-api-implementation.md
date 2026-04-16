# Anthropic Messages API 兼容实现计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在保持现有 OpenAI `responses` / `chat/completions` 行为不变的前提下，为运行时可配置 HTTP LLM 通道增加 Anthropic `v1/messages` 协议兼容，并覆盖普通聊天、流式输出、planner 与 provider-native tool use。

**Architecture:** 继续沿用 `ConfigurableHttpLLM` 作为统一运行时入口，通过 `ApiProtocolResolver` 增加第三种 `ApiStyle`，把 Anthropic 的请求构造、SSE 解析和 tool-loop 解析接入现有内部消息 / 决策模型。运行时状态仍复用 `ChatTurnProviderStyle` 与 `providerStateJson`，只补充 Anthropic continuation 所需的最小状态。

**Tech Stack:** Flutter 3.29.2、Dart、`http`、`flutter_test`、现有 provider-native tool loop 架构

---

## 文件结构

本次实现预计涉及以下文件：

- 修改：`/Users/skka/flutterSpace/FlutterAIChat/.worktrees/codex-message-display-optimization/lib/models/llm/api_protocol_resolver.dart`
  - 增加 `anthropicMessages` 协议识别与 `/v1/messages` URI 构造
- 修改：`/Users/skka/flutterSpace/FlutterAIChat/.worktrees/codex-message-display-optimization/lib/models/llm/api_stream_parser.dart`
  - 增加 Anthropic SSE 事件解析
- 修改：`/Users/skka/flutterSpace/FlutterAIChat/.worktrees/codex-message-display-optimization/lib/models/llm/configurable_http_llm.dart`
  - 接入第三种协议的请求头、payload builder、planner 分支、turn decision 分支、非流式文本请求分支
- 新增：`/Users/skka/flutterSpace/FlutterAIChat/.worktrees/codex-message-display-optimization/lib/models/llm/tool_loop/anthropic_messages_tool_loop_adapter.dart`
  - 负责把 Anthropic `tool_use` / assistant content 解析成现有 `ModelTurnDecision`
- 修改：`/Users/skka/flutterSpace/FlutterAIChat/.worktrees/codex-message-display-optimization/lib/models/chat_turn.dart`
  - 增加 Anthropic provider style 枚举值
- 修改：`/Users/skka/flutterSpace/FlutterAIChat/.worktrees/codex-message-display-optimization/lib/services/agent_planner_service.dart`
  - provider continuation items 按 provider style 分流，补 Anthropic `tool_result`
- 测试：`/Users/skka/flutterSpace/FlutterAIChat/.worktrees/codex-message-display-optimization/test/models/llm/configurable_http_llm_test.dart`
  - 增加协议识别、请求头、payload、planner / tool-loop 解析测试
- 视情况新增：`/Users/skka/flutterSpace/FlutterAIChat/.worktrees/codex-message-display-optimization/test/models/llm/api_stream_parser_test.dart`
  - 如果现有单测文件过重，把 Anthropic SSE 解析单独拆开

### Task 1: 补齐协议识别与基础测试

**Files:**
- Modify: `/Users/skka/flutterSpace/FlutterAIChat/.worktrees/codex-message-display-optimization/lib/models/llm/api_protocol_resolver.dart`
- Test: `/Users/skka/flutterSpace/FlutterAIChat/.worktrees/codex-message-display-optimization/test/models/llm/configurable_http_llm_test.dart`

- [ ] **Step 1: 先补失败测试，锁定 `/v1/messages` 识别与 URI 构造**

```dart
test('anthropic messages endpoint resolves and appends correctly', () {
  const resolver = ApiProtocolResolver();

  expect(
    resolver.resolveStyle('https://anthropic.example/v1/messages'),
    ApiStyle.anthropicMessages,
  );
  expect(
    resolver.buildRequestUri(
      'https://anthropic.example',
      ApiStyle.anthropicMessages,
    ).toString(),
    'https://anthropic.example/v1/messages',
  );
});
```

- [ ] **Step 2: 运行单测，确认新增断言先失败**

Run: `cd /Users/skka/flutterSpace/FlutterAIChat/.worktrees/codex-message-display-optimization && fvm flutter test test/models/llm/configurable_http_llm_test.dart`
Expected: FAIL，提示 `ApiStyle.anthropicMessages` 不存在或 URI 构造不符合预期

- [ ] **Step 3: 最小实现协议识别**

```dart
enum ApiStyle {
  chatCompletions,
  responses,
  anthropicMessages,
}
```

```dart
if (path.endsWith('/v1/messages')) {
  return ApiStyle.anthropicMessages;
}
```

- [ ] **Step 4: 实现 Anthropic URI 构造**

```dart
if (style == ApiStyle.anthropicMessages) {
  if (path.endsWith('/v1/messages')) {
    return uri;
  }
  return uri.replace(path: '$path/v1/messages');
}
```

- [ ] **Step 5: 重新运行单测，确认协议识别通过**

Run: `cd /Users/skka/flutterSpace/FlutterAIChat/.worktrees/codex-message-display-optimization && fvm flutter test test/models/llm/configurable_http_llm_test.dart`
Expected: PASS，且已有 OpenAI 协议相关测试不回归

- [ ] **Step 6: 提交这一小步**

```bash
cd /Users/skka/flutterSpace/FlutterAIChat/.worktrees/codex-message-display-optimization
git add lib/models/llm/api_protocol_resolver.dart test/models/llm/configurable_http_llm_test.dart
git commit -m "feat: detect anthropic messages endpoints"
```

### Task 2: 补齐 Anthropic 请求头与普通聊天 payload

**Files:**
- Modify: `/Users/skka/flutterSpace/FlutterAIChat/.worktrees/codex-message-display-optimization/lib/models/llm/configurable_http_llm.dart`
- Test: `/Users/skka/flutterSpace/FlutterAIChat/.worktrees/codex-message-display-optimization/test/models/llm/configurable_http_llm_test.dart`

- [ ] **Step 1: 为 Anthropic 请求头和普通聊天 payload 写失败测试**

```dart
expect(client.lastRequest?.headers['x-api-key'], 'test-key');
expect(client.lastRequest?.headers['anthropic-version'], '2023-06-01');
expect(client.lastRequestBody?['system'], '你是一个助手');
expect(client.lastRequestBody?['messages'], [
  {
    'role': 'user',
    'content': [
      {'type': 'text', 'text': '你好'}
    ],
  },
]);
```

- [ ] **Step 2: 运行目标单测，确认请求头 / payload 断言失败**

Run: `cd /Users/skka/flutterSpace/FlutterAIChat/.worktrees/codex-message-display-optimization && fvm flutter test test/models/llm/configurable_http_llm_test.dart --plain-name "anthropic"`
Expected: FAIL，原因是当前统一使用 Bearer 头且没有 Anthropic message payload

- [ ] **Step 3: 给 `_buildHeaders()` 按协议分流**

```dart
Map<String, String> _buildHeaders(
  LLMConfig config,
  ApiStyle apiStyle,
) {
  if (apiStyle == ApiStyle.anthropicMessages) {
    return {
      'Content-Type': 'application/json',
      'x-api-key': config.apiKey,
      'anthropic-version': '2023-06-01',
    };
  }
  return {
    'Content-Type': 'application/json',
    'Authorization': 'Bearer ${config.apiKey}',
  };
}
```

- [ ] **Step 4: 新增 `_buildAnthropicMessagesPayload()`，先支持 system + text messages**

```dart
Map<String, dynamic> _buildAnthropicMessagesPayload(
  List<ChatMessage> messages,
  ChatConfig config,
  String modelName, {
  required bool stream,
}) {
  return {
    'model': modelName,
    'system': config.systemPrompt,
    'messages': normalizedMessages.map((msg) => {
      'role': msg.role == MessageRole.assistant ? 'assistant' : 'user',
      'content': [
        {'type': 'text', 'text': msg.text},
      ],
    }).toList(),
    'stream': stream,
    'max_tokens': 4096,
  };
}
```

- [ ] **Step 5: 将 `chatStream()`、`validateApiKey()`、`_sendTextRequest()` 接入第三分支**

Run: `cd /Users/skka/flutterSpace/FlutterAIChat/.worktrees/codex-message-display-optimization && fvm flutter test test/models/llm/configurable_http_llm_test.dart`
Expected: PASS，Anthropic 请求头与普通消息 payload 测试通过，其余协议不回归

- [ ] **Step 6: 提交这一小步**

```bash
cd /Users/skka/flutterSpace/FlutterAIChat/.worktrees/codex-message-display-optimization
git add lib/models/llm/configurable_http_llm.dart test/models/llm/configurable_http_llm_test.dart
git commit -m "feat: add anthropic request headers and payloads"
```

### Task 3: 补齐 Anthropic SSE 流式解析

**Files:**
- Modify: `/Users/skka/flutterSpace/FlutterAIChat/.worktrees/codex-message-display-optimization/lib/models/llm/api_stream_parser.dart`
- Test: `/Users/skka/flutterSpace/FlutterAIChat/.worktrees/codex-message-display-optimization/test/models/llm/api_stream_parser_test.dart`

- [ ] **Step 1: 新增流式解析失败测试，覆盖文本与 thinking**

```dart
expect(chunks, contains(jsonEncode({'type': 'content', 'content': '你好'})));
expect(chunks, contains(jsonEncode({'type': 'reasoning', 'content': '先分析'})));
```

可用的模拟事件至少覆盖：

```text
event: content_block_delta
data: {"type":"content_block_delta","delta":{"type":"text_delta","text":"你好"}}

event: content_block_delta
data: {"type":"content_block_delta","delta":{"type":"thinking_delta","thinking":"先分析"}}
```

- [ ] **Step 2: 运行目标单测，确认当前解析器无法识别 Anthropic 事件**

Run: `cd /Users/skka/flutterSpace/FlutterAIChat/.worktrees/codex-message-display-optimization && fvm flutter test test/models/llm/api_stream_parser_test.dart`
Expected: FAIL，当前只支持 `responses` 和 `chat/completions`

- [ ] **Step 3: 为 `ApiStreamParser.parse()` 增加 `anthropicMessages` 分支**

```dart
switch (style) {
  case ApiStyle.anthropicMessages:
    return _parseAnthropicMessagesStream(response);
}
```

- [ ] **Step 4: 实现 `_parseAnthropicMessagesStream()`，容错处理未知事件**

```dart
if (deltaType == 'text_delta' && text.isNotEmpty) {
  yield jsonEncode({'type': 'content', 'content': text});
}
if ((deltaType == 'thinking_delta' || deltaType == 'redacted_thinking_delta') &&
    thinking.isNotEmpty) {
  yield jsonEncode({'type': 'reasoning', 'content': thinking});
}
```

- [ ] **Step 5: 重新运行流式解析测试**

Run: `cd /Users/skka/flutterSpace/FlutterAIChat/.worktrees/codex-message-display-optimization && fvm flutter test test/models/llm/api_stream_parser_test.dart`
Expected: PASS，文本和 thinking 均能映射到内部 chunk

- [ ] **Step 6: 提交这一小步**

```bash
cd /Users/skka/flutterSpace/FlutterAIChat/.worktrees/codex-message-display-optimization
git add lib/models/llm/api_stream_parser.dart test/models/llm/api_stream_parser_test.dart
git commit -m "feat: parse anthropic streaming events"
```

### Task 4: 增加 Anthropic tool-loop adapter 与 planner 解析

**Files:**
- Create: `/Users/skka/flutterSpace/FlutterAIChat/.worktrees/codex-message-display-optimization/lib/models/llm/tool_loop/anthropic_messages_tool_loop_adapter.dart`
- Modify: `/Users/skka/flutterSpace/FlutterAIChat/.worktrees/codex-message-display-optimization/lib/models/llm/configurable_http_llm.dart`
- Test: `/Users/skka/flutterSpace/FlutterAIChat/.worktrees/codex-message-display-optimization/test/models/llm/configurable_http_llm_test.dart`

- [ ] **Step 1: 先写 planner / turn decision 的失败测试**

```dart
expect(choice?.toolName, 'web_search');
expect(choice?.arguments, {'query': 'Anthropic API'});
expect(decision?.toolCalls.first.providerCallId, 'toolu_123');
```

示例响应可包含：

```json
{
  "id": "msg_123",
  "content": [
    {
      "type": "tool_use",
      "id": "toolu_123",
      "name": "web_search",
      "input": {"query": "Anthropic API"}
    }
  ]
}
```

- [ ] **Step 2: 运行目标单测，确认当前无法解析 Anthropic `tool_use`**

Run: `cd /Users/skka/flutterSpace/FlutterAIChat/.worktrees/codex-message-display-optimization && fvm flutter test test/models/llm/configurable_http_llm_test.dart --plain-name "anthropic tool"`
Expected: FAIL，当前 planner 解析只识别 OpenAI 两种结构

- [ ] **Step 3: 新建 `AnthropicMessagesToolLoopAdapter`**

```dart
class AnthropicMessagesToolLoopAdapter {
  const AnthropicMessagesToolLoopAdapter();

  ModelTurnDecision? parseDecision(Map<String, dynamic> payload) {
    // 解析 content 中的 tool_use / text / thinking block
  }
}
```

- [ ] **Step 4: 在 `ConfigurableHttpLLM` 中接入 Anthropic planner choice 和 turn decision 分支**

```dart
final choice = apiStyle == ApiStyle.anthropicMessages
    ? _parsePlannerAnthropicChoice(decoded)
    : ...
```

```dart
final decision = apiStyle == ApiStyle.anthropicMessages
    ? _anthropicMessagesToolLoopAdapter.parseDecision(decoded)
    : ...
```

- [ ] **Step 5: 为 `_toProviderStyle()` 增加 `ChatTurnProviderStyle.anthropicMessages`**

Run: `cd /Users/skka/flutterSpace/FlutterAIChat/.worktrees/codex-message-display-optimization && fvm flutter test test/models/llm/configurable_http_llm_test.dart`
Expected: PASS，Anthropic planner 既能提取 `tool_use`，也能回退直接 assistant 文本

- [ ] **Step 6: 提交这一小步**

```bash
cd /Users/skka/flutterSpace/FlutterAIChat/.worktrees/codex-message-display-optimization
git add lib/models/llm/tool_loop/anthropic_messages_tool_loop_adapter.dart lib/models/llm/configurable_http_llm.dart lib/models/chat_turn.dart test/models/llm/configurable_http_llm_test.dart
git commit -m "feat: add anthropic tool loop parsing"
```

### Task 5: 补齐 Anthropic tool_result continuation

**Files:**
- Modify: `/Users/skka/flutterSpace/FlutterAIChat/.worktrees/codex-message-display-optimization/lib/services/agent_planner_service.dart`
- Modify: `/Users/skka/flutterSpace/FlutterAIChat/.worktrees/codex-message-display-optimization/lib/models/llm/configurable_http_llm.dart`
- Test: `/Users/skka/flutterSpace/FlutterAIChat/.worktrees/codex-message-display-optimization/test/models/llm/configurable_http_llm_test.dart`

- [ ] **Step 1: 为 continuation 写失败测试**

```dart
expect(client.lastRequestBody?['messages'].last, {
  'role': 'user',
  'content': [
    {
      'type': 'tool_result',
      'tool_use_id': 'toolu_123',
      'content': '{"status":"success","data":{"answer":"ok"}}',
    },
  ],
});
```

- [ ] **Step 2: 运行目标单测，确认当前 continuation 只会生成 OpenAI `function_call_output`**

Run: `cd /Users/skka/flutterSpace/FlutterAIChat/.worktrees/codex-message-display-optimization && fvm flutter test test/models/llm/configurable_http_llm_test.dart --plain-name "continuation"`
Expected: FAIL，当前 provider continuation items 不包含 Anthropic `tool_result`

- [ ] **Step 3: 在 `agent_planner_service.dart` 中按 provider style 分流 continuation 构造**

```dart
if (turn.providerStyle == ChatTurnProviderStyle.anthropicMessages) {
  return [
    {
      'role': 'user',
      'content': [
        {
          'type': 'tool_result',
          'tool_use_id': step.providerCallId,
          'content': _encodeProviderStepOutput(step),
        },
      ],
    },
  ];
}
```

- [ ] **Step 4: 在 `ConfigurableHttpLLM` 的 Anthropic planner payload builder 中接入 continuation items**

```dart
payload['messages'] = [
  ...payload['messages'],
  ...continuationItems,
];
```

- [ ] **Step 5: 跑通 continuation 与 turn decision 相关测试**

Run: `cd /Users/skka/flutterSpace/FlutterAIChat/.worktrees/codex-message-display-optimization && fvm flutter test test/models/llm/configurable_http_llm_test.dart`
Expected: PASS，Anthropic continuation 正常续传，OpenAI `responses` continuation 行为不变

- [ ] **Step 6: 提交这一小步**

```bash
cd /Users/skka/flutterSpace/FlutterAIChat/.worktrees/codex-message-display-optimization
git add lib/services/agent_planner_service.dart lib/models/llm/configurable_http_llm.dart test/models/llm/configurable_http_llm_test.dart
git commit -m "feat: continue anthropic tool calls with tool_result"
```

### Task 6: 端到端回归与文档收尾

**Files:**
- Modify: `/Users/skka/flutterSpace/FlutterAIChat/.worktrees/codex-message-display-optimization/docs/superpowers/specs/2026-04-17-anthropic-messages-api-design.md`
  - 仅在实现偏离设计时更新
- Modify: `/Users/skka/flutterSpace/FlutterAIChat/AGENTS.md`
  - 仅在团队约定或实现规则发生变化时更新

- [ ] **Step 1: 运行聚焦单测**

Run: `cd /Users/skka/flutterSpace/FlutterAIChat/.worktrees/codex-message-display-optimization && fvm flutter test test/models/llm/configurable_http_llm_test.dart`
Expected: PASS

- [ ] **Step 2: 运行 SSE 解析测试**

Run: `cd /Users/skka/flutterSpace/FlutterAIChat/.worktrees/codex-message-display-optimization && fvm flutter test test/models/llm/api_stream_parser_test.dart`
Expected: PASS

- [ ] **Step 3: 运行静态检查**

Run: `cd /Users/skka/flutterSpace/FlutterAIChat/.worktrees/codex-message-display-optimization && fvm flutter analyze`
Expected: 如有问题，仅新增问题需要处理；已有历史 `info` 级噪声不作为本次阻塞项

- [ ] **Step 4: 检查设计与实现是否有偏差**

重点核对：

- `thinking` 是否进入现有 reasoning 通道
- endpoint 是否仅由 `/v1/messages` 激活 Anthropic 分支
- OpenAI `responses` / `chat/completions` 是否没有回归

- [ ] **Step 5: 如实现边界有变化，回写文档**

```bash
cd /Users/skka/flutterSpace/FlutterAIChat/.worktrees/codex-message-display-optimization
git add docs/superpowers/specs/2026-04-17-anthropic-messages-api-design.md AGENTS.md
git commit -m "docs: align anthropic implementation notes"
```

- [ ] **Step 6: 最终提交实现**

```bash
cd /Users/skka/flutterSpace/FlutterAIChat/.worktrees/codex-message-display-optimization
git add lib/models/llm lib/models/chat_turn.dart lib/services/agent_planner_service.dart test/models/llm
git commit -m "feat: support anthropic messages api"
```
