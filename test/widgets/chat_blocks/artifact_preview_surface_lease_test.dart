import 'package:ai_chat/services/artifact/artifact_render_session_recorder.dart';
import 'package:ai_chat/services/artifact/artifact_webview_lease_coordinator.dart';
import 'package:ai_chat/utils/logger.dart';
import 'package:ai_chat/widgets/chat_blocks/artifact_preview_surface.dart';
import 'package:ai_chat/widgets/chat_timeline/artifact_keep_alive.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:webview_flutter_platform_interface/webview_flutter_platform_interface.dart';

import '../../helpers/fake_webview_platform.dart';

void main() {
  late FakeWebViewPlatform platform;

  setUp(() {
    platform = FakeWebViewPlatform();
    WebViewPlatform.instance = platform;
    artifactLeaseReattachProbeDelay = const Duration(milliseconds: 50);
  });

  tearDown(() {
    artifactLeaseReattachProbeDelay = const Duration(milliseconds: 300);
  });

  Widget buildArtifactList({
    required ScrollController controller,
    required ArtifactWebViewLeaseCoordinator coordinator,
    required EventRecordingSessionRecorder recorder,
  }) {
    return MaterialApp(
      home: Scaffold(
        body: ListView(
          controller: controller,
          cacheExtent: 0,
          children: [
            ArtifactKeepAlive(
              child: ArtifactPreviewSurface(
                artifactId: 'artifact-a',
                source: '<div>doc-a</div>',
                sourcePath: 'inline://a',
                sessionRecorder: recorder,
                leaseCoordinator: coordinator,
                turnId: 'turn-a',
              ),
            ),
            ...List.generate(
              20,
              (i) => SizedBox(height: 300, child: Text('filler $i')),
            ),
            ArtifactKeepAlive(
              child: ArtifactPreviewSurface(
                artifactId: 'artifact-b',
                source: '<div>doc-b</div>',
                sourcePath: 'inline://b',
                sessionRecorder: recorder,
                leaseCoordinator: coordinator,
                turnId: 'turn-b',
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> scrollBy(WidgetTester tester, double delta) async {
    // Multiple short drags keep each gesture inside the list bounds while
    // exercising the real scroll-activity lifecycle (drag → ballistic →
    // settle), which is what drives the coordinator's grant passes.
    var remaining = delta;
    while (remaining.abs() > 0) {
      final step = remaining.clamp(-400.0, 400.0);
      await tester.drag(find.byType(ListView), Offset(0, -step));
      remaining -= step;
    }
    await tester.pumpAndSettle();
  }

  testWidgets(
      'keep-alive keeps the surface state alive while the lease demotes the '
      'off-screen webview to a placeholder', (WidgetTester tester) async {
    platform.javaScriptResultHandler = (js) =>
        js.contains('document.readyState') ? '"complete:true"' : '"success"';
    final coordinator = ArtifactWebViewLeaseCoordinator(maxMounted: 1);
    final recorder = EventRecordingSessionRecorder();
    final controller = ScrollController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      buildArtifactList(
        controller: controller,
        coordinator: coordinator,
        recorder: recorder,
      ),
    );
    await tester.pumpAndSettle();
    expect(platform.controllers, hasLength(1));
    final controllerA = platform.controllers.first;

    await scrollBy(tester, 6400);
    // Surface B is now visible and takes the single mounted slot; surface A
    // must survive in the keep-alive bucket without being disposed.
    expect(recorder.eventsFor('artifact-a'), isNot(contains('dispose')));
    expect(
      recorder.leaseStatesFor('artifact-a'),
      contains('controllerOnly'),
    );
    expect(platform.controllers, hasLength(2));

    // Scroll back: A regains the mount, the retained controller is reused
    // (no extra loadHtmlString) after a healthy re-attach probe.
    await scrollBy(tester, -6400);
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pumpAndSettle();

    expect(recorder.eventsFor('artifact-a'), isNot(contains('dispose')));
    expect(recorder.leaseStatesFor('artifact-a').last, 'mounted');
    expect(controllerA.loadedHtmlStrings, hasLength(1));
    expect(recorder.eventsFor('artifact-a'),
        isNot(contains('lease_reattach_reload')));
    // The single placeholder left belongs to surface B, which gave the
    // mounted slot back to A.
    expect(
      find.byKey(artifactPreviewLeasePlaceholderKey, skipOffstage: false),
      findsOneWidget,
    );
    expect(recorder.leaseStatesFor('artifact-b').last, 'controllerOnly');
  });

  testWidgets('failed re-attach probe rebuilds the controller',
      (WidgetTester tester) async {
    platform.javaScriptResultHandler = (js) =>
        js.contains('document.readyState') ? '"unknown:false"' : '"success"';
    final coordinator = ArtifactWebViewLeaseCoordinator(maxMounted: 1);
    final recorder = EventRecordingSessionRecorder();
    final controller = ScrollController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      buildArtifactList(
        controller: controller,
        coordinator: coordinator,
        recorder: recorder,
      ),
    );
    await tester.pumpAndSettle();
    final controllerA = platform.controllers.first;
    expect(controllerA.loadedHtmlStrings, hasLength(1));

    await scrollBy(tester, 6400);
    expect(recorder.leaseStatesFor('artifact-a'), contains('controllerOnly'));

    await scrollBy(tester, -6400);
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pumpAndSettle();

    // The probe reported a dead document; the surface must reload from
    // scratch on a fresh controller.
    expect(recorder.eventsFor('artifact-a'), contains('lease_reattach_reload'));
    final controllersForA = platform.controllers
        .where((c) => c.loadedHtmlStrings.any((html) => html.contains('doc-a')))
        .toList();
    expect(controllersForA.length, greaterThan(1));
  });

  testWidgets('placeholder keeps the persisted preview height',
      (WidgetTester tester) async {
    platform.javaScriptResultHandler = (js) =>
        js.contains('document.readyState') ? '"complete:true"' : '"success"';
    final coordinator = ArtifactWebViewLeaseCoordinator(maxMounted: 1);
    final recorder = EventRecordingSessionRecorder();
    final controller = ScrollController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      buildArtifactList(
        controller: controller,
        coordinator: coordinator,
        recorder: recorder,
      ),
    );
    await tester.pumpAndSettle();

    await scrollBy(tester, 6400);
    final placeholderFinder = find.byKey(
      artifactPreviewLeasePlaceholderKey,
      skipOffstage: false,
    );
    expect(placeholderFinder, findsOneWidget);
    final placeholder = tester.widget<Container>(placeholderFinder.first);
    // Both build branches size themselves from the same `_previewHeight`
    // (260 by default here, since no height message ever arrived), so the
    // row extent cannot shift when the webview is swapped for the shell.
    expect(placeholder.constraints, isNotNull);
    expect(placeholder.constraints!.maxHeight, 260);
  });
}

class EventRecordingSessionRecorder extends ArtifactRenderSessionRecorder {
  EventRecordingSessionRecorder()
      : super(traceEmitter: (_, __, {level = LogLevel.info, data}) {});

  final List<({String artifactId, String event, Map<String, dynamic> data})>
      events = [];

  @override
  void recordSurfaceLifecycle({
    required String sessionId,
    required String event,
    required DateTime timestamp,
    Map<String, dynamic> data = const <String, dynamic>{},
  }) {
    events.add((
      artifactId: '${data['artifactId']}',
      event: event,
      data: Map<String, dynamic>.from(data),
    ));
    super.recordSurfaceLifecycle(
      sessionId: sessionId,
      event: event,
      timestamp: timestamp,
      data: data,
    );
  }

  List<String> eventsFor(String artifactId) => events
      .where((e) => e.artifactId == artifactId)
      .map((e) => e.event)
      .toList(growable: false);

  List<String> leaseStatesFor(String artifactId) => events
      .where((e) =>
          e.artifactId == artifactId && e.event == 'lease_state_changed')
      .map((e) => '${e.data['leaseState']}')
      .toList(growable: false);
}
