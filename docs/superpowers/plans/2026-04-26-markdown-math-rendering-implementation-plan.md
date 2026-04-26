# Markdown 公式渲染 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在 `FlutterMarkdownImpl` 中支持常见行内与块级 TeX 公式，并保持聊天阅读流的专业文档质感。

**Architecture:** 使用 `flutter_math_fork` 负责公式渲染，项目内新增 Markdown inline/block syntax 和 builder 作为薄适配层。行内公式作为 inline widget 融入正文，块级公式作为满宽可横向滚动的文档块展示，解析失败时降级显示原文。

**Tech Stack:** Flutter 3.29.2, `flutter_markdown`, `markdown`, `flutter_math_fork 0.7.3`, `flutter_test`.

---

## 文件结构

- Modify: `pubspec.yaml`
  - 新增 `flutter_math_fork` 依赖。
- Create: `lib/widgets/markdown/math_inline_syntax.dart`
  - 识别 `$...$` 与 `\(...\)` 行内公式。
- Create: `lib/widgets/markdown/math_block_syntax.dart`
  - 识别 `$$...$$` 与 `\[...\]` 块级公式。
- Create: `lib/widgets/markdown/markdown_math_widgets.dart`
  - 封装 `MarkdownInlineMath`、`MarkdownBlockMath`、失败降级和横向滚动。
- Create: `lib/widgets/markdown/markdown_math_builder.dart`
  - 将 `math-inline` / `math-block` AST 节点转换为项目内公式 widget。
- Modify: `lib/widgets/markdown/flutter_markdown_impl.dart`
  - 注册公式 syntax 和 builder。
- Test: `test/widgets/markdown/math_inline_syntax_test.dart`
- Test: `test/widgets/markdown/math_block_syntax_test.dart`
- Test: `test/widgets/markdown/markdown_math_widgets_test.dart`
- Modify: `test/widgets/chat_blocks/chat_blocks_test.dart`
  - 增加 `FlutterMarkdownImpl` 集成测试。

---

### Task 1: 添加公式渲染依赖

**Files:**
- Modify: `pubspec.yaml`
- Modify: `pubspec.lock`

- [ ] **Step 1: 添加依赖**

在 `dependencies` 中加入。注意：项目固定 Flutter 3.29.2，`flutter_math_fork 0.7.4` 面向 Flutter 3.32.0，当前工具链不可用，因此第一版固定到 `0.7.3`。

```yaml
flutter_math_fork: 0.7.3
```

- [ ] **Step 2: 更新 lockfile**

Run: `flutter pub get`

Expected: `flutter_math_fork` 被写入 `pubspec.lock`。

- [ ] **Step 3: 提交**

```bash
git add pubspec.yaml pubspec.lock
git commit -m "chore: add markdown math dependency"
```

---

### Task 2: 行内公式语法

**Files:**
- Create: `lib/widgets/markdown/math_inline_syntax.dart`
- Create: `test/widgets/markdown/math_inline_syntax_test.dart`

- [ ] **Step 1: 写失败测试**

测试内容：

```dart
import 'package:ai_chat/widgets/markdown/math_inline_syntax.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:markdown/markdown.dart' as md;

void main() {
  group('MathInlineSyntax', () {
    test('parses dollar inline math', () {
      final document = md.Document(
        inlineSyntaxes: [MathInlineSyntax()],
        encodeHtml: false,
      );

      final nodes = document.parseInline('能量公式 $E = mc^2$。');
      final math = nodes.whereType<md.Element>().single;

      expect(math.tag, 'math-inline');
      expect(math.textContent, 'E = mc^2');
      expect(math.attributes['delimiter'], r'$');
    });

    test('parses escaped parenthesis inline math', () {
      final document = md.Document(
        inlineSyntaxes: [MathInlineSyntax()],
        encodeHtml: false,
      );

      final nodes = document.parseInline(r'能量公式 \( E = mc^2 \)。');
      final math = nodes.whereType<md.Element>().single;

      expect(math.tag, 'math-inline');
      expect(math.textContent, 'E = mc^2');
      expect(math.attributes['delimiter'], r'\(');
    });

    test('does not parse common dollar text as math', () {
      final document = md.Document(
        inlineSyntaxes: [MathInlineSyntax()],
        encodeHtml: false,
      );

      expect(
        document.parseInline(r'价格是 $12.99，路径是 $HOME。')
            .whereType<md.Element>()
            .where((element) => element.tag == 'math-inline'),
        isEmpty,
      );
    });
  });
}
```

