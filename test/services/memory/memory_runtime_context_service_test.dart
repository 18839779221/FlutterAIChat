import 'package:ai_chat/models/chat_message.dart';
import 'package:ai_chat/services/memory/memory_runtime_context_service.dart';
import 'package:ai_chat/services/chat_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('MemoryRuntimeContextService', () {
    test('returns empty context when memory index is missing', () async {
      final service = MemoryRuntimeContextService(
        readFile: (_) async => null,
      );

      final section = await service.buildContextSection(userInput: 'hello');

      expect(section, isEmpty);
    });

    test('returns empty context when user asks to ignore memory', () async {
      final service = MemoryRuntimeContextService(
        readFile: (_) async =>
            '- [Android debug](feedback/android-debug.md) — debug install preference',
      );

      final section = await service.buildContextSection(
        userInput: 'please do not use memory',
      );

      expect(section, isEmpty);
    });

    test('loads memory index as runtime context', () async {
      final service = MemoryRuntimeContextService(
        readFile: (path) async {
          if (path == '/memories/MEMORY.md') {
            return '- [Android debug](feedback/android-debug.md) — debug install preference';
          }
          return null;
        },
      );

      final section = await service.buildContextSection(userInput: 'hello');

      expect(section, contains('# memoryIndex'));
      expect(section, contains('MEMORY.md is always loaded'));
      expect(section, contains('[Android debug](feedback/android-debug.md)'));
    });

    test('loads recalled topic file when the side selector picks it',
        () async {
      final service = MemoryRuntimeContextService(
        readFile: (path) async {
          switch (path) {
            case '/memories/MEMORY.md':
              return '''
- [Android debug](feedback/android-debug.md) — debug install preference
- [Theme choice](project/theme.md) — visual direction
''';
            case '/memories/feedback/android-debug.md':
              return '''
---
name: Android debug install preference
description: User prefers debug overwrite install on Android real devices.
type: feedback
---

Rule/fact: use overwrite installs on Android.
''';
            case '/memories/project/theme.md':
              return '''
---
name: Theme choice
description: Visual direction for the app.
type: project
---

Rule/fact: keep the UI grounded and readable.
''';
            default:
              return null;
          }
        },
        selectRelevantTopics: ({
          required userInput,
          required candidates,
          sideRuntimeConfigOverride,
          sideTaskRunner,
        }) async {
          expect(userInput, contains('Android debug'));
          expect(candidates, hasLength(2));
          return const ['/memories/feedback/android-debug.md'];
        },
      );

      final section = await service.buildContextSection(
        userInput: 'Need Android debug install help',
      );

      expect(section, contains('# recalledMemories'));
      expect(section, contains('Android debug install preference'));
      expect(section, contains('use overwrite installs on Android'));
      expect(section, isNot(contains('/memories/project/theme.md')));
    });

    test('skips topic paths outside /memories', () async {
      final service = MemoryRuntimeContextService(
        readFile: (path) async {
          if (path == '/memories/MEMORY.md') {
            return '- [Bad](../escape.md) — blocked';
          }
          return null;
        },
        selectRelevantTopics: ({
          required userInput,
          required candidates,
          sideRuntimeConfigOverride,
          sideTaskRunner,
        }) async {
          expect(candidates, isEmpty);
          return const [];
        },
      );

      final section = await service.buildContextSection(userInput: 'hello');

      expect(section, contains('# memoryIndex'));
      expect(section, isNot(contains('# recalledMemories')));
    });

    test('uses selector output to build recalled memory sections', () async {
      var selectorCalled = false;
      final service = MemoryRuntimeContextService(
        readFile: (path) async {
          switch (path) {
            case '/memories/MEMORY.md':
              return '- [Android debug](feedback/android-debug.md) — debug install preference';
            case '/memories/feedback/android-debug.md':
              return '''
---
name: Android debug install preference
description: User prefers debug overwrite install on Android real devices.
type: feedback
---

Rule/fact: use overwrite installs on Android.
''';
            default:
              return null;
          }
        },
        selectRelevantTopics: ({
          required userInput,
          required candidates,
          sideRuntimeConfigOverride,
          sideTaskRunner,
        }) async {
          selectorCalled = true;
          expect(userInput, contains('debug'));
          expect(candidates, hasLength(1));
          expect(candidates.single.title, 'Android debug');
          expect(candidates.single.hook, contains('debug install preference'));
          return const ['/memories/feedback/android-debug.md'];
        },
      );

      final section = await service.buildContextSection(
        userInput: 'debug memory please',
      );

      expect(selectorCalled, isTrue);
      expect(section, contains('# recalledMemories'));
      expect(section, contains('Android debug install preference'));
      expect(section, contains('User prefers debug overwrite install on Android real devices.'));
    });

    test('passes side task runner into selector when provided', () async {
      var runnerCalled = false;
      var selectorSawRunner = false;
      final service = MemoryRuntimeContextService(
        readFile: (path) async {
          switch (path) {
            case '/memories/MEMORY.md':
              return '- [Android debug](feedback/android-debug.md) — debug install preference';
            case '/memories/feedback/android-debug.md':
              return '''
---
name: Android debug install preference
description: User prefers debug overwrite install on Android real devices.
type: feedback
---

Rule/fact: use overwrite installs on Android.
''';
            default:
              return null;
          }
        },
        selectRelevantTopics: ({
          required userInput,
          required candidates,
          sideRuntimeConfigOverride,
          sideTaskRunner,
        }) async {
          selectorSawRunner = sideTaskRunner != null;
          if (sideTaskRunner != null) {
            final result = await sideTaskRunner(
              const [],
              config: ChatConfig(systemPrompt: ''),
              requestLabel: 'memory_side_selector',
            );
            runnerCalled = result.isEmpty;
          }
          return const ['/memories/feedback/android-debug.md'];
        },
      );

      final section = await service.buildContextSection(
        userInput: 'debug memory please',
        sideTaskRunner: (
          List<ChatMessage> messages, {
          required ChatConfig config,
          required String requestLabel,
          Duration? timeout,
        }) async {
          expect(requestLabel, 'memory_side_selector');
          expect(messages, isEmpty);
          expect(config.systemPrompt, '');
          return '';
        },
      );

      expect(selectorSawRunner, isTrue);
      expect(runnerCalled, isTrue);
      expect(section, contains('# recalledMemories'));
    });
  });
}
