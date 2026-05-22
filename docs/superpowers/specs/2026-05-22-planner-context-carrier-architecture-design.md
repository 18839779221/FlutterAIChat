# Planner 上下文 Carrier 架构设计

## 背景

每发现一个 provider 特有字段需要在会话中往返（DeepSeek 的 `reasoning_content`、Anthropic 的 `thinking` 块及 `signature`、OpenAI 的 `cache_control`、未来 Responses API 的新字段等），我们就会在生产环境踩一次 400，然后在 `adapter.parse*` → `ModelTurnDecision` → `turn_harness` 写入 → `ChatEvent` payload schema → `adapter.build*` 这五个点上做协调修改才能修好。

根本原因是分层错误：provider 响应在入站时立刻被**压平**成 provider-agnostic 的 `ChatEvent`，到下一轮出站时又**从这些 events 重建**。任何没有在 `ChatMessage` / `ModelContextItem` 中间类型里建模的信息，都会在"写入边界"上被静默丢弃。

这不是一个 bug，而是**一类 bug**。已确认的具体实例两起（`AskUserQuestion` 工具结果配对、`reasoning_content` 往返）；Anthropic 和 Responses adapter 里还有更多潜在实例。

## 目标

把 provider 形状边界**下沉**：在 adapter parse 时把 provider 响应捕获为**原样 provider JSON**，原样持久化，并在下一次出站请求中逐字节回放。`ChatMessage` / projection 类型只服务于"我方合成"的数据——system prompt、用户输入、工具结果、运行时上下文、compaction 总结。

`SessionContextService` 退化为纯**编排器**，输出有类型的载体列表。`ApiStyleAdapter` 成为唯一拥有 wire 格式知识的层——入站、出站都是。

## 非目标

- 流式 UI 渲染（不改——细粒度 events 保留）
- 跨 provider 消息转换（明确禁止——见 Policy A）
- 兼容现有会话（一次切干净——见迁移章节）

## 架构

### 双轨事件架构

改造后，`ChatEvent` 事件分两条**互不重叠**的轨道：

| 轨道 | 事件 | 消费者 |
|---|---|---|
| **UI 渲染** | `assistantPlannerMessage`、`assistantTextDelta`、`assistantReasoningDelta`、`assistantToolCall`、`assistantQuestionPrompt`、`userInteractionResult`、... | Chat UI、debug inspector |
| **LLM 往返** | `userMessage`、`toolResult`、`toolError`、`userInteractionResult`、**`assistantTurnSnapshot`（新增）** | `SessionContextService.buildPlannerCarriers` |

两条轨道**不变量分离**：LLM 往返路径**绝不**读 UI 事件；UI 路径**绝不**读 `assistantTurnSnapshot`。混读是 code review 红线。

### 分层示意

```
┌────────────────────────────────────────────────────────────────┐
│  HTTP wire（provider 形状的 JSON）                              │
└──────────────────────────────┬─────────────────────────────────┘
                               │
                       ApiStyleAdapter
                       （唯一懂 wire 形状的层）
                               │
   入站：extractRawAssistantMessage / assembleRawFromStreamingSnapshot
                               │  ↓                ↑  出站：
                               │                      buildPlannerPayloadFromCarriers
                               │  ↓                ↑
┌──────────────────────────────┴─────────────────────────────────┐
│  PlannerContextCarrier（sealed）                                │
│    ├─ SyntheticCarrier（system | user | toolResult）            │
│    └─ RawAssistantCarrier（apiStyle + rawJson）                 │
└──────────────────────────────┬─────────────────────────────────┘
                               │
                  SessionContextService
                  （纯编排器：按顺序组合 carrier、
                    compaction、基于 carrier 估算的 token budget）
                               │
┌──────────────────────────────┴─────────────────────────────────┐
│  ChatEvent（持久化）—— 双轨                                       │
│    UI 事件（细粒度） | assistantTurnSnapshot（原样）              │
│    + chat_turn_group.lockedProviderStyle                       │
└────────────────────────────────────────────────────────────────┘
```

## 组件

### 1. `PlannerContextCarrier`（新类型，`lib/models/context/planner_context_carrier.dart`）

```dart
sealed class PlannerContextCarrier {
  const PlannerContextCarrier();
  int get estimatedTokens;
}

class SyntheticCarrier extends PlannerContextCarrier {
  final SyntheticRole role;
  final String content;
  final String? toolCallId;  // role == toolResult 时必填，否则 null
  // estimatedTokens: content.length / 4（沿用现有 heuristic）
}

enum SyntheticRole { system, user, toolResult }

class RawAssistantCarrier extends PlannerContextCarrier {
  final ChatTurnProviderStyle apiStyle;
  final Map<String, dynamic> rawJson;
  // estimatedTokens: 累加 rawJson 中 content + reasoning_content +
  //                  tool_calls[*].function.arguments 的字符数，再除 4
}
```

