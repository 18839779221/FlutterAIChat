# flutter_markdown 表格自渲染 + 边缘渐隐外壳实现计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 把 `MarkdownWidgetImpl` 的表格视觉（圆角面板 + `TableEdgeFadeScrollShell` + `IntrinsicColumnWidth` 内容定宽）迁回主路径 `FlutterMarkdownImpl`，同步把 `flutter_markdown 0.6.x` 升级到 `flutter_markdown_plus 1.0.6`。

**Architecture:** 子类化 `markdown` 包的 `TableSyntax`，将解析产物的 AST 标签从 `<table>` 等改名为私有 `<rich-*>`，绕过 `flutter_markdown_plus` 对 `<table>` 的硬编码渲染路径。通过 `MarkdownElementBuilder` 接管 `<rich-table>`，自渲染 Flutter `Table` widget + 套上现有 `TableEdgeFadeScrollShell`。单元格 inline markdown 通过反序列化器还原为 markdown 字符串后嵌套 `MarkdownBody` 渲染。

**Tech Stack:** Flutter 3.35.7、`flutter_markdown_plus ^1.0.6`、`markdown ^7.x`、现有 `TableEdgeFadeScrollShell` / `FlutterMarkdownReaderTokens` / `AppThemeSpec`。

**Spec:** `docs/superpowers/specs/2026-05-31-flutter-markdown-table-shell-design.md`

---

## File Structure

### 阶段 1：依赖升级（独立 commit）

修改：
- `pubspec.yaml` — `flutter_markdown ^0.6.18` → `flutter_markdown_plus ^1.0.6`
- `lib/widgets/markdown/code_block_builder.dart` — import 切换
- `lib/widgets/markdown/flutter_markdown_impl.dart` — import 切换
- `lib/widgets/markdown/markdown_callout_builder.dart` — import 切换
- `lib/widgets/markdown/markdown_math_builder.dart` — import 切换
- `test/widgets/chat_blocks/chat_blocks_test.dart` — import 切换

### 阶段 2：自渲染表格（独立 commit）

新增：
- `lib/widgets/markdown/rich_table_inline_serializer.dart` — 单一职责：把单元格内的 `md.Node` 子树反序列化回 markdown 字符串片段
- `lib/widgets/markdown/rich_table_block_syntax.dart` — 单一职责：子类化 `md.TableSyntax`，把产出 AST 改名为 `<rich-*>`
- `lib/widgets/markdown/rich_table_element_builder.dart` — 单一职责：接管 `<rich-table>` 的 widget 渲染（Flutter `Table` + `TableEdgeFadeScrollShell` + 圆角外壳）
- `test/widgets/markdown/rich_table_inline_serializer_test.dart`
- `test/widgets/markdown/rich_table_block_syntax_test.dart`
- `test/widgets/markdown/rich_table_rendering_test.dart`

修改：
- `lib/widgets/markdown/flutter_markdown_impl.dart` — 注入 `RichTableBlockSyntax` 替换默认 GFM table 解析，注册 `builders['rich-table']`
- `test/widgets/markdown/markdown_rendering_regression_test.dart` — 添加表格样本断言走主路径

---

## 阶段 1：升级 flutter_markdown_plus

### Task 1: 切换 pubspec.yaml 依赖

**Files:**
- Modify: `pubspec.yaml`

- [ ] **Step 1: 替换依赖项**

打开 `pubspec.yaml`，找到 `flutter_markdown: ^0.6.18`，替换为 `flutter_markdown_plus: ^1.0.6`。保持字母顺序排列；其它依赖保持不变。

- [ ] **Step 2: 拉依赖**

```bash
flutter pub get
```

预期：成功解析，输出 `Got dependencies!` 或类似；`pubspec.lock` 中 `flutter_markdown` 消失、`flutter_markdown_plus` 出现。

- [ ] **Step 3: 不要 commit 这一步**

阶段 1 是一个完整的可工作 commit；继续 Task 2 直至所有 import 切换完毕再 commit。

### Task 2: 切换所有 import 到 flutter_markdown_plus

**Files:**
- Modify: `lib/widgets/markdown/code_block_builder.dart:3`
- Modify: `lib/widgets/markdown/flutter_markdown_impl.dart:2`
- Modify: `lib/widgets/markdown/markdown_callout_builder.dart:3`
- Modify: `lib/widgets/markdown/markdown_math_builder.dart:3`
- Modify: `test/widgets/chat_blocks/chat_blocks_test.dart:24`

- [ ] **Step 1: 把所有 5 个文件的 import 行替换**

对每个文件，把：

```dart
import 'package:flutter_markdown/flutter_markdown.dart';
```

替换为：

```dart
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
```

可一次性用 `Edit` 工具的 `replace_all` 模式分别处理每个文件，或用以下命令在 shell 里验证替换前后没有遗漏：

```bash
grep -rn "package:flutter_markdown[^_]" lib test
```

预期：无输出（确认所有引用均已切换）。

- [ ] **Step 2: 跑静态分析**

```bash
flutter analyze
```

预期：可能出现 `flutter_markdown_plus` API 差异引起的错误，按错误信息逐个处理。常见情况：

