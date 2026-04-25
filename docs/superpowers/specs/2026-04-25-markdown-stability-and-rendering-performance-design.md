# Markdown 展示稳定性与渲染性能设计

## 背景

当前聊天时间线中的完成态回答主要通过 [chat_message_list.dart](/Users/skka/flutterSpace/FlutterAIChat/lib/widgets/chat_message_list.dart)、[final_response_block.dart](/Users/skka/flutterSpace/FlutterAIChat/lib/widgets/chat_blocks/final_response_block.dart)、[assistant_doc_block.dart](/Users/skka/flutterSpace/FlutterAIChat/lib/widgets/chat_blocks/assistant_doc_block.dart) 和 [flutter_markdown_impl.dart](/Users/skka/flutterSpace/FlutterAIChat/lib/widgets/markdown/flutter_markdown_impl.dart) 渲染。用户反馈在长列表滚动过程中，可以感受到轻微的 Markdown 内容偏移与站位变化，同时也怀疑 Markdown 解析存在过于频繁的实时触发。

结合当前实现和补充调研，问题更接近以下组合效应，而不是单一的“Markdown 每帧重新解析”：

1. `messagesProvider` 中任意消息更新都会触发 [ChatMessageList](/Users/skka/flutterSpace/FlutterAIChat/lib/widgets/chat_message_list.dart) 重新构造整段时间线。
2. 流式输出阶段 UI 刷新频率较高，导致父级列表与可见区 item 更容易反复 build。
3. 完成态消息虽然使用 `flutter_markdown`，但长列表中的 item 在滚动、插入历史消息、父级重建时仍会重新参与 layout / build。
4. 流式阶段使用纯文本组件，完成后切换为 Markdown 组件，天然存在一次布局语义变化。

这会带来两个直接后果：

1. UI 稳定性不足：滚动长消息时，用户能感受到轻微的文字站位变化。
2. 渲染成本偏高：完成态长 Markdown 在不必要的父级更新下重复参与构建与布局。

## 目标

### 1. 完成态 Markdown 视觉稳定

消息一旦进入完成态，在常规滚动、分页插入旧消息、其他消息流式更新等场景下，已有 Markdown 块不应出现明显的重新站位感。

### 2. 收紧时间线更新粒度

正在流式变化的消息应尽量局部更新，避免任意一条消息变化都重新组装整个时间线。

### 3. 为后续性能验证提供清晰边界

实现后应能够通过 widget tests、手动回归和 DevTools profile 检查，验证“重建范围下降”和“滚动稳定性提升”。

## 非目标

1. 不修改数据库结构、消息表结构或 `ChatMessage` 持久化协议。
2. 不改动 Markdown 语法支持范围，不新增表格、Mermaid、LaTeX 等富文本能力。
3. 不引入自定义文档引擎、段落级虚拟化或 RenderObject 级重写。
4. 不在本次改动中重做消息卡片视觉样式。

## 现状约束

### 1. 时间线组装与渲染耦合在同一组件中

[chat_message_list.dart](/Users/skka/flutterSpace/FlutterAIChat/lib/widgets/chat_message_list.dart) 当前直接监听 `messagesProvider`，在 `build()` 中排序消息、拼装 turn segment、映射 assistant blocks，并立即生成整组 timeline widgets。该结构让“数据变化范围”和“UI 重建范围”耦合过紧。

### 2. `flutter_markdown` 自带缓存无法覆盖 item 身份不稳定的问题

`flutter_markdown` 内部会在同一组件实例内缓存解析结果；但当父级时间线重建、item 被销毁或替换时，这类内部缓存无法跨实例复用。因此问题并不只在 Markdown 组件内部，而在于列表 item 的生命周期管理。

### 3. 流式阶段与完成阶段渲染语义不同

[streaming_response_block.dart](/Users/skka/flutterSpace/FlutterAIChat/lib/widgets/chat_blocks/streaming_response_block.dart) 使用轻量文本；完成后切换为 `FinalResponseBlock` / `AssistantDocBlock` 中的 Markdown。这个两阶段策略本身合理，但需要降低切换后旧消息继续抖动的概率。

### 4. 当前仓库已有两套 Markdown 能力

项目同时依赖 `flutter_markdown` 与 `markdown_widget`。其中 `flutter_markdown` 是当前主链路，`markdown_widget` 提供 `MarkdownGenerator` 这类更适合“先编译后复用”的能力，但当前并未进入主时间线渲染路径。

