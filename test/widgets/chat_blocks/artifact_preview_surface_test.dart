import 'package:ai_chat/widgets/chat_blocks/artifact_preview_surface.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('wraps fragment source into constrained html document', () {
    final document = buildArtifactPreviewDocument('<div>Hello</div>');

    expect(document, contains('<!DOCTYPE html>'));
    expect(document, contains('Content-Security-Policy'));
    expect(document, contains("connect-src 'none'"));
    expect(document, contains('<div>Hello</div>'));
  });

  test('injects constrained head content into existing html', () {
    const source = '<html><head><title>A</title></head><body>Hi</body></html>';

    final document = buildArtifactPreviewDocument(source);

    expect(document, contains('<title>A</title>'));
    expect(document, contains('Content-Security-Policy'));
    expect(document, contains('<base target="_self">'));
  });

  test('injects height reporter script into preview document', () {
    final document = buildArtifactPreviewDocument('<div style="height: 480px"></div>');

    expect(document, contains('__artifactHeight__'));
    expect(document, contains('ResizeObserver'));
    expect(document, contains('scrollHeight'));
  });

  test('clamps reported preview height into supported bounds', () {
    expect(clampArtifactPreviewHeight(80), 180);
    expect(clampArtifactPreviewHeight(320), 320);
    expect(clampArtifactPreviewHeight(2000), 720);
  });

  test('registers vertical drag recognizer for nested artifact preview scroll', () {
    expect(
      artifactPreviewGestureRecognizers.any(
        (factory) => factory.type == VerticalDragGestureRecognizer,
      ),
      isTrue,
    );
  });
}
