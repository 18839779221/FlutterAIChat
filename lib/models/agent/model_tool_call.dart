/// One provider-native tool call extracted from a single model turn.
class ModelToolCall {
  /// Provider call id such as OpenAI tool call ids or response call ids.
  final String? providerCallId;
  final String toolName;

  /// Normalized JSON arguments for the runtime tool registry.
  final Map<String, dynamic> arguments;

  /// Order inside one provider decision payload.
  final int sequence;

  const ModelToolCall({
    this.providerCallId,
    required this.toolName,
    required this.arguments,
    required this.sequence,
  });
}
