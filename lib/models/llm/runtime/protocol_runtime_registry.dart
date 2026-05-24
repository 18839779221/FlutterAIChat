import '../api_protocol_resolver.dart';
import 'protocol_execution_runtime.dart';

/// Resolves a protocol execution runtime by [ApiStyle].
class ProtocolRuntimeRegistry {
  ProtocolRuntimeRegistry({
    required Map<ApiStyle, ProtocolExecutionRuntime> runtimes,
  }) : _runtimes = Map<ApiStyle, ProtocolExecutionRuntime>.unmodifiable(
          runtimes,
        );

  final Map<ApiStyle, ProtocolExecutionRuntime> _runtimes;

  ProtocolExecutionRuntime runtimeFor(ApiStyle apiStyle) {
    final runtime = _runtimes[apiStyle];
    if (runtime == null) {
      throw StateError('No ProtocolExecutionRuntime registered for $apiStyle');
    }
    return runtime;
  }
}
