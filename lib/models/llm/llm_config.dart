class LLMConfig {
  final String apiKey;
  final String apiUrl;
  final String model;
  final Map<String, dynamic> additionalConfig;

  const LLMConfig({
    required this.apiKey,
    required this.apiUrl,
    required this.model,
    this.additionalConfig = const {},
  });
}
