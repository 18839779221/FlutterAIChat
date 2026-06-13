# 结构化 Composer、语音输入与 CommandNode 设计

## 背景

当前聊天输入框仍以纯文本 `TextEditingController` 为唯一真相，语音输入只是通过长按麦克风触发一段临时识别，并在识别过程中直接改写输入框文本。这个实现已经能完成基础的语音转写，但有两个明显问题：

1. 录音手势是长按开始、松手结束，控制感弱，容易误触，也不适合较长语音输入。
2. 识别结果直接写入普通文本，无法表达“识别中临时文本”和“最终确认文本”的差异。

同时，当前 slash command 只是普通文本提示。仓库已经有 `/compact` 等命令提示与插入逻辑，但用户已经明确希望它未来成为非纯文本输入单元，具备特殊显示、一键删除、独立行为等能力。

这意味着聊天输入框的长期方向不应继续围绕“纯字符串 + 局部字符串技巧”演进，而应升级为一个支持结构化节点的输入模型，让普通文本、命令节点、语音识别节点共存。

## 本次目标

本次设计覆盖两个联动改造方向，并以统一的结构化 composer 为基础：

1. 将语音输入从长按模型改为“点按开始录音 / 点按结束录音”。
2. 将 slash command 从普通文本提示升级为结构化 `CommandNode`。

用户已经确认以下交互目标：

- 点一下麦克风进入录音态，再点一下结束录音。
- 录音开始时锚定当前光标位置。
- 识别中的文本从当前光标位置开始插入，并随着识别持续更新。
- 识别中的文本要以特殊样式区分，当前设计采用下划线。
- 会话结束后，用最终 `final text` 整体替换掉识别中的临时文本，并移除下划线。
- 录音期间不允许手动编辑输入框，不允许移动光标。
- `/command` 未来要以非纯文本节点存在，具备特殊显示和整体删除能力。

## 非目标

本次不覆盖以下内容：

- 不改动聊天发送接口的对外契约；发送链路仍以 plain text 为兼容导出形式。
- 不在本次设计中引入新的后端命令协议；`CommandNode` 第一阶段仍可导出为文本形式。
- 不扩展为多模态富文档编辑器；本次只覆盖聊天输入框内的最小结构化节点能力。
- 不在本次强制定义录音取消 UI；如果实现中需要取消动作，可作为次级扩展设计。

## 现状问题

### 语音输入现状

当前 `VoiceInputController` 既承担语音会话状态机，也直接持有 `TextEditingController` 并频繁改写文本。它会：

- 在按下长按时启动语音会话。
- 保存原始文本与插入位置。
- 监听 partial/final 结果。
- 直接拼接并写回 `textController.value`。
- 松手后结束录音，并在没有 final text 时恢复原始文本。

这个方案对“纯文本替换”是有效的，但它把语音事实、编辑状态、输入框渲染三者耦合在一起，难以继续演进：

- 无法表达识别中 span 的特殊样式。
- 无法与未来的 `CommandNode` 共存。
- 用户一旦在录音过程中编辑文本，字符串锚点就会失真。

### Slash command 现状

当前 slash suggestion 只是从输入框字符串中提取 `/...` 查询，用户点选后将文本替换为 `/compact` 之类的插入字符串。这套逻辑能完成提示，但它仍是纯文本，无法满足后续需求：

- `/command` 不能以结构化块显示。
- 删除命令时不能整块删除。
- 命令与普通文本、语音识别内容之间没有明确边界。

## 总体设计方向

将 composer 升级为“结构化文档模型 + plain text 导出”，让普通文本、命令、语音识别中的临时 span 都成为显式节点。

原则如下：

- `SpeechNode` 和 `CommandNode` 都是非纯文本输入单元。
- plain text 不再是 composer 的唯一真相，而只是对外兼容导出形式之一。
- 语音识别中的 span 是运行时投影，不直接等同于普通文本本体。
- slash command 在用户显式确认后升级为 `CommandNode`，而不是在输入 `/co...` 的早期阶段过早结构化。

## 数据模型

### ComposerDocument

新增 `ComposerDocument` 作为输入框内部的唯一真相：

```text
ComposerDocument = List<ComposerNode>
```

`ComposerNode` 的第一阶段最小集合为：

- `TextNode`
- `CommandNode`
- `SpeechNode`

### TextNode

表示普通可编辑文本。

字段建议：

- `text`

行为建议：

- 可在内部正常编辑。
- 可与相邻 `TextNode` 自动合并。

### CommandNode

表示结构化 slash command，例如 `/compact`。

字段建议：

- `commandText`
- `commandId`
- `displayLabel`

第一阶段最小行为：

- 特殊样式显示。
- 光标不能进入内部。
- Backspace/Delete 可整块删除。
- 导出 plain text 时先导出为命令字符串，例如 `/compact`。

### SpeechNode

表示录音会话进行中的临时语音输入节点，只在语音会话活跃时存在。

字段建议：

- `finalizedText`
- `interimText`
- `phase`

其中：

- `finalizedText` 表示已经较稳定的识别片段。
- `interimText` 表示仍会被 partial 持续覆盖的识别片段。
- `phase` 至少可表达 `recording` 与 `finalizing`。

