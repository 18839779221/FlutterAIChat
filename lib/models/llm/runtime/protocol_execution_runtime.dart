import 'dart:async';

import '../llm_cache_usage.dart';
import '../llm_config.dart';
import '../streaming_message_event.dart';
import 'protocol_request_spec.dart';

/// Unified execution interface for provider protocol runtimes.
///
/// A runtime is responsible for transport execution only: it receives a
/// protocol-native request spec and returns normalized execution artifacts.
abstract class ProtocolExecutionRuntime {
  const ProtocolExecutionRuntime();

  Future<ProtocolExecutionResult> execute({
    required ProtocolRequestSpec requestSpec,
    required LLMConfig runtimeConfig,
    required Duration timeout,
  });

  Future<ProtocolStreamExecutionResult> streamExecute({
    required ProtocolRequestSpec requestSpec,
    required LLMConfig runtimeConfig,
    required Duration idleTimeout,
    required Duration overallTimeout,
  });
}

class ProtocolExecutionResult {
  const ProtocolExecutionResult({
    required this.rawResponseJson,
    this.cacheUsage,
  });

  /// Provider-shaped response JSON used by existing tool-loop parsers.
  final Map<String, dynamic> rawResponseJson;

  /// Optional normalized usage extracted from provider-native metadata.
  final LlmCacheUsage? cacheUsage;
}

class ProtocolStreamExecutionResult {
  ProtocolStreamExecutionResult({
    required this.events,
    this.nonStreamingFallbackJson,
    this.cacheUsage,
  });

  /// Unified preview events consumed by accumulator and preview projector.
  final Stream<StreamingMessageEvent> events;

  /// Some providers may answer a streaming request with a single JSON body.
  final Map<String, dynamic>? nonStreamingFallbackJson;

  /// Optional normalized usage extracted from streaming response.
  final LlmCacheUsage? cacheUsage;
}
