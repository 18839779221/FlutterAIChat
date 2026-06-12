import 'package:ai_chat/widgets/chat_blocks/artifact_preview_surface.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:webview_flutter_platform_interface/webview_flutter_platform_interface.dart';

import '../../helpers/fake_webview_platform.dart';

void main() {
  late FakeWebViewPlatform platform;

  setUp(() {
    platform = FakeWebViewPlatform();
    WebViewPlatform.instance = platform;
  });

  tearDown(() {
    artifactControllerReadyTimeout = const Duration(seconds: 8);
    artifactTakeoverFallbackDelay = const Duration(seconds: 10);
  });

  group('shouldSurfaceArtifactWebResourceError', () {
    test('surfaces main-frame errors', () {
      expect(
        shouldSurfaceArtifactWebResourceError(isForMainFrame: true),
        isTrue,
      );
    });

    test('treats unknown frame as main-frame', () {
      expect(
        shouldSurfaceArtifactWebResourceError(isForMainFrame: null),
        isTrue,
      );
    });

    test('ignores sub-resource errors', () {
      expect(
        shouldSurfaceArtifactWebResourceError(isForMainFrame: false),
        isFalse,
      );
    });
  });

  group('isArtifactApplyResultSuccess', () {
    test('accepts raw and JSON-quoted success', () {
      expect(isArtifactApplyResultSuccess('success'), isTrue);
      expect(isArtifactApplyResultSuccess('"success"'), isTrue);
    });

    test('rejects failure markers and null', () {
      expect(isArtifactApplyResultSuccess('no-root'), isFalse);
      expect(isArtifactApplyResultSuccess('"no-apply-function"'), isFalse);
      expect(isArtifactApplyResultSuccess('error: boom'), isFalse);
      expect(isArtifactApplyResultSuccess(null), isFalse);
    });
  });

  Widget buildSurface({
    required String? source,
    bool isRuntimePreview = false,
  }) {
    return MaterialApp(
      home: Scaffold(
        body: ArtifactPreviewSurface(
          artifactId: 'artifact-1',
          source: source,
          sourcePath: 'inline://artifact-1',
          isRuntimePreview: isRuntimePreview,
          turnId: 'turn-1',
          providerCallId: 'call-1',
        ),
      ),
    );
  }

  testWidgets('sub-resource error keeps the preview alive',
      (WidgetTester tester) async {
    await tester.pumpWidget(buildSurface(source: '<div>doc</div>'));
    await tester.pump();

    expect(platform.controllers, hasLength(1));
    platform.controllers.first.fireWebResourceError(
      const WebResourceError(
        errorCode: -2,
        description: 'image failed to load',
        isForMainFrame: false,
      ),
    );
    await tester.pump();

    expect(find.textContaining('Preview unavailable'), findsNothing);

    platform.controllers.first.fireWebResourceError(
      const WebResourceError(
        errorCode: -2,
        description: 'document failed to load',
        isForMainFrame: true,
      ),
    );
    await tester.pump();

    expect(find.textContaining('Preview unavailable'), findsOneWidget);
    expect(find.textContaining('document failed to load'), findsOneWidget);
  });

  testWidgets('failed runtime apply is retried instead of book-kept',
      (WidgetTester tester) async {
    var jsCalls = 0;
    platform.javaScriptResultHandler = (_) {
      jsCalls += 1;
      return jsCalls == 1 ? '"no-root"' : '"success"';
    };

    await tester.pumpWidget(
      buildSurface(source: '<div>stream</div>', isRuntimePreview: true),
    );
    await tester.pump();

    expect(
      platform.controllers.first.runJavaScriptReturningResultCalls,
      hasLength(1),
    );

    // The failure schedules a retry through the 1s streaming loop. If the
    // failed apply had been book-kept as rendered, this tick would skip the
    // source as "unchanged" and no second JS call would happen.
    await tester.pump(const Duration(seconds: 1));
    await tester.pump();

    expect(
      platform.controllers.first.runJavaScriptReturningResultCalls,
      hasLength(2),
    );

    // Loop must stop once the retry succeeds (no pending timers at teardown).
    await tester.pump(const Duration(seconds: 2));
    expect(
      platform.controllers.first.runJavaScriptReturningResultCalls,
      hasLength(2),
    );
  });

  testWidgets('controller-ready timeout keeps the streaming pipeline alive',
      (WidgetTester tester) async {
    artifactControllerReadyTimeout = const Duration(milliseconds: 200);
    platform.autoCompletePageLoads = false;

    await tester.pumpWidget(
      buildSurface(source: '<div>first</div>', isRuntimePreview: true),
    );
    await tester.pump();

    // onPageFinished never fires; the apply must unblock via timeout.
    expect(
      platform.controllers.first.runJavaScriptReturningResultCalls,
      isEmpty,
    );
    await tester.pump(const Duration(milliseconds: 250));
    expect(
      platform.controllers.first.runJavaScriptReturningResultCalls,
      hasLength(1),
    );

    // A later streaming update must still flow (in-flight flag not stuck).
    await tester.pumpWidget(
      buildSurface(source: '<div>second</div>', isRuntimePreview: true),
    );
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(milliseconds: 250));
    expect(
      platform.controllers.first.runJavaScriptReturningResultCalls,
      hasLength(2),
    );
  });

  testWidgets('stuck final takeover falls back to the active controller',
      (WidgetTester tester) async {
    artifactTakeoverFallbackDelay = const Duration(milliseconds: 250);

    await tester.pumpWidget(
      buildSurface(source: '<div>stream</div>', isRuntimePreview: true),
    );
    await tester.pump();
    final runtimeController = platform.controllers.first;
    expect(runtimeController.loadedHtmlStrings, hasLength(1));

    // The pending final controller loads but never reports onPageFinished,
    // so promotion never happens.
    platform.autoCompletePageLoads = false;
    const finalSource = '<html><body><div>final-doc</div></body></html>';
    await tester.pumpWidget(buildSurface(source: finalSource));
    await tester.pump();

    expect(platform.controllers, hasLength(2));
    expect(runtimeController.loadedHtmlStrings, hasLength(1));

    await tester.pump(const Duration(milliseconds: 300));

    // Fallback reloads the final document on the active runtime controller.
    expect(runtimeController.loadedHtmlStrings, hasLength(2));
    expect(runtimeController.loadedHtmlStrings.last, contains('final-doc'));

    // Completing that load surfaces the content (sweep shell goes away).
    runtimeController.firePageFinished();
    await tester.pump();
    expect(
      find.byKey(const Key('artifact-preview-sweep-shell')),
      findsNothing,
    );
  });
}
