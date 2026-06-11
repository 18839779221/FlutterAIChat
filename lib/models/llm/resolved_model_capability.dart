import 'api_protocol_resolver.dart';
import 'model_capability_source_kind.dart';

/// Resolved capability facts for one runtime provider/model pair.
class ResolvedModelCapability {
  final String providerId;
  final ApiStyle providerStyle;
  final String baseUrlFingerprint;
  final String modelId;
  final int? contextWindowTotal;
  final int? maxInputTokens;
  final int? maxOutputTokens;
  final ModelCapabilitySourceKind source;

  const ResolvedModelCapability({
    required this.providerId,
    required this.providerStyle,
    required this.baseUrlFingerprint,
    required this.modelId,
    this.contextWindowTotal,
    this.maxInputTokens,
    this.maxOutputTokens,
    required this.source,
  });

  factory ResolvedModelCapability.fromJson(Map<String, dynamic> json) {
    return ResolvedModelCapability(
      providerId: (json['providerId'] as String? ?? '').trim(),
      providerStyle: _readApiStyle(json['providerStyle']) ??
          ApiStyle.chatCompletions,
      baseUrlFingerprint: (json['baseUrlFingerprint'] as String? ?? '').trim(),
      modelId: (json['modelId'] as String? ?? '').trim(),
      contextWindowTotal: _readInt(
        json['contextWindowTotal'] ?? json['context_window_total'],
      ),
      maxInputTokens:
          _readInt(json['maxInputTokens'] ?? json['max_input_tokens']),
      maxOutputTokens:
          _readInt(json['maxOutputTokens'] ?? json['max_output_tokens']),
      source: _readSource(json['source']) ?? ModelCapabilitySourceKind.catalog,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'providerId': providerId,
      'providerStyle': providerStyle.name,
      'baseUrlFingerprint': baseUrlFingerprint,
      'modelId': modelId,
      if (contextWindowTotal != null) 'contextWindowTotal': contextWindowTotal,
      if (maxInputTokens != null) 'maxInputTokens': maxInputTokens,
      if (maxOutputTokens != null) 'maxOutputTokens': maxOutputTokens,
      'source': source.name,
    };
  }

  static ApiStyle? _readApiStyle(dynamic rawValue) {
    if (rawValue is! String) {
      return null;
    }
    final normalized = rawValue.trim();
    for (final style in ApiStyle.values) {
      if (style.name == normalized) {
        return style;
      }
    }
    return null;
  }

  static ModelCapabilitySourceKind? _readSource(dynamic rawValue) {
    if (rawValue is! String) {
      return null;
    }
    final normalized = rawValue.trim();
    for (final source in ModelCapabilitySourceKind.values) {
      if (source.name == normalized) {
        return source;
      }
    }
    return null;
  }

  static int? _readInt(dynamic value) {
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.toInt();
    }
    return null;
  }
}
