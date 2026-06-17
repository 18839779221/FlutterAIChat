import 'package:ai_chat/bootstrap/bootstrap_startup_probe.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('startup probe buffers early events and flushes them once', () {
    final emitted = <_LoggedEvent>[];
    final probe = BootstrapStartupProbe(
      createNow: _FakeNow.sequence(
        const [
          Duration.zero,
          Duration(milliseconds: 12),
          Duration(milliseconds: 28),
        ],
      ).call,
      emit: ({required name, required elapsedMsSinceStart, Object? error}) {
        emitted.add(
          _LoggedEvent(
            name: name,
            elapsedMsSinceStart: elapsedMsSinceStart,
            error: error,
          ),
        );
      },
    );

    probe.mark('bootstrap.start');
    probe.mark('bootstrap.first_frame');

    expect(emitted, isEmpty);

    probe.attachLogger();

    expect(
      emitted,
      [
        const _LoggedEvent(name: 'bootstrap.start', elapsedMsSinceStart: 0),
        const _LoggedEvent(
          name: 'bootstrap.first_frame',
          elapsedMsSinceStart: 12,
        ),
      ],
    );

    probe.mark('bootstrap.first_frame');
    probe.mark('bootstrap.ready');

    expect(
      emitted,
      [
        const _LoggedEvent(name: 'bootstrap.start', elapsedMsSinceStart: 0),
        const _LoggedEvent(
          name: 'bootstrap.first_frame',
          elapsedMsSinceStart: 12,
        ),
        const _LoggedEvent(name: 'bootstrap.ready', elapsedMsSinceStart: 28),
      ],
    );
  });

  test('startup probe can record failed bootstrap exactly once', () {
    final emitted = <_LoggedEvent>[];
    final probe = BootstrapStartupProbe(
      createNow: _FakeNow.sequence(
        const [
          Duration.zero,
          Duration(milliseconds: 41),
          Duration(milliseconds: 65),
        ],
      ).call,
      emit: ({required name, required elapsedMsSinceStart, Object? error}) {
        emitted.add(
          _LoggedEvent(
            name: name,
            elapsedMsSinceStart: elapsedMsSinceStart,
            error: error,
          ),
        );
      },
    );

    probe.mark('bootstrap.start');
    probe.attachLogger();

    final error = StateError('boom');
    probe.markFailed(error);
    probe.markFailed(StateError('later failure'));

    expect(
      emitted,
      [
        const _LoggedEvent(name: 'bootstrap.start', elapsedMsSinceStart: 0),
        _LoggedEvent(
          name: 'bootstrap.failed',
          elapsedMsSinceStart: 41,
          error: error,
        ),
      ],
    );
  });
}

class _FakeNow {
  _FakeNow.sequence(List<Duration> offsets)
      : _offsets = offsets,
        _base = DateTime(2026, 6, 17, 12);

  final List<Duration> _offsets;
  final DateTime _base;
  var _index = 0;

  DateTime call() {
    final safeIndex = _index >= _offsets.length ? _offsets.length - 1 : _index;
    _index += 1;
    return _base.add(_offsets[safeIndex]);
  }
}

class _LoggedEvent {
  const _LoggedEvent({
    required this.name,
    required this.elapsedMsSinceStart,
    this.error,
  });

  final String name;
  final int elapsedMsSinceStart;
  final Object? error;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) {
      return true;
    }
    return other is _LoggedEvent &&
        other.name == name &&
        other.elapsedMsSinceStart == elapsedMsSinceStart &&
        other.error == error;
  }

  @override
  int get hashCode => Object.hash(name, elapsedMsSinceStart, error);
}
