# Streaming Response Buffer Design

## 背景

当前聊天回复的“打字机”体验并不是一个独立动画器在按固定速率吐字，而是模型每返回一个流式文本片段，客户端就立刻做一次完整消费：

- 当前主回答链路直接消费上游流式文本片段，不再依赖单独的 `ChatService.streamFinalAnswer()` 包装层
- `ChatSendCoordinator` 每个 delta 都会更新消息文本，并立即写入存储
- UI 渲染层会基于更新后的整段文本重新构建消息块
- 助手最终回答默认使用 Markdown 渲染，长文本时重建成本会持续变高

当新模型输出更长、chunk 更碎时，这条链路会同时放大：

1. UI 刷新频率
2. 数据库存储频率
3. Markdown 全量重建频率

于是用户体感上会出现“回复整体出来很慢”的问题，尤其是在长回答和代码块较多时更明显。

## 目标

本次设计目标如下：

1. 降低长回复场景下的流式渲染卡顿感
2. 保持“正在输出”的实时感，不改成一次性整段出现
3. 将上游模型输出节奏与 UI / 持久化消费节奏解耦
4. 保证最终文本不丢失，完成态与中断态都可正确落盘
5. 以小范围增量改造为主，不重写现有 LLM 协议和 controller 边界

## 非目标

本轮设计明确不包含：

- 不引入通用事件总线或重型消息队列框架
- 不修改 `BaseLLM` / `ChatService` 的流式协议
- 不重写整个 assistant message rendering pipeline
- 不在本轮处理 reasoning 流的独立渲染优化
- 不实现复杂优先级调度或多消费者插件架构

## 核心判断

这个问题本质上不是“打字机速率固定”，而是“生产快、消费贵”：

- 生产端：LLM 流式返回 delta，频率高且粒度不稳定
- 消费端：每个 delta 都触发 UI 状态更新、整段文本重算，以及存储写入

因此本次优化重点应该是：

- 隔离生产与消费
- 对 UI 和存储分别做不同频率的 flush
- 降低生成中渲染成本

## 方案总览

推荐引入一个轻量的 `AssistantStreamOutputBuffer`，作为单生产者、双消费者的缓冲层。

```text
LLM delta producer
    ↓
AssistantStreamOutputBuffer
    ├─ UI consumer (高频 flush，约 24-33ms)
    └─ Persistence consumer (低频 flush，约 200-250ms)
    ↓
final flush on finish / cancel / error
```

该对象不承担业务编排职责，只负责：

1. 接收上游 delta
2. 拼接完整文本
3. 节流 UI flush
4. 节流持久化 flush
5. 在结束时强制同步最终文本

## 推荐架构

### 1. 新增流式输出缓冲服务

建议新增：

- `lib/services/assistant_stream_output_buffer.dart`

建议职责：

- 接收 `onDelta(String chunk)`
- 维护完整 `fullText`
- 使用独立的 UI flush 定时器，推送最新可见文本
- 使用独立的持久化 flush 定时器，推送最新落盘文本
- 在 `finish()` / `cancel()` / `dispose()` 时完成最终同步

建议接口：

- `void onDelta(String chunk)`
- `Future<void> finish()`
- `Future<void> cancel()`
- `void dispose()`

建议构造参数：

- `FutureOr<void> Function(String text) onUiFlush`
- `FutureOr<void> Function(String text) onPersistFlush`
- `Duration uiFlushInterval`
- `Duration persistFlushInterval`

### 2. 在 ChatSendCoordinator 中接入缓冲层

当前 `ChatSendCoordinator` 在 `assistantTextDelta` 分支里直接：

- `appendToMessage(...)`
- `dbHelper.updateMessage(...)`

本次建议改为：

1. 首次 delta 到来时创建 assistant placeholder message
2. 为该 message 创建一个 `AssistantStreamOutputBuffer`
3. 后续每个 delta 仅调用 `buffer.onDelta(chunk)`
4. `finalAnswer` 到来时先 `buffer.finish()`，然后删除 placeholder，并落一条新的 completed 最终回答消息
5. 错误、中断、取消时也调用最终 flush，再切换状态

这样可以把“消费节奏控制”从 coordinator 的业务流程中剥离出来。