- [ ] **Step 2: 验证红灯**

Run: `flutter test test/widgets/markdown/math_inline_syntax_test.dart`

Expected: FAIL because `math_inline_syntax.dart` does not exist.

- [ ] **Step 3: 实现最小语法**

实现 `MathInlineSyntax extends md.InlineSyntax`：

- 支持 `\(...\)`。
- 支持保守 `$...$`。
- 输出 `md.Element.text('math-inline', tex)`。
- 设置 `delimiter` attribute。
- 对 `$12.99`、`$HOME` 返回 false 或不匹配。

- [ ] **Step 4: 验证绿灯**

Run: `flutter test test/widgets/markdown/math_inline_syntax_test.dart`

Expected: All tests passed.

- [ ] **Step 5: 提交**

```bash
git add lib/widgets/markdown/math_inline_syntax.dart test/widgets/markdown/math_inline_syntax_test.dart
git commit -m "feat: parse inline markdown math"
```

---

### Task 3: 块级公式语法

**Files:**
- Create: `lib/widgets/markdown/math_block_syntax.dart`
- Create: `test/widgets/markdown/math_block_syntax_test.dart`

- [ ] **Step 1: 写失败测试**

覆盖：

- `$$` 多行公式生成 `math-block`。
- `\[` / `\]` 多行公式生成 `math-block`。
- 未闭合公式不吞掉后续普通段落。

- [ ] **Step 2: 验证红灯**

Run: `flutter test test/widgets/markdown/math_block_syntax_test.dart`

Expected: FAIL because `math_block_syntax.dart` does not exist.

- [ ] **Step 3: 实现最小语法**

实现 `MathBlockSyntax extends md.BlockSyntax`：

- 起始行匹配 `^\s*\$\$\s*$` 或 `^\s*\\\[\s*$`。
- 读取到对应结束行。
- 输出 `md.Element('math-block', [md.Text(tex.trim())])`。
- 设置 `delimiter` attribute。
- 未找到结束行时返回普通 paragraph 行为；若无法优雅回退，至少不应吞掉整段后续内容。

- [ ] **Step 4: 验证绿灯**

Run: `flutter test test/widgets/markdown/math_block_syntax_test.dart`

Expected: All tests passed.

- [ ] **Step 5: 提交**

```bash
git add lib/widgets/markdown/math_block_syntax.dart test/widgets/markdown/math_block_syntax_test.dart
git commit -m "feat: parse block markdown math"
```

---

### Task 4: 公式 Widget 与失败降级

**Files:**
- Create: `lib/widgets/markdown/markdown_math_widgets.dart`
- Create: `test/widgets/markdown/markdown_math_widgets_test.dart`

- [ ] **Step 1: 写失败测试**

覆盖：

- `MarkdownInlineMath(tex: 'E = mc^2')` 能渲染。
- `MarkdownBlockMath(tex: longTex)` 包含横向滚动容器。
- 非法公式显示原始文本，不抛异常。

- [ ] **Step 2: 验证红灯**

Run: `flutter test test/widgets/markdown/markdown_math_widgets_test.dart`

Expected: FAIL because widget file does not exist.

- [ ] **Step 3: 实现最小 Widget**

实现：

- `MarkdownInlineMath extends StatelessWidget`
  - 使用 `Math.tex(tex, textStyle: inheritedStyle)`。
  - 捕获构建错误或使用 `onErrorFallback` 展示原始文本。
- `MarkdownBlockMath extends StatelessWidget`
  - `SizedBox(width: double.infinity)`。
  - 内部 `SingleChildScrollView(scrollDirection: Axis.horizontal)`。
  - 公式居中，失败时显示原始文本。

- [ ] **Step 4: 验证绿灯**