### 2. 新增 `ChatEventType.assistantTurnSnapshot`

每个产出了非空 provider 响应的 planner iteration 写一条。Schema：

```dart
ChatEvent(
  eventType: ChatEventType.assistantTurnSnapshot,
  role: MessageRole.assistant,
  content: '',  // 不用；raw 在 payload 里
  payloadJson: {
    'apiStyle': 'openaiChatCompletions' | 'anthropicMessages' | 'openaiResponses',
    'rawAssistantMessage': { /* provider 形状的 assistant message JSON */ },
  },
)
```

`ChatEventRepository.appendAssistantTurnSnapshot` 是唯一写入者。

### 3. `chat_turn_group.lockedProviderStyle`（新增字段，NOT NULL）

在创建 group 时用用户当前选中的 provider 写入；不可变。`ConfigurableHttpLLM.planTurnDecision` 入口处做防御性检查：当前 active provider style 必须等于 `lockedProviderStyle`，否则抛错。

### 4. `ApiStyleAdapter` 契约（变更）

```dart
abstract class ApiStyleAdapter {
  // 移除：
  // Map<String,dynamic> buildPlannerPayload({required List<ChatMessage> messages, ...});

  // 新增：
  Map<String, dynamic> buildPlannerPayloadFromCarriers({
    required List<PlannerContextCarrier> carriers,
    required ChatConfig config,
    required String modelName,
    required List<PlannerToolOption> availableTools,
    required bool parallelToolCalls,
    LlmRequestOptions requestOptions,
  });

  Map<String, dynamic>? extractRawAssistantMessage(Map<String, dynamic> responsePayload);
  Map<String, dynamic>? assembleRawFromStreamingSnapshot(StreamingPlannerSnapshot snapshot);

  // 保留：parsePlannerChoice、buildHeaders 等
}
```

各 adapter 实现：
- `SdkChatCompletionsAdapter`：raw 是 `{role: 'assistant', content, tool_calls, reasoning_content, ...}`（OpenAI / DeepSeek 形状）
- `AnthropicMessagesAdapter`：raw 是 `{role: 'assistant', content: [<content_block>, ...]}`（Anthropic 形状，含 thinking/signature）
- `ResponsesAdapter`：raw 匹配 Responses API item 形状

### 5. `PlannerInvariantValidator`（新增，`lib/models/llm/planner_invariant_validator.dart`）

`ConfigurableHttpLLM.planTurnDecision` 在调用 adapter 前执行的预检：

```dart
class PlannerInvariantValidator {
  void validate({
    required List<PlannerContextCarrier> carriers,
    required ChatTurnProviderStyle activeApiStyle,
    required bool currentTurnRunning,
  });
}
```

强制：
- 每个 `RawAssistantCarrier.apiStyle == activeApiStyle`（否则 `InconsistentProviderStateError`）
- 对 `RawAssistantCarrier.tool_calls` 中的每个 `tool_call_id`，列表后续必须有 `SyntheticCarrier(toolResult, toolCallId=<id>)` 配对——**除非**该 carrier 来自正在进行的 turn 且 `currentTurnRunning == true`（允许 AskUserQuestion 挂起中）

### 6. `SessionContextService`（职责变化）

- **解耦**对 `SessionContextProjector` 中 assistant 事件的依赖
- 新方法 `buildPlannerCarriers` 取代 `buildPlannerMessages`，返回 `List<PlannerContextCarrier>`
- carrier 组装顺序：
  1. 运行时用户上下文 → SyntheticCarrier(system, ...)
  2. 当前 snapshot 总结（若存在）→ SyntheticCarrier(system, ...)
  3. 对每个 recent 历史 turn：用户消息 → 该 turn 的 assistant snapshots → 工具结果 / 交互回答（按 event sequence 顺序）
  4. 对当前 turn transcript 同上
- token budget 直接用 `PlannerContextCarrier.estimatedTokens`；`SessionTokenBudgetService.estimateMessagesTokens` 改名/替换为 `estimateCarriersTokens`
- compaction policy 不变：超出 budget 时把最旧的 turn 压成 snapshot 总结（仍是文本）。被 compact 掉的 turn 的 `assistantTurnSnapshot` event **保留在 DB**（方便 inspector 排错），但不再进入 carrier 列表

### 7. `SessionContextProjector`（降级为"仅生产 synthetic 的 carrier 助手"）

改造后，`SessionContextProjector` 只产 `SyntheticCarrier`，且只处理以下事件类型：

| 事件 | 产出 carrier |
|---|---|
| `userMessage` | `SyntheticCarrier(user, content)` |
| `userInteractionResult`（payload 必须有 `providerCallId`） | `SyntheticCarrier(toolResult, toolCallId=<providerCallId>, content)` |
| `toolResult`、`toolError`（必须有 `providerCallId`） | `SyntheticCarrier(toolResult, toolCallId=<providerCallId>, content)` |