- `MarkdownBody` 的某些参数被移除/重命名
- `MarkdownElementBuilder.visitElementAfter` 签名差异（`visitElementAfterWithContext` 已在 0.6.x 引入，plus 沿用）
- `selectable` 参数语义变化（plus 中 `MarkdownBody.selectable` 仍存在，默认 false）

若出现 `Undefined name '...'`/`The method '...' isn't defined` 等错误，对照 plus 的最新 API 文档调整。

- [ ] **Step 3: 跑相关测试**

```bash
flutter test test/widgets/markdown/ test/widgets/chat_blocks/
```

预期：全部通过。如有失败，针对失败用例修正适配，再跑。

- [ ] **Step 4: 真机视觉验证（可选但推荐）**

如有 Android 真机：

```bash
bash scripts/android_install_debug.sh
```

打开 app，发送含 code / list / blockquote / math / callout 的 assistant 消息，确认渲染无回归。

无真机时跳过此步，依赖 widget 测试。

- [ ] **Step 5: 提交阶段 1**

```bash
git add pubspec.yaml pubspec.lock lib/widgets/markdown/code_block_builder.dart lib/widgets/markdown/flutter_markdown_impl.dart lib/widgets/markdown/markdown_callout_builder.dart lib/widgets/markdown/markdown_math_builder.dart test/widgets/chat_blocks/chat_blocks_test.dart
git commit -m "$(cat <<'EOF'
chore(deps): migrate flutter_markdown to flutter_markdown_plus 1.0.6

Drop the archived google/flutter_markdown package in favor of the
community-maintained flutter_markdown_plus 1.0.6 fork. API surface
is largely compatible; this commit only swaps the import path.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

预期：commit 成功；`git status` clean。

---

## 阶段 2：自渲染表格

### Task 3: RichTableInlineSerializer — 单元格 inline 反序列化器

**Files:**
- Create: `lib/widgets/markdown/rich_table_inline_serializer.dart`
- Test: `test/widgets/markdown/rich_table_inline_serializer_test.dart`

**职责：** 把单元格内的 `md.Node` 子树（已经被 `md.TableSyntax._parseRow` 跑过 `BlockParser.parseInlineContent` 之后的 AST 节点：`md.Text` 与若干 `md.Element` 如 `em`/`strong`/`code`/`a`/`del`/`br`/`math-inline`）反序列化为 markdown 字符串片段，以便嵌套 `MarkdownBody` 重新跑一遍渲染。

- [ ] **Step 1: 写失败测试**

创建 `test/widgets/markdown/rich_table_inline_serializer_test.dart`：

```dart
import 'package:ai_chat/widgets/markdown/rich_table_inline_serializer.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:markdown/markdown.dart' as md;

void main() {
  group('RichTableInlineSerializer', () {
    String serialize(List<md.Node> nodes) =>
        RichTableInlineSerializer.serialize(nodes);

    test('plain text passes through unchanged', () {
      expect(serialize([md.Text('hello world')]), 'hello world');
    });

    test('em -> *...*', () {
      final em = md.Element('em', [md.Text('hi')]);
      expect(serialize([em]), '*hi*');
    });

    test('strong -> **...**', () {
      final s = md.Element('strong', [md.Text('hi')]);
      expect(serialize([s]), '**hi**');
    });

    test('code -> backtick wrapped', () {
      final c = md.Element('code', [md.Text('x')]);
      expect(serialize([c]), '`x`');
    });

    test('anchor -> [text](href)', () {
      final a = md.Element('a', [md.Text('site')])
        ..attributes['href'] = 'https://example.com';
      expect(serialize([a]), '[site](https://example.com)');
    });

    test('del -> ~~...~~', () {
      final d = md.Element('del', [md.Text('gone')]);
      expect(serialize([d]), '~~gone~~');
    });

    test('br -> trailing two spaces + newline', () {
      final br = md.Element.empty('br');
      expect(serialize([md.Text('a'), br, md.Text('b')]), 'a  \nb');
    });

    test('math-inline dollar delimiter is restored', () {
      final m = md.Element.text('math-inline', 'x^2')
        ..attributes['delimiter'] = r'$';
      expect(serialize([m]), r'$x^2$');
    });

    test(r'math-inline \( delimiter is restored', () {
      final m = md.Element.text('math-inline', 'x^2')
        ..attributes['delimiter'] = r'\(';
      expect(serialize([m]), r'\(x^2\)');
    });

    test('nested emphasis composes', () {
      final strong = md.Element('strong', [
        md.Text('a '),
        md.Element('em', [md.Text('b')]),
        md.Text(' c'),
      ]);
      expect(serialize([strong]), '**a *b* c**');
    });

    test('unknown element falls back to textContent', () {
      final u = md.Element('weird-tag', [md.Text('payload')]);
      expect(serialize([u]), 'payload');
    });

    test('pipe in text is escaped so it does not break table cell', () {
      expect(serialize([md.Text('a | b')]), r'a \| b');
    });
  });
}
```

- [ ] **Step 2: 跑测试确认失败**

```bash
flutter test test/widgets/markdown/rich_table_inline_serializer_test.dart
```

预期：FAIL，`Error: Couldn't resolve the package 'ai_chat' for the URI 'package:ai_chat/widgets/markdown/rich_table_inline_serializer.dart'` 或类似。

- [ ] **Step 3: 写最小实现**

创建 `lib/widgets/markdown/rich_table_inline_serializer.dart`：

