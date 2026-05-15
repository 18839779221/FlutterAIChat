class SpeechInputConfig {
  /// Whether the current runtime instance should expose speech input UI.
  final bool enabled;

  /// Provider identifier for the current speech-to-text backend.
  final String provider;

  /// WebSocket endpoint used for realtime recognition sessions.
  final String endpoint;

  /// API key injected through local defaults for development and testing.
  final String apiKey;

  /// Sample rate expected by the downstream realtime ASR backend.
  final int sampleRate;

  /// Preferred recognition languages forwarded to the provider when supported.
  final List<String> languageHints;

  const SpeechInputConfig({
    required this.enabled,
    required this.provider,
    required this.endpoint,
    required this.apiKey,
    required this.sampleRate,
    required this.languageHints,
  });

  /// Whether the config is complete enough to attempt a realtime session.
  bool get isValid =>
      enabled &&
      provider.trim().isNotEmpty &&
      endpoint.trim().isNotEmpty &&
      apiKey.trim().isNotEmpty;

  factory SpeechInputConfig.fromJson(Map<String, dynamic> json) {
    final languageHints = (json['languageHints'] as List<dynamic>?)
            ?.whereType<String>()
            .map((item) => item.trim())
            .where((item) => item.isNotEmpty)
            .toList(growable: false) ??
        const <String>['zh', 'en'];

    return SpeechInputConfig(
      enabled: json['enabled'] as bool? ?? false,
      provider: (json['provider'] as String? ?? '').trim(),
      endpoint: (json['endpoint'] as String? ?? '').trim(),
      apiKey: (json['apiKey'] as String? ?? json['api_key'] as String? ?? '')
          .trim(),
      sampleRate: json['sampleRate'] as int? ?? 16000,
      languageHints: languageHints,
    );
  }
}
