import 'package:ai_chat/bootstrap/app_bootstrap_controller.dart';
import 'package:ai_chat/bootstrap/app_bootstrap_state.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('bootstrap starts in booting state and becomes ready after init',
      () async {
    final controller = AppBootstrapController<_FakeRuntime>(
      initializeRuntime: () async => const _FakeRuntime('ready'),
    );

    expect(controller.state.phase, AppBootstrapPhase.booting);
    expect(controller.state.isComposerEditable, isTrue);
    expect(controller.state.isSendAvailable, isFalse);
    expect(controller.state.runtime, isNull);

    await controller.start();

    expect(controller.state.phase, AppBootstrapPhase.ready);
    expect(controller.state.isReady, isTrue);
    expect(controller.state.isComposerEditable, isTrue);
    expect(controller.state.isSendAvailable, isTrue);
    expect(controller.state.runtime, const _FakeRuntime('ready'));
    expect(controller.state.error, isNull);
  });

  test('bootstrap stores failure state when delayed init throws', () async {
    final controller = AppBootstrapController<_FakeRuntime>(
      initializeRuntime: () async {
        throw StateError('bootstrap exploded');
      },
    );

    await controller.start();

    expect(controller.state.phase, AppBootstrapPhase.failed);
    expect(controller.state.isReady, isFalse);
    expect(controller.state.isComposerEditable, isTrue);
    expect(controller.state.isSendAvailable, isFalse);
    expect(controller.state.runtime, isNull);
    expect(controller.state.error, isA<StateError>());
  });

  test('bootstrap only starts once even when start is called repeatedly',
      () async {
    var callCount = 0;
    final controller = AppBootstrapController<_FakeRuntime>(
      initializeRuntime: () async {
        callCount += 1;
        return const _FakeRuntime('singleton');
      },
    );

    await controller.start();
    await controller.start();

    expect(callCount, 1);
    expect(controller.state.phase, AppBootstrapPhase.ready);
    expect(controller.state.runtime, const _FakeRuntime('singleton'));
  });
}

class _FakeRuntime {
  const _FakeRuntime(this.id);

  final String id;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) {
      return true;
    }
    return other is _FakeRuntime && other.id == id;
  }

  @override
  int get hashCode => id.hashCode;
}
