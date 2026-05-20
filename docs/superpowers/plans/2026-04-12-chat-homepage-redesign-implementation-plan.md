# Chat Homepage Redesign Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在不改变聊天业务架构的前提下，重构聊天主页的视觉骨架与交互层级，让它符合 `Tonal AI Workbench` 方向。

**Architecture:** 本次实现以聊天主页 UI 骨架重组为主线，先重做 shell、header、message rail 与 composer 的布局关系，再统一消息表面语言，最后处理空状态和会话导航的降噪。实现遵循现有 Flutter/Riverpod 结构，优先收敛为聊天页专用 widget 与主题 token，而不是在页面文件内做零散样式覆盖。

**Tech Stack:** Flutter 3.29.2、Material 3 ThemeData、ThemeExtension、flutter_riverpod、现有聊天页 widgets 与 controllers

---

## File Structure

- Modify: `lib/pages/chat_page.dart`
  - 将传统 `Scaffold + AppBar + bottom container` 重组为聊天页专用 shell。
- Modify: `lib/widgets/chat_input.dart`
  - 将现有输入区改造成 anchored composer。
- Modify: `lib/widgets/chat_message_list.dart`
  - 调整消息轨道宽度、padding、空状态、滚动控制按钮位置与节奏。
- Modify: `lib/widgets/chat_drawer.dart`
  - 去掉当前渐变 hero 感，统一到新聊天页系统。
- Modify: `lib/widgets/chat_blocks/user_anchor_bubble.dart`
  - 调整 user message 的轮廓、宽度、边界逻辑。
- Modify: `lib/widgets/chat_blocks/assistant_doc_block.dart`
  - 统一 assistant 文档块表面语义与节奏。
- Modify: `lib/widgets/chat_blocks/final_response_block.dart`
  - 与 assistant 内容系统统一，避免“另一套卡片语言”。
- Potentially Modify: `lib/widgets/chat_blocks/tool_workflow_card.dart`
  - 如需要，补齐 tool workflow 与主消息系统的一致性。
- Potentially Modify: `lib/widgets/chat_blocks/structured_output_block.dart`
  - 如需要，补齐 structured output 与主消息系统的一致性。
- Modify: `lib/theme/app_theme_spec.dart`
  - 收敛表面角色，强化聊天页专用色阶语义。
- Modify: `lib/theme/app_spacing.dart`
  - 调整 spacing 节奏，支撑更高级的垂直 rhythm。
- Modify: `lib/theme/app_radius.dart`
  - 统一 header、bubble、card、composer 的圆角体系。
- Modify: `lib/theme/app_component_theme.dart`
  - 更新输入、卡片等通用表面默认值。
- Modify: `lib/theme/app_theme.dart`
  - 将主题入口从接近默认 Material 组装，收敛为更明确的 chat-first dark theme。
- Test/Verify: `test/` 下与聊天主页相关的 widget tests
  - 如当前没有合适覆盖，需要新增至少最小化结构测试。

## Task 1: 建立聊天主页实施基线

**Files:**
- Review: `docs/superpowers/specs/2026-04-12-chat-homepage-redesign-design.md`
- Review: `lib/pages/chat_page.dart`
- Review: `lib/widgets/chat_input.dart`
- Review: `lib/widgets/chat_message_list.dart`
- Review: `lib/widgets/chat_drawer.dart`

- [ ] **Step 1: 写出实施约束清单**

在工作笔记中列出本轮必须满足的 6 条设计约束：

- header 必须变轻，且默认中间留空
- 顶部可见阅读区域必须增加
- composer 必须成为主交互面
- message list 必须收敛为统一阅读轨道
- drawer 必须去掉当前渐变 hero 感
- 桌面端消息内容必须有受控宽度

- [ ] **Step 2: 验证当前页面不满足约束**

人工核对以下现状：

- `chat_page.dart` 仍使用标准 `AppBar`
- `chat_drawer.dart` 仍有强渐变头部
- `chat_input.dart` 仍偏紧凑表单式输入区
- `chat_message_list.dart` 尚无完整空状态与阅读轨道控制

