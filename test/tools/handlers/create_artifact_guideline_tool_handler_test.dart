import 'package:ai_chat/models/tool/tool_result.dart';
import 'package:ai_chat/theme/app_theme_spec.dart';
import 'package:ai_chat/tools/core/tool_execution_context.dart';
import 'package:ai_chat/tools/handlers/create_artifact_guideline_tool_handler.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('CreateArtifactGuidelineToolHandler', () {
    test('guideline tool description requires first-call pairing', () {
      final handler = CreateArtifactGuidelineToolHandler(
        activeThemeSpecProvider: () => AppThemeSpec.claude(),
      );

      expect(handler.definition.name, 'create_artifact__guideline');
      expect(handler.definition.descriptionForModel, contains('IMPORTANT:'));
      expect(
        handler.definition.descriptionForModel,
        contains('before the first `create_artifact` call'),
      );
      expect(
        handler.definition.descriptionForModel,
        contains('Do not skip this step for the first version'),
      );
    });

    test('returns host markup contract and rendering guidance', () async {
      final handler = CreateArtifactGuidelineToolHandler(
        activeThemeSpecProvider: () => AppThemeSpec.claude(),
      );

      final result = await handler.execute(
        ToolExecutionContext(
          groupId: 1,
          toolName: 'create_artifact__guideline',
          arguments: const <String, dynamic>{},
          history: const [],
          now: DateTime(2026, 5, 26, 12),
        ),
      );

      expect(result.status, ToolExecutionStatus.success);
      expect(result.data['usage'], isNotEmpty);
      expect(result.data['host_markup_contract'], contains(':root'));
      expect(result.data['host_markup_contract'], contains('#artifact-root'));
      expect(result.data['layout_constraints'], isA<List<dynamic>>());
      expect(result.data['rendering_rules'], isA<List<dynamic>>());
    });
  });
}
