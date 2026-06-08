import 'package:ai_chat/widgets/chat_blocks/artifact_preview_surface.dart';
import 'package:ai_chat/widgets/tool_renderers/tool_running_effects.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
      'mounts artifact preview without inherited widget initState error',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: ArtifactPreviewSurface(
            artifactId: 'artifact-1',
            source: '<div>Hello</div>',
            sourcePath: 'test://artifact',
          ),
        ),
      ),
    );

    await tester.pump();

    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'does not expose raw source text before preview controller is ready',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: ArtifactPreviewSurface(
            artifactId: 'artifact-1',
            source: '<div>Hello artifact</div>',
            sourcePath: 'test://artifact',
          ),
        ),
      ),
    );

    await tester.pump();

    expect(find.textContaining('Hello artifact'), findsNothing);
  });

  testWidgets(
      'waiting runtime preview uses sweep shell instead of legacy text label',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: ArtifactPreviewSurface(
            artifactId: 'artifact-1',
            source: null,
            sourcePath: 'runtime://artifact',
            isRuntimePreview: true,
          ),
        ),
      ),
    );

    await tester.pump();

    expect(
        find.byKey(const Key('artifact-preview-sweep-shell')), findsOneWidget);
    expect(find.textContaining('正在准备预览'), findsNothing);
  });

  testWidgets('waiting runtime preview uses the configured shimmer sweep',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: ArtifactPreviewSurface(
            artifactId: 'artifact-1',
            source: null,
            sourcePath: 'runtime://artifact',
            isRuntimePreview: true,
          ),
        ),
      ),
    );

    await tester.pump();

    final sweep = tester.widget<RunningSweepSurface>(
      find.byType(RunningSweepSurface).first,
    );

    expect(sweep.sweepColor, const Color(0xFFF6F6F2));
    expect(sweep.duration, const Duration(milliseconds: 2600));
    expect(sweep.sweepAngle, closeTo(-0.24, 0.0001));
    expect(sweep.travelDirection, AxisDirection.right);
    expect(sweep.activeSweepFraction, 1.0);
    expect(sweep.showBorder, isFalse);
    expect(sweep.usePreciseChildExtent, isTrue);
    expect(sweep.widthFactor, 0.56);
    expect(sweep.sweepOpacity, 1.08);
  });

  testWidgets(
      'waiting runtime preview shell uses a solid neutral surface instead of a diagonal gradient',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: ArtifactPreviewSurface(
            artifactId: 'artifact-1',
            source: null,
            sourcePath: 'runtime://artifact',
            isRuntimePreview: true,
          ),
        ),
      ),
    );

    await tester.pump();

    final previewShell = tester.widget<Container>(
      find.byKey(const Key('artifact-preview-sweep-shell')),
    );
    final decoration = previewShell.decoration as BoxDecoration;

    expect(decoration.gradient, isNull);
    expect(decoration.color, isNotNull);
    expect(decoration.color, isNot(const Color(0xFFFFFFFF)));
  });

  test('wraps fragment source into constrained host document', () {
    final document = buildArtifactPreviewDocument(
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
    expect(document, contains('window.__applyArtifactSource__'));
    expect(document, contains('window.__applyArtifactPayload__'));
    expect(document, contains('<div id="artifact-root"></div>'));
    expect(document, isNot(contains('<div>Hello</div>')));
  });

  test('keeps host shell even when source is a full html document', () {
    const source = '<html><head><title>A</title></head><body>Hi</body></html>';

    final document = buildArtifactPreviewDocument(
      hostCssVariables: const <String, String>{
        '--app-artifact-page-bg': '#faf9f5',
      },
    );

    expect(document, contains('Content-Security-Policy'));
    expect(document, contains('<base target="_self">'));
    expect(document, contains('--app-artifact-page-bg: #faf9f5;'));
    expect(document, contains('window.__applyArtifactSource__'));
    expect(document, contains('DOMParser'));
    expect(document, contains('applyManagedHead'));
    expect(document, contains('<div id="artifact-root"></div>'));
    expect(document, isNot(contains(source)));
  });

  test('injects height reporter script into preview document', () {
    final document = buildArtifactPreviewDocument();

    expect(document, contains('__artifactHeight__'));
    expect(document, contains('__artifactLockScroll__'));
    expect(document, contains('__applyArtifactPayload__'));
    expect(document, contains("overflow = 'hidden'"));
    expect(document, contains('ResizeObserver'));
    expect(document, contains('scrollHeight'));
    expect(document, contains('artifactRectHeight'));
    expect(document, contains('JSON.stringify'));
  });

  test('does not inline artifact source into the host document script context',
      () {
    const source =
        '<div>before</div><script>console.log("x")</script><div>after</div>';

    final document = buildArtifactPreviewDocument();

    expect(document, isNot(contains(source)));
    expect(document, isNot(contains('console.log("x")')));
  });

  test('runtime preview host does not emulate artifact script execution', () {
    final document = buildArtifactPreviewDocument();

    expect(document, isNot(contains('executeArtifactScripts')));
    expect(document, isNot(contains("document.createElement('script')")));
    expect(document, isNot(contains('original.replaceWith')));
  });

  test('final preview document loads the complete source with host injection',
      () {
    const source = '''
<!DOCTYPE html>
<html>
  <head><title>A</title></head>
  <body><button>Toggle</button><script>window.ready = true;</script></body>
</html>
''';

    final document = buildFinalArtifactPreviewDocument(
      source,
      hostCssVariables: const <String, String>{
        '--app-artifact-page-bg': '#faf9f5',
      },
    );

    expect(document, contains('<title>A</title>'));
    expect(document, contains('<button>Toggle</button>'));
    expect(document, contains('<script>window.ready = true;</script>'));
    expect(document, contains('Content-Security-Policy'));
    expect(document, contains('__artifactHeight__'));
    expect(document, contains('--app-artifact-page-bg: #faf9f5;'));
  });

  test('detail preview document can keep internal scrolling enabled', () {
    final document = buildArtifactPreviewDocument(
      lockScroll: false,
      hostCssVariables: const <String, String>{
        '--app-artifact-page-bg': '#faf9f5',
      },
    );

    expect(document, contains("overflow = 'auto'"));
    expect(document, contains("touchAction = 'auto'"));
    expect(document, isNot(contains("overflow = 'hidden'")));
  });

  test(
      'final takeover is still required when runtime preview already rendered identical source',
      () {
    expect(
      shouldPrepareFinalArtifactTakeover(
        source: '<div>same</div>',
        lastRenderedSource: '<div>same</div>',
        pendingFinalSource: null,
        hasPendingFinalController: false,
        isRuntimePreview: false,
        previousWasRuntimePreview: true,
      ),
      isTrue,
    );
  });

  test('final takeover is skipped when final source is already active', () {
    expect(
      shouldPrepareFinalArtifactTakeover(
        source: '<div>same</div>',
        lastRenderedSource: '<div>same</div>',
        pendingFinalSource: null,
        hasPendingFinalController: false,
        isRuntimePreview: false,
        previousWasRuntimePreview: false,
      ),
      isFalse,
    );
  });

  test('clamps reported preview height into three-screen bounds', () {
    expect(clampArtifactPreviewHeight(80, viewportHeight: 800), 180);
    expect(clampArtifactPreviewHeight(320, viewportHeight: 800), 320);
    expect(clampArtifactPreviewHeight(2000, viewportHeight: 800), 2000);
    expect(clampArtifactPreviewHeight(5000, viewportHeight: 800), 2400);
  });

  test(
      'prefers artifact rect height when root scroll height is transiently stretched',
      () {
    final resolved = resolveArtifactMeasuredHeight(
      reportedHeight: 1338,
      artifactRectHeight: 667.1049,
      bodyScrollHeight: 667,
      bodyOffsetHeight: 667,
      rootScrollHeight: 1338,
      rootOffsetHeight: 667,
    );

    expect(resolved, isNotNull);
    expect(resolved!.height, 668);
    expect(resolved.basis, ArtifactMeasuredHeightBasis.artifactRect);
  });

  test('falls back to body height when artifact rect height is missing', () {
    final resolved = resolveArtifactMeasuredHeight(
      reportedHeight: null,
      artifactRectHeight: 0,
      bodyScrollHeight: 637,
      bodyOffsetHeight: 637,
      rootScrollHeight: 903,
      rootOffsetHeight: 637,
    );

    expect(resolved, isNotNull);
    expect(resolved!.height, 637);
    expect(resolved.basis, ArtifactMeasuredHeightBasis.body);
  });

  test('derives host viewport metrics from measured and clamped heights', () {
    final metrics = resolveArtifactHostViewportMetrics(
      configuredPreviewHeight: 263,
      hostRenderHeight: 320,
      measuredHeight: 114,
      clampedHeight: 180,
    );

    expect(metrics, isNotNull);
    expect(metrics!.renderHeight, 320);
    expect(metrics.configuredPreviewHeight, 263);
    expect(metrics.overshootPx, 57);
    expect(metrics.gapFromMeasuredHeightPx, 206);
    expect(metrics.gapFromClampedHeightPx, 140);
  });

  test('classifies host viewport probe status from render availability', () {
    expect(
      resolveArtifactHostViewportProbeStatus(
        hasContext: false,
        hasRenderObject: false,
        isRenderBox: false,
        hasSize: false,
        renderHeight: null,
      ),
      ArtifactHostViewportProbeStatus.noContext,
    );
    expect(
      resolveArtifactHostViewportProbeStatus(
        hasContext: true,
        hasRenderObject: true,
        isRenderBox: true,
        hasSize: false,
        renderHeight: null,
      ),
      ArtifactHostViewportProbeStatus.noSize,
    );
    expect(
      resolveArtifactHostViewportProbeStatus(
        hasContext: true,
        hasRenderObject: true,
        isRenderBox: true,
        hasSize: true,
        renderHeight: 320,
      ),
      ArtifactHostViewportProbeStatus.ok,
    );
  });

  test('exposes a stable truncation hint for overlong artifact previews', () {
    expect(artifactPreviewTruncationMessage, contains('详情页'));
    expect(artifactPreviewTruncationMessage, contains('完整内容'));
  });

  test(
      'artifact inline preview keeps details page wording as the overflow path',
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
