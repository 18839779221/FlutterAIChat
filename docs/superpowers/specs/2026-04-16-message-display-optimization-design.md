# Message Display Optimization Design

## Background

`docs/feature_todo.md` 的第四点希望优化聊天消息展示体验，目标集中在 3 个方面：

1. 用户发送新消息后，当前视口应自然聚焦到本轮消息，旧消息退出可见区域。
2. 助手流式输出期间，用户一旦主动上滑查看历史，不应再被强制拉回当前回复。
3. 进入会话时默认显示最新消息，而不是最早消息。

在当前实现中，[chat_message_list.dart](/Users/skka/flutterSpace/FlutterAIChat/lib/widgets/chat_message_list.dart) 使用正序 `ListView`，并通过“首次布局后滚到底部”的方式试图满足最新消息优先展示。由于消息块包含 Markdown、代码块、结构化卡片和流式增量文本，单次布局后的 `maxScrollExtent` 不稳定，初始化贴底需要额外校正，容易产生跳动和时机竞争。

## Decision

本次设计采用“反转列表 + 底部锚点”方案，而不是继续沿用正序列表并在初始化阶段反复补偿滚动位置。

核心原因：

1. 反转列表可以把“最新消息优先可见”变成列表的天然初始行为，而不是依赖多帧滚动修正。
2. 当前消息块高度不稳定，包含 Markdown 渲染和流式变化，正序列表的初始化贴底方案难以稳定验证。
3. 用户已经明确认可反转列表方案，并认为它比初始化贴底补偿更稳。

## Goals

### 1. Enter Session at Latest Message

进入 App、切换会话、重新打开已有会话时，列表默认落在最新消息位置。

### 2. Keep Current Turn in View After Sending

用户发送新消息后，当前视口应保持在最新消息锚点附近，新一轮消息自然出现在输入区上方，旧消息被推到上方不可见区域，无需新增“查看历史”入口或显式分隔条。

### 3. Allow Free Browsing During Streaming

流式输出期间，只要用户仍停留在当前锚点附近，列表可以继续自动跟随；一旦用户手动上滑离开锚点，后续流式更新不得再自动打断当前阅读位置，直到用户主动点击“回到底部”。

## Non-Goals

1. 不新增历史消息折叠态、分隔条或“本轮对话开始”卡片。
2. 不改变消息存储顺序与数据库结构。
3. 不调整消息块视觉设计，只优化滚动与展示语义。

## Current Constraints

### Current Message Ordering

[chat_message_list.dart](/Users/skka/flutterSpace/FlutterAIChat/lib/widgets/chat_message_list.dart) 当前会先对消息做时间线排序，再用正序 `ListView.builder` 渲染。消息块由 `ChatBlockBuilder` 将一条用户消息及其后续助手消息组合成一个 turn 片段。

### Current Scroll Ownership Is Split

[chat_controller.dart](/Users/skka/flutterSpace/FlutterAIChat/lib/controllers/chat_controller.dart) 和 [chat_message_list.dart](/Users/skka/flutterSpace/FlutterAIChat/lib/widgets/chat_message_list.dart) 都在监听同一个 `ScrollController`，并且都会修改 `autoScrollToBottomProvider`。这会导致滚动语义分散、状态来源不清。

### Current Pagination Assumes Top == Older History

[chat_session_coordinator.dart](/Users/skka/flutterSpace/FlutterAIChat/lib/controllers/chat_session_coordinator.dart) 的 `loadMoreMessages()` 基于当前列表顶部附近触发加载更多，而列表反转后，触发位置和插入后的可见锚点维护都需要同步调整。

## Proposed Design

### 1. Reverse the Message List

[chat_message_list.dart](/Users/skka/flutterSpace/FlutterAIChat/lib/widgets/chat_message_list.dart) 的消息列表改为 `reverse: true`。

设计含义：

1. 视图初始自然停在最新消息锚点。
2. 用户向上滑动时浏览更早历史。
3. 新消息和流式增量内容天然靠近输入区，更符合聊天产品预期。

为避免“数据顺序”和“视觉顺序”重复反转，消息 timeline 的组装逻辑需要统一梳理：

1. 保持 `ChatBlockBuilder` 基于时间顺序构建 turn block。
2. 在进入 `ListView.builder` 前，明确生成一组适合反转列表消费的 item 顺序。
3. 顶部 loading 指示器、空态、回到底部按钮都要按反转后的语义重新检查位置。

### 2. Make the List Widget the Single Scroll Authority

滚动状态应尽量集中在 [chat_message_list.dart](/Users/skka/flutterSpace/FlutterAIChat/lib/widgets/chat_message_list.dart)，避免控制器和组件双写同一个滚动意图。

建议保留 [chat_ui_providers.dart](/Users/skka/flutterSpace/FlutterAIChat/lib/providers/chat_ui_providers.dart) 中的 provider，但收紧语义：

