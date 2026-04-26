# Markdown Callout Blocks Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在 `flutter_markdown` 路径支持 `[!TYPE]` 风格 Markdown Callout，并保持普通 `>` 引用仍是 Hybrid Reader 旁注。

**Architecture:** 新增 `CalloutBlockSyntax` 在 Markdown parser 阶段识别 `> [!TYPE] 可选标题`，生成自定义 `callout` AST element；新增 `MarkdownCalloutBuilder` 和 `MarkdownCalloutBlock` 完整渲染语义块。`FlutterMarkdownImpl` 只接入自定义 block syntax 和 builder，不改消息模型，不处理 `markdown_widget` 表格路径。

**Tech Stack:** Flutter 3.29.2、`flutter_markdown 0.6.23`、`markdown 7.3.0`、Flutter widget tests、项目现有 `AppTypography` / `AppColors` / `FlutterMarkdownReaderTokens`。

---

## 文件结构

- 新增：`lib/widgets/markdown/callout_block_syntax.dart`
  - 定义 `CalloutBlockSyntax`。
  - 定义 callout 类型归一化 helper。
  - 负责把标准 blockquote callout 解析为 `md.Element('callout', children)`。
- 新增：`lib/widgets/markdown/markdown_callout_block.dart`
  - 定义 `MarkdownCalloutBlock` 视觉组件。
  - 定义 callout tone / type 到 label、icon、色彩的映射。
- 新增：`lib/widgets/markdown/markdown_callout_builder.dart`
  - 定义 `MarkdownCalloutBuilder extends MarkdownElementBuilder`。
  - `isBlockElement() => true`。
  - 从 AST attributes 读取 `type` / `rawType` / `title` / content。
- 修改：`lib/widgets/markdown/flutter_markdown_impl.dart`
  - 给 `MarkdownBody` 增加 `blockSyntaxes: [CalloutBlockSyntax()]`。
  - 给 `builders` 增加 `'callout': MarkdownCalloutBuilder()`。
  - 保留普通 `blockquote` style sheet。
- 修改：`lib/widgets/markdown/flutter_markdown_reader_tokens.dart`
  - 视实现需要增加 Callout 表面/文字 token。
  - 若 token 只在 `MarkdownCalloutBlock` 内部足够清晰，可不修改。
- 新增：`test/widgets/markdown/callout_block_syntax_test.dart`
  - 直接用 `markdown` package 解析，锁定 AST 和降级行为。
- 新增或修改：`test/widgets/markdown/markdown_callout_block_test.dart`
  - 直接测试视觉组件的 label、内容、未知类型降级。
- 修改：`test/widgets/chat_blocks/chat_blocks_test.dart`
  - 增加 `FlutterMarkdownImpl` 集成测试：Callout 渲染、普通引用不受影响、表格路径不误触。

## 任务 1：锁定 Callout parser 行为

**Files:**
- Create: `test/widgets/markdown/callout_block_syntax_test.dart`
- Create: `lib/widgets/markdown/callout_block_syntax.dart`（先只放空类或最小骨架以满足 import，再通过测试驱动完善）

- [ ] **Step 1: 写 parser 红灯测试**

新建 `test/widgets/markdown/callout_block_syntax_test.dart`：

