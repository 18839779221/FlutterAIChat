import 'dart:async';

import 'package:ai_chat/widgets/chat_blocks/artifact_preview_surface.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ArtifactPreviewSurface debouncing', () {
    testWidgets('cancels debounce timer when widget is disposed',
        (WidgetTester tester) async {
      // Build widget
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: ArtifactPreviewSurface(
              source: '<div>Initial</div>',
              sourcePath: 'test://artifact',
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Update source to trigger debouncing
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: ArtifactPreviewSurface(
              source: '<div>Updated</div>',
              sourcePath: 'test://artifact',
            ),
          ),
        ),
      );

      await tester.pump();

      // Dispose widget before debounce completes
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SizedBox.shrink(),
          ),
        ),
      );

      // Wait for debounce delay
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();

      // Should not crash (timer was properly cancelled)
      expect(tester.takeException(), isNull);
    });

    testWidgets('rebuilds to empty state when source becomes unavailable',
        (WidgetTester tester) async {
      // Build initial widget
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: ArtifactPreviewSurface(
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
              source: null,
              sourcePath: 'test://artifact',
            ),
          ),
        ),
      );

      await tester.pump();

      expect(find.textContaining('Preview unavailable'), findsOneWidget);
    });

    test('buildArtifactPreviewDocument still works correctly', () {
      final document = buildArtifactPreviewDocument('<div>Test</div>');

      expect(document, contains('<!DOCTYPE html>'));
      expect(document, contains('<div>Test</div>'));
      expect(document, contains('Content-Security-Policy'));
    });
  });

  group('Debouncing logic unit tests', () {
    test('Timer cancellation prevents callback execution', () async {
      var callbackExecuted = false;
      final timer = Timer(const Duration(milliseconds: 100), () {
        callbackExecuted = true;
      });

      // Cancel immediately
      timer.cancel();

      // Wait longer than the timer duration
      await Future.delayed(const Duration(milliseconds: 200));

      expect(callbackExecuted, isFalse);
    });

    test('Timer executes callback after delay', () async {
      var callbackExecuted = false;
      Timer(const Duration(milliseconds: 50), () {
        callbackExecuted = true;
      });

      // Wait for timer to fire
      await Future.delayed(const Duration(milliseconds: 100));

      expect(callbackExecuted, isTrue);
    });

    test('Multiple timer cancellations are safe', () {
      final timer = Timer(const Duration(milliseconds: 100), () {});

      // Multiple cancellations should not throw
      expect(() {
        timer.cancel();
        timer.cancel();
        timer.cancel();
      }, returnsNormally);
    });
  });
}
