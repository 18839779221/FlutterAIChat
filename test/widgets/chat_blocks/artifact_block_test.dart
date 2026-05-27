import 'package:ai_chat/models/artifact/artifact_turn_projection.dart';
import 'package:ai_chat/models/artifact/artifact_type.dart';
import 'package:ai_chat/theme/app_theme.dart';
import 'package:ai_chat/widgets/chat_blocks/artifact_block.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('renders inline artifact preview without card chrome', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: ArtifactBlock(
            projection: ArtifactTurnProjection(
              artifactId: 'portfolio-pie',
              turnId: '7_1',
              title: '投资组合饼图',
              type: ArtifactType.html,
              sourcePath: 'artifacts/7/portfolio-pie.html',
              source: '<div>artifact</div>',
              createdAt: DateTime(2026, 4, 30, 10),
              updatedAt: DateTime(2026, 4, 30, 10),
            ),
          ),
        ),
      ),
    );

    expect(find.byType(ArtifactBlock), findsOneWidget);
    expect(find.byType(ArtifactBlock), findsOneWidget);
  });
}
