import 'package:ai_chat/pages/component_motion_debug_page.dart';
import 'package:ai_chat/theme/app_theme.dart';
import 'package:ai_chat/widgets/chat_blocks/artifact_preview_surface.dart';
import 'package:ai_chat/widgets/chat_blocks/tool_workflow_card.dart';
import 'package:ai_chat/widgets/chat_blocks/unified_turn_status_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('component motion debug page shows the initial running previews',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: const ComponentMotionDebugPage(),
      ),
    );

    await tester.pump();

    expect(find.text('组件与动效调试'), findsOneWidget);
    expect(find.text('模型回复状态提示'), findsOneWidget);
    expect(find.text('Tool Workflow 运行卡片'), findsOneWidget);
    expect(find.text('Artifact Preview'), findsOneWidget);
    expect(find.byType(UnifiedTurnStatusBar), findsNWidgets(2));
    expect(find.byType(ToolWorkflowCard), findsOneWidget);
    expect(find.byType(ArtifactPreviewSurface), findsOneWidget);
    expect(
      find.byKey(const Key('artifact-preview-sweep-shell')),
      findsOneWidget,
    );
    expect(find.byType(Slider), findsOneWidget);
    expect(find.text('文本刀光时长 2500ms'), findsOneWidget);
  });

  testWidgets('component motion debug page can switch status text length',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: const ComponentMotionDebugPage(),
      ),
    );

    await tester.pump();

    expect(find.text('正在规划下一步'), findsWidgets);

    await tester.tap(find.widgetWithText(ChoiceChip, '长文案'));
    await tester.pump();

    expect(find.textContaining('正在分析工具返回结果并组织最终回复'), findsWidgets);
  });

  testWidgets('component motion debug page can replay artifact runtime loading',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: const ComponentMotionDebugPage(),
      ),
    );

    await tester.pump();

    await tester.ensureVisible(
      find.byKey(const ValueKey('component-motion-artifact-replay')),
    );
    await tester.pump();
    await tester
        .tap(find.byKey(const ValueKey('component-motion-artifact-replay')));
    await tester.pump();

    expect(find.byType(ArtifactPreviewSurface), findsOneWidget);
  });

  testWidgets(
      'component motion debug page exposes a draggable status speed slider',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: const ComponentMotionDebugPage(),
      ),
    );

    await tester.pump();

    final sliderFinder = find.byType(Slider);
    expect(sliderFinder, findsOneWidget);

    final slider = tester.widget<Slider>(sliderFinder);
    expect(slider.value, 2500);
    expect(slider.min, 1800);
    expect(slider.max, 3200);

    await tester.drag(sliderFinder, const Offset(120, 0));
    await tester.pump();

    expect(find.textContaining('文本刀光时长'), findsOneWidget);
  });
}
