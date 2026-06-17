enum AppBootstrapPhase {
  booting,
  ready,
  failed,
}

class AppBootstrapState<TRuntime> {
  const AppBootstrapState({
    required this.phase,
    this.runtime,
    this.error,
  });

  const AppBootstrapState.booting()
      : phase = AppBootstrapPhase.booting,
        runtime = null,
        error = null;

  const AppBootstrapState.ready(this.runtime)
      : phase = AppBootstrapPhase.ready,
        error = null;

  const AppBootstrapState.failed(this.error)
      : phase = AppBootstrapPhase.failed,
        runtime = null;

  final AppBootstrapPhase phase;
  final TRuntime? runtime;
  final Object? error;

  bool get isReady => phase == AppBootstrapPhase.ready;

  bool get isComposerEditable => true;

  bool get isSendAvailable => isReady;
}
