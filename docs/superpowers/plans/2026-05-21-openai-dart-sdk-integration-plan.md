# openai_dart SDK 接入实现计划

对应设计文档：`docs/superpowers/specs/2026-05-21-openai-dart-sdk-integration-design.md`

## Task A：基础设施（依赖 + 消息转换）

### A1. 添加 `openai_dart` 依赖

- `pubspec.yaml` 添加 `openai_dart: ^5.0.0`
- 运行 `fvm flutter pub get`

### A2. 新建 `lib/models/llm/adapters/sdk_message_converter.dart`

消息转换层，核心职责：

1. **单条转换**：我们的 `ChatMessage`（带 `payloadJson.modelContextType`）→ SDK 的 `ChatMessage`
   - `null` / `plainText` + system → `ChatMessage.system(text)`
   - `null` / `plainText` + user → `ChatMessage.user(text)`
   - `null` / `plainText` + assistant → `ChatMessage.assistant(content: text)`
   - `assistantToolUse` → `ChatMessage.assistant(toolCalls: [...])`
   - `userToolResult` → `ChatMessage.tool(toolCallId: ..., content: text)`
   - 其他 contentType（toolInvocation、actionConfirmation 等 UI 专用）→ 跳过或降级为 assistant text

2. **合并逻辑**：遍历消息列表，当 `assistantMessage`（纯文本）后紧跟 `assistantToolUse` 时，合并为单条 `ChatMessage.assistant(content: ..., toolCalls: [...])`

3. **空消息过滤**：跳过 `text.trim().isEmpty` 的消息（与现有 `normalizeMessagesWithConfiguredSystemPrompt` 行为一致）

### A3. 新建 `test/models/llm/adapters/sdk_message_converter_test.dart`

测试用例：
- system / user / assistant 基本转换
- assistantToolUse 转换（含 providerCallId、toolName、arguments）
- userToolResult 转换（含 toolCallId）
- 相邻 assistant + toolUse 合并
- 多条 assistant 文本不合并（间隔有 user 消息）
- 空消息过滤
- 无 payloadJson 的 assistant 消息正确降级

## Task B：SDK 适配器

### B1. 新建 `lib/models/llm/adapters/sdk_chat_completions_adapter.dart`

实现 `ApiStyleAdapter` 接口：

- `style` → `ApiStyle.chatCompletions`
- `buildHeaders` → 委托 `OpenAIClient` 的 auth（Bearer token）
- `buildChatPayload` → 用 `SdkMessageConverter` 转换消息，构建 `ChatCompletionCreateRequest`，序列化为 JSON
- `buildPlannerPayload` → 同上，添加 `tools`（`PlannerToolOption` → SDK `Tool.function`）
- `parsePlannerChoice` → 从 `ChatCompletion.fromJson(payload)` 提取 `ModelTurnDecision`
  - `AssistantMessage.toolCalls` → `ModelToolCall` 列表
  - `AssistantMessage.content` → `assistantMessage`
  - `AssistantMessage.reasoningContent` → `visibleReasoning`
- `extractNonStreamText` → `payload.choices.first.message.content`

内部持有 `OpenAIClient` 实例，懒初始化（首次调用时从 `LLMConfig` 构建）。

注意：`parallelToolCalls` 参数由 SDK 管理，我们传 `null` 让 SDK 决定是否包含此字段（SDK 默认不发送 null 字段）。

### B2. 新建 `lib/models/llm/adapters/sdk_stream_adapter.dart`

将 SDK 的 `Stream<ChatStreamEvent>` 转换为 `Stream<StreamingPlannerChunk>`：

```dart
Stream<StreamingPlannerChunk> adaptStream(Stream<ChatStreamEvent> sdkStream) async* {
  await for (final event in sdkStream) {
    final delta = event.choices?.firstOrNull?.delta;
    if (delta == null) continue;

    // reasoning
    if (delta.reasoningContent != null && delta.reasoningContent!.isNotEmpty) {
      yield StreamingPlannerChunk.reasoningDelta(delta.reasoningContent!);
    }

    // content
    if (delta.content != null && delta.content!.isNotEmpty) {
      yield StreamingPlannerChunk.contentDelta(delta.content!);
    }

    // tool calls
    if (delta.toolCalls != null) {
      for (final tc in delta.toolCalls!) {
        if (tc.id != null && tc.function?.name != null) {
          yield StreamingPlannerChunk.toolCallStarted(
            toolCallIndex: tc.index,
            providerCallId: tc.id,
            toolName: tc.function!.name,
          );
        }
        if (tc.function?.arguments != null && tc.function!.arguments!.isNotEmpty) {
          yield StreamingPlannerChunk.toolCallArgumentsDelta(
            toolCallIndex: tc.index,
            providerCallId: tc.id,
            toolName: tc.function?.name,
            argumentsTextDelta: tc.function!.arguments!,
          );
        }
      }
    }
  }
  yield const StreamingPlannerChunk.streamCompleted();
}
```

### B3. 新建 `test/models/llm/adapters/sdk_chat_completions_adapter_test.dart`

测试用例：
- `buildPlannerPayload` 输出包含 `model`、`messages`、`tools`、`tool_choice`
- `buildPlannerPayload` 输出不含 `parallel_tool_calls`（SDK 管理）
- `parsePlannerChoice` 解析 text-only 响应
- `parsePlannerChoice` 解析 tool_calls 响应
- `parsePlannerChoice` 解析 reasoning_content
- `extractNonStreamText` 正确提取文本
- DeepSeek 模型场景：消息合并后序列正确

## Task C：切换机制

### C1. 重命名现有 adapter

- `chat_completions_adapter.dart` → `legacy_chat_completions_adapter.dart`
- 更新所有 import 引用

### C2. 修改 `ConfigurableHttpLLM`

- `_defaultAdapters` 中 `ApiStyle.chatCompletions` 默认指向 `SdkChatCompletionsAdapter`
- 新增 `_legacyAdapters` map
- 构造函数接受一个可选的 `bool useSdkChatAdapter` 参数（默认 `true`）
- 或者通过 `AppSettingsRepository` 读取配置

### C3. 添加配置项

- `AppSettingsRepository` 添加 `getChatCompletionsAdapterType()` → `'sdk'` | `'legacy'`
- `main.dart` 中读取配置传递给 `ConfigurableHttpLLM`
- 设置页可选：添加一个开发者开关（可后续做，不阻塞核心功能）

## Task D：集成验证

### D1. 单元测试

- `flutter test test/models/llm/adapters/` — 全部 adapter 测试通过
- `flutter test test/models/llm/configurable_http_llm_test.dart` — 现有 LLM 测试不受影响

### D2. Live 测试

- `bash scripts/run_live_llm_contract_tests.sh minimax-openai`
- 手动在 Android 设备用 DeepSeek 发送带工具调用的消息，确认不再 400

### D3. 回退验证

- 设置中切换到 `legacy` adapter
- 重复 DeepSeek 测试，确认回退到旧行为（400 复现）
- 切回 `sdk`，确认恢复正常

## 执行顺序

```
A1 (依赖) → A2 (消息转换) → A3 (转换测试)
                                ↓
                              B1 (SDK adapter) → B2 (流式适配) → B3 (adapter 测试)
                                                                    ↓
                                                                  C1 (重命名) → C2 (切换逻辑) → C3 (配置)
                                                                                                    ↓
                                                                                                  D1 (单元测试) → D2 (live) → D3 (回退)
```

A2/A3 和 B1/B2/B3 可以并行推进（消息转换和 adapter 实现互不阻塞）。