显示时，`SpeechNode` 的可见文本为：

```text
finalizedText + interimText
```

并对整段施加下划线样式。

### 文档示例

普通文本与命令共存：

```text
[TextNode("先"), CommandNode("/compact"), TextNode("再继续整理")]
```

语音插入时：

```text
[TextNode("帮我安排一下"), SpeechNode(finalizedText: "", interimText: "明天下午"), TextNode("下周的计划")]
```

录音结束后：

```text
[TextNode("帮我安排一下"), TextNode("明天下午三点和产品开会"), TextNode("下周的计划")]
```

随后自动合并相邻 `TextNode`。

## 选择与光标模型

纯字符串 offset 不再足以表达节点边界。composer 需要一套最小的结构化选择模型，用于描述光标落点与删除行为。

建议新增 `ComposerSelection`，表达“节点之间”或“文本节点内部”的位置，而不是只依赖 plain text offset。

规则如下：

- 光标允许进入 `TextNode` 内部。
- 光标不允许进入 `CommandNode` 内部。
- 光标不允许进入录音中的 `SpeechNode` 内部。
- 光标可以停在 `CommandNode` 或 `SpeechNode` 的前后边界。

例如：

```text
TextNode("帮我") | CommandNode("/compact") | TextNode("整理一下")
```

光标允许在：

- `帮我` 文本内部或末尾
- `CommandNode` 前后边界
- `整理一下` 文本内部

不允许出现在 `/co|mpact` 这种命令内部位置。

## 编辑规则

### 普通输入

- 普通键盘输入只作用于当前 `TextNode`。
- 如果光标在结构化节点边界且旁侧没有 `TextNode`，则新建 `TextNode`。
- 相邻 `TextNode` 自动合并。

### 删除行为

- 在 `TextNode` 内部时，按普通字符删除规则执行。
- 光标位于 `CommandNode` 后方时，`Backspace` 整块删除 `CommandNode`。
- 光标位于 `CommandNode` 前方时，`Delete` 整块删除 `CommandNode`。
- 录音期间，`SpeechNode` 不允许用户部分删除。
- 录音结束后，`SpeechNode` 已转为 `TextNode`，恢复普通删除行为。

### 节点合并

- 相邻 `TextNode` 自动合并。
- `CommandNode` 和 `SpeechNode` 不参与合并。
- `SpeechNode` 在提交后转成 `TextNode`，再立刻尝试与左右文本节点合并。

## Slash Command 结构化规则

### 结构化时机

用户输入 `/co...` 时，仍作为普通文本存在。

只有在用户显式选中 slash suggestion 后，才将匹配区间从 `TextNode` 替换成 `CommandNode`。这能避免过早结构化，并保留现有输入体验。

### 共存规则

`CommandNode` 前后都允许存在普通文本节点。例如：

```text
[TextNode("先"), CommandNode("/compact"), TextNode("整理一下")]
```

### 删除规则

当用户在 `CommandNode` 相邻边界触发删除时，命令节点整体移除，前后 `TextNode` 按规则重新合并。

### 导出规则

第一阶段为兼容现有发送链路，`CommandNode` 导出为命令文本，例如 `/compact`。后续如果发送协议升级，再考虑结构化导出。

## 语音输入设计

### 手势模型

将当前长按语音输入改为显式点按切换：

- 第一次点击麦克风：开始录音。
- 第二次点击麦克风：结束录音。

这比长按更稳定，也更适合持续口述。

### 会话锚定

录音开始时，冻结当前 `ComposerSelection`，并在该位置插入一个 `SpeechNode`。

语音识别产生的 partial/final 结果只更新这个 `SpeechNode`，而不是直接改写整份 plain text。

### Partial / Final 处理

在运行时层面，语音识别事件分为：

- partial
- segment-final（如果底层支持）
- session-final

建议规则：

- partial 更新 `interimText`
- 较稳定的 final 片段并入 `finalizedText`
- 会话结束时，用最终 transcript 整体替换 `SpeechNode`

### 显示语义

录音期间，`SpeechNode` 的整段显示文本加下划线，以提示它仍处于识别中。

会话结束后：

- 用最终 `final text` 替换 `SpeechNode`
- 将其立即降级为普通 `TextNode`
- 移除下划线样式

这与用户确认的行为一致：下划线只属于识别中的临时文本区，不属于最终文本。

### 录音期间的输入锁定

为了保护 `SpeechNode` 锚点稳定，本次设计明确禁止录音期间的用户编辑干扰。

录音中禁止：

- 键盘输入
- 移动光标
- 选择文本
- 删除节点
- 触发 slash suggestion

录音期间仅允许：

- 再次点击麦克风结束录音
- 后续如需要再补取消录音动作

## 运行时状态边界

### VoiceInputController

`VoiceInputController` 继续负责语音会话本身，但不再直接持有或改写 composer 的最终显示文本。

保留职责：

- 录音/STT 会话状态机
- 麦克风权限与连接状态
- partial/final 事件监听
- 对外暴露语音会话运行时状态

移除职责：