## 方案比较

### 方案 A：仅替换 Markdown 库

做法：

1. 将主时间线从 `flutter_markdown` 全量切换到 `markdown_widget`。
2. 不改变时间线 item 的组装方式与状态边界。

优点：

1. 改动感知点集中在 Markdown 组件。
2. 若新库默认布局更轻，可能获得部分收益。

缺点：

1. 无法解决“整表重建”这一更大的成本来源。
2. 容易把问题误判为解析器问题，而忽略列表生命周期问题。
3. 迁移风险高于收益确定性。

结论：

不作为首选。

### 方案 B：先收紧列表粒度，再为完成态 Markdown 增加稳定壳层

做法：

1. 保留现有 `flutter_markdown` 主链路。
2. 将时间线 item 从“现组现造 widget”调整为“稳定 item 描述 + 稳定 key + 独立 row widget”。
3. 让完成态 Markdown 所在 row 具备更稳定的生命周期，尽量复用已有 Markdown state。
4. 只让与当前 item 相关的状态变化触发该 row 更新。

优点：

1. 与 Flutter 官方“局部化状态变化、降低 build 成本”的建议一致。
2. 风险较低，不需要立即替换 Markdown 引擎。
3. 能同时改善 UI 稳定性与渲染性能。

缺点：

1. 不能一步到位获得“预编译 Markdown”能力。
2. 仍需手动验证极长代码块和复杂列表在真机上的收益。

结论：

作为首选方案。

### 方案 C：在方案 B 基础上引入完成态 Markdown 编译缓存

做法：

1. 先完成方案 B。
2. 再评估是否将完成态 Markdown 切换为“消息完成时编译一次、后续复用结果”的缓存链路。
3. 可基于 `markdown_widget.MarkdownGenerator` 或自定义轻量缓存层实现。

优点：

1. 对超长 Markdown 的滚动稳定性和重复构建成本最有帮助。
2. 为后续消息展示优化预留了可扩展方向。

缺点：

1. 需要额外处理主题变化、文本缩放、消息内容变更后的缓存失效。
2. 相比方案 B 更复杂，验证成本更高。

结论：

作为第二阶段增强，而不是本次首发范围。

## 决策

本次设计采用方案 B，并在 spec 中明确预留方案 C 的扩展接口。

原因：

1. 当前最主要的问题是“时间线整表重建 + item 生命周期不稳定”，不是 Markdown 语法库单点问题。
2. 先修正列表边界与稳定 identity，能够直接放大现有 `flutter_markdown` 的内部缓存收益。
3. 该路径与现有代码结构更兼容，利于以低风险方式逐步落地和验证。

## 设计方案

### 1. 将时间线拆成稳定 item 描述，而不是在 `build()` 中直接生成整组 widget

[chat_message_list.dart](/Users/skka/flutterSpace/FlutterAIChat/lib/widgets/chat_message_list.dart) 需要从“消息列表 -> widget 列表”的直接映射，调整为：

1. 消息列表 -> 时间线 item 描述列表。
2. `SliverList` 基于 item 描述渲染稳定 row。
3. 每个 row 持有稳定 `ValueKey`，避免旧 item 因插入历史消息或父级重建而轻易 remount。

这里的 item 描述至少要区分：

1. 用户锚点气泡。
2. assistant block。
3. latest running tail 包装态。

目标不是引入新的持久化模型，而是把“时间线结构”与“具体 widget 实例”解耦。

### 2. 让 assistant row 成为边界明确的独立组件

完成态 Markdown 不应继续依附在 `ChatMessageList` 的一次性 widget 组装中。更合适的做法是：

1. 由独立 row widget 接收 block 描述与必要的 source message。
2. row 内部再决定渲染 `StreamingResponseBlock`、`FinalResponseBlock`、`AssistantDocBlock`、工具卡片或交互卡片。
3. 与该 row 无关的 provider 状态不应促使其参与重建。

这能把状态边界收紧到单条时间线 item。

### 3. 为完成态 Markdown row 提供更稳定的生命周期

对完成态 Markdown row，优先采用“稳定 key + keep alive + 组件实例复用”的低风险策略，而不是立即把 Markdown 输出做大规模自定义缓存。

具体原则：

1. 已完成的 assistant Markdown row 应尽量保持稳定实例身份。
2. 滚动离屏再回到视口附近时，优先复用已有 state。
3. 先利用 Flutter 列表机制与 `flutter_markdown` 组件内部缓存，再决定是否需要引入第二阶段编译缓存。

