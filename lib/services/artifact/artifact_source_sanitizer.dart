class ArtifactSanitizationResult {
  final bool isValid;
  final String sanitizedSource;
  final int bytes;
  final List<String> warnings;
  final String? errorCode;

  const ArtifactSanitizationResult({
    required this.isValid,
    required this.sanitizedSource,
    required this.bytes,
    this.warnings = const <String>[],
    this.errorCode,
  });

  factory ArtifactSanitizationResult.invalid(String errorCode) {
    return ArtifactSanitizationResult(
      isValid: false,
      sanitizedSource: '',
      bytes: 0,
      errorCode: errorCode,
    );
  }
}

/// Performs lightweight source validation and strips obvious external assets.
class ArtifactSourceSanitizer {
  static const int defaultMaxBytes = 200 * 1024;

  const ArtifactSourceSanitizer({
    this.maxBytes = defaultMaxBytes,
  });

  final int maxBytes;

  ArtifactSanitizationResult sanitize(String source) {
    final trimmed = source.trim();
    if (trimmed.isEmpty) {
      return ArtifactSanitizationResult.invalid('empty_source');
    }

    final warnings = <String>[];
    var sanitized = trimmed;

    final scriptSrcPattern = RegExp(
      "<script\\b[^>]*\\bsrc\\s*=\\s*['\\\"][^'\\\"]+['\\\"][^>]*>\\s*</script>",
      caseSensitive: false,
      multiLine: true,
    );
    if (scriptSrcPattern.hasMatch(sanitized)) {
      sanitized = sanitized.replaceAll(scriptSrcPattern, '');
      warnings.add('removed_external_script');
    }

    final linkHrefPattern = RegExp(
      "<link\\b[^>]*\\brel\\s*=\\s*['\\\"]stylesheet['\\\"][^>]*\\bhref\\s*=\\s*['\\\"]https?:\\/\\/[^'\\\"]+['\\\"][^>]*>",
      caseSensitive: false,
      multiLine: true,
    );
    if (linkHrefPattern.hasMatch(sanitized)) {
      sanitized = sanitized.replaceAll(linkHrefPattern, '');
      warnings.add('removed_external_stylesheet');
    }

    final bytes = sanitized.codeUnits.length;
    if (bytes > maxBytes) {
      return ArtifactSanitizationResult.invalid('source_too_large');
    }

    return ArtifactSanitizationResult(
      isValid: true,
      sanitizedSource: sanitized,
      bytes: bytes,
      warnings: warnings,
    );
  }
}
