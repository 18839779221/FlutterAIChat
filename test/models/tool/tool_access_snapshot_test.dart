import 'package:ai_chat/models/tool/tool_access_snapshot.dart';
import 'package:ai_chat/models/tool/tool_definition.dart';
import 'package:ai_chat/models/tool/tool_policy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ToolAccessSnapshot', () {
    test('toJson emits the shared policy snapshot shape', () {
      const snapshot = ToolAccessSnapshot(
        definition: ToolDefinition(
          name: 'create_reminder',
          title: '创建提醒',
        ),
        executionDecision: ToolPolicyDecision.requireConfirmation,
        executionPolicyLabel: 'require_confirmation',
        isVisibleToPlanner: true,
      );

      expect(snapshot.toJson(), {
        'toolName': 'create_reminder',
        'executionDecision': 'requireConfirmation',
        'executionPolicy': 'require_confirmation',
        'isVisibleToPlanner': true,
      });
    });

    test('autoRun constructor emits the default visible runtime snapshot', () {
      const definition = ToolDefinition(
        name: 'web_search',
        title: '联网搜索',
      );

      final snapshot = ToolAccessSnapshot.autoRun(definition: definition);

      expect(snapshot.executionDecision, ToolPolicyDecision.autoRun);
      expect(snapshot.executionPolicyLabel, 'auto_run');
      expect(snapshot.isVisibleToPlanner, isTrue);
      expect(snapshot.toJson()['toolName'], 'web_search');
    });

    test('fromLegacyDefinition maps blocked and confirmation semantics once',
        () {
      final blocked = ToolAccessSnapshot.fromLegacyDefinition(
        definition: const ToolDefinition(
          name: 'create_reminder',
          title: '创建提醒',
          requiresConfirmation: true,
        ),
        isBlocked: true,
      );
      final confirmation = ToolAccessSnapshot.fromLegacyDefinition(
        definition: const ToolDefinition(
          name: 'Write',
          title: '写入文件',
          requiresConfirmation: true,
        ),
      );

      expect(blocked.executionDecision, ToolPolicyDecision.blocked);
      expect(blocked.executionPolicyLabel, 'blocked');
      expect(blocked.isVisibleToPlanner, isFalse);

      expect(
        confirmation.executionDecision,
        ToolPolicyDecision.requireConfirmation,
      );
      expect(confirmation.executionPolicyLabel, 'require_confirmation');
      expect(confirmation.isVisibleToPlanner, isTrue);
    });

    test('fromDecision centralizes policy label and visibility mapping', () {
      const definition = ToolDefinition(
        name: 'share_result',
        title: '分享结果',
      );

      final blocked = ToolAccessSnapshot.fromDecision(
        definition: definition,
        executionDecision: ToolPolicyDecision.blocked,
      );
      final confirmation = ToolAccessSnapshot.fromDecision(
        definition: definition,
        executionDecision: ToolPolicyDecision.requireConfirmation,
      );

      expect(blocked.executionPolicyLabel, 'blocked');
      expect(blocked.isVisibleToPlanner, isFalse);
      expect(confirmation.executionPolicyLabel, 'require_confirmation');
      expect(confirmation.isVisibleToPlanner, isTrue);
    });
  });
}