### 3. 区分 UI 消费和持久化消费

这两个消费者不应继续绑在一个 delta 处理动作里：

- UI 目标是保持流畅，允许跳过中间很多小更新，只保留最新快照
- 持久化目标是最终正确，不需要追每个 delta

因此建议：

- UI flush：约每 `33ms`
- DB flush：约每 `250ms`
- `finish/cancel/error`：立即强制 flush

### 4. 生成中渲染使用轻量路径

即使加了 buffer，如果生成中的每次 flush 仍然重建整段 Markdown，长回复时体感仍可能继续变差。

因此建议在第一阶段缓冲层接入后，再顺手引入生成中轻量渲染：

- `MessageStatus.generating` 时优先使用轻量文本组件
- `MessageStatus.completed` 后再切回正式 Markdown 渲染

这能显著降低长回复中后段的重建成本。

## 组件边界

### AssistantStreamOutputBuffer

负责：

- 输入节流
- 文本累计
- UI / DB flush 协调

不负责：

- 新建消息
- 状态机切换
- tool flow / interaction flow 编排

### ChatSendCoordinator

继续负责：

- turn event 投影
- placeholder 创建
- send state 切换
- 最终消息完成/失败/中断状态更新

不再负责：

- 每个 delta 的逐条 UI 写入节奏
- 每个 delta 的逐条 DB 写入节奏

### UI 渲染层

继续负责：

- 根据 `ChatMessage.status` 和 `contentType` 决定渲染方式

新增职责：

- `generating` 状态下走轻量渲染分支

## 参数建议

第一版建议使用固定参数，不做自适应：

- UI flush interval: `33ms`
- Persistence flush interval: `250ms`

第二阶段如需继续优化，再加简单自适应规则：

- 文本长度超过 `1000` 字后，UI flush interval 放宽到 `48ms`

## 正确性要求

设计中最重要的约束是最终文本正确：

1. 中间过程允许 UI 跳帧
2. 中间过程允许持久化低频同步
3. `finish()` 必须保证最终完整文本已同步到 UI 和存储
4. `cancel()` / `error` 也必须保留已生成内容，不得回退到旧文本

换句话说，中间态可以近似，最终态必须精确。

## 测试策略

### 缓冲服务测试

新增测试建议：

- 高频 `onDelta()` 下，UI flush 次数少于 delta 次数
- 高频 `onDelta()` 下，持久化 flush 次数少于 UI flush 次数
- `finish()` 后最终文本完整
- `cancel()` 后已生成文本不会丢失
- `dispose()` 后不会继续触发 flush

### Coordinator 回归测试

需要补充：

- assistant 流式消息在长回复场景下仍能最终变为 `completed`
- 中断时消息保留最后一段已输出文本
- 失败时消息文本和状态仍符合当前行为

### UI 测试

需要补充：

- `generating` 状态走轻量组件
- `completed` 状态恢复正式 Markdown 渲染

## 风险与控制

### 风险 1：最终文本被旧 timer 覆盖

控制方式：

- flush 始终基于 buffer 当前完整文本
- `finish()` 先停止 timer，再执行最终同步

### 风险 2：中断分支丢失最后若干 chunk

控制方式：

- `cancel()` 明确触发一次最终 flush
- coordinator 在状态切换前等待 flush 完成

### 风险 3：buffer 生命周期泄漏

控制方式：

- 每条 active assistant stream 只绑定一个 buffer
- 完成、错误、取消后统一 `dispose()`

## 实施顺序

建议分两步推进：

1. 先接入 `AssistantStreamOutputBuffer`，解决 UI/DB 合批刷新
2. 再为 `generating` 状态引入轻量渲染组件

这样可以先拿到主要收益，再决定是否继续做第二步优化。

## 结论

本次问题有必要做“轻量 producer-consumer 化”，但没有必要上重型消息队列架构。

对当前仓库最合适的方案是：

- 在 `ChatSendCoordinator` 和渲染层之间新增一个小型流式输出缓冲对象
- 用不同 flush 频率解耦 UI 与持久化消费
- 进一步为生成中消息提供轻量渲染路径

这个方向能够在不破坏现有 controller / service 边界的前提下，显著改善长回复场景下的输出体感。
