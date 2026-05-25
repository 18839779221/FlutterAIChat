import 'package:ai_chat/widgets/chat_blocks/artifact_preview_surface.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('mounts artifact preview without inherited widget initState error',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: ArtifactPreviewSurface(
            source: '<div>Hello</div>',
            isStale: false,
            sourcePath: 'test://artifact',
          ),
        ),
      ),
    );

    await tester.pump();

    expect(tester.takeException(), isNull);
  });

  test('wraps fragment source into constrained html document', () {
    final document = buildArtifactPreviewDocument(
      '<div>Hello</div>',
      hostCssVariables: const <String, String>{
        '--app-artifact-page-bg': '#faf9f5',
        '--app-artifact-text-primary': '#1f1f1e',
      },
    );

    expect(document, contains('<!DOCTYPE html>'));
    expect(document, contains('Content-Security-Policy'));
    expect(document, contains("connect-src 'none'"));
    expect(document, contains(':root'));
    expect(document, contains('--app-artifact-page-bg: #faf9f5;'));
    expect(document, contains('#artifact-root'));
    expect(document, contains('<div>Hello</div>'));
  });

  test('injects constrained head content into existing html', () {
    const source = '<html><head><title>A</title></head><body>Hi</body></html>';

    final document = buildArtifactPreviewDocument(
      source,
      hostCssVariables: const <String, String>{
        '--app-artifact-page-bg': '#faf9f5',
      },
    );

    expect(document, contains('<title>A</title>'));
    expect(document, contains('Content-Security-Policy'));
    expect(document, contains('<base target="_self">'));
    expect(document, contains('--app-artifact-page-bg: #faf9f5;'));
  });

  test('injects height reporter script into preview document', () {
    final document = buildArtifactPreviewDocument('<div style="height: 480px"></div>');

    expect(document, contains('__artifactHeight__'));
    expect(document, contains('__artifactLockScroll__'));
    expect(document, contains("overflow = 'hidden'"));
    expect(document, contains('ResizeObserver'));
    expect(document, contains('scrollHeight'));
  });

  test('detail preview document can keep internal scrolling enabled', () {
    final document = buildArtifactPreviewDocument(
      '<div style="height: 480px"></div>',
      lockScroll: false,
      hostCssVariables: const <String, String>{
        '--app-artifact-page-bg': '#faf9f5',
      },
    );

    expect(document, contains("overflow = 'auto'"));
    expect(document, contains("touchAction = 'auto'"));
    expect(document, isNot(contains("overflow = 'hidden'")));
  });

  test('clamps reported preview height into three-screen bounds', () {
    expect(clampArtifactPreviewHeight(80, viewportHeight: 800), 180);
    expect(clampArtifactPreviewHeight(320, viewportHeight: 800), 320);
    expect(clampArtifactPreviewHeight(2000, viewportHeight: 800), 2000);
    expect(clampArtifactPreviewHeight(5000, viewportHeight: 800), 2400);
  });

  test('exposes a stable truncation hint for overlong artifact previews', () {
    expect(artifactPreviewTruncationMessage, contains('详情页'));
    expect(artifactPreviewTruncationMessage, contains('完整内容'));
  });

  test('artifact inline preview keeps details page wording as the overflow path',
      () {
    expect(artifactPreviewTruncationMessage, contains('详情页'));
    expect(artifactPreviewTruncationMessage, isNot(contains('展开更多')));
    expect(artifactPreviewTruncationMessage, isNot(contains('收起')));
  });

  test('builds host preview styles with root variables and native wrapper', () {
    final styles = buildArtifactPreviewHostStyles(const <String, String>{
      '--app-artifact-page-bg': '#faf9f5',
      '--app-artifact-chart-1': '#c96442',
    });

    expect(styles, contains(':root'));
    expect(styles, contains('--app-artifact-page-bg: #faf9f5;'));
    expect(styles, contains('--app-artifact-chart-1: #c96442;'));
    expect(styles, contains('html, body'));
    expect(styles, contains('#artifact-root'));
    expect(styles, isNot(contains('background: transparent')));
  });
}
