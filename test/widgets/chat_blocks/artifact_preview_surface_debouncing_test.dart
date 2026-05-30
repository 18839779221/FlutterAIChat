import 'package:ai_chat/widgets/chat_blocks/artifact_preview_surface.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ArtifactPreviewSurface streaming updates', () {
    testWidgets('cancels scheduled update loop when widget is disposed',
        (WidgetTester tester) async {
      // Build widget
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: ArtifactPreviewSurface(
              artifactId: 'artifact-1',
              source: '<div>Initial</div>',
              sourcePath: 'test://artifact',
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Update source to trigger scheduled updates.
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: ArtifactPreviewSurface(
              artifactId: 'artifact-1',
              source: '<div>Updated</div>',
              sourcePath: 'test://artifact',
            ),
          ),
        ),
      );

      await tester.pump();

      // Dispose widget before the scheduled update runs.
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SizedBox.shrink(),
          ),
        ),
      );

      // Wait longer than the scheduled update interval.
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();

      // Should not crash.
      expect(tester.takeException(), isNull);
    });

    testWidgets('rebuilds to unavailable state when source becomes unavailable',
        (WidgetTester tester) async {
      // Build initial widget
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: ArtifactPreviewSurface(
              artifactId: 'artifact-1',
              source: '<div>Initial</div>',
              sourcePath: 'test://artifact',
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Clear source
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: ArtifactPreviewSurface(
              artifactId: 'artifact-1',
              source: null,
              sourcePath: 'test://artifact',
            ),
          ),
        ),
      );

      await tester.pump();

      expect(find.textContaining('Preview unavailable'), findsOneWidget);
    });

    testWidgets(
        'keeps runtime preview in a waiting state before source arrives',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: ArtifactPreviewSurface(
              artifactId: 'artifact-1',
              source: null,
              sourcePath: 'runtime://create_artifact/tool_1',
              isRuntimePreview: true,
            ),
          ),
        ),
      );

      await tester.pump();

      expect(find.textContaining('Preview unavailable'), findsNothing);
      expect(find.textContaining('正在准备预览'), findsOneWidget);
    });

    test('buildArtifactPreviewDocument still works correctly', () {
      final document = buildArtifactPreviewDocument();

      expect(document, contains('<!DOCTYPE html>'));
      expect(document, contains('window.__applyArtifactSource__'));
      expect(document, contains('window.__applyArtifactPayload__'));
      expect(document, contains('Content-Security-Policy'));
    });
  });
}
