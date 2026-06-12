import 'package:ai_chat/services/artifact/artifact_webview_lease_coordinator.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

class TestLeaseClient implements ArtifactWebViewLeaseClient {
  TestLeaseClient(
    this.debugLabel, {
    this.isResident = false,
    double distance = 0,
  }) : sample = ArtifactLeaseVisibilitySample.attached(
          distanceToViewportPx: distance,
        );

  @override
  final String debugLabel;

  @override
  final bool isResident;

  bool allowMountGrant = true;

  @override
  bool get allowsMountGrantNow => allowMountGrant;

  ArtifactLeaseVisibilitySample sample;

  final List<ArtifactWebViewLeaseState> stateChanges =
      <ArtifactWebViewLeaseState>[];

  @override
  ArtifactLeaseVisibilitySample sampleVisibility() => sample;

  @override
  void onLeaseStateChanged(ArtifactWebViewLeaseState state) {
    stateChanges.add(state);
  }
}

void main() {
  late List<VoidCallback> pendingPumps;
  late DateTime now;

  ArtifactWebViewLeaseCoordinator buildCoordinator({
    int maxMounted = 3,
    int maxControllers = 6,
    bool enforce = true,
  }) {
    pendingPumps = <VoidCallback>[];
    now = DateTime(2026, 6, 12);
    return ArtifactWebViewLeaseCoordinator(
      maxMounted: maxMounted,
      maxControllers: maxControllers,
      enforce: enforce,
      clock: () => now,
      passPump: pendingPumps.add,
    );
  }

  void flushPumps() {
    while (pendingPumps.isNotEmpty) {
      pendingPumps.removeAt(0)();
    }
  }

  test('grants tiers by viewport distance within budgets', () {
    final coordinator = buildCoordinator();
    final clients = List.generate(
      8,
      (i) => TestLeaseClient('client-$i', distance: i * 100.0),
    );
    final handles = clients.map(coordinator.register).toList();

    expect(
      handles.map((h) => h.state).toList(),
      <ArtifactWebViewLeaseState>[
        ArtifactWebViewLeaseState.mounted,
        ArtifactWebViewLeaseState.mounted,
        ArtifactWebViewLeaseState.mounted,
        ArtifactWebViewLeaseState.controllerOnly,
        ArtifactWebViewLeaseState.controllerOnly,
        ArtifactWebViewLeaseState.controllerOnly,
        ArtifactWebViewLeaseState.released,
        ArtifactWebViewLeaseState.released,
      ],
    );
  });

  test('a closer client demotes the farthest mounted one', () {
    final coordinator = buildCoordinator(maxMounted: 1, maxControllers: 2);
    final far = TestLeaseClient('far', distance: 500);
    final farHandle = coordinator.register(far);
    expect(farHandle.state, ArtifactWebViewLeaseState.mounted);

    final near = TestLeaseClient('near', distance: 0);
    final nearHandle = coordinator.register(near);

    expect(nearHandle.state, ArtifactWebViewLeaseState.mounted);
    expect(farHandle.state, ArtifactWebViewLeaseState.controllerOnly);
  });

  test('pin mounts immediately and survives ranking; release re-ranks', () {
    final coordinator = buildCoordinator(maxMounted: 1, maxControllers: 4);
    final near = TestLeaseClient('near', distance: 0);
    final far = TestLeaseClient('far', distance: 900);
    coordinator.register(near);
    final farHandle = coordinator.register(far);
    expect(farHandle.state, ArtifactWebViewLeaseState.controllerOnly);

    farHandle.acquirePin();
    expect(farHandle.state, ArtifactWebViewLeaseState.mounted);

    coordinator.debugRunPass();
    expect(farHandle.state, ArtifactWebViewLeaseState.mounted);

    farHandle.releasePin();
    flushPumps();
    expect(farHandle.state, ArtifactWebViewLeaseState.controllerOnly);
  });

  test('mount promotions are deferred while scrolling, demotions are not', () {
    final coordinator = buildCoordinator(maxMounted: 1, maxControllers: 4);
    final a = TestLeaseClient('a', distance: 0);
    final b = TestLeaseClient('b', distance: 800);
    final aHandle = coordinator.register(a);
    final bHandle = coordinator.register(b);
    expect(aHandle.state, ArtifactWebViewLeaseState.mounted);
    expect(bHandle.state, ArtifactWebViewLeaseState.controllerOnly);

    // The user scrolled: b is now visible, a is far away.
    a.sample =
        const ArtifactLeaseVisibilitySample.attached(distanceToViewportPx: 800);
    b.sample =
        const ArtifactLeaseVisibilitySample.attached(distanceToViewportPx: 0);

    coordinator.debugRunPass(allowMountGrants: false);
    // Demotion applied right away; promotion deferred to the settle pass.
    expect(aHandle.state, ArtifactWebViewLeaseState.controllerOnly);
    expect(bHandle.state, ArtifactWebViewLeaseState.controllerOnly);

    coordinator.debugRunPass(allowMountGrants: true);
    expect(bHandle.state, ArtifactWebViewLeaseState.mounted);
    expect(aHandle.state, ArtifactWebViewLeaseState.controllerOnly);
  });

  test('client veto (recommendDeferredLoading) blocks a settle-pass grant', () {
    final coordinator = buildCoordinator(maxMounted: 1, maxControllers: 4);
    final a = TestLeaseClient('a', distance: 0);
    final aHandle = coordinator.register(a);
    expect(aHandle.state, ArtifactWebViewLeaseState.mounted);

    a.sample =
        const ArtifactLeaseVisibilitySample.attached(distanceToViewportPx: 900);
    final b = TestLeaseClient('b', distance: 0)..allowMountGrant = false;
    final bHandle = coordinator.register(b);
    expect(bHandle.state, ArtifactWebViewLeaseState.controllerOnly);

    b.allowMountGrant = true;
    coordinator.debugRunPass(allowMountGrants: true);
    expect(bHandle.state, ArtifactWebViewLeaseState.mounted);
  });

  test('unregister frees the slot for the next ranked client', () {
    final coordinator = buildCoordinator(maxMounted: 1, maxControllers: 4);
    final a = TestLeaseClient('a', distance: 0);
    final b = TestLeaseClient('b', distance: 100);
    final aHandle = coordinator.register(a);
    final bHandle = coordinator.register(b);
    expect(aHandle.state, ArtifactWebViewLeaseState.mounted);
    expect(bHandle.state, ArtifactWebViewLeaseState.controllerOnly);

    aHandle.unregister();
    flushPumps();
    expect(bHandle.state, ArtifactWebViewLeaseState.mounted);
  });

  test('detached clients are ranked by most recent visibility', () {
    final coordinator = buildCoordinator(maxMounted: 1, maxControllers: 2);
    final oldClient = TestLeaseClient('old', distance: 0);
    final oldHandle = coordinator.register(oldClient);
    expect(oldHandle.state, ArtifactWebViewLeaseState.mounted);

    // `old` leaves the cache extent; a fresh visible client takes the slot.
    now = now.add(const Duration(seconds: 5));
    oldClient.sample = const ArtifactLeaseVisibilitySample.detached();
    final fresh = TestLeaseClient('fresh', distance: 0);
    final freshHandle = coordinator.register(fresh);
    expect(freshHandle.state, ArtifactWebViewLeaseState.mounted);
    expect(oldHandle.state, ArtifactWebViewLeaseState.controllerOnly);

    // A second detached client with no visibility history ranks below `old`,
    // pushing it past the controller budget.
    final ghost = TestLeaseClient('ghost')
      ..sample = const ArtifactLeaseVisibilitySample.detached();
    final ghostHandle = coordinator.register(ghost);
    expect(oldHandle.state, ArtifactWebViewLeaseState.controllerOnly);
    expect(ghostHandle.state, ArtifactWebViewLeaseState.released);
  });

  test('residents are always mounted and consume no budget', () {
    final coordinator = buildCoordinator(maxMounted: 1, maxControllers: 2);
    final resident = TestLeaseClient('resident', isResident: true);
    final residentHandle = coordinator.register(resident);
    final inline = TestLeaseClient('inline', distance: 0);
    final inlineHandle = coordinator.register(inline);

    expect(residentHandle.state, ArtifactWebViewLeaseState.mounted);
    expect(inlineHandle.state, ArtifactWebViewLeaseState.mounted);
  });

  test('observe-only mode keeps everyone mounted but reports intents', () {
    final coordinator = buildCoordinator(
      maxMounted: 1,
      maxControllers: 2,
      enforce: false,
    );
    final intents = <String>[];
    coordinator.observationSink = (event, data) {
      if (event == 'lease_intent_changed') {
        intents.add('${data['client']}:${data['to']}');
      }
    };
    final clients = List.generate(
      3,
      (i) => TestLeaseClient('client-$i', distance: i * 100.0),
    );
    final handles = clients.map(coordinator.register).toList();

    expect(
      handles.map((h) => h.state),
      everyElement(ArtifactWebViewLeaseState.mounted),
    );
    expect(intents, contains('client-0:mounted'));
    expect(intents, contains('client-1:controllerOnly'));
    expect(
      handles.map((h) => h.intendedState).toList(),
      <ArtifactWebViewLeaseState>[
        ArtifactWebViewLeaseState.mounted,
        ArtifactWebViewLeaseState.controllerOnly,
        ArtifactWebViewLeaseState.released,
      ],
    );
  });
}