```dart
import 'package:markdown/markdown.dart' as md;

/// Serializes a Markdown AST inline sub-tree back to a Markdown string
/// fragment suitable for nested `MarkdownBody` rendering inside a table cell.
///
/// Only covers the inline element set produced by GFM table cell parsing:
/// `em`, `strong`, `code`, `a`, `del`, `br`, plus the project-specific
/// `math-inline` tag emitted by [MathInlineSyntax]. Unknown elements fall
/// back to their `textContent` so cell text is never silently dropped.
class RichTableInlineSerializer {
  const RichTableInlineSerializer._();

  static String serialize(List<md.Node> nodes) {
    final buffer = StringBuffer();
    for (final node in nodes) {
      _writeNode(buffer, node);
    }
    return buffer.toString();
  }

  static void _writeNode(StringBuffer buffer, md.Node node) {
    if (node is md.Text) {
      buffer.write(_escapeText(node.text));
      return;
    }
    if (node is md.Element) {
      switch (node.tag) {
        case 'em':
          buffer.write('*');
          _writeChildren(buffer, node);
          buffer.write('*');
          return;
        case 'strong':
          buffer.write('**');
          _writeChildren(buffer, node);
          buffer.write('**');
          return;
        case 'code':
          buffer.write('`');
          buffer.write(node.textContent);
          buffer.write('`');
          return;
        case 'a':
          buffer.write('[');
          _writeChildren(buffer, node);
          buffer.write('](');
          buffer.write(node.attributes['href'] ?? '');
          buffer.write(')');
          return;
        case 'del':
          buffer.write('~~');
          _writeChildren(buffer, node);
          buffer.write('~~');
          return;
        case 'br':
          buffer.write('  \n');
          return;
        case 'math-inline':
          final delimiter = node.attributes['delimiter'] ?? r'$';
          final tex = node.textContent;
          if (delimiter == r'\(') {
            buffer..write(r'\(')..write(tex)..write(r'\)');
          } else {
            buffer..write(r'$')..write(tex)..write(r'$');
          }
          return;
        default:
          buffer.write(node.textContent);
          return;
      }
    }
  }

  static void _writeChildren(StringBuffer buffer, md.Element element) {
    final children = element.children;
    if (children == null) return;
    for (final child in children) {
      _writeNode(buffer, child);
    }
  }

  // GFM table cells use `|` as the separator. The `markdown` parser
  // already unescapes `\|` during cell parsing, so we must re-escape
  // pipes in raw text before nesting them through MarkdownBody again.
  static String _escapeText(String text) =>
      text.replaceAll(r'\', r'\\').replaceAll('|', r'\|');
}
```

- [ ] **Step 4: 跑测试确认通过**

```bash
flutter test test/widgets/markdown/rich_table_inline_serializer_test.dart
```

预期：所有用例 PASS。

如失败，注意：
- `_escapeText` 对 `\\` 与 `|` 的处理顺序与测试断言一致（先转义反斜杠，再转义 pipe）
- 测试中的 `'a | b'` → `'a \\| b'` 是 raw string 期望

- [ ] **Step 5: 跑 analyze**

```bash
flutter analyze lib/widgets/markdown/rich_table_inline_serializer.dart test/widgets/markdown/rich_table_inline_serializer_test.dart
```

预期：无 warning/error。

- [ ] **Step 6: 提交**

```bash
git add lib/widgets/markdown/rich_table_inline_serializer.dart test/widgets/markdown/rich_table_inline_serializer_test.dart
git commit -m "$(cat <<'EOF'
feat(markdown): add RichTableInlineSerializer for nested cell rendering

Serializes inline AST sub-trees (em/strong/code/a/del/br/math-inline)
back to Markdown fragments so table cells can be rendered through a
nested MarkdownBody while preserving inline syntax (bold, code, links,
inline math).

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

### Task 4: RichTableBlockSyntax — 私有标签 GFM table 解析器

**Files:**
- Create: `lib/widgets/markdown/rich_table_block_syntax.dart`
- Test: `test/widgets/markdown/rich_table_block_syntax_test.dart`

**职责：** 继承 `md.TableSyntax`，复用其全部 GFM table 解析逻辑（管道符切分、对齐分隔行、单元格 inline 解析），仅在 `parse()` 返回前深度遍历替换标签名为 `rich-*`。

- [ ] **Step 1: 写失败测试**

创建 `test/widgets/markdown/rich_table_block_syntax_test.dart`：