```dart
import 'package:ai_chat/widgets/markdown/callout_block_syntax.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:markdown/markdown.dart' as md;

void main() {
  group('CalloutBlockSyntax', () {
    List<md.Node> parse(String source) {
      final document = md.Document(
        blockSyntaxes: [const CalloutBlockSyntax()],
        extensionSet: md.ExtensionSet.gitHubFlavored,
      );
      return document.parseLines(source.split('\n'));
    }

    test('parses note callout into callout element', () {
      final nodes = parse('> [!NOTE]\n> 这是补充说明。');

      expect(nodes, hasLength(1));
      final callout = nodes.single as md.Element;
      expect(callout.tag, 'callout');
      expect(callout.attributes['type'], 'NOTE');
      expect(callout.attributes['rawType'], 'NOTE');
      expect(callout.attributes['title'], '');
      expect(callout.textContent, contains('这是补充说明。'));
    });

    test('preserves custom title', () {
      final nodes = parse('> [!WARNING] 数据限制\n> 只基于当前样本。');

      final callout = nodes.single as md.Element;
      expect(callout.attributes['type'], 'WARNING');
      expect(callout.attributes['rawType'], 'WARNING');
      expect(callout.attributes['title'], '数据限制');
      expect(callout.textContent, contains('只基于当前样本。'));
    });

    test('downgrades unknown types to generic callout', () {
      final nodes = parse('> [!EXAMPLE] 示例\n> 具体用法。');

      final callout = nodes.single as md.Element;
      expect(callout.attributes['type'], 'CALLOUT');
      expect(callout.attributes['rawType'], 'EXAMPLE');
      expect(callout.attributes['title'], '示例');
    });

    test('leaves ordinary blockquote untouched', () {
      final nodes = parse('> 普通旁注');

      final quote = nodes.single as md.Element;
      expect(quote.tag, 'blockquote');
      expect(quote.textContent, contains('普通旁注'));
    });
  });
}
```

- [ ] **Step 2: 创建最小骨架**

新建 `lib/widgets/markdown/callout_block_syntax.dart`：

```dart
import 'package:markdown/markdown.dart' as md;

/// Parses blockquote-style Markdown callouts such as `> [!NOTE] Title`.
class CalloutBlockSyntax extends md.BlockSyntax {
  const CalloutBlockSyntax();

  @override
  RegExp get pattern => RegExp(r'^\s*>\s*\[![A-Za-z][A-Za-z0-9_-]*\]');

  @override
  md.Node? parse(md.BlockParser parser) => null;
}
```

- [ ] **Step 3: 运行 parser 测试并确认失败**

Run:

```bash
flutter test test/widgets/markdown/callout_block_syntax_test.dart
```

Expected: FAIL。当前 `parse` 返回 `null`，测试应失败。

- [ ] **Step 4: 实现 `CalloutBlockSyntax`**

实现要点：

```dart
static final RegExp _markerPattern = RegExp(
  r'^\s*>\s*\[!([A-Za-z][A-Za-z0-9_-]*)\]\s*(.*)?$',
);
```

核心流程：

1. 从首行解析 `rawType` 和 `title`。
2. 将 raw type 归一化为大写。
3. `NOTE` / `TIP` / `WARNING` / `RESULT` / `SOURCES` 保持专属类型。
4. `INFO` / `CALLOUT` 归一为 `CALLOUT`。
5. 未知类型 `type = CALLOUT`，`rawType` 保留。
6. 消费后续以 `>` 开头的行，移除 blockquote marker 后作为 child lines。
7. 首行 marker 后如果还有正文标题以外内容，不作为正文；标题来自 marker 后内容。
8. 用 `md.BlockParser(childLines, parser.document).parseLines(parentSyntax: this)` 解析内部内容。
9. 返回 `md.Element('callout', children)` 并设置 attributes。

注意：MVP 只支持标准 `>` 前缀多行。非 `>` 懒续行不纳入第一版。

- [ ] **Step 5: 运行 parser 测试并确认通过**

Run:

```bash
flutter test test/widgets/markdown/callout_block_syntax_test.dart
```

Expected: PASS。

- [ ] **Step 6: 提交 parser**

```bash
git add lib/widgets/markdown/callout_block_syntax.dart test/widgets/markdown/callout_block_syntax_test.dart
git commit -m "feat: parse markdown callout blocks"
```

## 任务 2：实现 Callout 视觉组件

**Files:**
- Create: `lib/widgets/markdown/markdown_callout_block.dart`
- Create: `test/widgets/markdown/markdown_callout_block_test.dart`

- [ ] **Step 1: 写视觉组件红灯测试**

新建 `test/widgets/markdown/markdown_callout_block_test.dart`：

