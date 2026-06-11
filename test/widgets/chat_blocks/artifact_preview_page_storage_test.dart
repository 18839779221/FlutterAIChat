import 'package:ai_chat/widgets/chat_blocks/artifact_preview_page_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('resolves default artifact preview visual state without cached snapshot',
      () {
    final state = resolveArtifactPreviewVisualState(
      cachedSnapshot: null,
      defaultPreviewHeight: 260,
    );

    expect(state.previewHeight, 260);
    expect(state.isPreviewTruncated, isFalse);
  });

  test('restores cached height without reviving legacy truncation state', () {
    final state = resolveArtifactPreviewVisualState(
      cachedSnapshot: const ArtifactPreviewPageStorageSnapshot(
        previewHeight: 480,
        isPreviewTruncated: true,
      ),
      defaultPreviewHeight: 260,
    );

    expect(state.previewHeight, 480);
    expect(state.isPreviewTruncated, isFalse);
  });

  testWidgets('restores artifact preview snapshot across subtree remounts',
      (tester) async {
    final bucket = PageStorageBucket();
    late BuildContext storageContext;

    await tester.pumpWidget(
      MaterialApp(
        home: PageStorage(
          bucket: bucket,
          child: StatefulBuilder(
            builder: (context, setState) {
              storageContext = context;
              return Column(
                children: [
                  const SizedBox(),
                  TextButton(
                    onPressed: () => setState(() {}),
                    child: const Text('refresh'),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );

    const snapshot = ArtifactPreviewPageStorageSnapshot(
      previewHeight: 512,
      isPreviewTruncated: true,
    );

    writeArtifactPreviewPageStorageSnapshot(
      context: storageContext,
      artifactId: 'artifact-1',
      snapshot: snapshot,
    );

    await tester.tap(find.text('refresh'));
    await tester.pump();

    final restored = readArtifactPreviewPageStorageSnapshot(
      context: storageContext,
      artifactId: 'artifact-1',
    );

    expect(restored, isNotNull);
    expect(restored!.previewHeight, 512);
    expect(restored.isPreviewTruncated, isTrue);
  });

  testWidgets('returns null when no artifact preview snapshot was stored',
      (tester) async {
    final bucket = PageStorageBucket();
    late BuildContext storageContext;

    await tester.pumpWidget(
      MaterialApp(
        home: PageStorage(
          bucket: bucket,
          child: Builder(
            builder: (context) {
              storageContext = context;
              return const SizedBox();
            },
          ),
        ),
      ),
    );

    final restored = readArtifactPreviewPageStorageSnapshot(
      context: storageContext,
      artifactId: 'missing-artifact',
    );

    expect(restored, isNull);
  });
}
