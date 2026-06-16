import 'package:ai_chat/services/artifact/artifact_render_session_recorder.dart';
import 'package:ai_chat/utils/logger.dart';
import 'package:ai_chat/widgets/chat_blocks/artifact_preview_surface.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('emits surface lifecycle events on init update and dispose',
      (WidgetTester tester) async {
    final recorder = FakeArtifactRenderSessionRecorder();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ArtifactPreviewSurface(
            artifactId: 'artifact-1',
            source: null,
            sourcePath: 'runtime://artifact',
            isRuntimePreview: true,
            sessionRecorder: recorder,
            turnId: 'turn-1',
            providerCallId: 'call-1',
          ),
        ),
      ),
    );

    await tester.pump();

    // Lease coordination emits its own lifecycle events; this test only
    // asserts the core init/update/dispose sequence.
    List<SurfaceLifecycleEvent> coreEvents() => recorder.surfaceLifecycleEvents
        .where((event) => !event.event.startsWith('lease_'))
        .toList(growable: false);

    expect(coreEvents(), hasLength(1));
    expect(coreEvents().first.event, 'initState');
    expect(
      coreEvents().first.data,
      containsPair('sourceLength', 0),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ArtifactPreviewSurface(
            artifactId: 'artifact-1',
            source: '<div>Updated</div>',
            sourcePath: 'runtime://artifact',
            isRuntimePreview: true,
            sessionRecorder: recorder,
            turnId: 'turn-1',
            providerCallId: 'call-1',
          ),
        ),
      ),
    );

    await tester.pump();

    expect(coreEvents(), hasLength(2));
    expect(coreEvents()[1].event, 'didUpdateWidget');
    expect(
      coreEvents()[1].data,
      containsPair('oldSourceLength', 0),
    );
    expect(
      coreEvents()[1].data,
      containsPair('newSourceLength', '<div>Updated</div>'.length),
    );

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SizedBox.shrink(),
        ),
      ),
    );

    await tester.pump();

    expect(coreEvents(), hasLength(3));
    expect(coreEvents().last.event, 'dispose');
    expect(
      coreEvents().last.data,
      containsPair('hasRenderedVisibleContent', false),
    );
  });

  testWidgets(
      'rebuilds runtime host when switching from final preview back to runtime preview',
      (WidgetTester tester) async {
    final recorder = FakeArtifactRenderSessionRecorder();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ArtifactPreviewSurface(
            artifactId: 'artifact-1',
            source: '<div>Final</div>',
            sourcePath: 'test://artifact',
            isRuntimePreview: false,
            sessionRecorder: recorder,
            turnId: 'turn-1',
            providerCallId: 'call-1',
          ),
        ),
      ),
    );

    await tester.pump();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ArtifactPreviewSurface(
            artifactId: 'artifact-1',
            source: '<div>Runtime restart</div>',
            sourcePath: 'runtime://artifact',
            isRuntimePreview: true,
            sessionRecorder: recorder,
            turnId: 'turn-1',
            providerCallId: 'call-1',
          ),
        ),
      ),
    );

    await tester.pump();

    expect(
      recorder.surfaceLifecycleEvents
          .where((event) => event.event == 'runtime_restart_host_rebuild'),
      hasLength(1),
    );
  });
}

class FakeArtifactRenderSessionRecorder extends ArtifactRenderSessionRecorder {
  FakeArtifactRenderSessionRecorder()
      : super(traceEmitter: (_, __, {level = LogLevel.info, data}) {});

  final List<SurfaceLifecycleEvent> surfaceLifecycleEvents =
      <SurfaceLifecycleEvent>[];

  @override
  void recordSurfaceLifecycle({
    required String sessionId,
    required String event,
    required DateTime timestamp,
    Map<String, dynamic> data = const <String, dynamic>{},
  }) {
    surfaceLifecycleEvents.add(
      SurfaceLifecycleEvent(
        sessionId: sessionId,
        event: event,
        data: Map<String, dynamic>.from(data),
      ),
    );
    super.recordSurfaceLifecycle(
      sessionId: sessionId,
      event: event,
      timestamp: timestamp,
      data: data,
    );
  }
}

class SurfaceLifecycleEvent {
  const SurfaceLifecycleEvent({
    required this.sessionId,
    required this.event,
    required this.data,
  });

  final String sessionId;
  final String event;
  final Map<String, dynamic> data;
}