所有 assistant 事件分支（`assistantPlannerMessage`、`assistantToolCall`、`assistantQuestionPrompt`、`assistantReasoningDelta` 等）**全部从 projector 删除**——往返路径改读 `assistantTurnSnapshot`。

`ModelContextItem.assistantMessage` 和 `ModelContextItem.assistantToolUse` 两个工厂方法**删除**。

`SdkMessageConverter` 中的 `_isAssistantPlainText`、`_isAssistantToolUse`、`_mergeAssistantWithToolUse` 以及 `convert()` 里的整段合并分支**删除**——这段合并逻辑存在的目的就是"重组"我们现在原样持久化的东西。

2026-05-22 的临时补丁中针对 `assistantQuestionPrompt` 的 skip 分支随上面的 assistant 事件整体删除一起**移除**。同一补丁中 `userInteractionResult` → 工具结果的映射则**保留并泛化**——它就是上面表格里 projector 的标准分支之一。`userInteractionResult` 不带 `providerCallId` 视为 schema 违规（记录日志后跳过）；v12 schema 保证 `providerCallId` 必填。

## 数据流

### 入站（响应 → DB）

```
HTTP response body / SSE 流
  │
  ▼
Adapter:
  ├─ parsePlannerChoice / 流式累积 → ModelTurnDecision
  └─ extractRawAssistantMessage /  → rawJson
     assembleRawFromStreamingSnapshot
  │
  ▼
TurnHarness:
  ├─ 现有：写细粒度事件（planner message、reasoning delta、tool call ...） → UI 轨道
  └─ 新增：appendAssistantTurnSnapshot(apiStyle, rawJson)                    → 往返轨道
```

### 出站（DB → 请求）

```
SessionContextService.buildPlannerCarriers()
  │
  ▼
List<PlannerContextCarrier>（有序）
  │
  ▼
PlannerInvariantValidator.validate(...)  ← 违反契约时立即抛错
  │
  ▼
adapter.buildPlannerPayloadFromCarriers(carriers, ...)
  │
  按顺序把每个 carrier 物化为该 adapter 的 wire 形状：
    例如 SdkChatCompletionsAdapter:
      SyntheticCarrier(system)     → oai.ChatMessage.system(content)
      SyntheticCarrier(user)       → oai.ChatMessage.user(content)
      SyntheticCarrier(toolResult) → oai.ChatMessage.tool(toolCallId, content)
      RawAssistantCarrier          → oai.ChatMessage.fromJson(rawJson) 原样
    AnthropicMessagesAdapter / ResponsesAdapter 把同样的 carrier 列表
    物化为各自的 wire 形状。
  │
  ▼
provider-specific 请求对象 → toJson → HTTP POST
```

### Policy A：会话内 provider 锁定

- 创建 `chat_turn_group` 时把用户当前选中的 provider 写入 `lockedProviderStyle`
- 设置页的 provider 切换器只影响**下一个新会话**；当前已打开会话锁定
- Drawer UI 标注每个 group 锁定的 provider；激活会话时切换控件灰掉
- `ConfigurableHttpLLM.planTurnDecision` 断言 active provider style 等于该 group 的 `lockedProviderStyle`；不等是硬错误（UI 路径下不应可达）

## 失败模式

| 失败 | 检测点 | 处理 |
|---|---|---|
| `RawAssistantCarrier.apiStyle != activeApiStyle` | `PlannerInvariantValidator.validate` | 抛 `InconsistentProviderStateError`，turn 失败 |
| `rawJson` 损坏 / 缺关键字段 | `oai.ChatMessage.fromJson(rawJson)` 抛错 | 传播为 `MalformedRawAssistantError`，附 snapshotId |
| turn 有 `assistantToolCall` 但缺 `assistantTurnSnapshot` | `buildPlannerCarriers` 发现 gap | 抛 `MissingAssistantTurnSnapshotError` |
| 已完成 turn 的 `tool_call_id` 找不到配对的工具结果 | `_validateToolCallPairing` | 抛 `ToolCallPairingError` |

错误一律传播；**绝不静默 fallback**。静默 fallback 就是我们要逃离的那个旧世界（projection 兜底）。

## 迁移

DB schema 升级到 v12。`onUpgrade` v11→v12 **直接 drop** `chat_turn_group`、`chat_turn`、`chat_event`、`session_context_snapshot` 表后按新 schema 重建（新增 `lockedProviderStyle` 字段、新增 `assistantTurnSnapshot` 事件类型）。

非会话表（provider 配置、prompt、skills 存储、app 设置）不动。

不做 legacy-readonly、不做 UI 兼容——App 尚未上线。