```dart
import 'package:ai_chat/widgets/markdown/rich_table_block_syntax.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:markdown/markdown.dart' as md;

void main() {
  group('RichTableBlockSyntax', () {
    List<md.Node> parse(String source) {
      final document = md.Document(
        blockSyntaxes: const [RichTableBlockSyntax()],
        extensionSet: md.ExtensionSet.gitHubFlavored,
      );
      return document.parseLines(source.split('\n'));
    }

    md.Element findFirstElement(List<md.Node> nodes, String tag) {
      for (final n in nodes) {
        if (n is md.Element && n.tag == tag) return n;
      }
      throw StateError('No element <$tag> in parsed nodes');
    }

    test('basic GFM table parses into <rich-table> with rich-* subtree', () {
      final nodes = parse('''
| a | b |
|---|---|
| 1 | 2 |
''');

      final table = findFirstElement(nodes, 'rich-table');
      expect(table.tag, 'rich-table');

      final thead = table.children![0] as md.Element;
      expect(thead.tag, 'rich-thead');
      final headerRow = thead.children![0] as md.Element;
      expect(headerRow.tag, 'rich-tr');
      final th = headerRow.children![0] as md.Element;
      expect(th.tag, 'rich-th');

      final tbody = table.children![1] as md.Element;
      expect(tbody.tag, 'rich-tbody');
      final bodyRow = tbody.children![0] as md.Element;
      expect(bodyRow.tag, 'rich-tr');
      final td = bodyRow.children![0] as md.Element;
      expect(td.tag, 'rich-td');
    });

    test('no <table>/<thead>/<tbody>/<tr>/<th>/<td> remain in tree', () {
      final nodes = parse('''
| a | b |
|---|---|
| 1 | 2 |
''');

      void assertNoLegacyTag(md.Node node) {
        if (node is md.Element) {
          expect(
            const {'table', 'thead', 'tbody', 'tr', 'th', 'td'},
            isNot(contains(node.tag)),
            reason: 'legacy tag ${node.tag} leaked into tree',
          );
          for (final c in node.children ?? const <md.Node>[]) {
            assertNoLegacyTag(c);
          }
        }
      }

      for (final n in nodes) {
        assertNoLegacyTag(n);
      }
    });

    test('alignment attributes are preserved on cells', () {
      final nodes = parse('''
| L | C | R |
|:--|:-:|--:|
| 1 | 2 | 3 |
''');

      final table = findFirstElement(nodes, 'rich-table');
      final tbody = table.children![1] as md.Element;
      final row = tbody.children![0] as md.Element;
      final cells = row.children!.cast<md.Element>();

      expect(cells[0].attributes['align'], 'left');
      expect(cells[1].attributes['align'], 'center');
      expect(cells[2].attributes['align'], 'right');
    });

    test('cell inline children are preserved (em/strong/code)', () {
      final nodes = parse('''
| h |
|---|
| **b** *i* `c` |
''');

      final table = findFirstElement(nodes, 'rich-table');
      final tbody = table.children![1] as md.Element;
      final row = tbody.children![0] as md.Element;
      final cell = row.children![0] as md.Element;

      final cellTags = cell.children!
          .whereType<md.Element>()
          .map((e) => e.tag)
          .toList();
      expect(cellTags, containsAll(['strong', 'em', 'code']));
    });

    test('invalid table (no separator row) is not parsed as table', () {
      final nodes = parse('''
| a | b |
| 1 | 2 |
''');

      expect(
        nodes.whereType<md.Element>().any((e) => e.tag == 'rich-table'),
        isFalse,
      );
    });
  });
}
```

- [ ] **Step 2: 跑测试确认失败**

```bash
flutter test test/widgets/markdown/rich_table_block_syntax_test.dart
```

预期：FAIL（文件不存在）。

- [ ] **Step 3: 写最小实现**

创建 `lib/widgets/markdown/rich_table_block_syntax.dart`：

```dart
import 'package:markdown/markdown.dart' as md;

/// GFM table syntax that produces private `rich-*` AST tags instead of
/// the standard `<table>` / `<thead>` / etc.
///
/// This indirection lets [FlutterMarkdownImpl] take over table rendering
/// through `builders['rich-table']`, bypassing flutter_markdown_plus's
/// hard-coded `<table>` widget construction path while preserving GFM's
/// alignment and inline-content semantics.
class RichTableBlockSyntax extends md.TableSyntax {
  const RichTableBlockSyntax();

  static const Map<String, String> _tagRename = {
    'table': 'rich-table',
    'thead': 'rich-thead',
    'tbody': 'rich-tbody',
    'tr': 'rich-tr',
    'th': 'rich-th',
    'td': 'rich-td',
  };

  @override
  md.Node? parse(md.BlockParser parser) {
    final node = super.parse(parser);
    if (node is md.Element) {
      return _rebuildWithRename(node);
    }
    return node;
  }

  // md.Element.tag is final in the markdown 7.x package, so we rebuild the
  // sub-tree top-down instead of mutating in place. Attributes (including the
  // GFM `align` value on cells) are preserved verbatim.
  static md.Element _rebuildWithRename(md.Element element) {
    final newTag = _tagRename[element.tag] ?? element.tag;
    final originalChildren = element.children;
    final List<md.Node>? newChildren = originalChildren == null
        ? null
        : [
            for (final child in originalChildren)
              child is md.Element ? _rebuildWithRename(child) : child,
          ];
    final rebuilt = newChildren == null
        ? md.Element.empty(newTag)
        : md.Element(newTag, newChildren);
    rebuilt.attributes.addAll(element.attributes);
    return rebuilt;
  }
}
```

- [ ] **Step 4: 跑测试**

```bash
flutter test test/widgets/markdown/rich_table_block_syntax_test.dart
```

预期：全部 PASS。如失败：
- 若属性丢失：rebuild 实现中务必拷贝 `attributes`（已包含 `rebuilt.attributes.addAll(element.attributes)`）

- [ ] **Step 5: 跑 analyze**

```bash
flutter analyze lib/widgets/markdown/rich_table_block_syntax.dart test/widgets/markdown/rich_table_block_syntax_test.dart
```

