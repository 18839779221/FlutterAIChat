# openai_dart SDK 接入：Chat Completions 协议层双轨设计

## 背景

`ChatCompletionsAdapter` 及相关解析层（`OpenAIChatCompletionsToolLoopAdapter`、`ApiStreamParser._parseChatCompletionsPlannerChunks`）是自行实现的 OpenAI Chat Completions 协议适配。在 DeepSeek 等非 OpenAI provider 上反复出现兼容性问题：

- **当前 bug**：`SessionContextProjector` 将 planner 的文本输出和 tool_use 输出投影为两条独立的 assistant 消息，导致发给 DeepSeek 的消息序列中出现不带 `tool_calls` 的 assistant 消息紧接带 `tool_calls` 的 assistant 消息，DeepSeek 对此返回 400（"An assistant message with 'tool_calls' must be followed by tool messages"）
- **历史问题**：`parallel_tool_calls` 参数不被 DeepSeek 支持（已临时修复）、`reasoning_content` 字段兼容等

根本原因是自实现的协议层无法覆盖所有 provider 的 quirks，且每次修复都是点状补丁。

**`openai_dart` v5.0.0**（by davidmigloz，[ai_clients_dart](https://github.com/davidmigloz/ai_clients_dart)）是一个高质量社区 Dart SDK：
- 127 likes, 22.4k 月下载, 18天前发版, MIT 协议
- 消息模型正确实现 OpenAI API 规范（`AssistantMessage` 的 `content` + `toolCalls` 合并到同一条消息）
- 已内置 DeepSeek `reasoning_content` 兼容，并提供 `toApiJson()` 排除 reasoning 字段避免 400
- 不可变 sealed class 消息模型，类型安全
- 支持 streaming + tool calls + OpenRouter 等扩展

## 目标

1. 引入 `openai_dart` 作为 Chat Completions 协议的**主实现**（`SdkChatCompletionsAdapter`）
2. 保留现有自实现作为**可回退的 backup**（`LegacyChatCompletionsAdapter`）
3. 默认使用 SDK，通过运行时配置一键切换回 legacy
4. SDK 只接管 Chat Completions 路径；Responses API 和 Anthropic Messages 继续用现有 adapter
5. 修复 DeepSeek 400 bug（消息序列合并问题在 SDK 侧自然解决）
6. 上层架构（`BaseLLM`、`ConfigurableHttpLLM`、`TurnHarness`、`AgentPlannerService`）**不改动**

## 非目标

- 不替换 Responses API 或 Anthropic Messages 的 adapter
- 不修改 `BaseLLM` 接口签名
- 不修改 `ConfigurableHttpLLM` 的传输/路由/重试逻辑
- 不引入新的 DI 框架
- 不替换 `SessionContextProjector` 或 `ModelContextItemEncoder`（消息投影层保持不变）
- 不引入 Anthropic Dart SDK（当前不在范围内）

## 现状分析

### 当前 Chat Completions 请求构建链路

```
TurnHarness → AgentPlannerService.planTurnDecision
  → ConfigurableHttpLLM.planTurnDecision
    → ChatCompletionsAdapter.buildPlannerPayload    // 构建请求 JSON
      → ChatCompletionsAdapter._buildMessage        // 逐条转换 ChatMessage → wire format
    → ApiStreamParser._parseChatCompletionsPlannerChunks  // 解析流式响应
    → StreamingDecisionAccumulator                   // 组装 ModelTurnDecision
```

### 问题根因

`SessionContextProjector.projectEventToContextItem` 为每个 `ChatEvent` 独立投影：

| 事件类型 | 投影结果 | wire format |
|---------|---------|-------------|
| `assistantPlannerMessage` | `assistantMessage` | `{role: 'assistant', content: '我需要查询...'}` |
| `assistantToolCall` | `assistantToolUse` | `{role: 'assistant', content: '', tool_calls: [...]}` |
| `toolResult` | `userToolResult` | `{role: 'tool', tool_call_id: '...', content: '...'}` |

OpenAI 对此宽容（允许连续多条 assistant 消息），DeepSeek 严格校验 tool_calls 后必须紧跟 tool 消息。

### openai_dart SDK 的正确实现

```dart
// AssistantMessage.toJson() - content + tool_calls 合并
{
  'role': 'assistant',
  if (content != null) 'content': content,        // 文本
  if (toolCalls != null) 'tool_calls': toolCalls,  // 工具调用 — 同一条消息！
}

// ToolMessage.toJson()
{ 'role': 'tool', 'tool_call_id': '...', 'content': '...' }
```

### 现有 adapter 接口

```dart
abstract class ApiStyleAdapter {
  ApiStyle get style;
  Map<String, String> buildHeaders(LLMConfig runtimeConfig);
  Map<String, dynamic> buildChatPayload({...});
  Map<String, dynamic> buildPlannerPayload({...});
  PlannerToolChoice? parsePlannerChoice(Map<String, dynamic> payload);
  String extractNonStreamText(Map<String, dynamic> payload);
}
```

SDK adapter 实现此接口即可无缝接入 `ConfigurableHttpLLM` 的路由逻辑。

## 设计方案

### 架构总览

```
ConfigurableHttpLLM._adapters:
  ApiStyle.chatCompletions  → SdkChatCompletionsAdapter (默认)
                           ↘ LegacyChatCompletionsAdapter (backup)
  ApiStyle.responses        → ResponsesAdapter (不变)
  ApiStyle.anthropicMessages → AnthropicMessagesAdapter (不变)
```

### 新增文件

| 文件 | 职责 |
|------|------|
| `lib/models/llm/adapters/sdk_chat_completions_adapter.dart` | SDK 主适配器，实现 `ApiStyleAdapter` |
| `lib/models/llm/adapters/sdk_message_converter.dart` | 我方 `ChatMessage` → SDK `ChatMessage` 转换，含合并逻辑 |
| `lib/models/llm/adapters/sdk_stream_adapter.dart` | SDK 流式事件 → `StreamingPlannerChunk` 转换 |
| `test/models/llm/adapters/sdk_chat_completions_adapter_test.dart` | 单元测试 |

### 修改文件

| 文件 | 改动 |
|------|------|
| `pubspec.yaml` | 添加 `openai_dart: ^5.0.0` |
| `lib/models/llm/adapters/chat_completions_adapter.dart` | 重命名为 `legacy_chat_completions_adapter.dart` |
| `lib/models/llm/configurable_http_llm.dart` | adapter 选择逻辑（读取配置决定用 SDK 还是 legacy） |
| `lib/repositories/app_settings_repository.dart` | 添加 `llm.chat_completions_adapter` 配置项 |
| `lib/models/llm/llm_factory.dart` | 传递配置到 `ConfigurableHttpLLM` |

### 关键设计：消息转换与合并

`SdkMessageConverter` 负责将我们的 `ChatMessage`（带 `payloadJson`）转换为 SDK 的 `ChatMessage`：

```dart
// 核心合并逻辑
List<oai.ChatMessage> convertWithMerging(List<ChatMessage> messages) {
  final result = <oai.ChatMessage>[];
  for (var i = 0; i < messages.length; i++) {
    final current = messages[i];
    final next = i + 1 < messages.length ? messages[i + 1] : null;

    // 合并: assistantMessage + assistantToolUse → 单条 assistant(content + toolCalls)
    if (_isAssistantText(current) && next != null && _isAssistantToolUse(next)) {
      result.add(oai.ChatMessage.assistant(
        content: current.text,
        toolCalls: _convertToolCalls(next),
      ));
      i++; // 跳过 next
      continue;
    }

    result.add(_convertSingle(current));
  }
  return result;
}
```

### 关键设计：流式响应适配

`SdkStreamAdapter` 将 SDK 的 `Stream<ChatStreamEvent>` 转换为 `Stream<StreamingPlannerChunk>`，对接现有 `StreamingDecisionAccumulator`：

```
SDK delta.content          → StreamingPlannerChunk.contentDelta
SDK delta.toolCalls[i].id  → StreamingPlannerChunk.toolCallStarted
SDK delta.toolCalls[i].fn  → StreamingPlannerChunk.toolCallArgumentsDelta
SDK delta.reasoningContent → StreamingPlannerChunk.reasoningDelta
SDK stream end             → StreamingPlannerChunk.streamCompleted
```

### 关键设计：运行时切换

`AppSettingsRepository` 中新增配置键 `llm.chat_completions_adapter`，值为：
- `sdk`（默认）— 使用 `SdkChatCompletionsAdapter`
- `legacy` — 使用 `LegacyChatCompletionsAdapter`

`ConfigurableHttpLLM` 构造时根据此配置注入对应的 adapter：

```dart
final chatAdapter = useSdkAdapter
    ? SdkChatCompletionsAdapter(settingsRepository: settingsRepository)
    : LegacyChatCompletionsAdapter();
```

在设置页可以加一个开关让用户切换，或通过 `config/local_defaults.json` 配置。

### 与现有工具循环的兼容

SDK adapter 返回的 `ModelTurnDecision` 与现有完全一致：

```dart
ModelTurnDecision(
  toolCalls: [ModelToolCall(providerCallId: 'call_1', toolName: 'web_search', arguments: {...})],
  assistantMessage: '我来搜索一下',
  providerState: {'response_id': 'chatcmpl-xxx'},
  isTerminal: false, // 有 toolCalls
)
```

下游的 `TurnHarness`、`DecisionToolCallExecutor`、`ToolCallService` 完全不需要改动。

## 验证标准

1. `flutter test` — 全量单元测试通过
2. `flutter test test/models/llm/adapters/` — 新旧 adapter 测试均通过
3. Android 设备 + DeepSeek (chat completions)：发送需要工具调用的消息，确认不再 400
4. 设置中切换回 legacy adapter，原有行为不变
5. `bash scripts/run_live_llm_contract_tests.sh minimax-openai` — live provider 测试通过