```dart
import 'package:ai_chat/theme/app_theme.dart';
import 'package:ai_chat/widgets/markdown/markdown_callout_block.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('MarkdownCalloutBlock', () {
    testWidgets('renders known type label and title', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: const Scaffold(
            body: MarkdownCalloutBlock(
              type: 'WARNING',
              rawType: 'WARNING',
              title: '数据限制',
              child: Text('只基于当前样本。'),
            ),
          ),
        ),
      );

      expect(find.text('WARNING'), findsOneWidget);
      expect(find.text('数据限制'), findsOneWidget);
      expect(find.text('只基于当前样本。'), findsOneWidget);
    });

    testWidgets('uses raw type for unknown generic callout without title', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: const Scaffold(
            body: MarkdownCalloutBlock(
              type: 'CALLOUT',
              rawType: 'EXAMPLE',
              title: '',
              child: Text('具体用法。'),
            ),
          ),
        ),
      );

      expect(find.text('EXAMPLE'), findsOneWidget);
      expect(find.text('具体用法。'), findsOneWidget);
    });
  });
}
```

- [ ] **Step 2: 运行测试并确认失败**

Run:

```bash
flutter test test/widgets/markdown/markdown_callout_block_test.dart
```

Expected: FAIL。组件尚不存在。

- [ ] **Step 3: 实现 `MarkdownCalloutBlock`**

建议实现：

- `StatelessWidget`
- public fields 均写注释：
  - `type`
  - `rawType`
  - `title`
  - `child`
- 使用 `Theme.of(context).extension<AppColors>()!` 和 `AppTypography`。
- 外层 `DecoratedBox` + `Padding`。
- header 使用 `Row`：
  - 小 icon，优先 Material Icons：`info_outline` / `tips_and_updates_outlined` / `warning_amber_rounded` / `check_circle_outline` / `link_outlined`。
  - label 文本。
  - title 非空时显示 title。
- 背景和边线低饱和，不用强红/大色块。

MVP 可以在组件内做私有 `_CalloutTone` 映射；如果后续需要复用，再抽 token。

- [ ] **Step 4: 运行视觉组件测试并确认通过**

Run:

```bash
flutter test test/widgets/markdown/markdown_callout_block_test.dart
```

Expected: PASS。

- [ ] **Step 5: 提交视觉组件**

```bash
git add lib/widgets/markdown/markdown_callout_block.dart test/widgets/markdown/markdown_callout_block_test.dart
git commit -m "feat: add markdown callout block widget"
```

## 任务 3：实现 Callout builder 并接入 FlutterMarkdownImpl

**Files:**
- Create: `lib/widgets/markdown/markdown_callout_builder.dart`
- Modify: `lib/widgets/markdown/flutter_markdown_impl.dart`
- Modify: `test/widgets/chat_blocks/chat_blocks_test.dart`

- [ ] **Step 1: 写集成红灯测试**

在 `test/widgets/chat_blocks/chat_blocks_test.dart` 中导入：

```dart
import 'package:ai_chat/widgets/markdown/markdown_callout_block.dart';
```

新增测试：

```dart
testWidgets('markdown callout renders semantic block', (tester) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light(),
      home: const Scaffold(
        body: FlutterMarkdownImpl(
          data: '> [!WARNING] 数据限制\n> 这个结论只基于当前样本。',
        ),
      ),
    ),
  );

  expect(find.byType(MarkdownCalloutBlock), findsOneWidget);
  expect(find.text('WARNING'), findsOneWidget);
  expect(find.text('数据限制'), findsOneWidget);
  expect(find.textContaining('当前样本'), findsOneWidget);
});

testWidgets('unknown markdown callout falls back to generic block', (
  tester,
) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light(),
      home: const Scaffold(
        body: FlutterMarkdownImpl(
          data: '> [!EXAMPLE]\n> 具体用法。',
        ),
      ),
    ),
  );

  expect(find.byType(MarkdownCalloutBlock), findsOneWidget);
  expect(find.text('EXAMPLE'), findsOneWidget);
  expect(find.textContaining('具体用法'), findsOneWidget);
});
```