预期：无 warning/error。

- [ ] **Step 6: 提交**

```bash
git add lib/widgets/markdown/rich_table_block_syntax.dart test/widgets/markdown/rich_table_block_syntax_test.dart
git commit -m "$(cat <<'EOF'
feat(markdown): add RichTableBlockSyntax with private rich-* AST tags

Subclasses md.TableSyntax to rename produced AST elements from
table/thead/tbody/tr/th/td to rich-table/rich-thead/... so that a
custom MarkdownElementBuilder can take over table rendering without
fighting flutter_markdown_plus's hard-coded <table> widget path.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

### Task 5: RichTableElementBuilder — 自渲染 Table widget

**Files:**
- Create: `lib/widgets/markdown/rich_table_element_builder.dart`
- Test: `test/widgets/markdown/rich_table_rendering_test.dart`

**职责：** 注册到 `builders['rich-table']`。接管 widget 渲染，遍历 `<rich-thead>` / `<rich-tbody>` 子树构造 `TableRow`，每个 `<rich-th>` / `<rich-td>` 用 `RichTableInlineSerializer` 反序列化后通过嵌套 `MarkdownBody` 渲染单元格。整体套 `TableEdgeFadeScrollShell` 实现横滚 + fade，外层圆角面板背景。

- [ ] **Step 1: 写 widget 测试（rendering）**

创建 `test/widgets/markdown/rich_table_rendering_test.dart`：

```dart
import 'package:ai_chat/widgets/markdown/flutter_markdown_impl.dart';
import 'package:ai_chat/widgets/markdown/table_edge_fade_scroll_shell.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _wrap(Widget child) =>
    MaterialApp(home: Scaffold(body: SingleChildScrollView(child: child)));

void main() {
  group('RichTableElementBuilder rendering', () {
    testWidgets('renders a Table inside TableEdgeFadeScrollShell',
        (tester) async {
      const data = '''
| a | b |
|---|---|
| 1 | 2 |
''';

      await tester.pumpWidget(_wrap(const FlutterMarkdownImpl(data: data)));
      await tester.pump();

      expect(find.byType(TableEdgeFadeScrollShell), findsOneWidget);
      expect(find.byType(Table), findsOneWidget);

      final Table table = tester.widget(find.byType(Table));
      expect(table.defaultColumnWidth, isA<IntrinsicColumnWidth>());
    });

    testWidgets('cell inline bold renders as a styled span, not literal **',
        (tester) async {
      const data = '''
| h |
|---|
| **bold** |
''';

      await tester.pumpWidget(_wrap(const FlutterMarkdownImpl(data: data)));
      await tester.pump();

      // The literal asterisks should NOT appear; the bolded word should.
      expect(find.textContaining('**bold**'), findsNothing);
      expect(find.textContaining('bold'), findsWidgets);
    });

    testWidgets('cell inline code renders as code (no backticks)',
        (tester) async {
      const data = '''
| h |
|---|
| `x` |
''';

      await tester.pumpWidget(_wrap(const FlutterMarkdownImpl(data: data)));
      await tester.pump();

      expect(find.textContaining('`x`'), findsNothing);
      expect(find.textContaining('x'), findsWidgets);
    });

    testWidgets('alignment attribute reaches TableCell (center)',
        (tester) async {
      const data = '''
| L | C | R |
|:--|:-:|--:|
| 1 | 2 | 3 |
''';

      await tester.pumpWidget(_wrap(const FlutterMarkdownImpl(data: data)));
      await tester.pump();

      // We expose alignment via DefaultTextStyle.textAlign inside cell.
      // Find the cell containing '2' and inspect its DefaultTextStyle.
      final cellFinder = find.ancestor(
        of: find.textContaining('2'),
        matching: find.byType(DefaultTextStyle),
      );
      expect(cellFinder, findsWidgets);
      final styles = tester
          .widgetList<DefaultTextStyle>(cellFinder)
          .toList();
      expect(
        styles.any((s) => s.textAlign == TextAlign.center),
        isTrue,
      );
    });

    testWidgets('long-content column widens; short stays compact',
        (tester) async {
      const data = '''
| short | long                                              |
|-------|---------------------------------------------------|
| 1     | this is a much longer content cell expected wider |
''';

      await tester.pumpWidget(_wrap(const FlutterMarkdownImpl(data: data)));
      await tester.pump();

      final cells = tester
          .widgetList<TableCell>(find.byType(TableCell))
          .toList();
      expect(cells.length, greaterThanOrEqualTo(4));

      // Pick the two body cells (last 2). Width of the long-content
      // cell should exceed the short-content cell by at least 30 px.
      final shortRect = tester.getRect(find.byWidget(cells[2]));
      final longRect = tester.getRect(find.byWidget(cells[3]));
      expect(longRect.width, greaterThan(shortRect.width + 30));
    });
  });
}
```

- [ ] **Step 2: 跑测试确认失败**

```bash
flutter test test/widgets/markdown/rich_table_rendering_test.dart
```

预期：FAIL（`RichTableBlockSyntax` 尚未集成进 `FlutterMarkdownImpl`，且 `RichTableElementBuilder` 不存在）。

- [ ] **Step 3: 写 RichTableElementBuilder 实现**

创建 `lib/widgets/markdown/rich_table_element_builder.dart`：

```dart
import 'package:ai_chat/theme/app_theme_spec.dart';
import 'package:ai_chat/theme/app_typography.dart';
import 'package:ai_chat/widgets/markdown/callout_block_syntax.dart';
import 'package:ai_chat/widgets/markdown/code_block_builder.dart';
import 'package:ai_chat/widgets/markdown/markdown_callout_builder.dart';
import 'package:ai_chat/widgets/markdown/markdown_math_builder.dart';
import 'package:ai_chat/widgets/markdown/math_block_syntax.dart';
import 'package:ai_chat/widgets/markdown/math_inline_syntax.dart';
import 'package:ai_chat/widgets/markdown/rich_table_inline_serializer.dart';
import 'package:ai_chat/widgets/markdown/table_edge_fade_scroll_shell.dart';
import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:markdown/markdown.dart' as md;