Expected: 当前实现不能通过上述约束。

- [ ] **Step 3: 确认首轮边界**

记录首轮只处理：

- 聊天页骨架
- floating header
- message rail
- composer
- empty state
- drawer/session surface cleanup

明确本轮不做：

- 设置页重做
- 复杂动画系统
- 全应用品牌化整理

- [ ] **Step 4: 提交工作笔记或在 plan 中打勾确认**

完成后再进入代码层任务，避免范围漂移。

## Task 2: 重构主题 token，支撑聊天主页新层级

**Files:**
- Modify: `lib/theme/app_theme_spec.dart`
- Modify: `lib/theme/app_spacing.dart`
- Modify: `lib/theme/app_radius.dart`
- Modify: `lib/theme/app_component_theme.dart`
- Modify: `lib/theme/app_theme.dart`

- [ ] **Step 1: 写 failing verification checklist**

确认主题层至少要满足：

- 有明确的聊天页背景/悬浮 chrome/composer/阅读面层级
- spacing 能支撑更舒展的垂直 rhythm
- radius 能统一 header、bubble、card、composer
- `ThemeData` 不再只像默认 Material 主题的浅层包装

- [ ] **Step 2: 先写最小化主题测试或验证点**

如果已有主题测试框架：

- 新增一个最小 widget/theme test，断言关键 `ThemeExtension` token 存在并可读取

如果当前没有现成测试：

- 记录人工验证项，至少包含：
  - `AppTheme` 是否提供深色聊天页语义
  - `AppThemeSpec.dark()` 是否能区分 page / chrome / composer / reading surface

- [ ] **Step 3: 实现 token 收敛**

具体改动方向：

- `app_theme_spec.dart`
  - 保留语义化命名
  - 增加或重命名为更贴近页面层级的 surface token
  - 弱化“按具体卡片类型命名”的割裂感
- `app_spacing.dart`
  - 把当前偏紧的节奏调整为更适合 premium chat 的刻度
- `app_radius.dart`
  - 保证 composer shell 与 message system 共享同一轮廓语言
- `app_component_theme.dart`
  - 收敛 InputDecoration 和 Card 默认语气
- `app_theme.dart`
  - 输出更明确的 chat-first dark theme，并准备给主页消费

- [ ] **Step 4: 运行主题相关验证**

Run:

```bash
fvm flutter test
```

或在没有测试时：

```bash
fvm flutter analyze
```

Expected:

- 没有新增主题层错误
- `ThemeExtension` 与相关组件引用正常

- [ ] **Step 5: Commit**

```bash
git add lib/theme/app_theme_spec.dart lib/theme/app_spacing.dart lib/theme/app_radius.dart lib/theme/app_component_theme.dart lib/theme/app_theme.dart
git commit -m "feat: refine chat page theme tokens"
```

## Task 3: 重做聊天页 shell 与 floating header

**Files:**
- Modify: `lib/pages/chat_page.dart`
- Potentially Create: `lib/widgets/chat_floating_header.dart`
- Potentially Create: `lib/widgets/chat_shell_scaffold.dart`

- [ ] **Step 1: 写 failing widget test**

新增或修改聊天页 widget test，覆盖最小结构要求：

- 页面不再渲染传统 `AppBar`
- header 区仅包含左右轻量操作容器
- header 中间区域默认不展示实心标题条
- 页面 body 是连续阅读表面，而不是顶部实色栏 + 底部输入容器的硬切分

- [ ] **Step 2: 运行测试确认失败**

Run:

```bash
fvm flutter test
```

Expected:

- 旧页面结构导致测试失败

- [ ] **Step 3: 写最小实现**

实现方向：

- 在 `chat_page.dart` 中移除传统 `AppBar`
- 改用 `Stack` 或聊天页专用 shell 组织：
  - 底层：连续阅读背景
  - 中层：message rail
  - 顶层：floating header
  - 底层前景：anchored composer
