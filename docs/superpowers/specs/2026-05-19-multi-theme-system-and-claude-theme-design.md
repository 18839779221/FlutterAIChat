# Multi-Theme System & Claude Theme — Design Spec

**Date:** 2026-05-19
**Owner:** wanglun03
**Status:** Draft, awaiting user review

---

## 1. 背景与动机

当前 App 的视觉体系存在三类问题：

1. **风格倾向偏离意图**：现有 light 主题是"黄绿纸感（橄榄米色，色相 60–80°）"，在产品方向尚未确定的阶段先入为主，且用户已明确表达不喜欢。
2. **信息层级糊在一起**：13 个语义色中有 5 个面板色挤在同一个低对比米色域内，user / assistant / tool / structured / exception 视觉上难以快速区分；warning/exception 没有"跳出感"。
3. **阅读体验不足**：Markdown 正文 13.2px / 行高 1.52，对长答案偏小偏紧，远离 Claude.ai (16/1.7) 等长文阅读基准。

更重要的是，当时的核心问题是**主题切换链路本身并不存在**：`AppTheme.light()` 是孤立工厂，没有 ThemeController、没有用户入口。`AppTypography` 也不是 ThemeExtension，只是三个 builder，导致 100+ 个 `fontSize` / `height` 字面量散落各处。

因此本次工作的本质**不是换皮，而是建立"主题作为一等公民"的系统**：

- 抽象 `AppThemeSpec` 接口
- 把 typography 升级为命名角色
- 收编游离硬编码
- 统一两套 Markdown 渲染器对 reader sub-theme 的依赖
- 在此基础上把 Claude 主题作为第一个内置实例
- 留好未来扩展第二、第三主题的口子

深色模式本期不做（用户已确认），但接口要确保未来 dark 主题可以以同样方式接入，不留二次重构债。

## 2. 目标

### 必须达成

- 用户可在设置页"外观"分区选择主题；首期内置 **Claude** 与 **Olive Paper** 两套主题
- Claude 主题完整覆盖：暖中性米底色、衬线长文阅读体、用户保留气泡、Assistant 改文档流、品牌橙作为唯一强调色
- 主题切换是真正的运行时切换，无须重启 App
- 9 维度的所有视觉 token 全部经过 `AppThemeSpec`，不存在"换主题但有元素不跟随"的情况
- 阅读 tokens 提升：bodyReader 字号 15.5px / 行高 1.72

### 不做

- 深色模式
  - 本期仍不做；当前第二套主题是另一套浅色设计语言，不是 dark theme
- 第三个及以上内置主题（结构留好，待产品方向定后再加）
- 用户自定义主题 / 上传配色
- 布局结构、交互流程改动
- 动效曲线 / 时长重新设计
- "messageShape 形状参数化"抽象（避免假抽象，详见 §4.3）

## 3. 主题接口的 9 个维度

基于对约 50 个组件、所有 theme tokens 文件、~40 处硬编码字面量的代码调研，最少需要覆盖以下维度才能完整重皮：

| # | 维度 | 包含什么 | 取代了什么硬编码 |
|---|------|---------|-----------------|
| 1 | **Surface palette** | 现有 8 个面板色 + 新增 `artifactSurface` / `calloutNoteSurface` / `calloutWarnSurface` / `codeBlockSurface` / `accent`（替代 brandAccent） | code_widget、callout、artifact_preview 中的硬编码底色 |
| 2 | **Workflow accents** | `running` / `success` / `warning` + 新增 `danger` | 散落 `Colors.red` 字面量 |
| 3 | **Text tones** | `primaryText` / `secondaryText` + 新增 `mutedText` / `onAccentText` | `withValues(alpha:)` 临时派生 |
| 4 | **Borders** | `divider` + 新增 `strongBorder`（focus/active 专用） | 当前 focus border 借用 `workflowRunning`，主题改色会跟错 |
| 5 | **Typography roles** | `bodyChat` / `bodyReader` / `caption` / `metaLabel` / `h1` / `h2` / `h3` / `codeInline` / `codeBlock` + UI/document/code 三组字体族 | 100+ 个 `fontSize` / `height` 字面量 |
| 6 | **Spacing** | 沿用现有 6 级 `xxs..xl` | 无需扩展 |
| 7 | **Radius** | 现有 4 级 + 新增 `xs`（≤8）和 `card` 语义别名 | 8+ 文件的 `BorderRadius.circular(N)` 字面量 |
| 8 | **Motion** | 现有 durations + curves + 新增 `streamingPulse` / `confirmationSnap` 语义别名 | `tool_running_effects.dart` 自烤的 11 处常量 |
| 9 | **Reader / Markdown sub-theme** | `body` / `secondaryBody` / `h1-h3` / `quoteBg+Border` / `codeBlockSurface` / `calloutNote` / `calloutWarn` / `mathAccent` | `markdown_widget_impl.dart` 16 处字号字面量、`code_widget.dart` 3 处硬编码色 |