/// Renders <rich-table> AST sub-trees into a Flutter `Table` widget
/// wrapped in [TableEdgeFadeScrollShell] and a rounded panel.
///
/// Cell inline content is round-tripped through [RichTableInlineSerializer]
/// then rendered through a nested [MarkdownBody] so all inline syntax
/// (bold, code, links, inline math) keeps working with the same theme.
class RichTableElementBuilder extends MarkdownElementBuilder {
  RichTableElementBuilder();

  @override
  bool isBlockElement() => true;

  @override
  Widget? visitElementAfter(md.Element element, TextStyle? preferredStyle) {
    if (element.tag != 'rich-table') return null;
    // Builder instances are scoped to the parent MarkdownBody; resolve theme
    // tokens through a Builder so we have a fresh BuildContext on rebuild.
    return Builder(builder: _buildShell(element));
  }

  WidgetBuilder _buildShell(md.Element table) {
    return (context) {
      final theme = Theme.of(context);
      final isDark = theme.brightness == Brightness.dark;
      final colors = theme.extension<AppThemeSpec>()!;
      final bodyColor = theme.colorScheme.onSurface;

      final tableDividerColor =
          colors.divider.withValues(alpha: isDark ? 0.4 : 0.16);
      final tableHeaderFill =
          colors.toolWorkflowSurface.withValues(alpha: isDark ? 0.72 : 0.52);
      final tableBodyFill =
          colors.assistantSurface.withValues(alpha: isDark ? 0.2 : 0.08);
      final tableShellFill =
          colors.assistantSurface.withValues(alpha: isDark ? 0.3 : 0.14);

      final headerStyle = AppTypography.uiStyle(
        color: bodyColor,
        fontSize: 12.5,
        height: 1.2,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.08,
      );
      final bodyStyle = AppTypography.documentStyle(
        color: bodyColor,
        fontSize: 12.8,
        height: 1.35,
      );

      final rows = <TableRow>[];
      _appendRows(
        rows,
        table,
        cellTag: 'rich-th',
        rowDecoration: BoxDecoration(color: tableHeaderFill),
        textStyle: headerStyle,
        defaultAlign: TextAlign.center,
      );
      _appendRows(
        rows,
        table,
        cellTag: 'rich-td',
        rowDecoration: BoxDecoration(color: tableBodyFill),
        textStyle: bodyStyle,
        defaultAlign: TextAlign.left,
      );

      if (rows.isEmpty) return const SizedBox.shrink();

      final tableWidget = Table(
        defaultColumnWidth: const IntrinsicColumnWidth(),
        border: TableBorder(
          horizontalInside:
              BorderSide(color: tableDividerColor, width: 0.7),
        ),
        children: rows,
      );

      return Container(
        margin: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: tableShellFill,
          borderRadius: BorderRadius.circular(12),
        ),
        clipBehavior: Clip.antiAlias,
        child: TableEdgeFadeScrollShell(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2),
            child: tableWidget,
          ),
        ),
      );
    };
  }

  void _appendRows(
    List<TableRow> out,
    md.Element table, {
    required String cellTag,
    required BoxDecoration rowDecoration,
    required TextStyle textStyle,
    required TextAlign defaultAlign,
  }) {
    final sectionTag = cellTag == 'rich-th' ? 'rich-thead' : 'rich-tbody';
    final section = table.children?.firstWhere(
      (n) => n is md.Element && n.tag == sectionTag,
      orElse: () => md.Element.empty(sectionTag),
    );
    if (section is! md.Element) return;
    final rows = section.children?.whereType<md.Element>() ?? const [];
    for (final tr in rows) {
      if (tr.tag != 'rich-tr') continue;
      final cells = tr.children?.whereType<md.Element>().toList() ?? const [];
      out.add(TableRow(
        decoration: rowDecoration,
        children: [
          for (final cell in cells)
            _buildCell(
              cell,
              textStyle: textStyle,
              defaultAlign: defaultAlign,
            ),
        ],
      ));
    }
  }

  Widget _buildCell(
    md.Element cell, {
    required TextStyle textStyle,
    required TextAlign defaultAlign,
  }) {
    final align = _alignFor(cell, defaultAlign);
    final cellMarkdown = RichTableInlineSerializer.serialize(
      cell.children ?? const <md.Node>[],
    );
    return TableCell(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
        child: DefaultTextStyle(
          style: textStyle,
          textAlign: align,
          child: MarkdownBody(
            data: cellMarkdown,
            selectable: false,
            fitContent: true,
            extensionSet: md.ExtensionSet.gitHubFlavored,
            inlineSyntaxes: [MathInlineSyntax()],
            blockSyntaxes: const [
              MathBlockSyntax(),
              CalloutBlockSyntax(),
            ],
            builders: {
              'math-inline': MarkdownInlineMathBuilder(),
              'math-block': MarkdownBlockMathBuilder(),
              'callout': MarkdownCalloutBuilder(),
              'code': CodeElementBuilder(),
              'pre': CodeBlockBuilder(),
            },
            styleSheet: MarkdownStyleSheet(
              p: textStyle,
              blockSpacing: 0,
              textAlign: _wrapAlignFor(align),
            ),
          ),
        ),
      ),
    );
  }

  TextAlign _alignFor(md.Element cell, TextAlign fallback) {
    switch (cell.attributes['align']) {
      case 'left':
        return TextAlign.left;
      case 'center':
        return TextAlign.center;
      case 'right':
        return TextAlign.right;
      default:
        return fallback;
    }
  }

  WrapAlignment _wrapAlignFor(TextAlign align) {
    switch (align) {
      case TextAlign.center:
        return WrapAlignment.center;
      case TextAlign.right:
        return WrapAlignment.end;
      default:
        return WrapAlignment.start;
    }
  }
}
```

注意点：

- `MarkdownBody` 的 `fitContent: true` 让单元格内 markdown 不强制 stretch，配合 `Table` 的 `IntrinsicColumnWidth` 测量
- `selectable: false` 保持与主路径一致
- `MarkdownBody.builders` 透传项目的 inline math / callout / code 等自定义，使行内 math 与行内 code 在单元格里继续工作
- 一些 import 在 `flutter_markdown_plus` 上可能要校准，若 API 与 0.6.x 不完全一致，按编译错误调整

- [ ] **Step 4: 暂不集成进 FlutterMarkdownImpl，先编译 + analyze**

```bash
flutter analyze lib/widgets/markdown/rich_table_element_builder.dart
```

预期：可能报 `MarkdownInlineMathBuilder` / `MarkdownBlockMathBuilder` / `MarkdownCalloutBuilder` 等的位置/签名问题，按实际报错调整 import 与 builder 名称。

- [ ] **Step 5: 跑测试（仍然会失败，因为 FlutterMarkdownImpl 还没接入）**

```bash
flutter test test/widgets/markdown/rich_table_rendering_test.dart
```

预期：FAIL（表格仍按 flutter_markdown_plus 默认渲染，找不到 `TableEdgeFadeScrollShell`）。继续到 Task 6 集成。

### Task 6: 集成 RichTable 到 FlutterMarkdownImpl

**Files:**
- Modify: `lib/widgets/markdown/flutter_markdown_impl.dart`

- [ ] **Step 1: 构造无 TableSyntax 的 ExtensionSet 并注入 builder**

打开 `lib/widgets/markdown/flutter_markdown_impl.dart`。当前内容（参考 spec 现状梳理）：

```dart
return RepaintBoundary(
  child: MarkdownBody(
    data: data,
    selectable: false,
    fitContent: false,
    onTapLink: (text, href, title) => _launchUrl(text, href),
    blockSyntaxes: const [
      MathBlockSyntax(),
      CalloutBlockSyntax(),
    ],
    inlineSyntaxes: [
      MathInlineSyntax(),
    ],
    styleSheet: MarkdownStyleSheet( ... ),
    builders: {
      'math-inline': MarkdownInlineMathBuilder(),
      'math-block': MarkdownBlockMathBuilder(),
      'callout': MarkdownCalloutBuilder(),
      'code': CodeElementBuilder(),
      'pre': CodeBlockBuilder(),
    },
  ),
);
```

修改为：

```dart
return RepaintBoundary(
  child: MarkdownBody(
    data: data,
    selectable: false,
    fitContent: false,
    onTapLink: (text, href, title) => _launchUrl(text, href),
    extensionSet: md.ExtensionSet(
      [
        const RichTableBlockSyntax(),
        for (final s in md.ExtensionSet.gitHubFlavored.blockSyntaxes)
          if (s is! md.TableSyntax) s,
      ],
      md.ExtensionSet.gitHubFlavored.inlineSyntaxes,
    ),
    blockSyntaxes: const [
      MathBlockSyntax(),
      CalloutBlockSyntax(),
    ],
    inlineSyntaxes: [
      MathInlineSyntax(),
    ],
    styleSheet: MarkdownStyleSheet( ... unchanged ... ),
    builders: {
      'math-inline': MarkdownInlineMathBuilder(),
      'math-block': MarkdownBlockMathBuilder(),
      'callout': MarkdownCalloutBuilder(),
      'code': CodeElementBuilder(),
      'pre': CodeBlockBuilder(),
      'rich-table': RichTableElementBuilder(),
    },
  ),
);
```

在文件顶部增加 imports：

```dart
import 'package:markdown/markdown.dart' as md;

