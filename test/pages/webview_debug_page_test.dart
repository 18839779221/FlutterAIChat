import 'dart:io';

import 'package:ai_chat/pages/webview_debug_page.dart';
import 'package:ai_chat/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'discoverWebviewDebugArtifactFiles finds workspace-based agent artifacts',
    () async {
      final tempRoot = await Directory.systemTemp.createTemp(
        'webview_debug_page_test',
      );
      addTearDown(() async {
        if (await tempRoot.exists()) {
          await tempRoot.delete(recursive: true);
        }
      });

      final artifactRoot = Directory(
        '${tempRoot.path}/agent/workspaces/.default/artifacts',
      );
      await artifactRoot.create(recursive: true);
      final artifactFile = File('${artifactRoot.path}/sample-artifact.html');
      await artifactFile.writeAsString('<div>Sample artifact</div>');

      final files = await discoverWebviewDebugArtifactFiles(
        Directory('${tempRoot.path}/agent'),
      );

      expect(files.map((file) => file.name), contains('sample-artifact.html'));
    },
  );

  test('artifact replay truncates raw selected html by target length', () {
    const artifactContent = '<html><body>artifact</body></html>';

    final selected = resolveWebviewDebugReplaySource(
      artifactContent: artifactContent,
      targetLength: 12,
    );

    expect(selected, artifactContent.substring(0, 12));
  });

  test('artifact replay returns full html when target length exceeds content',
      () {
    const artifactContent = '<html><body>artifact</body></html>';

    final selected = resolveWebviewDebugReplaySource(
      artifactContent: artifactContent,
      targetLength: 9999,
    );

    expect(selected, artifactContent);
  });

  test('resolveWebviewDebugReplayTargetLength clamps into supported range', () {
    expect(resolveWebviewDebugReplayTargetLength(-50, 1200), 0);
    expect(resolveWebviewDebugReplayTargetLength(1200, 1200), 1200);
    expect(resolveWebviewDebugReplayTargetLength(50000, 1200), 1200);
  });

  test('resolveStreamingInterval divides total playback duration by chunk count',
      () {
    expect(
      resolveWebviewDebugStreamingInterval(
        totalPlaybackDuration: const Duration(seconds: 24),
        chunkCount: 8,
      ),
      const Duration(seconds: 3),
    );
    expect(
      resolveWebviewDebugStreamingInterval(
        totalPlaybackDuration: const Duration(seconds: 5),
        chunkCount: 8,
      ),
      const Duration(milliseconds: 625),
    );
  });

  testWidgets('fixed clock banner stays visible while the page scrolls',
      (tester) async {
    final tempRoot = await Directory.systemTemp.createTemp(
      'webview_debug_page_clock_test',
    );
    addTearDown(() async {
      await tester.binding.setSurfaceSize(null);
      if (await tempRoot.exists()) {
        await tempRoot.delete(recursive: true);
      }
    });

    final artifactRoot = Directory(
      '${tempRoot.path}/agent/workspaces/.default/artifacts',
    );
    await artifactRoot.create(recursive: true);
    await File('${artifactRoot.path}/sample-artifact.html').writeAsString(
      '<div>${List.filled(400, 'artifact body').join(' ')}</div>',
    );

    await tester.binding.setSurfaceSize(const Size(390, 500));

    final fixedTime = DateTime(2026, 6, 16, 16, 13, 24, 421);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: WebviewDebugPage(
          appSupportDirectoryProvider: () async => tempRoot,
          nowProvider: () => fixedTime,
          enableLiveClock: false,
        ),
      ),
    );

    await tester.pump();
    await tester.pump();

    final clockBanner = find.byKey(const Key('webview-debug-clock-banner'));
    expect(clockBanner, findsOneWidget);
    expect(find.text('16:13:24.421'), findsOneWidget);

    final initialTop = tester.getTopLeft(clockBanner).dy;

    await tester.drag(find.byType(ListView), const Offset(0, -280));
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pump(const Duration(milliseconds: 200));

    expect(clockBanner, findsOneWidget);
    expect(tester.getTopLeft(clockBanner).dy, initialTop);
  });
}
