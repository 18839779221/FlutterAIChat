/// Declares provider/runtime capabilities that affect common orchestration
/// decisions in `ConfigurableHttpLLM`.
class ProviderCapabilities {
  const ProviderCapabilities({
    required this.supportsPlannerStreaming,
    required this.supportsParallelToolCalls,
    required this.supportsImageInput,
    required this.supportsPreUploadedFiles,
    required this.supportsInlineBase64Images,
    required this.supportsRemoteImageUrl,
  });

  /// Whether planner requests should use the runtime streaming path when
  /// available for this provider contract.
  final bool supportsPlannerStreaming;

  /// Whether this provider contract can advertise/use parallel tool calls in
  /// outbound planner requests.
  final bool supportsParallelToolCalls;

  /// Whether user messages can include image input for this provider contract.
  final bool supportsImageInput;

  /// Whether this provider can consume previously uploaded provider-native files.
  final bool supportsPreUploadedFiles;

  /// Whether this provider can consume inline/base64 image payloads.
  final bool supportsInlineBase64Images;

  /// Whether this provider can consume remote image URLs directly.
  final bool supportsRemoteImageUrl;
}