import 'rich_table_block_syntax.dart';
import 'rich_table_element_builder.dart';
```

- [ ] **Step 2: 跑表格 widget 测试**

```bash
flutter test test/widgets/markdown/rich_table_rendering_test.dart
```

预期：全部 PASS。

如出现「`MarkdownBody` 同时接收 `extensionSet` 和 `blockSyntaxes` 导致语法重复注册」：检查 `flutter_markdown_plus` 是否把两者合并（应当是 OK 的，`blockSyntaxes` 仅追加项目自定义 syntax）。

如出现单元格里 `MarkdownBody` 没接收到自定义 inline math / callout：在 `RichTableElementBuilder._buildCell` 中已透传，再次确认 import 与 builder 实例化无误。

- [ ] **Step 3: 跑全部 markdown 测试 + chat blocks 测试**

```bash
flutter test test/widgets/markdown/ test/widgets/chat_blocks/
```

预期：全部 PASS。

- [ ] **Step 4: 跑 analyze**

```bash
flutter analyze
```

预期：无 warning/error。

### Task 7: 扩展 regression test 样本

**Files:**
- Modify: `test/widgets/markdown/markdown_rendering_regression_test.dart`

- [ ] **Step 1: 阅读现有 regression test 结构**

打开 `test/widgets/markdown/markdown_rendering_regression_test.dart`，先读懂当前结构（已存在两个用 `MarkdownWidgetImpl` 的用例）。

- [ ] **Step 2: 添加一个走 FlutterMarkdownImpl 的表格用例**

在该文件已有 group 内追加新 testWidgets：

```dart
import 'package:ai_chat/widgets/markdown/flutter_markdown_impl.dart';
import 'package:ai_chat/widgets/markdown/table_edge_fade_scroll_shell.dart';
// ... 现有 import 保留