## 测试策略

### 单元测试

- `PlannerContextCarrier` 各子类的序列化、`estimatedTokens` 估算
- `PlannerInvariantValidator`：apiStyle 不匹配、tool-call 配对（running vs completed 分支）、纯 synthetic 列表 pass-through
- `SessionContextService.buildPlannerCarriers`：纯 synthetic / 纯 raw / 混合 history；compaction 把 raw snapshot 折叠成 snapshot summary；当前 turn 处于 AskUserQuestion 挂起状态仍能产出合法 carrier 序列
- 对**每个** adapter（3 个）：
  - `extractRawAssistantMessage`：覆盖含 `reasoning_content`、多个 `tool_calls`、list 形 `content` 等真实非流式响应样本
  - `assembleRawFromStreamingSnapshot` round-trip 等同非流式样本（字段逐项相等）
  - `buildPlannerPayloadFromCarriers`：`RawAssistantCarrier` 的 JSON 在最终 payload 中**逐字节相同**
  - tool-call → tool-result 在 messages 序列中配对保留

### 集成测试

- 重写 `test/services/session_context_service_test.dart` 全部既有测试为新 API
- `test/integration/chat_send_live/` 在每个 live 测试结束加断言：构造的 payload 中 assistant 消息字段集合 ⊆ provider 样本字段集合（只透传，不增改）

### 真机回归（无可省略，是设计成立与否的最终判据）

- DeepSeek + 单次 `web_search` round-trip
- DeepSeek + `AskUserQuestion` → 用户回答 → 终态回答
- DeepSeek + 多轮 tool loop 串联
- DeepSeek 思考模型多轮 `reasoning_content`
- turn 中途**强杀 App** 后重启，验证 snapshot 已经持久化、下一轮 planner 请求构造正确

### 不写的测试

- "老数据迁移到新结构"测试（无迁移路径）
- projection fallback 测试（已删除）
- 跨 provider 切换测试（policy A 禁止）

## 落地顺序

1. **类型骨架** —— `PlannerContextCarrier` + `PlannerInvariantValidator` 空骨架 + 单测
2. **DB 迁移 v12** —— drop-and-recreate，添加 `lockedProviderStyle`，添加 event type，repo 方法
3. **入站捕获** —— 各 adapter 实现 `extract*` / `assembleRaw*`，`TurnHarness` 写 snapshot event；round-trip 单测通过
4. **出站编排** —— `SessionContextService.buildPlannerCarriers`、各 adapter 实现 `buildPlannerPayloadFromCarriers`，`ConfigurableHttpLLM` 走 validator → 新 adapter 方法
5. **清理删除** —— 移除旧 `buildPlannerPayload`、projector 中 assistant 分支、`ModelContextItem.assistantMessage` / `assistantToolUse`、`SdkMessageConverter` 合并逻辑、2026-05-22 的 projector 补丁中 `assistantQuestionPrompt` 分支
6. **provider 锁定 UI** —— 新建会话时记录 `lockedProviderStyle`、drawer 显示锁定 provider、会话进行中禁用切换
7. **真机回归** —— 上面 4 个 DeepSeek 场景一一验证

每步独立可验证（dart analyze + 相关测试绿），代码库在每一步结束都可以编译运行。新路径在 Step 4 原子性切换；Step 5 是纯删除已经失效的代码。

## 风险

- **R1 —— 流式 raw 拼接正确性。** `assembleRawFromStreamingSnapshot` 必须把 SSE deltas 累积成完整消息且不丢字段（尤其是后到的 chunk 中的字段，如 `reasoning_content`）。**缓解**：写"流式样本 vs 同等内容非流式样本"的字段相等对照测试
- **R2 —— tool-call 配对校验过严。** validator 必须允许 running turn 中存在未配对 tool_call（AskUserQuestion 挂起），但 completed turn 必须配对完整。**缓解**：显式 `currentTurnRunning` 参数；每个分支独立测试用例
- **R3 —— token budget 估算偏差。** `RawAssistantCarrier.estimatedTokens` 是对 JSON 字符数的估算，可能与真实分词偏差 5-10%。**缓解**：上线后头几周观察 group 的实际 token 使用，必要时调整估算系数
- **R4 —— snapshot 跨 iteration 顺序。** 多 iteration turn 产出多条 snapshot，carrier 顺序必须严格跟 event sequence。**缓解**：event sequence 字段本来就严格递增；补"3-iteration turn 的 carrier 顺序"专项测试
- **R5 —— UI / inspector 对 projector assistant 输出的隐式依赖。** 删除 `ModelContextItem.assistantMessage` 和 projector assistant 分支之前，必须审计所有消费者。**缓解**：Step 5 实施前做一次 `assistantMessage` / `assistantToolUse` 的全仓 grep；任何消费者改为直接读细粒度 UI 事件