- [ ] **Step 2: 运行集成测试并确认失败**

Run:

```bash
flutter test test/widgets/chat_blocks/chat_blocks_test.dart --plain-name "markdown callout renders semantic block"
```

Expected: FAIL。`MarkdownCalloutBlock` 尚未接入 `FlutterMarkdownImpl`。

- [ ] **Step 3: 实现 `MarkdownCalloutBuilder`**

新建 `lib/widgets/markdown/markdown_callout_builder.dart`：

```dart
import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:markdown/markdown.dart' as md;

import 'markdown_callout_block.dart';

/// Builds widgets for custom `callout` Markdown AST elements.
class MarkdownCalloutBuilder extends MarkdownElementBuilder {
  const MarkdownCalloutBuilder();

  @override
  bool isBlockElement() => true;

  @override
  Widget? visitElementAfterWithContext(
    BuildContext context,
    md.Element element,
    TextStyle? preferredStyle,
    TextStyle? parentStyle,
  ) {
    final type = element.attributes['type'] ?? 'CALLOUT';
    final rawType = element.attributes['rawType'] ?? type;
    final title = element.attributes['title'] ?? '';
    final content = element.textContent.trim();

    return MarkdownCalloutBlock(
      type: type,
      rawType: rawType,
      title: title,
      child: Text(content),
    );
  }
}
```

说明：第一版使用纯文本内容，锁定 MVP。后续若要支持完整内部 Markdown，再单独设计递归渲染。

- [ ] **Step 4: 在 `FlutterMarkdownImpl` 接入 syntax 和 builder**

修改：

```dart
import 'callout_block_syntax.dart';
import 'markdown_callout_builder.dart';
```

在 `MarkdownBody` 中加入：

```dart
blockSyntaxes: const [CalloutBlockSyntax()],
```

在 builders 中加入：

```dart
'callout': const MarkdownCalloutBuilder(),
```

保留 `'code'` 和 `'pre'`。

- [ ] **Step 5: 运行集成测试并确认通过**

Run:

```bash
flutter test test/widgets/chat_blocks/chat_blocks_test.dart --plain-name "markdown callout renders semantic block"
flutter test test/widgets/chat_blocks/chat_blocks_test.dart --plain-name "unknown markdown callout falls back to generic block"
```

Expected: PASS。

- [ ] **Step 6: 验证普通引用仍然是旁注**

Run:

```bash
flutter test test/widgets/chat_blocks/chat_blocks_test.dart --plain-name "markdown blockquote reads as a quiet side note"
```

Expected: PASS。

- [ ] **Step 7: 提交 builder 接入**

```bash
git add lib/widgets/markdown/markdown_callout_builder.dart lib/widgets/markdown/flutter_markdown_impl.dart test/widgets/chat_blocks/chat_blocks_test.dart
git commit -m "feat: render markdown callout blocks"
```

## 任务 4：补齐类型覆盖与 Sources 行为

**Files:**
- Modify: `test/widgets/chat_blocks/chat_blocks_test.dart`
- Modify as needed: `lib/widgets/markdown/markdown_callout_block.dart`

- [ ] **Step 1: 增加专属类型覆盖测试**

新增参数化或循环式 widget test，覆盖：

```dart
for (final type in ['NOTE', 'TIP', 'WARNING', 'RESULT', 'SOURCES', 'INFO', 'CALLOUT']) {
  // pump FlutterMarkdownImpl(data: '> [!$type]\n> 内容')
  // expect MarkdownCalloutBlock
  // expect label text
}
```

- [ ] **Step 2: 运行测试并确认当前行为**

Run:

```bash
flutter test test/widgets/chat_blocks/chat_blocks_test.dart --plain-name "markdown callout supports known semantic types"
```

Expected: PASS 或 FAIL。如果失败，按缺失映射补实现。

- [ ] **Step 3: 若失败，补全类型 tone/label 映射**

在 `MarkdownCalloutBlock` 内补全：

- `NOTE`
- `TIP`
- `WARNING`
- `RESULT`
- `SOURCES`
- `CALLOUT`