### 维度的判断原则

- **凡是会让"换主题不跟随"的视觉变量，必须独立成维度**
- 维度独立 ≠ 必须独立类。颜色家族可在 `SurfacePalette` 一个类里，typography roles 可在 `AppTypographySpec` 一个类里。9 个维度是逻辑分组，不是 9 个类。
- 不抽象代码里实际并不存在的开关。例如 user_anchor_bubble / assistant_doc_block 是独立 widget 文件，没有"形状参数"，因此**不抽象 messageShape 维度**。Claude 主题就直接改 assistant_doc_block 的渲染；未来要换形状会动 widget 而不是动 token。

## 4. 架构设计

### 4.1 文件结构

```
lib/theme/
  app_theme_spec.dart          # 主题真源与内建主题工厂
  app_theme_controller.dart    # 运行时持有当前主题 + 切换 API
  tokens/
    surface_palette.dart       # 维度 1
    workflow_accents.dart      # 维度 2
    text_tones.dart            # 维度 3
    borders.dart               # 维度 4
    app_typography_spec.dart   # 维度 5（命名角色）
    app_spacing.dart           # 维度 6（保留）
    app_radius.dart            # 维度 7（扩展）
    app_motion.dart            # 维度 8（扩展）
    reader_sub_theme.dart      # 维度 9
  app_typography.dart          # 字体辅助封装
  app_theme.dart               # 由 AppThemeSpec 生成 Material ThemeData
```

### 4.2 接口形态

```dart
abstract class AppThemeSpec {
  String get id;                       // 'claude'
  String get displayName;              // 'Claude'

  SurfacePalette get surfaces;         // 维度 1
  WorkflowAccents get accents;         // 维度 2
  TextTones get text;                  // 维度 3
  Borders get borders;                 // 维度 4
  AppTypographySpec get typography;    // 维度 5
  AppSpacing get spacing;              // 维度 6
  AppRadius get radius;                // 维度 7
  AppMotion get motion;                // 维度 8
  ReaderSubTheme get reader;           // 维度 9
}
```

### 4.3 ThemeController

- 在顶层 Provider 持有当前 `AppThemeSpec`
- 切换 API：`setTheme(String id)`
- 持久化：通过现有 storage 层保存用户选择
- 默认主题：首启动 = Claude

### 4.4 与旧主题层的关系

最终实现不保留 `AppColors` 兼容层，而是直接完成调用点迁移：

- `Theme.of(context).extension<AppThemeSpec>()!`
- `AppThemeSpec.of(context)`
- `spec.core` / `spec.semantic` / `spec.components`

这保证主题系统只有一个真源，避免未来设计继续被旧字段语义带偏。

### 4.5 AppTypography 的兼容关系

`AppTypography.uiStyle/documentStyle/codeStyle` 三个 builder **保留**，但内部从主题 spec 取字体族，调用方依然可以传 fontSize/height。

**新的命名角色**通过 `AppTypographySpec` 暴露：

```dart
class AppTypographySpec {
  final TextStyle bodyChat;       // 14 / 1.6
  final TextStyle bodyReader;     // 15.5 / 1.72
  final TextStyle caption;        // 12 / 1.5
  final TextStyle metaLabel;      // 11 / 1.4 / uppercase
  final TextStyle h1;
  final TextStyle h2;
  final TextStyle h3;
  final TextStyle codeInline;
  final TextStyle codeBlock;
}
```

收编硬编码时，调用方优先迁到命名角色；无法迁的（如临时调整字重）继续走 builder。

## 5. Claude 主题的具体取值

### 5.1 Surface palette

