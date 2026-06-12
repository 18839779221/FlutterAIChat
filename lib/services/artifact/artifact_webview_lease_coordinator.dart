import 'dart:async';

import 'package:flutter/widgets.dart';

/// Lifecycle tier granted to one artifact preview surface.
///
/// `mounted` keeps a live `WebViewWidget` (native platform view) in the tree;
/// `controllerOnly` keeps the loaded `WebViewController` but renders a
/// fixed-height placeholder; `released` drops the controller entirely and a
/// later grant rebuilds the document from scratch.
enum ArtifactWebViewLeaseState { mounted, controllerOnly, released }

/// One viewport-visibility probe result reported by a lease client.
class ArtifactLeaseVisibilitySample {
  const ArtifactLeaseVisibilitySample.detached()
      : attached = false,
        distanceToViewportPx = null;

  const ArtifactLeaseVisibilitySample.attached({
    required double this.distanceToViewportPx,
  }) : attached = true;

  /// Whether the client's render object is attached to the render tree.
  /// Kept-alive sliver children that scrolled past the cache extent report
  /// `false` here.
  final bool attached;

  /// Distance in pixels between the client and the viewport edge; `0` (or
  /// negative) means visible. `null` when unknown (detached without a usable
  /// scroll-offset estimate).
  final double? distanceToViewportPx;
}

/// Contract a preview surface implements to participate in lease ranking.
abstract class ArtifactWebViewLeaseClient {
  /// Stable label for observation events.
  String get debugLabel;

  /// Resident clients (detail page, surfaces outside a scrollable) bypass the
  /// budget and are always `mounted`. They do not consume budget slots.
  bool get isResident;

  /// Consulted right before a `mounted` grant; surfaces wrap
  /// `Scrollable.recommendDeferredLoadingForContext` here so platform views
  /// are never created mid-fling.
  bool get allowsMountGrantNow;

  ArtifactLeaseVisibilitySample sampleVisibility();

  /// Called outside of build/layout whenever the granted state changes.
  void onLeaseStateChanged(ArtifactWebViewLeaseState state);
}

typedef ArtifactLeaseObservationSink = void Function(
  String event,
  Map<String, Object?> data,
);

/// Central budget manager for live artifact WebViews.
///
/// Ranks registered clients by viewport proximity (then most-recently
/// visible) and grants at most [maxMounted] live platform views and
/// [maxControllers] retained controllers in total. Demotions are applied on
/// any pass; promotions to `mounted` only happen on settle passes
/// (`allowMountGrants`), never while the list is scrolling.
class ArtifactWebViewLeaseCoordinator {
  ArtifactWebViewLeaseCoordinator({
    this.maxMounted = 3,
    this.maxControllers = 6,
    this.enforce = true,
    DateTime Function()? clock,
    void Function(VoidCallback callback)? passPump,
    this.scrollPassThrottle = const Duration(milliseconds: 150),
  })  : _clock = clock ?? DateTime.now,
        _passPump = passPump ?? _defaultPassPump;

  /// Process-wide default used by preview surfaces.
  static final ArtifactWebViewLeaseCoordinator instance =
      ArtifactWebViewLeaseCoordinator();

  final int maxMounted;
  final int maxControllers;

  /// When false the coordinator only observes: every client is granted
  /// `mounted` and intended decisions are emitted through [observationSink].
  final bool enforce;

  final Duration scrollPassThrottle;
  final DateTime Function() _clock;
  final void Function(VoidCallback callback) _passPump;

  /// Optional hook for the render-session recorder; receives ranking and
  /// transition events.
  ArtifactLeaseObservationSink? observationSink;

  final List<_LeaseEntry> _entries = <_LeaseEntry>[];
  final Map<ScrollPosition, _PositionSubscription> _positions =
      <ScrollPosition, _PositionSubscription>{};
  int _registrationCounter = 0;
  bool _passScheduled = false;
  bool _scheduledPassAllowsGrants = false;
  DateTime? _lastScrollPassAt;

