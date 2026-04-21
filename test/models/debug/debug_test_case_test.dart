import 'package:ai_chat/models/debug/debug_test_case.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('DebugTestCase', () {
    test('parses complete e2e case', () {
      final parsed = DebugTestCase.fromJson(_validCaseJson());

      expect(parsed.id, 'file-read-then-edit-with-confirmation');
      expect(parsed.group, 'file-sandbox-looped');
      expect(parsed.title, '先读后改并确认');
      expect(parsed.prompt, '把 memories/todo.md 里的 beta 改成 delta');
      expect(parsed.tags, containsAll(['file', 'edit', 'agent-loop']));
      expect(parsed.featured, isTrue);
      expect(parsed.enabled, isTrue);
      expect(parsed.setup.historyMessages, isEmpty);
      expect(parsed.setup.files, hasLength(1));
      expect(parsed.setup.files.single.path, 'memories/todo.md');
      expect(parsed.setup.files.single.content, contains('beta'));
      expect(parsed.checkpoints, [
        'tool:Read:success',
        'tool:Edit:awaiting_confirmation',
        'tool:Edit:success',
        'finalAnswer',
      ]);
      expect(parsed.assertions.endStatus, ['completed']);
      expect(parsed.assertions.mustContainEvents, contains('finalAnswer'));
      expect(parsed.assertions.finalFileContains.single.path, 'memories/todo.md');
      expect(parsed.assertions.finalFileContains.single.text, 'delta');
      expect(parsed.assertions.mustNotHang, isTrue);
    });

    test('rejects invalid checkpoint', () {
      final json = _validCaseJson();
      json['checkpoints'] = [
        'tool:Read:done',
        'finalAnswer',
      ];

      expect(
        () => DebugTestCase.fromJson(json),
        _throwsFormatExceptionContaining('非法 checkpoint'),
      );
    });

    test('rejects mutation after unknown checkpoint', () {
      final json = _validCaseJson();
      json['checkpoints'] = [
        'tool:Edit:awaiting_confirmation',
        'tool:Edit:success',
        'finalAnswer',
      ];
      (json['setup'] as Map<String, dynamic>)['mutationsAfterCheckpoints'] = [
        {
          'after': 'tool:Read:success',
          'path': 'memories/todo.md',
          'content': 'changed externally',
        },
      ];

      expect(
        () => DebugTestCase.fromJson(json),
        _throwsFormatExceptionContaining('必须引用当前 case 的 checkpoint'),
      );
    });

    test('rejects mutation path that is not seeded', () {
      final json = _validCaseJson();
      (json['setup'] as Map<String, dynamic>)['mutationsAfterCheckpoints'] = [
        {
          'after': 'tool:Read:success',
          'path': 'memories/other.md',
          'content': 'changed externally',
        },
      ];

      expect(
        () => DebugTestCase.fromJson(json),
        _throwsFormatExceptionContaining('必须先在 setup.files 中声明'),
      );
    });

    test('rejects finalFileContains without successful write checkpoint', () {
      final json = _validCaseJson();
      json['checkpoints'] = [
        'tool:Read:success',
        'finalAnswer',
      ];

      expect(
        () => DebugTestCase.fromJson(json),
        _throwsFormatExceptionContaining('必须包含成功写操作'),
      );
    });

    test('rejects ask-user-question case without askUser:prompted', () {
      final json = _validCaseJson();
      json['id'] = 'ask-user-question-missing-prompt';
      json['group'] = 'ask-user-question';
      json['checkpoints'] = ['finalAnswer'];
      json['assertions'] = {
        'endStatus': ['completed'],
        'mustContainEvents': ['finalAnswer'],
        'mustNotHang': true,
      };

      expect(
        () => DebugTestCase.fromJson(json),
        _throwsFormatExceptionContaining('必须包含 askUser:prompted'),
      );
    });

    test('rejects featured but disabled case', () {
      final json = _validCaseJson();
      json['featured'] = true;
      json['enabled'] = false;

      expect(
        () => DebugTestCase.fromJson(json),
        _throwsFormatExceptionContaining('不能同时 featured=true 且 enabled=false'),
      );
    });

    test('rejects conflicting final file expectations', () {
      final json = _validCaseJson();
      final assertions = Map<String, dynamic>.from(
        json['assertions'] as Map<String, dynamic>,
      );
      assertions['finalFileUnchanged'] = ['memories/todo.md'];
      json['assertions'] = assertions;

      expect(
        () => DebugTestCase.fromJson(json),
        _throwsFormatExceptionContaining('finalFileContains 与 finalFileUnchanged 冲突'),
      );
    });
  });
}

Map<String, dynamic> _validCaseJson() => {
      'id': 'file-read-then-edit-with-confirmation',
      'group': 'file-sandbox-looped',
      'title': '先读后改并确认',
      'summary': '已有文件修改前必须先读取，再进入确认并执行编辑。',
      'prompt': '把 memories/todo.md 里的 beta 改成 delta',
      'tags': ['file', 'read', 'edit', 'confirmation', 'agent-loop'],
      'featured': true,
      'enabled': true,
      'setup': {
        'historyMessages': [],
        'files': [
          {
            'path': 'memories/todo.md',
            'content': 'alpha\nbeta\ngamma\n',
          }
        ],
        'mutationsAfterCheckpoints': [],
      },
      'checkpoints': [
        'tool:Read:success',
        'tool:Edit:awaiting_confirmation',
        'tool:Edit:success',
        'finalAnswer',
      ],
      'assertions': {
        'endStatus': ['completed'],
        'mustContainEvents': [
          'assistantToolCall',
          'assistantToolConfirmation',
          'toolResult',
          'finalAnswer',
        ],
        'forbidErrorCodes': ['unread_file', 'stale_file_version'],
        'finalFileContains': [
          {
            'path': 'memories/todo.md',
            'text': 'delta',
          }
        ],
        'mustNotHang': true,
      },
    };

Matcher _throwsFormatExceptionContaining(String text) {
  return throwsA(
    isA<FormatException>().having(
      (error) => error.message,
      'message',
      contains(text),
    ),
  );
}