- floating header 默认只保留：
  - 左侧菜单/session 按钮
  - 右侧新建/更多操作
  - 中间保持留白
- 若使用模糊或半透明，必须极轻，只服务可读性

- [ ] **Step 4: 运行测试确认通过**

Run:

```bash
fvm flutter test
```

Expected:

- 聊天页结构测试通过
- 没有因去掉 `AppBar` 破坏现有操作入口

- [ ] **Step 5: Commit**

```bash
git add lib/pages/chat_page.dart lib/widgets/chat_floating_header.dart lib/widgets/chat_shell_scaffold.dart test
git commit -m "feat: redesign chat page shell and floating header"
```

## Task 4: 重构 message rail 与空状态

**Files:**
- Modify: `lib/widgets/chat_message_list.dart`
- Potentially Create: `lib/widgets/chat_empty_state.dart`

- [ ] **Step 1: 写 failing widget test**

测试覆盖：

- 空消息时显示有设计感的空状态，而不是空白列表
- 消息列表具有受控横向宽度或轨道约束
- 回到底部按钮不会破坏 composer 区域

- [ ] **Step 2: 运行测试确认失败**

Run:

```bash
fvm flutter test
```

Expected:

- 当前没有空状态或轨道控制，测试失败

- [ ] **Step 3: 写最小实现**

实现方向：

- 给 `ChatMessageList` 增加空状态分支
- 为消息内容增加 rail 宽度约束与更稳定的横向 padding
- 调整 turn 间距与 block 间距的节奏
- 调整回到底部按钮位置，使其与新 composer 布局兼容

- [ ] **Step 4: 运行测试确认通过**

Run:

```bash
fvm flutter test
```

Expected:

- 空状态存在
- 轨道约束正常
- 滚动辅助按钮位置合理

- [ ] **Step 5: Commit**

```bash
git add lib/widgets/chat_message_list.dart lib/widgets/chat_empty_state.dart test
git commit -m "feat: refine chat reading rail and empty state"
```

## Task 5: 将输入区升级为 anchored composer

**Files:**
- Modify: `lib/widgets/chat_input.dart`

- [ ] **Step 1: 写 failing widget test**

测试覆盖：

- composer 存在外层 dock surface 与内层 input surface
- helper/status 文案位于 composer 系统内部
- mode toggles 作为 composer 附着控制存在
- send action 明确是主操作

- [ ] **Step 2: 运行测试确认失败**

Run:

```bash
fvm flutter test
```

Expected:

- 当前结构偏向单层输入容器，无法满足测试

- [ ] **Step 3: 写最小实现**

实现方向：

- 增强 composer 外层容器的停靠感
- 增加内部层级，使输入区域、状态提示和模式开关更像一个整体
- 调整字号、padding、按钮尺寸与 chip 语气
- 保留现有 send phase 行为，但统一到更平静的 composer 状态表达中

- [ ] **Step 4: 运行测试确认通过**

Run:

```bash
fvm flutter test
```

Expected:

- composer 结构测试通过
- 发送、停止、等待确认等状态未回归

- [ ] **Step 5: Commit**

```bash
git add lib/widgets/chat_input.dart test
git commit -m "feat: redesign anchored chat composer"
```

## Task 6: 统一用户消息与助手消息表面语言

**Files:**
- Modify: `lib/widgets/chat_blocks/user_anchor_bubble.dart`
- Modify: `lib/widgets/chat_blocks/assistant_doc_block.dart`
- Modify: `lib/widgets/chat_blocks/final_response_block.dart`
- Potentially Modify: `lib/widgets/chat_blocks/tool_workflow_card.dart`
- Potentially Modify: `lib/widgets/chat_blocks/structured_output_block.dart`

- [ ] **Step 1: 写 failing widget test**

测试覆盖：

- user 与 assistant 共享一致的 radius/border 体系
- assistant 表面更适合长文阅读
- final/tool/structured block 不再像完全不同的卡片系统

- [ ] **Step 2: 运行测试确认失败**

Run:

```bash
fvm flutter test
```

Expected:

- 现有 block 体系在表面语言上不够统一，测试失败

- [ ] **Step 3: 写最小实现**

实现方向：

- 调整 user bubble 宽度、padding、字体和边界
- 调整 assistant 文档块的表面反差和内边距
- 调整 final response 块与 assistant 主表面保持同源
- 如有需要，同步收敛 tool workflow / structured output 的卡片语气

- [ ] **Step 4: 运行测试确认通过**

Run:

```bash
fvm flutter test
```

Expected:

- 主消息系统视觉语言更统一
- 文本可读性未退化

- [ ] **Step 5: Commit**

```bash
git add lib/widgets/chat_blocks/user_anchor_bubble.dart lib/widgets/chat_blocks/assistant_doc_block.dart lib/widgets/chat_blocks/final_response_block.dart lib/widgets/chat_blocks/tool_workflow_card.dart lib/widgets/chat_blocks/structured_output_block.dart test
git commit -m "feat: unify chat message surfaces"
```

## Task 7: 清理 drawer / session surface 并适配大屏构图

**Files:**
- Modify: `lib/widgets/chat_drawer.dart`
- Modify: `lib/pages/chat_page.dart`

- [ ] **Step 1: 写 failing widget test**

测试覆盖：

- drawer 去掉渐变 hero 头部
- 会话列表与聊天主页的新视觉系统一致
- 在较宽布局下，页面仍保持阅读轨道优先，不出现“整页拉宽”

- [ ] **Step 2: 运行测试确认失败**

Run:

```bash
fvm flutter test
```

Expected:

- 当前 drawer 与宽屏布局不满足要求

- [ ] **Step 3: 写最小实现**

实现方向：

- 去除 `chat_drawer.dart` 当前的高存在感渐变头部
- 将新建对话、会话项、设置入口统一到更克制的 surface 体系
- 如聊天页 shell 已支持宽屏布局，在此补齐 rail/drawer 的适配逻辑

- [ ] **Step 4: 运行测试确认通过**

Run:

```bash
fvm flutter test
```

Expected:

- drawer 与主页风格一致
- 宽屏下阅读轨道仍然稳定

- [ ] **Step 5: Commit**

```bash
git add lib/widgets/chat_drawer.dart lib/pages/chat_page.dart test
git commit -m "feat: align chat navigation surfaces with new shell"
```

## Task 8: 全量验证与设计回归检查

**Files:**
- Review: `lib/pages/chat_page.dart`
- Review: `lib/widgets/chat_input.dart`
- Review: `lib/widgets/chat_message_list.dart`
- Review: `lib/widgets/chat_drawer.dart`
- Review: `lib/widgets/chat_blocks/*.dart`
- Review: `lib/theme/*.dart`

- [ ] **Step 1: 运行静态检查**

Run:

```bash
fvm flutter analyze
```

Expected:

- 无新增 analyzer 错误

- [ ] **Step 2: 运行测试**

Run:

```bash
fvm flutter test
```

Expected:

- 所有相关 widget tests 通过

- [ ] **Step 3: 手工验证聊天主页**

至少验证以下场景：

- 空状态首页
- 普通 user -> assistant 对话
- 长文本 assistant 回复
- streaming 状态
- awaiting confirmation / executing tool 状态
- drawer 打开与切换会话
- 窄屏与宽屏布局

- [ ] **Step 4: 对照 spec 做回归核对**

逐条核对：

- header 是否足够轻且保留阅读面积
- composer 是否是最强主交互面
- 消息系统是否统一
- drawer 是否去掉旧的 demo 感
- 大屏是否不再只是拉宽手机布局

- [ ] **Step 5: Commit**

```bash
git add .
git commit -m "feat: complete chat homepage redesign"
```

## Follow-Up

- 完成实现后，使用 `flutter-ui-review` 对最终聊天主页进行一次严格 UI 评审。
- 若评审结果仍有方向级问题，应回到 shell / hierarchy 层继续调整，而不是只做表面 polish。