  static void _defaultPassPump(VoidCallback callback) {
    scheduleMicrotask(callback);
  }

  ArtifactWebViewLeaseHandle register(ArtifactWebViewLeaseClient client) {
    final entry = _LeaseEntry(
      client: client,
      registrationIndex: _registrationCounter++,
    );
    _entries.add(entry);
    // New surfaces (a streaming artifact appearing at the bottom) must not
    // wait for the next scroll pass to get their first grant.
    _runPass(allowMountGrants: true);
    return ArtifactWebViewLeaseHandle._(this, entry);
  }

  void _unregister(_LeaseEntry entry) {
    if (!_entries.remove(entry)) {
      return;
    }
    _detachScrollPosition(entry);
    _emit('lease_client_unregistered', <String, Object?>{
      'client': entry.client.debugLabel,
      'lastState': entry.state.name,
    });
    // A freed slot may unblock a waiting neighbor.
    _schedulePass(allowMountGrants: true);
  }

  void _attachScrollPosition(_LeaseEntry entry, ScrollPosition? position) {
    if (identical(entry.scrollPosition, position)) {
      return;
    }
    _detachScrollPosition(entry);
    if (position == null) {
      return;
    }
    entry.scrollPosition = position;
    final subscription = _positions.putIfAbsent(position, () {
      final created = _PositionSubscription(
        position: position,
        onOffsetChanged: (isScrolling) =>
            _handleScrollTick(isScrolling: isScrolling),
        onScrollingChanged: (isScrolling) {
          if (!isScrolling) {
            _schedulePass(allowMountGrants: true);
          }
        },
      );
      position.addListener(created.offsetListener);
      position.isScrollingNotifier.addListener(created.scrollingListener);
      return created;
    });
    subscription.refCount += 1;
  }

  void _detachScrollPosition(_LeaseEntry entry) {
    final position = entry.scrollPosition;
    if (position == null) {
      return;
    }
    entry.scrollPosition = null;
    final subscription = _positions[position];
    if (subscription == null) {
      return;
    }
    subscription.refCount -= 1;
    if (subscription.refCount <= 0) {
      position.removeListener(subscription.offsetListener);
      position.isScrollingNotifier.removeListener(subscription.scrollingListener);
      _positions.remove(position);
    }
  }

  void _handleScrollTick({required bool isScrolling}) {
    if (!isScrolling) {
      // Programmatic jumps (jumpTo) move the offset without ever flipping
      // isScrollingNotifier; treat them as already settled.
      _schedulePass(allowMountGrants: true);
      return;
    }
    final now = _clock();
    final last = _lastScrollPassAt;
    if (last != null && now.difference(last) < scrollPassThrottle) {
      return;
    }
    _lastScrollPassAt = now;
    _schedulePass(allowMountGrants: false);
  }

  void _schedulePass({required bool allowMountGrants}) {
    _scheduledPassAllowsGrants = _scheduledPassAllowsGrants || allowMountGrants;
    if (_passScheduled) {
      return;
    }
    _passScheduled = true;
    _passPump(() {
      _passScheduled = false;
      final allowGrants = _scheduledPassAllowsGrants;
      _scheduledPassAllowsGrants = false;
      _runPass(allowMountGrants: allowGrants);
    });
  }

  void _handlePinAcquired(_LeaseEntry entry) {
    // A pin means a takeover or streaming loop is active; the surface must be
    // mounted right now, budget overage included.
    if (entry.state != ArtifactWebViewLeaseState.mounted) {
      _transition(entry, ArtifactWebViewLeaseState.mounted, reason: 'pin');
    }
  }

  void _handlePinReleased(_LeaseEntry entry) {
    _schedulePass(allowMountGrants: true);
  }