| Token | Hex | 用途 |
|-------|-----|------|
| `chatBackground` | `#F5F4EE` | 页面底色 |
| `contentSurface` | `#FAF9F5` | 内容区底（assistant 文档区） |
| `cardSurface` | `#FFFFFF` | 卡片/输入框/工具卡 |
| `userBubbleSurface` | `#EDEAE0` | 用户气泡，低对比 |
| `settingsPanelBackground` | `#F0EEE6` | 设置分组 |
| `assistantSurface` | `#FAF9F5` | 兼容旧字段（指向 contentSurface） |
| `toolWorkflowSurface` | `#F5F2EA` | 工具工作流卡，比内容区略深 |
| `structuredSurface` | `#FAF9F5` | 结构化输出，复用 contentSurface |
| `toolOutcomeSurface` | `#F2F1EB` | 工具结果 |
| `toolExceptionSurface` | `#FBF1E8` | 工具异常，warning 色调 |
| `artifactSurface` | `#FFFFFF` | Artifact 卡 |
| `calloutNoteSurface` | `#F5F2EA` | Note callout |
| `calloutWarnSurface` | `#FBF1E8` | Warn callout |
| `codeBlockSurface` | `#F5F4EE` | 代码块底 |
| `accent` | `#C96442` | 砖橙强调色 |

### 5.2 Workflow accents

| Token | Hex |
|-------|-----|
| `running` | `#9A6C37` |
| `success` | `#2F6A4F` |
| `warning` | `#B45309` |
| `danger` | `#BE2222` |

### 5.3 Text tones

| Token | Hex |
|-------|-----|
| `primary` | `#1F1F1E` |
| `secondary` | `#3D3D3A` |
| `muted` | `#75726A` |
| `onAccent` | `#FFFFFF` |

### 5.4 Borders

| Token | Hex / 值 |
|-------|---------|
| `divider` | `#E8E6DC` |
| `strongBorder` | `#D9D6CC` |

### 5.5 Typography

- **UI 字体**：保留现有 `AnthropicSans` + CJK fallback 链
- **Document 字体**：`Charter` + 现有 CJK fallback 链
- **代码字体**：`JetBrainsMono`
- **bodyReader**：15.5px / 1.72（替代当前 13.2 / 1.52）
- **bodyChat**：14px / 1.6
- **h1/h2/h3**：17 / 15.2 / 14（保持现有）
- **caption**：12 / 1.5
- **metaLabel**：11 / 1.4 / 0.08em letter-spacing / uppercase

### 5.6 Radius

| Token | 值 |
|-------|----|
| `xs` | 6 |
| `sm` | 10 |
| `md` | 12 |
| `lg` | 16 |
| `card`（别名） | 12 |
| `pill` | 999 |

### 5.7 Motion

沿用现有 8 durations + 6 curves，新增语义别名：

- `streamingPulse` = `breathing` curve + `slow` duration
- `confirmationSnap` = `easeOut` + `quick` duration

### 5.8 Reader sub-theme

完整接管 Markdown 两套渲染器：

- body: 15.5 / 1.72 / Charter+CJK
- secondaryBody: 15 / 1.7 / Charter+CJK
- h1: 19 / 1.32 / w600
- h2: 17 / 1.36 / w600
- h3: 15.5 / 1.4 / w600
- quoteBg: `#F5F2EA`, quoteBorder: `accent` 30% alpha
- codeBlockSurface: `#F5F4EE`
- calloutNote: surface `#F5F2EA` + border `#E8E6DC`
- calloutWarn: surface `#FBF1E8` + border `#FED7AA`
- mathAccent: `accent` (`#C96442`)

## 6. UI 表层变更

### 6.1 用户消息（保持气泡）

- 容器：`userBubbleSurface` (`#EDEAE0`)
- 文本：`primary` (`#1F1F1E`)，`bodyChat` 角色
- 圆角：`16 16 6 16`（保持现有非对称）
- 无阴影

### 6.2 Assistant 消息（去气泡 → 文档流）

涉及组件：`assistant_doc_block.dart` / `streaming_response_block.dart` / `final_response_block.dart`

- 移除外层 surface 容器与圆角
- 顶部添加小型 meta 行：22px 圆形头像 (`accent` 背景，"C" 字) + "Claude" 文字（`muted` + 13px）
- 正文使用 `bodyReader` 角色（15.5 / 1.72 / Charter）
- 列表 / 标题 / 引用 / 代码块全部继承 Reader sub-theme

### 6.3 工具卡片（配色简化）

涉及：`tool_workflow_card.dart` / `tool_outcome_card.dart` / `tool_exception_card.dart` / `tool_inline_step_row.dart` / `tool_result_summary_row.dart` / `tool_renderers/*`

- 全部下沉到 `cardSurface` (`#FFFFFF`) + `divider` 边
- 状态色仅在小图标 / 顶部 1.5px 状态线上使用 `running` / `success` / `warning` / `danger`
- 不再各自占用独立底色（toolWorkflow / toolOutcome / toolException 的差异通过状态线与图标传达）
- `tool_running_effects.dart` 的 11 处自烤色统一接 `accents` + `motion`

