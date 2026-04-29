# DecisionBatch 最小领域模型设计

## 背景

当前项目已经具备以下结构化运行时基础：

- `ChatTurn` 表达一次用户请求对应的完整 Agent Loop
- `ChatTurnStep` 表达 turn 内的结构化执行单元
- `ChatEvent` 表达 turn 内的追加式 transcript
- `providerResponseId` / `providerCallId` 已开始承接 provider-native continuation 语义

随着真实 provider live integration 测试推进，一个新的语义缺口已经稳定暴露出来：

- 同一次 planner/provider 决策可能同时产出多个 tool call
- 这些 tool call 在 provider 侧天然属于同一批次
- 当前系统虽然已经能通过 `providerResponseId` 与 `providerCallId` 恢复大部分 provider 侧关系
- 但 Core、Projection、Assertion 仍然缺少一层显式的“决策批次”语义

结果是：

1. `step` 很容易被误用来同时表达“单个执行单元”和“一整批调用”
2. live integration 测试容易写出 `step 数 == 决策批次数` 之类错误假设
3. UI workflow 归并仍有较多逻辑依赖消息 payload 与 event 顺序反推
4. 对外看似是 provider 兼容问题，实则是内部领域语义仍未收紧

因此，本设计提出一个最小化的 `DecisionBatch` 领域模型：

- 先统一语义
- 先不落库
- 先不新增新表
- 先服务于 Core 解释、Projection 归并与 Headless Live Integration 断言

## 目标

本设计目标如下：

1. 明确区分以下三层语义：
   - `turn`
   - `decision batch`
   - `step`
2. 保留 `step = 单个执行单元` 的语义纯度
3. 让“同一轮模型决策内的多个 tool call 属于同一批次”不再依赖隐式推断
4. 为 `ChatBlockBuilder`、live integration assertions、后续 ask-user / mixed failure 场景提供统一归并语义
5. 保持现有数据库结构与 provider adapter 主链路不必立即重构

## 非目标

本轮不做以下事情：

1. 不新增 `decision_batches` 数据库表
2. 不修改 provider HTTP wire format
3. 不把 `DecisionBatch` 直接暴露为 UI 持久化实体
4. 不重写 `TurnHarness` 主状态机
5. 不要求当前所有历史测试立即切换到 batch 断言

## 为什么不能只靠 `providerResponseId + providerCallId`

`providerResponseId + providerCallId` 已足够表达 provider 侧关系，但不足以直接替代内部领域模型。

### 1. 它们首先是 provider 协议键

- `providerResponseId` 回答“这些调用来自哪一次 provider 决策响应”
- `providerCallId` 回答“这个结果对应哪一个具体 tool call”

它们适合做：

- continuation item 匹配
- tool result 回填
- 同批次 workflow 归组

但它们不直接表达：

- 该批次当前处于 `planned / running / waiting / completed / failed` 哪种状态
- 该批次是否带有 assistant 文本
- 该批次整体是否已经结束，还是等待用户确认 / 回答

### 2. `step` 的职责与 provider key 不同

根据当前架构约束：

- `ChatTurnStep` 属于 Agent Loop Core
- 它承担的是单个执行单元的结构化状态真相

因此：

- `providerResponseId` / `providerCallId` 解决“映射关系”
- `step` 解决“执行状态”

如果没有 batch，系统就容易把“一个 step 代表一个 tool call”与“多个 step 属于同一次决策”混在一起。

## 当前推荐的语义分层

长期推荐分层如下：

### 1. `ChatTurn`

表示：

- 一次用户输入触发的完整 Agent Loop

负责表达：

- 本轮用户目标
- turn 级终态
- turn 级 provider continuation 最新状态

### 2. `DecisionBatch`

表示：

- 一次 planner/provider 决策产出的一个批次

一个 batch 可以包含：

- 仅 assistant 文本
- assistant 文本 + 多个 tool call
- 单个 interaction-style call（例如 `ask_user_question`）
- terminal final answer

### 3. `ChatTurnStep`

表示：

- 一个具体 tool call 或 interaction checkpoint 的执行单元

负责表达：

- 单元状态
- 单元参数
- 单元结果
- 单元失败码
- 单元对应的 `providerCallId`

### 4. `ChatEvent`

表示：

- 过程级 transcript 流

它负责：

- 保留原始事件顺序
- 服务于 transcript 投影与调试

它不适合单独承担：

- 批次归组真相
- workflow 归并语义

## 最小 `DecisionBatch` 模型

本轮先引入一个不落库的领域模型，建议最小结构如下：

```dart
class DecisionBatch {
  final String batchKey;
  final int batchIndex;
  final DecisionBatchKind kind;
  final DecisionBatchStatus status;
  final String? providerResponseId;
  final String? assistantText;
  final List<DecisionBatchStepRef> steps;
}
```

建议的配套类型：

```dart
enum DecisionBatchKind {
  toolCalls,
  interaction,
  finalAnswer,
  plannerMessageOnly,
}

enum DecisionBatchStatus {
  planned,
  running,
  awaitingConfirmation,
  awaitingUserInteraction,
  completed,
  failed,
}

class DecisionBatchStepRef {
  final int? stepId;
  final String? providerCallId;
  final String toolName;
}
```

## 字段语义

### `batchKey`

当前推荐优先级：

1. `providerResponseId`
2. 若 provider 无该字段，则退化为 `turnId + batchIndex`

本字段是领域层稳定批次键，不要求等同于数据库主键。

### `batchIndex`

表示：

