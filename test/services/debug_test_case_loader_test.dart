import 'package:ai_chat/models/debug/debug_test_case.dart';
import 'package:ai_chat/services/debug_test_case_loader.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('loader parses enabled cases and keeps featured ordering', () async {
    final loader = AssetDebugTestCaseLoader(
      assetBundle: _FakeAssetBundle('''
{
  "version": 1,
  "cases": [
    {
      "id": "plain-answer",
      "group": "tool-call",
      "title": "纯文本直答",
      "summary": "无需工具。",
      "prompt": "用一句话解释什么是 SQLite",
      "tags": ["agent-loop", "plain-answer"],
      "featured": true,
      "enabled": true
    },
    {
      "id": "disabled",
      "group": "tool-call",
      "title": "停用案例",
      "summary": "不展示。",
      "prompt": "disabled",
      "tags": ["legacy"],
      "featured": true,
      "enabled": false
    },
    {
      "id": "confirmation",
      "group": "confirmation",
      "title": "确认暂停",
      "summary": "副作用工具。",
      "prompt": "提醒我今晚 8 点提交周报",
      "tags": ["confirmation"],
      "featured": true,
      "enabled": true
    }
  ]
}
'''),
    );

    final library = await loader.load();

    expect(library.version, 1);
    expect(library.allCases.map((item) => item.id), [
      'plain-answer',
      'confirmation',
    ]);
    expect(library.featuredCases.map((item) => item.id), [
      'plain-answer',
      'confirmation',
    ]);
    expect(library.allCases.map((item) => item.group), [
      'tool-call',
      'confirmation',
    ]);
  });

  test('debug test case model trims scalar strings and preserves group/tags', () {
    final parsed = DebugTestCase.fromJson(const {
      'id': '  plain-answer  ',
      'group': ' tool-call ',
      'title': '  纯文本直答 ',
      'summary': '  无需工具。 ',
      'prompt': '  用一句话解释什么是 SQLite ',
      'tags': ['agent-loop', ' plain-answer '],
      'featured': true,
      'enabled': true,
    });

    expect(parsed.id, 'plain-answer');
    expect(parsed.group, 'tool-call');
    expect(parsed.title, '纯文本直答');
    expect(parsed.summary, '无需工具。');
    expect(parsed.prompt, '用一句话解释什么是 SQLite');
    expect(parsed.tags, ['agent-loop', 'plain-answer']);
    expect(parsed.featured, isTrue);
    expect(parsed.enabled, isTrue);
  });
}

class _FakeAssetBundle extends CachingAssetBundle {
  final String _content;

  _FakeAssetBundle(this._content);

  @override
  Future<ByteData> load(String key) {
    throw UnimplementedError('本测试不会走二进制 asset 读取');
  }

  @override
  Future<String> loadString(String key, {bool cache = true}) async => _content;
}