`INFO` 归一后若 builder 收到 `CALLOUT`，label 可显示 `INFO` 或 `CALLOUT`，以 parser 行为为准。

- [ ] **Step 4: 运行类型覆盖测试并确认通过**

Run:

```bash
flutter test test/widgets/chat_blocks/chat_blocks_test.dart --plain-name "markdown callout supports known semantic types"
```

Expected: PASS。

- [ ] **Step 5: 提交类型覆盖**

```bash
git add lib/widgets/markdown/markdown_callout_block.dart test/widgets/chat_blocks/chat_blocks_test.dart
git commit -m "test: cover markdown callout semantic types"
```

## 任务 5：回归验证

**Files:**
- Verify only

- [ ] **Step 1: 运行 parser 测试**

Run:

```bash
flutter test test/widgets/markdown/callout_block_syntax_test.dart
```

Expected: PASS。

- [ ] **Step 2: 运行 Callout widget 测试**

Run:

```bash
flutter test test/widgets/markdown/markdown_callout_block_test.dart
```

Expected: PASS。

- [ ] **Step 3: 运行聊天块测试**

Run:

```bash
flutter test test/widgets/chat_blocks/chat_blocks_test.dart
```

Expected: PASS。

- [ ] **Step 4: 运行 Markdown 稳定性测试**

Run:

```bash
flutter test test/widgets/chat_timeline/stable_markdown_block_test.dart
```

Expected: PASS。

- [ ] **Step 5: 运行消息列表测试**

Run:

```bash
flutter test test/widgets/chat_message_list_test.dart
```

Expected: PASS。

- [ ] **Step 6: 运行局部 analyzer**

Run:

```bash
dart analyze \
  lib/widgets/markdown/callout_block_syntax.dart \
  lib/widgets/markdown/markdown_callout_block.dart \
  lib/widgets/markdown/markdown_callout_builder.dart \
  lib/widgets/markdown/flutter_markdown_impl.dart \
  test/widgets/markdown/callout_block_syntax_test.dart \
  test/widgets/markdown/markdown_callout_block_test.dart \
  test/widgets/chat_blocks/chat_blocks_test.dart
```

Expected: PASS。

全仓 `flutter analyze` 当前可能仍受既有 unrelated test/API 漂移影响；若失败，记录首个 unrelated failure，不在本任务中修复。

## 任务 6：人工视觉验证

**Files:**
- Verify only

- [ ] **Step 1: 准备样例**

```md
普通段落说明。

> 普通引用仍是旁注。

> [!NOTE]
> 这是补充说明。

> [!TIP] 下一步
> 可以先验证最小样例。

> [!WARNING] 数据限制
> 这个结论只基于当前样本。

> [!RESULT] 验证结果
> Markdown Callout 已渲染为语义块。

> [!SOURCES] Sources
> - [Flutter Markdown](https://pub.dev/packages/flutter_markdown)

> [!EXAMPLE] 示例
> 未知类型应降级为通用 Callout。
```

- [ ] **Step 2: 在 Android 真机或 Web 固定 origin 验证**

优先 Android 真机。若用 Web：

```bash
flutter run -d web-server --release --web-hostname 127.0.0.1 --web-port 7357
```

Expected:

- 普通引用和 Callout 视觉边界清楚。
- Callout 强于普通引用、弱于技术内容块。
- `WARNING` 不像强红警报。
- `SOURCES` 更像尾注。
- 手机宽度下内容不拥挤。

## 最终验收

- [ ] `NOTE`、`TIP`、`WARNING`、`RESULT`、`SOURCES` 渲染为语义块。
- [ ] `INFO` / `CALLOUT` 渲染为通用语义块。
- [ ] 未知 `[!XXX]` 降级为通用 Callout，保留 `rawType` 或 title。
- [ ] 普通 `>` 引用仍保持旁注风格。
- [ ] 未触碰 `markdown_widget` 表格路径。
- [ ] 相关 parser/widget/chat regression tests 通过。