// 在 main() 内的 group 末尾添加：

testWidgets(
  'FlutterMarkdownImpl renders a GFM table through TableEdgeFadeScrollShell',
  (tester) async {
    const data = '''
| name | qty |
|------|-----|
| **apple** | `3` |
| pear      | 2   |
''';

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: FlutterMarkdownImpl(data: data),
        ),
      ),
    ));
    await tester.pump();

    expect(find.byType(TableEdgeFadeScrollShell), findsOneWidget);
    expect(find.byType(Table), findsOneWidget);
    expect(find.textContaining('apple'), findsWidgets);
    expect(find.textContaining('**apple**'), findsNothing);
  },
);
```

- [ ] **Step 3: 跑该测试文件**

```bash
flutter test test/widgets/markdown/markdown_rendering_regression_test.dart
```

预期：全部 PASS（已有用例 + 新增的 FlutterMarkdownImpl 表格用例）。

### Task 8: 真机/视觉回归验证

**Files:** 无新增代码改动。

- [ ] **Step 1: 跑全套 widget 测试 + analyze**

```bash
flutter test
flutter analyze
```

预期：全部 PASS、无 lint。

- [ ] **Step 2: 真机视觉验证（若有设备）**

```bash
bash scripts/android_install_debug.sh
```

打开 app，构造并发送一条含表格的 assistant 消息（可以触发任意会输出 markdown table 的 prompt，例如让 AI 列一张对比表）。逐项确认：

- 表格出现圆角外壳、横向滚动
- 超出可视宽度的列触发左/右 fade 渐隐
- 单元格内 `**bold**` / `` `code` `` / `[link](url)` 渲染为对应样式
- 单元格内 `$x^2$` 行内数学渲染
- 列宽随内容变化（短列窄、长列宽）

如无真机，跳过此步骤，依赖 widget 测试。

- [ ] **Step 3: 提交阶段 2**

```bash
git add lib/widgets/markdown/rich_table_element_builder.dart lib/widgets/markdown/flutter_markdown_impl.dart test/widgets/markdown/rich_table_rendering_test.dart test/widgets/markdown/markdown_rendering_regression_test.dart
git commit -m "$(cat <<'EOF'
feat(markdown): migrate table visuals onto flutter_markdown_plus path

Adds RichTableElementBuilder that takes over <rich-table> rendering:
flutter Table widget with IntrinsicColumnWidth, wrapped in the existing
TableEdgeFadeScrollShell and a rounded panel matching the legacy
MarkdownWidgetImpl table look. Cells preserve inline markdown (bold,
em, code, link, inline math) by serializing back to a markdown fragment
and nesting a MarkdownBody.

FlutterMarkdownImpl now disables flutter_markdown_plus's default GFM
TableSyntax and injects RichTableBlockSyntax + builders['rich-table'],
so the main reading path uses a single rendering engine consistently.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

预期：commit 成功，`git status` clean。

---

## Self-Review Notes

- **Spec coverage**：阶段 1 实现「依赖升级」目标；Task 3 实现「单元格 inline 保留」；Task 4 实现「私有 AST 标签」；Task 5 实现「视觉迁移 + IntrinsicColumnWidth 内容定宽 + TableEdgeFadeScrollShell」；Task 6 实现「集成到主路径」；Task 7 实现「regression 覆盖」。spec 全部条目可对应到任务。
- **Placeholder scan**：未出现 "TBD" / "TODO" / "implement later"。`tag is final` 备选方案在 Task 4 步骤 3 给出了完整代码。
- **Type consistency**：所有用到的类名（`RichTableBlockSyntax` / `RichTableElementBuilder` / `RichTableInlineSerializer`）与方法签名（`serialize(List<md.Node>)`、`visitElementAfter` 等）跨任务一致。