### 6.4 设置页 - 外观分区（新增）

- 在 `settings_page.dart` 顶部新增"外观"分组
- 子项："主题"（segmented control 风格 / 卡片预览风格，二选一在实现期决定）
- 首期显示 Claude 与 Olive Paper 两套主题，均可直接切换
- 点击切换实时生效，无需重启

### 6.5 硬编码收编

下列文件必须改造为消费主题 token，作为本次范围一部分：

| 文件 | 主要硬编码内容 |
|------|--------------|
| `lib/widgets/tool_renderers/tool_running_effects.dart` | 11 处 shimmer/glow 色 |
| `lib/widgets/chat_input.dart` | 4 处 |
| `lib/widgets/markdown/code_widget.dart` | 3 处代码块色 |
| `lib/widgets/chat_drawer.dart` | 3 处 |
| `lib/widgets/interaction/ask_user_question_card.dart` | 4 处 + 12 处字号 |
| `lib/widgets/markdown/markdown_widget_impl.dart` | 16 处字号字面量 |
| `lib/widgets/debug/debug_test_case_sheet.dart` | 9 处字号 + 2 处圆角 |

其他散落字面量（个位数的）可后续清理，但**不能让本次主题切换在任何一个常见聊天/工具流路径上"漏色"**。

## 7. 实施分阶段

为降低风险，实施时建议分四阶段；每阶段都可单独验证：

### Stage 1: 主题接口骨架 + Claude 主题数据
- 建立 9 维度类
- 实现 `ClaudeTheme`
- `AppColors.fromSpec` / `AppTypographySpec` 接入
- `AppTheme` 由 spec 生成 ThemeData
- **验证**：跑通现有 light 路径，视觉无明显回归（此时仍是旧颜色，因为 ClaudeTheme 还没接管）

### Stage 2: 切换链路
- `AppThemeController` + 持久化
- 设置页"外观"入口
- 首启动 = Claude 主题
- **验证**：用户在设置页选择 Claude，App 立刻变成 Claude 风格

### Stage 3: Markdown 与硬编码收编
- 两套 Markdown 渲染器都接 Reader sub-theme
- 7 个硬编码文件改造
- 阅读 tokens 切到 15.5 / 1.72
- **验证**：长答案阅读体验、callout、code block、math 均跟随主题

### Stage 4: Assistant 文档流改造
- `assistant_doc_block` / `streaming_response_block` / `final_response_block` 去气泡
- 工具卡配色简化
- **验证**：完整一轮带工具调用的对话视觉对照设计图通过

## 8. 测试策略

- 已有的 `test/` 中 UI 相关测试需更新快照
- 新增：`test/theme/app_theme_controller_test.dart` — 验证默认主题、切换与持久化
- 新增：`test/theme/theme_controller_test.dart` — 验证切换、持久化、首启动默认主题
- 视觉回归：在四个 stage 结束点各做一次手工截图对照（chat / 含工具调用 / settings / artifact）

## 9. 风险与缓解

| 风险 | 缓解 |
|------|------|
| 100+ 字号字面量收编工作量被低估 | 分两批：本次只做 7 个高频文件，其余作为后续 cleanup task |
| 两套 Markdown 渲染器并存，迁移成本高 | Stage 3 单独切片，先迁 reader tokens，渲染器统一作为独立子项 |
| 用户实际看到的 Claude 风格与示意图差异感知大 | 每个 stage 末手工截图对照设计示意，必要时回调取值 |
| 旧主题调用点迁移不彻底，导致局部仍绕过 `AppThemeSpec` | 改造前后 grep 主题入口与字面量，确保无旧入口残留 |
| 主题持久化失败导致用户进 App 看到非预期主题 | 默认 fallback 始终是 ClaudeTheme |

## 10. 验收标准

- [ ] 设置页可见"外观 → 主题"入口，Claude 处于选中态
- [ ] 主题切换即时生效，无重启
- [ ] 首次启动默认使用 Claude 主题
- [ ] Assistant 回复在视觉上为文档流（无气泡壳），用户消息保留气泡
- [ ] Markdown 长文 body 字号 ≥ 15px、行距 ≥ 1.7
- [ ] 工具卡片不再使用 5 种独立底色，统一为 `cardSurface` + 状态线
- [ ] 7 个高频硬编码文件已收编
- [ ] 跑 `flutter test` 全绿
- [ ] 至少一组完整对话 + 工具调用的手工截图与设计示意一致
- [ ] 无任何绕过 `AppThemeSpec` 的旧主题入口残留
