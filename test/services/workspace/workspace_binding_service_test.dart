import 'package:ai_chat/services/workspace/workspace_binding_service.dart';
import 'package:ai_chat/services/workspace/workspace_id_generator.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('WorkspaceBindingService', () {
    test('resolves null workspace ids to .default', () {
      final service = WorkspaceBindingService();
      final resolved = service.resolveWorkspaceId(null);

      expect(resolved.workspaceId, '.default');
      expect(resolved.isDefault, isTrue);
      expect(resolved.fileRoot, '/workspaces/.default');
    });

    test('resolves explicit workspace ids to a scoped file root', () {
      final service = WorkspaceBindingService();
      final resolved = service.resolveWorkspaceId('ws_20260602_a3k9qx');

      expect(resolved.workspaceId, 'ws_20260602_a3k9qx');
      expect(resolved.isDefault, isFalse);
      expect(resolved.fileRoot, '/workspaces/ws_20260602_a3k9qx');
    });

    test('delegates auto workspace id generation', () {
      final service = WorkspaceBindingService(
        idGenerator: WorkspaceIdGenerator(
          randomIntProvider: (_) => 0,
        ),
      );

      expect(
        service.createAutoWorkspaceId(now: DateTime(2026, 6, 2)),
        'ws_20260602_aaaaaa',
      );
    });
  });
}
