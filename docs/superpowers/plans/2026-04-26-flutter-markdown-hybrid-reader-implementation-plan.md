# Flutter Markdown Hybrid Reader Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 将 `flutter_markdown` 路径的完成态回答打磨成 Hybrid Reader 阅读体验，优先提升标题、正文、列表、引用/旁注的专业文档级排版质感。

**Architecture:** 本计划只触碰 `FlutterMarkdownImpl` 及其直接相关测试，必要时新增一个仅服务 `flutter_markdown` 的 reader token helper。实现不处理 `markdown_widget`，不新增公式/图表/Mermaid，不改变消息模型或聊天页整体布局。

**Tech Stack:** Flutter 3.29.2、`flutter_markdown`、Flutter widget tests、项目现有 `AppTypography` / `AppThemeSpec` / `AppSpacing` / `AppTheme`。

---

## 文件结构

- 修改：`lib/widgets/markdown/flutter_markdown_impl.dart`
  - 继续作为 `flutter_markdown` 渲染入口。
  - 从内联数值迁移到 Hybrid Reader token/helper。
  - 调整正文、标题、列表、引用、分割线的 `MarkdownStyleSheet`。
- 新增：`lib/widgets/markdown/flutter_markdown_reader_tokens.dart`
  - 只服务 `flutter_markdown` 路径。
  - 集中表达 Hybrid Reader 的字号、行高、间距、引用表面等规则。
  - 不承担 `markdown_widget` 兼容职责。
- 修改：`lib/widgets/chat_blocks/streaming_response_block.dart`
  - 小幅对齐流式纯文本与完成态正文的字号/行高关系。
  - 保持轻量 `SelectableText`，不改成 Markdown 渲染。
- 修改：`test/widgets/chat_blocks/chat_blocks_test.dart`
  - 更新现有 Markdown rhythm 测试。
  - 增加标题、正文、列表、引用/旁注的更明确断言。
  - 增加流式态与完成态正文节奏接近的断言。

## 任务 1：锁定 Hybrid Reader 核心 Markdown 断言

**Files:**
- Modify: `test/widgets/chat_blocks/chat_blocks_test.dart`

- [ ] **Step 1: 更新现有 Markdown rhythm 测试为 Hybrid Reader 目标**

将现有 `markdown typography favors tighter document rhythm` 测试改名为：

```dart
testWidgets('markdown typography follows hybrid reader rhythm', (
  tester,
) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light(),
      home: const Scaffold(
        body: FlutterMarkdownImpl(
          data: '# Heading\n\n## Section\n\nFirst paragraph.\n\n- item',
        ),
      ),
    ),
  );

  final markdown = tester.widget<MarkdownBody>(find.byType(MarkdownBody));
  final styleSheet = markdown.styleSheet!;

  expect(styleSheet.p!.fontSize, 13.2);
  expect(styleSheet.p!.height, 1.52);
  expect(styleSheet.p!.fontFamily, 'AnthropicSans');
  expect(styleSheet.p!.fontWeight, FontWeight.w400);
  expect(
    styleSheet.p!.fontFamilyFallback,
    containsAllInOrder(
      const ['NotoSansCJKSC', 'Noto Sans SC', 'PingFang SC'],
    ),
  );
  expect(styleSheet.strong!.fontWeight, FontWeight.w500);
  expect(styleSheet.h1!.fontSize, 17);
  expect(styleSheet.h1!.fontWeight, FontWeight.w500);
  expect(styleSheet.h2!.fontSize, 15.2);
  expect(styleSheet.h2!.fontWeight, FontWeight.w500);
  expect(styleSheet.h3!.fontSize, 14);
  expect(styleSheet.blockSpacing, 10);
  expect(styleSheet.h2Padding!.top, greaterThan(styleSheet.h2Padding!.bottom));
  expect(styleSheet.h3Padding!.top, greaterThan(styleSheet.h3Padding!.bottom));
  expect(styleSheet.listIndent, lessThanOrEqualTo(17));
  expect(styleSheet.listBullet!.height, 1.46);
});
```

- [ ] **Step 2: 运行测试并确认失败**

Run:

```bash
fvm flutter test test/widgets/chat_blocks/chat_blocks_test.dart --plain-name "markdown typography follows hybrid reader rhythm"
```

