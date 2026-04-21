import 'package:ai_chat/services/debug_test_case_loader.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AssetDebugTestCaseLoader', () {
    test('parses enabled cases and keeps featured ordering', () async {
      final loader = AssetDebugTestCaseLoader(
        assetBundle: _FakeAssetBundle('''
{
  "cases": [
    {
      "id": "case-a",
      "group": "agent-loop-basic",
      "title": "A",
      "summary": "A summary",
      "prompt": "A prompt",
      "tags": ["agent-loop"],
      "featured": true,
      "enabled": true,
      "setup": {
        "historyMessages": [],
        "files": [],
        "mutationsAfterCheckpoints": []
      },
      "checkpoints": ["finalAnswer"],
      "assertions": {
        "endStatus": ["completed"],
        "mustContainEvents": ["finalAnswer"],
        "mustNotHang": true
      }
    },
    {
      "id": "case-b",
      "group": "file-sandbox-looped",
      "title": "B",
      "summary": "B summary",
      "prompt": "B prompt",
      "tags": ["file"],
      "featured": true,
      "enabled": true,
      "setup": {
        "historyMessages": [],
        "files": [
          {
            "path": "memories/todo.md",
            "content": "alpha"
          }
        ],
        "mutationsAfterCheckpoints": []
      },
      "checkpoints": [
        "tool:Read:success",
        "tool:Edit:success",
        "finalAnswer"
      ],
      "assertions": {
        "endStatus": ["completed"],
        "finalFileContains": [
          {
            "path": "memories/todo.md",
            "text": "delta"
          }
        ],
        "mustNotHang": true
      }
    },
    {
      "id": "case-c",
      "group": "agent-loop-basic",
      "title": "C",
      "summary": "C summary",
      "prompt": "C prompt",
      "tags": ["disabled"],
      "featured": false,
      "enabled": false,
      "setup": {
        "historyMessages": [],
        "files": [],
        "mutationsAfterCheckpoints": []
      },
      "checkpoints": ["finalAnswer"],
      "assertions": {
        "endStatus": ["completed"],
        "mustNotHang": true
      }
    }
  ]
}
'''),
      );

      final library = await loader.load();

      expect(library.allCases, hasLength(2));
      expect(library.allCases.map((item) => item.id), ['case-a', 'case-b']);
      expect(library.featuredCases.map((item) => item.id), ['case-a', 'case-b']);
      final fileCase = library.allCases.last;
      expect(fileCase.setup.files.single.path, 'memories/todo.md');
      expect(fileCase.checkpoints, containsAllInOrder([
        'tool:Read:success',
        'tool:Edit:success',
        'finalAnswer',
      ]));
      expect(fileCase.assertions.endStatus, ['completed']);
    });

    test('rejects duplicate ids', () async {
      final loader = AssetDebugTestCaseLoader(
        assetBundle: _FakeAssetBundle('''
{
  "cases": [
    {
      "id": "dup",
      "group": "agent-loop-basic",
      "title": "A",
      "summary": "A",
      "prompt": "A",
      "tags": [],
      "featured": false,
      "enabled": true,
      "setup": {
        "historyMessages": [],
        "files": [],
        "mutationsAfterCheckpoints": []
      },
      "checkpoints": ["finalAnswer"],
      "assertions": {
        "endStatus": ["completed"],
        "mustNotHang": true
      }
    },
    {
      "id": "dup",
      "group": "agent-loop-basic",
      "title": "B",
      "summary": "B",
      "prompt": "B",
      "tags": [],
      "featured": false,
      "enabled": true,
      "setup": {
        "historyMessages": [],
        "files": [],
        "mutationsAfterCheckpoints": []
      },
      "checkpoints": ["finalAnswer"],
      "assertions": {
        "endStatus": ["completed"],
        "mustNotHang": true
      }
    }
  ]
}
'''),
      );

      await expectLater(
        loader.load(),
        throwsA(
          isA<FormatException>().having(
            (error) => error.message,
            'message',
            contains('id 重复'),
          ),
        ),
      );
    });

    test('rejects non-object root', () async {
      final loader = AssetDebugTestCaseLoader(
        assetBundle: _FakeAssetBundle('[]'),
      );

      await expectLater(
        loader.load(),
        throwsA(
          isA<FormatException>().having(
            (error) => error.message,
            'message',
            contains('root 必须是对象'),
          ),
        ),
      );
    });

    test('rejects non-array cases', () async {
      final loader = AssetDebugTestCaseLoader(
        assetBundle: _FakeAssetBundle('{"cases": {}}'),
      );

      await expectLater(
        loader.load(),
        throwsA(
          isA<FormatException>().having(
            (error) => error.message,
            'message',
            contains('cases 必须是数组'),
          ),
        ),
      );
    });
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