1. `autoScrollToBottomProvider` 表示“当前是否允许继续跟随最新消息锚点”，而不是“此刻是否正在动画滚动到底部”。
2. `ChatMessageList` 负责根据用户手势、当前位置和生成状态更新该 provider。
3. [chat_controller.dart](/Users/skka/flutterSpace/FlutterAIChat/lib/controllers/chat_controller.dart) 内的重复滚动监听应删除或下沉，避免互相覆盖。

### 3. Define Explicit Scroll Rules

#### Session Entry

进入会话、切换会话、首次加载完成时：

1. 反转列表的默认布局即应优先展示最新消息。
2. 可保留轻量的首次锚点校正，但不再依赖多帧追底逻辑作为主方案。
3. 切换会话时重置“允许跟随最新消息”为 `true`。

#### After User Sends a Message

用户发送消息时：

1. 重置“允许跟随最新消息”为 `true`。
2. 视口明确回到最新消息锚点。
3. 旧消息自然退出当前可见区域，形成接近“清屏”的效果。

#### During Streaming

流式输出时：

1. 如果用户仍停留在最新消息锚点附近，则继续自动跟随。
2. 如果用户主动上滑离开锚点，则立即停止自动跟随。
3. 即便本轮流式回复结束，也不自动恢复跟随。
4. 只有用户主动点击“回到底部”按钮时，才恢复跟随状态并返回最新消息锚点。

### 4. Rework Pagination for the Reversed List

反转列表后，历史分页要满足“用户正在看的内容不跳动”。

需要调整的点：

1. 触发加载更多的判断方向要切换到反转列表下的“更早历史侧”。
2. 插入更多历史消息后，要保持当前可见锚点稳定，不能因为新 item 注入而把用户带离正在阅读的位置。
3. 现有 `hasMoreMessages` 对应的 loading 指示器需要放到反转后的正确一侧。

推荐实现方式：

1. 在分页触发前记录当前 `pixels` 与相关 extent。
2. 插入历史消息后按反转列表语义恢复可见位置。
3. 把“首次进入贴近最新消息”和“历史分页保持阅读位置”视为两套互不干扰的规则。

## Implementation Outline

### Message List

主要改动 [chat_message_list.dart](/Users/skka/flutterSpace/FlutterAIChat/lib/widgets/chat_message_list.dart)：

1. 将 `ListView.builder` 改为 `reverse: true`。
2. 统一管理滚动监听、锚点判断和“回到底部”按钮显隐。
3. 调整 `itemCount` 与 loading item 的索引映射。
4. 重新核对 `timelineItems` 顺序，确保视觉上仍然是“旧消息在上，新消息在下”。

### Scroll State

主要改动 [chat_ui_providers.dart](/Users/skka/flutterSpace/FlutterAIChat/lib/providers/chat_ui_providers.dart)：

1. 保留现有 provider，更新注释与语义。
2. 如有必要，增加“是否完成首次会话定位”的轻量状态，避免切换会话时重复触发无意义滚动修正。

### Controller Cleanup

主要改动 [chat_controller.dart](/Users/skka/flutterSpace/FlutterAIChat/lib/controllers/chat_controller.dart)：

1. 移除 `_initScrollListener()` 中与 UI 组件重复的滚动状态写入。
2. 保留发送、切换会话等业务动作对滚动意图的显式重置。

### Session Loading

主要改动 [chat_session_coordinator.dart](/Users/skka/flutterSpace/FlutterAIChat/lib/controllers/chat_session_coordinator.dart)：

1. 保持历史分页数据获取接口不变。
2. 若现有插入位置与反转列表不匹配，需要同步调整 `messagesProvider` 中消息插入顺序，以保证 UI 层的索引映射可预测。

## Testing Strategy

至少覆盖以下场景：

1. 进入页面或切换会话后，默认显示最新消息。
2. 发送消息后，列表回到最新消息锚点，旧消息退出当前视口。
3. 流式回复中用户手动上滑后，后续增量不会再自动拉回。
4. 点击“回到底部”后，恢复跟随并返回最新消息锚点。
5. 加载更多历史消息时，当前阅读位置保持稳定，无明显跳动。

如果当前测试基础设施不方便直接验证像素级滚动，可先补 widget 层行为测试，并保留一次手动回归清单。

## Risks

1. 反转列表后，现有 timeline item 顺序可能出现双重翻转，需要在实现时逐步核对。
2. 分页 loading 指示器位置和触发条件最容易出错，是本次改动的主要回归点。
3. 控制器和组件若仍然双写滚动状态，会让“用户上滑后不再跟随”的规则失效。

## Open Notes

1. `docs/feature_todo.md` 原文中“进入 App 时默认显示第一条消息，而不是最新消息”与最终确认的目标相反；实现与后续计划应以本 spec 中的修正版本为准，即“进入会话默认显示最新消息”。
2. 这次改动属于交互与滚动行为优化，原则上不需要更新数据库结构，但建议在完成实现后同步更新 `README.md` 中对消息展示行为的描述（如果 README 有相关说明）。