Expected: FAIL。当前实现中 `p.fontSize` 是 `13`、`p.height` 是 `1.4`、`blockSpacing` 是 `9.0`，断言应失败。

- [ ] **Step 3: 新增引用/旁注测试**

在同一 group 内加入：

```dart
testWidgets('markdown blockquote reads as a quiet side note', (
  tester,
) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light(),
      home: const Scaffold(
        body: FlutterMarkdownImpl(
          data: '> 压缩边界应优先选择已完成 turn。',
        ),
      ),
    ),
  );

  final markdown = tester.widget<MarkdownBody>(find.byType(MarkdownBody));
  final styleSheet = markdown.styleSheet!;
  final decoration = styleSheet.blockquoteDecoration! as BoxDecoration;
  final border = decoration.border! as Border;

  expect(styleSheet.blockquote!.fontSize, 13);
  expect(styleSheet.blockquote!.height, 1.5);
  expect(styleSheet.blockquotePadding, const EdgeInsets.fromLTRB(13, 8, 9, 8));
  expect(decoration.borderRadius, BorderRadius.circular(8));
  expect(border.left.width, 1.4);
});
```

- [ ] **Step 4: 运行引用测试并确认失败**

Run:

```bash
fvm flutter test test/widgets/chat_blocks/chat_blocks_test.dart --plain-name "markdown blockquote reads as a quiet side note"
```

Expected: FAIL。当前引用行高和 padding 与目标不一致。

- [ ] **Step 5: 提交测试红灯**

```bash
git add test/widgets/chat_blocks/chat_blocks_test.dart
git commit -m "test: lock hybrid markdown reader rhythm"
```

## 任务 2：新增 flutter_markdown reader token helper

**Files:**
- Create: `lib/widgets/markdown/flutter_markdown_reader_tokens.dart`
- Modify: `lib/widgets/markdown/flutter_markdown_impl.dart`

- [ ] **Step 1: 创建 token helper**

新增文件：

```dart
import 'package:ai_chat/theme/app_theme_spec.dart';
import 'package:ai_chat/theme/app_typography.dart';
import 'package:flutter/material.dart';

/// Design tokens for the `flutter_markdown` Hybrid Reader surface.
///
/// These values intentionally serve only the `FlutterMarkdownImpl` path. They
/// keep long-form assistant answers readable while preserving the compact chat
/// density expected on phones.
class FlutterMarkdownReaderTokens {
  /// Builds the document-first style sheet used by completed assistant answers.
  static MarkdownReaderStyles build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.extension<AppThemeSpec>()!;
    final bodyColor = theme.colorScheme.onSurface;
    final secondaryColor = theme.colorScheme.onSurface.withValues(alpha: 0.82);
    final quoteBorderColor = colors.workflowRunning.withValues(alpha: 0.18);
    final quoteBackgroundColor = colors.assistantSurface.withValues(
      alpha: theme.brightness == Brightness.dark ? 0.28 : 0.18,
    );

    return MarkdownReaderStyles(
      body: AppTypography.documentStyle(
        color: bodyColor,
        fontSize: 13.2,
        height: 1.52,
      ),
      secondaryBody: AppTypography.documentStyle(
        color: secondaryColor,
        fontSize: 13,
        height: 1.5,
      ),
      h1: AppTypography.documentStyle(
        color: bodyColor,
        fontSize: 17,
        height: 1.18,
        fontWeight: FontWeight.w500,
      ),
      h2: AppTypography.documentStyle(
        color: bodyColor,
        fontSize: 15.2,
        height: 1.2,
        fontWeight: FontWeight.w500,
      ),
      h3: AppTypography.documentStyle(
        color: bodyColor,
        fontSize: 14,
        height: 1.22,
        fontWeight: FontWeight.w500,
      ),
      quoteBackgroundColor: quoteBackgroundColor,
      quoteBorderColor: quoteBorderColor,
    );
  }
}

/// Typography and tone values consumed by `FlutterMarkdownImpl`.
class MarkdownReaderStyles {
  /// Default paragraph style for completed assistant Markdown answers.
  final TextStyle body;

  /// Secondary body style used by list markers and quiet side-note text.
  final TextStyle secondaryBody;

  /// Highest-level heading style used rarely in chat answers.
  final TextStyle h1;

  /// Primary section heading style for long-form answers.
  final TextStyle h2;

  /// Subsection heading style for local answer structure.
  final TextStyle h3;

  /// Background tone for quiet blockquote side notes.
  final Color quoteBackgroundColor;

  /// Left border tone for quiet blockquote side notes.
  final Color quoteBorderColor;

  const MarkdownReaderStyles({
    required this.body,
    required this.secondaryBody,
    required this.h1,
    required this.h2,
    required this.h3,
    required this.quoteBackgroundColor,
    required this.quoteBorderColor,
  });
}
```