Run: `flutter test test/widgets/markdown/markdown_math_widgets_test.dart`

Expected: All tests passed.

- [ ] **Step 5: 提交**

```bash
git add lib/widgets/markdown/markdown_math_widgets.dart test/widgets/markdown/markdown_math_widgets_test.dart
git commit -m "feat: add markdown math widgets"
```

---

### Task 5: 接入 `FlutterMarkdownImpl`

**Files:**
- Create: `lib/widgets/markdown/markdown_math_builder.dart`
- Modify: `lib/widgets/markdown/flutter_markdown_impl.dart`
- Modify: `test/widgets/chat_blocks/chat_blocks_test.dart`

- [ ] **Step 1: 写失败集成测试**

在 `chat_blocks_test.dart` 添加：

- 行内公式渲染测试。
- 块级公式渲染测试。
- `$12.99` 不误判测试。

- [ ] **Step 2: 验证红灯**

Run: `flutter test test/widgets/chat_blocks/chat_blocks_test.dart --plain-name "markdown renders inline math"`

Expected: FAIL because formula is plain text.

- [ ] **Step 3: 实现 builder 和注册**

实现 `MarkdownMathBuilder extends MarkdownElementBuilder`：

- 对 `math-inline` 返回 `MarkdownInlineMath`。
- 对 `math-block` 返回 `MarkdownBlockMath`。
- `isBlockElement()` 仅对 `math-block` 需要成立；若同一 builder 难以同时支持 inline/block，则拆为 `MarkdownInlineMathBuilder` 和 `MarkdownBlockMathBuilder`。

在 `FlutterMarkdownImpl` 注册：

```dart
blockSyntaxes: const [
  MathBlockSyntax(),
  CalloutBlockSyntax(),
],
inlineSyntaxes: [
  MathInlineSyntax(),
],
builders: {
  'math-inline': MarkdownInlineMathBuilder(),
  'math-block': MarkdownBlockMathBuilder(),
  'callout': MarkdownCalloutBuilder(),
  'code': CodeElementBuilder(),
  'pre': CodeBlockBuilder(),
},
```

- [ ] **Step 4: 验证绿灯**

Run: `flutter test test/widgets/chat_blocks/chat_blocks_test.dart`

Expected: All tests passed.

- [ ] **Step 5: 提交**

```bash
git add lib/widgets/markdown/markdown_math_builder.dart lib/widgets/markdown/flutter_markdown_impl.dart test/widgets/chat_blocks/chat_blocks_test.dart
git commit -m "feat: render markdown math formulas"
```

---

### Task 6: 回归验证

**Files:**
- No source changes unless verification reveals a bug.

- [ ] **Step 1: 运行目标测试**

Run:

```bash
flutter test \
  test/widgets/markdown/math_inline_syntax_test.dart \
  test/widgets/markdown/math_block_syntax_test.dart \
  test/widgets/markdown/markdown_math_widgets_test.dart \
  test/widgets/markdown/callout_block_syntax_test.dart \
  test/widgets/markdown/markdown_callout_block_test.dart \
  test/widgets/chat_blocks/chat_blocks_test.dart \
  test/widgets/chat_timeline/stable_markdown_block_test.dart \
  test/widgets/chat_message_list_test.dart
```

Expected: All tests passed.

- [ ] **Step 2: 运行目标 analyzer**

Run:

```bash
dart analyze \
  lib/widgets/markdown/math_inline_syntax.dart \
  lib/widgets/markdown/math_block_syntax.dart \
  lib/widgets/markdown/markdown_math_widgets.dart \
  lib/widgets/markdown/markdown_math_builder.dart \
  lib/widgets/markdown/flutter_markdown_impl.dart \
  test/widgets/markdown/math_inline_syntax_test.dart \
  test/widgets/markdown/math_block_syntax_test.dart \
  test/widgets/markdown/markdown_math_widgets_test.dart \
  test/widgets/chat_blocks/chat_blocks_test.dart
```

Expected: No issues found.

- [ ] **Step 3: 记录未覆盖风险**

若未进行真机视觉验收，在最终说明中明确写出。
