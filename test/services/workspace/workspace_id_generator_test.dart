import 'package:ai_chat/services/workspace/workspace_id_generator.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('WorkspaceIdGenerator', () {
    test('exposes .default as the default workspace id', () {
      expect(WorkspaceIdGenerator.defaultWorkspaceId, '.default');
    });

    test('generates ws_<yyyyMMdd>_<6 lowercase alnum> ids', () {
      var cursor = 0;
      const values = <int>[0, 1, 2, 27, 28, 29];
      final generator = WorkspaceIdGenerator(
        randomIntProvider: (max) => values[cursor++ % values.length] % max,
      );

      final id = generator.generateAutoWorkspaceId(
        now: DateTime(2026, 6, 2),
      );

      expect(id, matches(r'^ws_20260602_[a-z0-9]{6}$'));
      expect(id, 'ws_20260602_abc123');
    });
  });
}