- 直接 `textController.value = ...`
- 直接拼接最终显示文本

### ComposerDocumentController

新增 `ComposerDocumentController` 作为 composer 的结构化状态控制器，负责：

- 文本插入
- `CommandNode` 插入与删除
- `SpeechNode` 的插入、更新、提交
- 结构化选择模型
- plain text 导出
- 相邻文本节点合并

### ChatInput

`ChatInput` 负责交互编排，而不是自己拼字符串：

- 监听 `ComposerDocumentController`
- 监听 `VoiceInputController`
- 驱动 slash suggestion 选中后插入 `CommandNode`
- 驱动麦克风按钮开始/结束录音
- 在录音期间切换输入框锁定态

## UI 策略

第一阶段不建议直接重写成完全自研编辑器。优先目标是建立结构化文档真相，并让现有输入框尽快具备节点显示能力。

建议策略：

- 内部真相使用 `ComposerDocument`
- UI 继续挂在当前聊天输入框位置
- 输入区通过文档投影生成可见文本与 `TextSpan`
- `CommandNode` 使用特殊样式显示
- `SpeechNode` 使用下划线样式显示
- plain text 仅作为对外导出和必要桥接

这条路线能在保持现有聊天输入框大体结构的前提下，逐步完成结构化升级。

## 代码映射

建议新增：

- `lib/models/composer/composer_document.dart`
- `lib/models/composer/composer_selection.dart`
- `lib/controllers/composer_document_controller.dart`
- `lib/models/speech/voice_composer_session.dart`

建议调整：

- `lib/controllers/voice_input_controller.dart`
  - 去掉直接改写 `TextEditingController` 的逻辑
  - 改为暴露语音会话状态与 transcript 更新
- `lib/widgets/chat_input.dart`
  - slash suggestion 选中后插入 `CommandNode`
  - 麦克风交互从长按改为单击切换
  - 录音期间切换到结构化只读态
- `lib/providers/chat_ui_providers.dart`
  - 新增 `composerDocumentControllerProvider`
  - 调整现有输入相关 provider 的真相来源

发送逻辑保持兼容：

- `submitCurrentInput()` 的文本来源改为 `ComposerDocumentController.exportPlainText()`
- 第一阶段不要求 `sendMessageRequest` 理解结构化输入

## 实施顺序

建议按以下顺序实施，以降低联动风险：

1. 建立 `ComposerDocument` 与节点模型。
2. 接入 slash suggestion，将已确认命令转为 `CommandNode`。
3. 实现删除规则、节点合并、plain text 导出。
4. 将语音输入从直接改写文本切换为 `SpeechNode` 会话模型。
5. 将麦克风交互从长按改为点按切换，并补上录音锁定与下划线样式。

这个顺序的理由是：`CommandNode` 比 `SpeechNode` 更容易先验证结构化输入模型是否顺手。结构先稳，再接语音，会显著降低实现复杂度。

## 测试策略

至少补充以下测试：

### 单元测试

- `composer_document_controller_test`
  - 普通文本插入
  - `CommandNode` 插入
  - `CommandNode` 整块删除
  - 相邻 `TextNode` 合并
  - plain text 导出
  - `SpeechNode` 插入与提交

### 语音控制器测试

- `voice_input_controller_test`
  - 从直接断言文本内容，改为断言语音会话状态与 transcript 更新
  - 开始录音、结束录音、无 final 回退、权限失败、连接失败

### Widget 测试

- `chat_input` widget test
  - slash suggestion 选中后渲染成 `CommandNode`
  - 麦克风单击开始/结束
  - 录音期间输入锁定
  - `SpeechNode` partial 下划线显示
  - `SpeechNode` final 后回退为普通文本显示

## 风险与取舍

### 风险

- Flutter 现有 `TextField` 对结构化节点内联编辑的原生支持有限，显示桥接层需要谨慎设计。
- 当前仓库中多处逻辑默认以 `TextEditingController.text` 为文本真相，迁移时需要审视所有读取入口。
- slash command 从纯文本升级为结构化节点后，现有字符串匹配逻辑需要适配节点模型。

### 取舍

本次不直接追求完整富文档编辑器，而是用最小结构化节点模型承接两个已明确的需求：`SpeechNode` 和 `CommandNode`。这是当前复杂度与长期收益之间最合理的平衡点。

## 最终结论

本次聊天输入框优化不应只修语音手势，也不应只做一次局部文本替换，而应趁这次机会完成 composer 的结构化底座升级。

最终方向是：

- 聊天输入框以 `ComposerDocument` 为唯一真相。
- 普通文本、`CommandNode`、`SpeechNode` 共存于同一结构化输入模型中。
- 语音输入从长按切换为点按开始/结束。
- 识别中的文本以 `SpeechNode` 形式存在，并以下划线表达临时态。
- slash command 在用户确认后升级为 `CommandNode`，而不是继续停留在普通文本层。
- 对外发送链路先保持 plain text 兼容导出，避免一次性扩大影响面。

这条路线既能解决本轮语音输入交互问题，也能为后续的命令节点样式、一键删除、结构化输入体验提供稳定基础。
