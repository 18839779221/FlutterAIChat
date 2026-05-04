/// Cache behavior for one LLM request.
enum LlmCacheStrategy {
  /// Do not emit cache hints.
  disabled,

  /// Observe provider usage but do not change request payloads.
  observeOnly,

  /// Emit provider-specific cache hints when the adapter supports them.
  providerHints,
}
