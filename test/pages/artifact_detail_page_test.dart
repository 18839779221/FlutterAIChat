import 'package:ai_chat/models/artifact/artifact_turn_projection.dart';
import 'package:ai_chat/models/artifact/artifact_type.dart';
import 'package:ai_chat/pages/artifact_detail_page.dart';
import 'package:ai_chat/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  ArtifactTurnProjection buildProjection({String? source}) {
    return ArtifactTurnProjection(
      artifactId: 'artifact-1',
      turnId: 'turn-1',
      title: '销售图表',
      type: ArtifactType.html,
      sourcePath: '/artifacts/group/sales.html',
      source: source,
      createdAt: DateTime(2026, 4, 30, 10),
      updatedAt: DateTime(2026, 4, 30, 10, 1),
    );
  }

  testWidgets('switches between preview and source modes', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: ArtifactDetailPage(
          projection: buildProjection(source: '<div>Sales</div>'),
        ),
      ),
    );

    expect(find.text('预览'), findsOneWidget);
    expect(find.text('源码'), findsOneWidget);
    expect(find.text('<div>Sales</div>'), findsNothing);

    await tester.tap(find.text('源码'));
    await tester.pumpAndSettle();

    expect(find.text('<div>Sales</div>'), findsOneWidget);
    expect(find.byTooltip('复制源码'), findsOneWidget);
  });

  testWidgets('shows empty state when source mode has no content', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: ArtifactDetailPage(
          projection: buildProjection(),
        ),
      ),
    );

    await tester.tap(find.text('源码'));
    await tester.pumpAndSettle();

    expect(find.text('当前没有可展示的 artifact 源码。'), findsOneWidget);
  });
}