  void _runPass({required bool allowMountGrants}) {
    if (_entries.isEmpty) {
      return;
    }
    final now = _clock();
    final ranked = <_LeaseEntry>[];
    for (final entry in _entries) {
      if (entry.client.isResident) {
        if (entry.state != ArtifactWebViewLeaseState.mounted) {
          _transition(entry, ArtifactWebViewLeaseState.mounted,
              reason: 'resident');
        }
        continue;
      }
      final sample = entry.client.sampleVisibility();
      entry.lastSample = sample;
      if (sample.attached && (sample.distanceToViewportPx ?? 1) <= 0) {
        entry.lastVisibleAt = now;
      }
      ranked.add(entry);
    }
    if (ranked.isEmpty) {
      return;
    }

    ranked.sort(_compareEntries);

    final pinnedCount = ranked.where((entry) => entry.isPinned).length;
    var mountedSlots = maxMounted - pinnedCount;
    if (mountedSlots < 0) {
      mountedSlots = 0;
    }
    var controllerSlots = maxControllers - pinnedCount;

    for (final entry in ranked) {
      ArtifactWebViewLeaseState intended;
      if (entry.isPinned) {
        intended = ArtifactWebViewLeaseState.mounted;
      } else if (mountedSlots > 0 && controllerSlots > 0) {
        intended = ArtifactWebViewLeaseState.mounted;
        mountedSlots -= 1;
        controllerSlots -= 1;
      } else if (controllerSlots > 0) {
        intended = ArtifactWebViewLeaseState.controllerOnly;
        controllerSlots -= 1;
      } else {
        intended = ArtifactWebViewLeaseState.released;
      }

      if (intended != entry.intendedState) {
        _emit('lease_intent_changed', <String, Object?>{
          'client': entry.client.debugLabel,
          'from': entry.intendedState.name,
          'to': intended.name,
          'enforce': enforce,
        });
        entry.intendedState = intended;
      }
      if (!enforce) {
        // Observe-only: every client stays mounted; intended decisions are
        // visible through the observation sink only.
        if (entry.state != ArtifactWebViewLeaseState.mounted) {
          _transition(entry, ArtifactWebViewLeaseState.mounted,
              reason: 'observe_only');
        }
        continue;
      }
      if (intended == entry.state) {
        continue;
      }
      final isPromotionToMounted =
          intended == ArtifactWebViewLeaseState.mounted &&
              entry.state != ArtifactWebViewLeaseState.mounted;
      if (isPromotionToMounted &&
          (!allowMountGrants || !entry.client.allowsMountGrantNow)) {
        // Defer the platform-view creation; keep (or raise to) controllerOnly
        // so the controller survives until the settle pass grants the mount.
        if (entry.state == ArtifactWebViewLeaseState.released) {
          _transition(entry, ArtifactWebViewLeaseState.controllerOnly,
              reason: 'grant_deferred');
        }
        continue;
      }
      _transition(entry, intended, reason: 'rank');
    }
  }

  int _compareEntries(_LeaseEntry a, _LeaseEntry b) {
    if (a.isPinned != b.isPinned) {
      return a.isPinned ? -1 : 1;
    }
    final distanceA = a.effectiveDistance;
    final distanceB = b.effectiveDistance;
    if (distanceA != distanceB) {
      return distanceA.compareTo(distanceB);
    }
    final visibleA = a.lastVisibleAt;
    final visibleB = b.lastVisibleAt;
    if (visibleA != null && visibleB != null && visibleA != visibleB) {
      return visibleB.compareTo(visibleA);
    }
    if ((visibleA == null) != (visibleB == null)) {
      return visibleA != null ? -1 : 1;
    }
    return b.registrationIndex.compareTo(a.registrationIndex);
  }

  void _transition(
    _LeaseEntry entry,
    ArtifactWebViewLeaseState next, {
    required String reason,
  }) {
    final previous = entry.state;
    if (previous == next) {
      return;
    }
    _emit('lease_state_changed', <String, Object?>{
      'client': entry.client.debugLabel,
      'from': previous.name,
      'to': next.name,
      'reason': reason,
      'enforce': enforce,
    });
    entry.state = next;
    entry.client.onLeaseStateChanged(next);
  }

