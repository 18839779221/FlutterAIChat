import 'api_protocol_resolver.dart';

class LLMConfig {
  final String apiKey;
  final String apiUrl;
  final String model;
  final ApiStyle? apiStyle;
  final Map<String, dynamic> additionalConfig;

  const LLMConfig({
    required this.apiKey,
    required this.apiUrl,
    required this.model,
    this.apiStyle,
    this.additionalConfig = const {},
  });
}