如实现时需要引用 `MarkdownReaderStyles` 以外字段，保持字段注释完整；这是可被 widget 层消费的结构。

- [ ] **Step 2: 格式化新增 token helper**

Run:

```bash
dart format lib/widgets/markdown/flutter_markdown_reader_tokens.dart
```

Expected: 文件格式化完成，无语法破坏。红灯已经由任务 1 的 widget tests 提供，本任务不需要人为制造 analyzer 失败。

- [ ] **Step 3: 在 `FlutterMarkdownImpl` 中接入 token helper**

在 `lib/widgets/markdown/flutter_markdown_impl.dart` 中导入：

```dart
import 'flutter_markdown_reader_tokens.dart';
```

在 `build` 中替换局部正文/标题/引用色值计算：

```dart
final reader = FlutterMarkdownReaderTokens.build(context);
```

并将 `MarkdownStyleSheet` 关键项改为：

```dart
p: reader.body,
h1: reader.h1,
h2: reader.h2,
h3: reader.h3,
listBullet: reader.secondaryBody.copyWith(height: 1.46),
blockquote: reader.secondaryBody,
blockquotePadding: const EdgeInsets.fromLTRB(13, 8, 9, 8),
blockquoteDecoration: BoxDecoration(
  color: reader.quoteBackgroundColor,
  border: Border(
    left: BorderSide(
      color: reader.quoteBorderColor,
      width: 1.4,
    ),
  ),
  borderRadius: BorderRadius.circular(8),
),
strong: reader.body.copyWith(fontWeight: FontWeight.w500),
em: reader.body.copyWith(fontStyle: FontStyle.italic),
blockSpacing: 10,
listIndent: 17,
h1Padding: const EdgeInsets.only(top: 5, bottom: 6),
h2Padding: const EdgeInsets.only(top: 15, bottom: 6),
h3Padding: const EdgeInsets.only(top: 12, bottom: 5),
```

保留 `onTapLink`、`builders`、`_containsMarkdownTable`、`codeblockDecoration` 等既有行为。

- [ ] **Step 4: 运行 Markdown rhythm 测试并确认通过**

Run:

```bash
fvm flutter test test/widgets/chat_blocks/chat_blocks_test.dart --plain-name "markdown typography follows hybrid reader rhythm"
```

Expected: PASS。

- [ ] **Step 5: 运行引用测试并确认通过**

Run:

```bash
fvm flutter test test/widgets/chat_blocks/chat_blocks_test.dart --plain-name "markdown blockquote reads as a quiet side note"
```

Expected: PASS。

- [ ] **Step 6: 提交 token helper 与 `FlutterMarkdownImpl` 接入**

```bash
git add lib/widgets/markdown/flutter_markdown_reader_tokens.dart lib/widgets/markdown/flutter_markdown_impl.dart
git commit -m "feat: add hybrid markdown reader tokens"
```

## 任务 3：对齐流式态与完成态正文节奏

**Files:**
- Modify: `lib/widgets/chat_blocks/streaming_response_block.dart`
- Modify: `test/widgets/chat_blocks/chat_blocks_test.dart`

- [ ] **Step 1: 新增流式态排版测试**

在 `test/widgets/chat_blocks/chat_blocks_test.dart` 中导入：

```dart
import 'package:ai_chat/widgets/chat_blocks/streaming_response_block.dart';
```

新增测试：

```dart
testWidgets('streaming response stays close to completed markdown rhythm', (
  tester,
) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light(),
      home: const Scaffold(
        body: StreamingResponseBlock(
          text: '这是一段正在生成的长回答，用来验证流式态和完成态之间不会出现明显视觉断层。',
        ),
      ),
    ),
  );

  final text = tester.widget<SelectableText>(find.byType(SelectableText));

  expect(text.style!.fontSize, 13.2);
  expect(text.style!.height, 1.48);
  expect(text.style!.fontFamily, 'AnthropicSans');
});
```