  void _emit(String event, Map<String, Object?> data) {
    observationSink?.call(event, data);
  }

  @visibleForTesting
  void debugRunPass({bool allowMountGrants = true}) {
    _runPass(allowMountGrants: allowMountGrants);
  }

  @visibleForTesting
  List<String> debugDescribeEntries() {
    return _entries
        .map((entry) =>
            '${entry.client.debugLabel}:${entry.state.name}'
            '${entry.isPinned ? ':pinned' : ''}')
        .toList(growable: false);
  }
}

/// Mutable handle owned by one registered client.
class ArtifactWebViewLeaseHandle {
  ArtifactWebViewLeaseHandle._(this._coordinator, this._entry);

  final ArtifactWebViewLeaseCoordinator _coordinator;
  final _LeaseEntry _entry;
  bool _unregistered = false;

  ArtifactWebViewLeaseState get state => _entry.state;

  /// What ranking decided, regardless of [state]. Differs from [state] in
  /// observe-only mode and while a mount grant is deferred during scrolling.
  ArtifactWebViewLeaseState get intendedState => _entry.intendedState;

  bool get isPinned => _entry.isPinned;

  /// Pins keep the surface mounted regardless of budget (takeover in flight,
  /// active streaming). Callers must pair every acquire with a release; the
  /// surface-side timers keep pin lifetimes bounded.
  void acquirePin() {
    if (_unregistered) {
      return;
    }
    _entry.pinCount += 1;
    if (_entry.pinCount == 1) {
      _coordinator._handlePinAcquired(_entry);
    }
  }

  void releasePin() {
    if (_unregistered || _entry.pinCount == 0) {
      return;
    }
    _entry.pinCount -= 1;
    if (_entry.pinCount == 0) {
      _coordinator._handlePinReleased(_entry);
    }
  }

  /// Binds the client to the scrollable it lives in. Idempotent; pass null
  /// for surfaces outside any scrollable.
  void attachScrollPosition(ScrollPosition? position) {
    if (_unregistered) {
      return;
    }
    _coordinator._attachScrollPosition(_entry, position);
  }

  void unregister() {
    if (_unregistered) {
      return;
    }
    _unregistered = true;
    _entry.pinCount = 0;
    _coordinator._unregister(_entry);
  }
}

class _LeaseEntry {
  _LeaseEntry({
    required this.client,
    required this.registrationIndex,
  });

  final ArtifactWebViewLeaseClient client;
  final int registrationIndex;

  ArtifactWebViewLeaseState state = ArtifactWebViewLeaseState.released;
  ArtifactWebViewLeaseState intendedState =
      ArtifactWebViewLeaseState.released;
  int pinCount = 0;
  DateTime? lastVisibleAt;
  ArtifactLeaseVisibilitySample? lastSample;
  ScrollPosition? scrollPosition;

  bool get isPinned => pinCount > 0;

  double get effectiveDistance {
    final sample = lastSample;
    if (sample == null) {
      return double.maxFinite;
    }
    final distance = sample.distanceToViewportPx;
    if (distance == null) {
      return double.maxFinite;
    }
    return distance < 0 ? 0 : distance;
  }
}

class _PositionSubscription {
  _PositionSubscription({
    required ScrollPosition position,
    required void Function(bool isScrolling) onOffsetChanged,
    required void Function(bool isScrolling) onScrollingChanged,
  })  : offsetListener =
            (() => onOffsetChanged(position.isScrollingNotifier.value)),
        scrollingListener =
            (() => onScrollingChanged(position.isScrollingNotifier.value));

  final VoidCallback offsetListener;
  final VoidCallback scrollingListener;
  int refCount = 0;
}
