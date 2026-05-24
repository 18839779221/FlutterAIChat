import 'package:ai_chat/models/llm/api_protocol_resolver.dart';
import 'package:ai_chat/models/llm/llm_config.dart';
import 'package:ai_chat/models/llm/runtime/protocol_execution_runtime.dart';
import 'package:ai_chat/models/llm/runtime/protocol_request_spec.dart';
import 'package:ai_chat/models/llm/runtime/protocol_runtime_registry.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('registry resolves runtime by api style', () {
    final chat = _FakeRuntime();
    final responses = _FakeRuntime();
    final anthropic = _FakeRuntime();
    final registry = ProtocolRuntimeRegistry(
      runtimes: {
        ApiStyle.chatCompletions: chat,
        ApiStyle.responses: responses,
        ApiStyle.anthropicMessages: anthropic,
      },
    );

    expect(registry.runtimeFor(ApiStyle.chatCompletions), same(chat));
    expect(registry.runtimeFor(ApiStyle.responses), same(responses));
    expect(registry.runtimeFor(ApiStyle.anthropicMessages), same(anthropic));
  });
}

class _FakeRuntime extends ProtocolExecutionRuntime {
  @override
  Future<ProtocolExecutionResult> execute({
    required ProtocolRequestSpec requestSpec,
    required LLMConfig runtimeConfig,
    required Duration timeout,
  }) async {
    return const ProtocolExecutionResult(rawResponseJson: {});
  }

  @override
  Future<ProtocolStreamExecutionResult> streamExecute({
    required ProtocolRequestSpec requestSpec,
    required LLMConfig runtimeConfig,
    required Duration idleTimeout,
    required Duration overallTimeout,
  }) async {
    return ProtocolStreamExecutionResult(chunks: const Stream.empty());
  }
}
