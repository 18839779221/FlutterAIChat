# Codex 风格 Steer / Queue 与中断半截回复恢复设计

## 摘要

本设计把用户在大模型执行期间的追加输入拆成两类：

- `Steer`：默认模式，目标是尽快引导当前 active turn 的下一次 planner 请求
- `Queue`：可选模式，排队到当前 turn 结束后再作为下一 turn 的起始输入

同时，本设计还解决一个更关键的问题：

- 大模型回复中断时，已生成的半截 assistant 输出必须进入后续上下文
- 还要附加一条轻量 `system-reminder` 风格的 userMessage，让模型知道这段输出没有正常完成

本轮强调的是 **spec / plan**，不是实现：

- 不引入新的兼容层
- 不改变 `TurnHarness` 作为唯一 turn loop 主入口的原则
- 不把“追加输入”做成 token 级、chunk 级的抢占
- 不依赖时间戳排序恢复语义顺序

## 背景

当前项目已经具备：

- append-only transcript
- turn / step ledger
- session context snapshot
- resume / confirmation / ask-user 相关恢复链路

但还缺少一套统一的“运行中追加输入”语义：

- 用户在模型恢复期间继续提问时，当前系统没有明确区分“引导当前 turn”与“排到下一 turn”
- 模型输出到一半出错或被中断时，已生成的半截 assistant 内容不会稳定进入后续 context
- 当前 `userMessage` 语义仍主要服务于 turn 起始输入，不足以表达中途追加

## 目标

1. 支持 `Steer` 与 `Queue` 两种追加输入模式。
2. 默认模式为 `Steer`，`Queue` 为显式可选。
3. `Steer` 只在 **下一次 planner 请求发起前** 统一消费，不新增更多插入时机。
4. 追加输入在真正消费前不落库；App 被强杀时，未消费输入可以直接丢弃。
5. 半截 assistant 输出进入后续模型上下文，并与轻量 `system-reminder` 形成互文。
6. 扩展 `userMessage` 语义，允许一个 turn 内出现多条连续 `start` 消息。
7. transcript 顺序只认 append 顺序，不靠 timestamp 判定语义顺序。

## 非目标

- 不做 token 级抢占
- 不做任意 tool call 中途插入
- 不做 provider-native continuation 的新语义层
- 不引入独立的持久化 pending follow-up 表
- 不把 partial assistant 只作为 UI 草稿，不进入模型上下文
- 不重新设计 `TurnHarness` 的主状态机

## 核心术语

### Dispatch Mode

用户对一条追加输入的运行时意图：

- `steer`
- `queue`

它只描述“想走哪条路径”，不直接决定最终 transcript subtype。

### User Message Kind

用户输入落入 transcript 后的真实语义类型：

- `start`
- `follow_up`
- `system_reminder`

它由 **实际插入位置** 决定，而不是由 dispatch mode 直接决定。

### Pending Follow-up

运行期内暂存、尚未消费的追加输入。

- 只存在于内存
- 不先写数据库
- 真正消费时才写入 transcript / ledger

## 设计原则

### 1. 默认 Steer

用户继续输入时，默认应当更像“引导当前对话”，而不是机械排队到下一轮。

### 2. 单一消费点

`Steer` 的消费时机必须收敛到一处：

- **下一次 planner 请求发起前**

不再拆成多个“可插入点”。

### 3. 队列只在消费时持久化

追加输入先进入运行期队列。

- 未消费时，App 退出可直接丢弃
- 已消费时，才写入 transcript / ledger

### 4. transcript 为唯一语义事实源

顺序、恢复、context 组装都以 transcript 为准。

- 时间戳只作展示
- 不允许靠时间戳恢复事件先后

## 输入模型

### 1. Steer

`Steer` 表示：

- 目标是当前 active turn
- 但只在下一次 planner 请求发起前统一消费
- 如果当前 turn 已经过了可插入边界，则该条输入改为下一 turn 的 `start`

### 2. Queue

`Queue` 表示：

- 明确不影响当前 turn 的后续 planner 请求
- 在当前 turn 结束后，作为下一 turn 的起始输入消费

### 3. 用户心智与实际类型

