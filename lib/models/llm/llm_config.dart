class LLMConfig {
  final String apiKey;
  final String apiUrl;
  final Map<String, dynamic> additionalConfig;

  const LLMConfig({
    required this.apiKey,
    required this.apiUrl,
    this.additionalConfig = const {},
  });
} 