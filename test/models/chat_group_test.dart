import 'package:ai_chat/models/chat_group.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ChatGroup', () {
    test('serializes and restores workspaceId', () {
      final group = ChatGroup(
        id: 1,
        title: 'Test',
        workspaceId: 'ws_20260602_a3k9qx',
      );

      expect(group.toMap()['workspace_id'], 'ws_20260602_a3k9qx');
      expect(ChatGroup.fromMap(group.toMap()).workspaceId, 'ws_20260602_a3k9qx');
      expect(group.toMap().containsKey('locked_provider_style'), isFalse);
    });

    test('copyWith preserves workspaceId by default and allows override', () {
      final original = ChatGroup(
        id: 1,
        title: 'Test',
        workspaceId: 'ws_20260602_a3k9qx',
      );

      expect(original.copyWith(title: 'Updated').workspaceId, original.workspaceId);
      expect(
        original.copyWith(workspaceId: '.default').workspaceId,
        '.default',
      );
    });
  });
}