同一条用户输入的最终 `kind` 由消费时机决定：

- 插入到当前 turn transcript 内，且位于首个非 user 语义事件之前，则为 `start`
- 插入到当前 turn transcript 内，且位于首个非 user 语义事件之后，则为 `follow_up`
- 应用内插入的轻量提示为 `system_reminder`

## Transcript 语义

### 1. `start` 可以有多条连续

不再约定一个 turn 只有一条 `kind=start` userMessage。

一个 turn 允许出现多条连续 `start`，只要它们都位于该 turn 的起始用户输入段中，且尚未出现首个非 user 语义事件。

### 2. `follow_up` 由插入位置决定

`follow_up` 不是“用户选择了 steer 就必然 follow_up”。

只有当该条输入被消费时已经处在 turn 执行中段，它才是 `follow_up`。

### 3. 顺序只认 append 顺序

所有模型可见上下文的顺序必须由 transcript 的 append 顺序决定：

- `chat_events.sequence`
- 或等价的事件自增 id

禁止用 timestamp 排序重建语义顺序。

## Partial Assistant 恢复

### 1. 必须进入上下文

模型回复中断时，已生成的半截 assistant 输出必须进入后续模型上下文。

### 2. 与 system-reminder 互文

半截 assistant 输出后紧跟一条轻量 `system-reminder` 风格的 userMessage，让模型明确：

- 这段 assistant 输出没有完成
- 下一轮需要延续而不是重写

### 3. 推荐上下文形态

模型可见上下文中的推荐形态：

1. 一条 assistant message，内容为半截输出
2. 一条轻量 userMessage，内容类似：
   - `User interrupted the previous response before it completed.`
   - `The previous response was interrupted before it completed.`

该 reminder 不应过重，不应引导模型过度关注它本身，只需提供事实提示。

### 4. 持久层语义

持久层仍应保留稳定的 partial / snapshot 事实，供：

- UI 恢复
- 调试
- 后续 context 重建

但模型上下文以 transcript projection 为准。

## 上下文组装规则

### 1. `chat_turn.userInput`

`chat_turn.userInput` 只保留 turn 起始输入的兼容镜像，不再承载完整 transcript 真相。

### 2. planner-visible context

下一轮 planner 可见上下文必须包含：

- runtime user context
- snapshot summary
- recent completed turns
- 当前 turn transcript
- 需要恢复的 partial assistant + reminder

### 3. 中断恢复

如果某 turn 已中断，但其半截 assistant 已形成稳定语义，则下轮 context 必须能看见它。

## 状态与边界

### 1. Steer 消费边界

唯一允许的消费边界：

- 下一次 planner 请求发起前

### 2. Queue 消费边界

唯一允许的消费边界：

- 当前 turn 终结后，创建下一 turn 前

### 3. 应用退出

未消费的追加输入不持久化。

- App 强杀
- 进程退出
- 断电

都可以视为未消费输入丢弃。

## 测试策略

### 1. 输入模式

验证：

- 默认模式是 `Steer`
- `Queue` 可显式选择
- `Steer` 只在下一次 planner 前消费

### 2. transcript 语义

验证：

- 一个 turn 可以有多条连续 `start`
- `follow_up` 由插入位置决定
- 顺序不依赖 timestamp

### 3. partial 恢复

验证：

- 中断时已生成 partial 会进入后续 context
- partial + reminder 共同表达“上一轮未完成”

### 4. 运行期丢弃

验证：

- 未消费 follow-up 不落库
- App 退出后不会生成死消息

## 风险

1. 复用 `userMessage` 语义后，部分既有逻辑可能默认“turn 内只有一条 userMessage”。
2. 若 reminder 文案过重，可能影响模型继续而不是自然续接。
3. 若顺序仍有任何地方依赖 timestamp，连续追加场景会出现不稳定重排。

## 结论

本设计的核心是把“追加输入”从单一发送行为，提升为 **运行期调度语义**：

- `Steer` 默认引导当前 turn
- `Queue` 显式排到下一 turn
- 半截 assistant 进入上下文
- transcript 顺序只认 append 顺序
- 未消费输入不落库
