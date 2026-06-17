import 'package:flutter/foundation.dart';

import 'app_bootstrap_state.dart';

class AppBootstrapController<TRuntime> extends ChangeNotifier {
  AppBootstrapController({
    required Future<TRuntime> Function() initializeRuntime,
  }) : _initializeRuntime = initializeRuntime;

  final Future<TRuntime> Function() _initializeRuntime;
  AppBootstrapState<TRuntime> _state = const AppBootstrapState.booting();
  Future<void>? _inFlightStart;

  AppBootstrapState<TRuntime> get state => _state;

  Future<void> start() {
    final inFlightStart = _inFlightStart;
    if (inFlightStart != null) {
      return inFlightStart;
    }

    final future = _startInternal();
    _inFlightStart = future;
    return future;
  }

  Future<void> _startInternal() async {
    try {
      final runtime = await _initializeRuntime();
      _state = AppBootstrapState.ready(runtime);
    } catch (error) {
      _state = AppBootstrapState.failed(error);
    } finally {
      notifyListeners();
    }
  }
}
