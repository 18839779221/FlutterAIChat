/// Captures the result of validating and normalizing raw tool arguments.
class ToolArgumentResolution {
  /// Whether the raw arguments are valid for the target tool.
  final bool isValid;

  /// Normalized arguments that should be used for execution when validation
  /// succeeds. Empty when validation fails.
  final Map<String, dynamic> normalizedArguments;

  /// Stable machine-readable error code for invalid arguments.
  final String? errorCode;

  /// Human-readable summary for invalid arguments.
  final String? errorSummary;

  /// Optional planner-facing context text for invalid arguments when the model
  /// needs a clearer failure explanation than the UI summary.
  final String? errorContextText;

  const ToolArgumentResolution._({
    required this.isValid,
    required this.normalizedArguments,
    this.errorCode,
    this.errorSummary,
    this.errorContextText,
  });

  factory ToolArgumentResolution.valid(Map<String, dynamic> normalizedArgs) {
    return ToolArgumentResolution._(
      isValid: true,
      normalizedArguments: Map<String, dynamic>.unmodifiable(normalizedArgs),
    );
  }

  factory ToolArgumentResolution.invalid({
    required String errorCode,
    required String errorSummary,
    String? errorContextText,
  }) {
    return ToolArgumentResolution._(
      isValid: false,
      normalizedArguments: const {},
      errorCode: errorCode,
      errorSummary: errorSummary,
      errorContextText: errorContextText,
    );
  }
}
