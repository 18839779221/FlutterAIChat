import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app_bootstrap_controller.dart';
import 'app_bootstrap_state.dart';
import 'bootstrap_startup_probe.dart';
import '../providers/chat_dependency_providers.dart';

class AppBootstrapScope<TRuntime> extends StatefulWidget {
  const AppBootstrapScope({
    super.key,
    required this.initializeRuntime,
    required this.child,
    this.startupProbe,
  });

  final Future<TRuntime> Function() initializeRuntime;
  final Widget child;
  final BootstrapStartupProbe? startupProbe;

  @override
  State<AppBootstrapScope<TRuntime>> createState() =>
      _AppBootstrapScopeState<TRuntime>();
}

class _AppBootstrapScopeState<TRuntime>
    extends State<AppBootstrapScope<TRuntime>> {
  late final ProviderContainer _container;
  late final AppBootstrapController<TRuntime> _controller;
  late final VoidCallback _listener;
  late final BootstrapStartupProbe _startupProbe;
  bool _bootstrapScheduled = false;
  AppBootstrapPhase? _lastLoggedPhase;

  @override
  void initState() {
    super.initState();
    _startupProbe = widget.startupProbe ?? BootstrapStartupProbe();
    _container = ProviderContainer(
      overrides: [
        bootstrapStartupProbeProvider.overrideWithValue(_startupProbe),
      ],
    );
    _container
        .read(appBootstrapStateNotifierProvider.notifier)
        .update(const AppBootstrapState<Object?>.booting());
    _controller = AppBootstrapController<TRuntime>(
      initializeRuntime: widget.initializeRuntime,
    );
    _listener = _syncBootstrapState;
    _controller.addListener(_listener);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _bootstrapScheduled) {
        return;
      }
      _bootstrapScheduled = true;
      _startupProbe.mark('bootstrap.first_frame');
      _syncBootstrapState();
      _controller.start();
    });
  }

  @override
  void dispose() {
    _controller.removeListener(_listener);
    _controller.dispose();
    _container.dispose();
    super.dispose();
  }

  void _syncBootstrapState() {
    final phase = _controller.state.phase;
    if (_lastLoggedPhase != phase) {
      switch (phase) {
        case AppBootstrapPhase.booting:
          break;
        case AppBootstrapPhase.ready:
          _startupProbe.mark('bootstrap.ready');
          _startupProbe.attachLogger();
          break;
        case AppBootstrapPhase.failed:
          final error = _controller.state.error;
          if (error != null) {
            _startupProbe.markFailed(error);
          } else {
            _startupProbe.mark('bootstrap.failed');
          }
          _startupProbe.attachLogger();
          break;
      }
      _lastLoggedPhase = phase;
    }
    _container.read(appBootstrapStateNotifierProvider.notifier).update(
          AppBootstrapState<Object?>(
            phase: _controller.state.phase,
            runtime: _controller.state.runtime,
            error: _controller.state.error,
          ),
        );
  }

  @override
  Widget build(BuildContext context) {
    return UncontrolledProviderScope(
      container: _container,
      child: widget.child,
    );
  }
}