### 4. 保留“流式轻文本，完成后 Markdown”的两阶段渲染，但要缩小视觉落差

本次不推翻当前两阶段策略，因为它本身对流式性能有利。设计要求是：

1. 继续保留生成中使用轻量文本组件。
2. 完成后再进入正式 Markdown 渲染。
3. 尽量让两阶段的字号、行高、左右 padding 保持接近，减少完成瞬间的视觉跳变。

### 5. 第二阶段预留完成态 Markdown 编译缓存接口

如果方案 B 落地后，profile 结果仍显示长 Markdown 在滚动中具有明显重复布局成本，则进入第二阶段：

1. 为完成态消息建立基于 `messageId + textHash + themeSignature` 的缓存键。
2. 在消息完成时生成可复用的 Markdown widgets / spans。
3. 主题、文本缩放或消息正文变化时按键失效并重新生成。

本次 spec 不要求直接交付这条链路，但要求代码结构不要阻断它。

## 文件边界建议

### 主要修改

1. [lib/widgets/chat_message_list.dart](/Users/skka/flutterSpace/FlutterAIChat/lib/widgets/chat_message_list.dart)
   负责时间线 item 描述生成、`SliverList` 绑定、稳定 key 与分页锚点保持。
2. [lib/widgets/chat_blocks/final_response_block.dart](/Users/skka/flutterSpace/FlutterAIChat/lib/widgets/chat_blocks/final_response_block.dart)
   如有必要，补充更稳定的完成态渲染壳层。
3. [lib/widgets/chat_blocks/assistant_doc_block.dart](/Users/skka/flutterSpace/FlutterAIChat/lib/widgets/chat_blocks/assistant_doc_block.dart)
   与完成态分析块的 Markdown 复用策略对齐。
4. [lib/widgets/markdown/flutter_markdown_impl.dart](/Users/skka/flutterSpace/FlutterAIChat/lib/widgets/markdown/flutter_markdown_impl.dart)
   保持主渲染实现，但为后续缓存或稳定化封装留出清晰边界。

### 测试修改

1. [test/widgets/chat_message_list_test.dart](/Users/skka/flutterSpace/FlutterAIChat/test/widgets/chat_message_list_test.dart)
   补时间线 item 稳定渲染与 block 不误切换的覆盖。
2. [test/widgets/chat_blocks/chat_blocks_test.dart](/Users/skka/flutterSpace/FlutterAIChat/test/widgets/chat_blocks/chat_blocks_test.dart)
   补完成态 Markdown 壳层或稳定性语义的测试。

## 测试策略

### 1. Widget 测试

至少覆盖：

1. 流式消息仍走轻量文本块。
2. 完成态消息渲染正式 Markdown。
3. 新增一条无关消息或切换发送阶段时，既有完成态 block 不应错误切换成其他组件类型。
4. 插入旧历史消息后，现有时间线 block 的 key 仍保持稳定映射。

### 2. 手动回归

至少验证：

1. 长段落 Markdown 在慢速上下滚动时，视觉站位更稳定。
2. 包含列表、标题、代码块的回答在插入旧历史消息后，不出现明显闪动。
3. 正在生成新回复时，上一轮长 Markdown 不因高频 flush 出现肉眼可见跳动。

### 3. DevTools / Profile 验证

建议在 profile 模式下观察：

1. `ChatMessageList` rebuild 次数是否下降。
2. 单条 assistant row 的 rebuild 是否被限制在局部范围。
3. 长 Markdown 场景下 layout / paint 峰值是否下降。

## 风险

1. 时间线 item 抽象如果设计过重，可能让现有工具卡片、交互卡片逻辑迁移成本升高。
2. 仅靠稳定 key 和 keep alive 无法覆盖所有长文档场景，仍可能需要第二阶段编译缓存。
3. 若 row 级别仍然直接依赖过多 provider，全局状态变化依旧可能扩散成大范围重建。

## 兼容性与文档

1. 本次不涉及数据库迁移。
2. 若最终实现引入新的时间线 item 结构或 Markdown 缓存壳层，需要同步更新 [README.md](/Users/skka/flutterSpace/FlutterAIChat/README.md) 中关于消息展示结构的描述。
3. 若实施后新增了明确的性能约束或实现规范，应补充到 [AGENTS.md](/Users/skka/flutterSpace/FlutterAIChat/AGENTS.md)。
