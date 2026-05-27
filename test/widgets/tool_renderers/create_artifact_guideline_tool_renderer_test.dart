import 'package:ai_chat/models/chat/tool_phase_visibility.dart';
import 'package:ai_chat/models/chat/tool_presentation_event.dart';
import 'package:ai_chat/models/tool/tool_result.dart';
import 'package:ai_chat/theme/app_theme.dart';
import 'package:ai_chat/widgets/tool_renderers/compact_tool_row_renderer.dart';
import 'package:ai_chat/widgets/tool_renderers/create_artifact_guideline_tool_renderer.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('CreateArtifactGuidelineToolUiRenderer', () {
    test('hides non-result phases and keeps result phase visible', () {
      const renderer = CreateArtifactGuidelineToolUiRenderer();

      expect(
        renderer.visibilityForPhase(
          'create_artifact__guideline',
          ToolPresentationEventPhase.proposed,
        ),
        ToolPhaseVisibility.hidden,
      );
      expect(
        renderer.visibilityForPhase(
          'create_artifact__guideline',
          ToolPresentationEventPhase.running,
        ),
        ToolPhaseVisibility.hidden,
      );
      expect(
        renderer.visibilityForPhase(
          'create_artifact__guideline',
          ToolPresentationEventPhase.result,
        ),
        ToolPhaseVisibility.visible,
      );
    });

    testWidgets('renders a compact guideline hint for successful result',
        (tester) async {
      const renderer = CreateArtifactGuidelineToolUiRenderer();

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: Scaffold(
            body: Builder(
              builder: (context) =>
                  renderer.buildResult(
                    context,
                    result: const ToolResult(
                      toolName: 'create_artifact__guideline',
                      status: ToolExecutionStatus.success,
                      summary: '已返回 artifact guideline',
                    ),
                    sourceMessage: null,
                  ) ??
                  const SizedBox.shrink(),
            ),
          ),
        ),
      );

      expect(find.byType(CompactToolRow), findsOneWidget);
      expect(find.text('已加载可视化规范'), findsOneWidget);
      expect(find.text('完成'), findsOneWidget);
    });
  });
}