- [ ] **Step 2: 运行测试并确认失败**

Run:

```bash
fvm flutter test test/widgets/chat_blocks/chat_blocks_test.dart --plain-name "streaming response stays close to completed markdown rhythm"
```

Expected: FAIL。当前 `StreamingResponseBlock` 行高为 `1.38`。

- [ ] **Step 3: 调整 `StreamingResponseBlock` 行高**

将 `lib/widgets/chat_blocks/streaming_response_block.dart` 中 `SelectableText` 的样式改为：

```dart
style: AppTypography.documentStyle(
  color: Theme.of(context).colorScheme.onSurface,
  fontSize: 13.2,
  height: 1.48,
),
```

左右 padding 保持现状，避免扩大本任务范围。

- [ ] **Step 4: 运行流式态测试并确认通过**

Run:

```bash
fvm flutter test test/widgets/chat_blocks/chat_blocks_test.dart --plain-name "streaming response stays close to completed markdown rhythm"
```

Expected: PASS。

- [ ] **Step 5: 提交流式态对齐**

```bash
git add lib/widgets/chat_blocks/streaming_response_block.dart test/widgets/chat_blocks/chat_blocks_test.dart
git commit -m "refactor: align streaming text rhythm"
```

## 任务 4：回归 Markdown 与聊天块测试

**Files:**
- Verify only

- [ ] **Step 1: 运行聊天块 widget 测试**

Run:

```bash
fvm flutter test test/widgets/chat_blocks/chat_blocks_test.dart
```

Expected: PASS。

- [ ] **Step 2: 运行 Markdown 稳定性测试**

Run:

```bash
fvm flutter test test/widgets/chat_timeline/stable_markdown_block_test.dart
```

Expected: PASS。

- [ ] **Step 3: 运行消息列表相关测试**

Run:

```bash
fvm flutter test test/widgets/chat_message_list_test.dart
```

Expected: PASS。重点观察 `StreamingResponseBlock` 相关断言是否仍成立。

- [ ] **Step 4: 运行 analyzer**

Run:

```bash
fvm flutter analyze
```

Expected: PASS，无 analyzer errors。

- [ ] **Step 5: 视情况运行完整测试**

如果前面任何测试暴露跨组件影响，运行：

```bash
fvm flutter test
```

Expected: PASS。

## 任务 5：人工视觉验证

**Files:**
- Verify only

- [ ] **Step 1: 准备三类样例回答**

使用真实聊天或 debug 输入准备：

```markdown
# 总结

这是一段 5 到 8 行的中文解释，包含 English terms、数字 123 和 `InlineCode`。

## 实施步骤

1. 第一项说明。
2. 第二项说明，包含较长文本用于验证手机换行。
3. 第三项说明。

> 这是一条旁注，用于表达约束或提醒，而不是强卡片。

普通段落继续收尾。
```

- [ ] **Step 2: 在手机宽度验证完成态 Markdown**

优先使用 Android 真机；若只做 Web 快速观察，使用固定 origin：

```bash
fvm flutter run -d web-server --release --web-hostname 127.0.0.1 --web-port 7357
```

Expected:

- 标题有章节感但不压过正文。
- 正文不挤也不散。
- 列表缩进不吞手机宽度。
- 引用像旁注，不像强提示卡片。

- [ ] **Step 3: 验证流式态到完成态切换**

发送一条会产生长回答的消息，观察生成中纯文本与完成态 Markdown 的切换。

Expected:

- 字号和密度没有明显突变。
- 完成态更精细，但不造成跳动感过强。

## 最终验收

- [ ] `test/widgets/chat_blocks/chat_blocks_test.dart` 通过。
- [ ] `test/widgets/chat_timeline/stable_markdown_block_test.dart` 通过。
- [ ] `test/widgets/chat_message_list_test.dart` 通过。
- [ ] `fvm flutter analyze` 通过。
- [ ] 人工视觉验证确认 Hybrid Reader 方向成立。
- [ ] 未修改 `markdown_widget` 路径。
- [ ] 未新增公式、图表、Mermaid 或 callout 能力。