- 当前 turn 内，第几个 decision batch

该值服务于：

- debug summary
- projection 排序
- live assertions

### `kind`

用于表达这次决策主要是什么类型：

- `toolCalls`
- `interaction`
- `finalAnswer`
- `plannerMessageOnly`

这样后续 Projection 不再需要从一堆 event 类型里二次猜测。

### `status`

用于表达该批次整体状态。

它不是简单复制 step 状态，而是汇总该批次的控制流结果：

- 是否已进入 waiting
- 是否已全部完成
- 是否已有失败且 turn 继续

### `assistantText`

用于承接同一 decision 内与 tool calls 并存的 assistant 文本。

这点很重要，因为当前架构已经明确：

- 一个 provider decision 可能同时包含 assistant text 与 tool calls
- 不能再强制工具或文本二选一

### `steps`

表示该批次下的叶子执行单元列表。

这里不内嵌完整 `ChatTurnStep`，而只保留轻量引用，避免一开始就把领域对象做重。

## 为什么本轮不落库

虽然从长期架构角度，`DecisionBatch` 很可能值得持久化，但本轮建议先不落库。

原因如下：

### 1. 当前批次主键已经可由 `providerResponseId` 近似承接

对当前受支持的 provider tool loop 路径：

- `providerResponseId` 已足以表达一轮 tool decision 的批次归属

### 2. 当前主要痛点在解释与消费层

最先痛的不是：

- 无法查询 batch 表

而是：

- live test 断言口径混乱
- workflow projection 归并逻辑分散
- `step` 语义容易被误用

因此先在领域模型层统一解释，比先上新表收益更高。

### 3. 避免当前 live test 主线再次被 schema 迁移打断

本轮主线仍然是：

- 继续补 Headless Live Integration 场景

如果此时引入新表，会把问题域扩大到：

- schema migration
- repository 读写
- web/native 双存储兼容

这不符合当前“先统一语义，再决定是否持久化”的原则。

## 与当前组件的关系

### 1. `TurnHarness`

当前不要求 `TurnHarness` 直接持有 `DecisionBatch` 持久实体。

但它应逐步统一以下口径：

- 一次 `ModelTurnDecision` 对应一个 batch
- 同一次 decision 内多个 tool call 仍属于同一 batch
- `sharedStepId` 不能再承担“批次归组”语义

### 2. `DecisionToolCallExecutor`

它仍然负责：

- 切 batch
- 跑并发/串行工具批
- 为每个工具建 step

但这里的“执行批”与本设计中的 `DecisionBatch` 并不冲突：

- 前者是 runtime 调度结构
- 后者是领域解释结构

多数情况下，一次 tool decision 会投影成一个 `DecisionBatch`，其中包含若干 step。

### 3. `ChatBlockBuilder`

这是当前最适合最先消费 `DecisionBatch` 语义的组件。

它当前的职责中，最容易受益的是：

- 将同一个 `providerResponseId` 下的多个 workflow / result 归并成一个 assistant block
- 继续用 `providerCallId` 精确匹配同名并发工具的结果

也就是说：

- 批次级归并：按 `providerResponseId`
- 叶子级匹配：按 `providerCallId`

### 4. Headless Live Integration Assertions

这是本轮最直接的受益点。

后续 live assertions 不应再默认：

- `step 数 == 批次数`

而应改为：

- 断言至少存在一个 tool batch
- 该 batch 下包含若干不同 `providerCallId`
- 这些 call 的 result/event 均已出现
- batch 最终进入 completed 或 waiting 态

## 推荐的测试口径调整

### 1. 当前 `news_multi_tool` case

后续推荐断言为：

- 存在一个 `providerResponseId = X` 的 tool batch
- 该 batch 下至少有两个 `providerCallId` 不同的 `web_search` 调用
- 两个调用都产出了 `assistantToolCall` 与 `toolResult`
- turn 最终未出现 planner/provider wire failure

而不是：

- 必须存在 2 个 step

### 2. ask-user resume case

后续推荐断言为：

- 存在一个 `interaction` batch
- 该 batch 进入 `awaitingUserInteraction`
- 用户提交后同一个 batch 关联 step 进入 completed
- 后续产生新的 planner batch

### 3. mixed success/failure case

后续推荐断言为：

- 同一 batch 下既有 success 也有 failure 的叶子调用
- 失败不会抹掉成功调用
- batch 结束后 turn 能继续到下一轮或合理停下

## 对当前 live integration 主线的影响

这份设计并不改变当前主线优先级，而是为主线降噪。

当前建议顺序调整为：

1. 保持现有 harness / fixture / live provider 入口继续推进
2. 先把 live assertions 与 projection 解释口径切到 batch 语义
3. 再继续补：
   - `news_multi_tool`
   - `ask_user resume`
   - `mixed success/failure`
   - `file ops real workspace`

也就是说：

- `DecisionBatch` 不是偏题
- 它是让后续 live case 不再建立在错误假设上的前置收边界动作

## 结论

从当前项目的长期架构角度，推荐固定以下原则：

1. `turn` 表达一次完整用户请求
2. `DecisionBatch` 表达一次 planner/provider 决策批次
3. `step` 表达一个具体执行单元
4. `event` 表达过程 transcript
5. `providerResponseId` 充当批次键
6. `providerCallId` 充当批次内叶子匹配键

本轮先做：

- 不落库的最小 `DecisionBatch` 领域模型
- 先统一 Projection 与 Assertion 语义

后续再视需要决定是否将 `DecisionBatch` 持久化为正式 ledger 实体。
