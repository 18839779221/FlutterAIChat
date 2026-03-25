import 'dart:convert';

import '../models/response/structured_summary_card.dart';

class StructuredSummaryParseResult {
  static const String fallbackMessage = '结构化整理失败，请重试。';

  final StructuredSummaryCard? card;
  final String? fallbackText;

  const StructuredSummaryParseResult.structured(StructuredSummaryCard this.card)
    : fallbackText = null;

  const StructuredSummaryParseResult.fallback()
    : card = null,
      fallbackText = fallbackMessage;

  bool get isStructuredCard => card != null;
}

class ResponseParserService {
  StructuredSummaryParseResult parseStructuredSummaryCard(String rawOutput) {
    try {
      final decoded = jsonDecode(rawOutput);
      if (decoded is! Map<String, dynamic>) {
        return const StructuredSummaryParseResult.fallback();
      }

      final card = StructuredSummaryCard.fromJson(decoded);
      return StructuredSummaryParseResult.structured(card);
    } catch (_) {
      return const StructuredSummaryParseResult.fallback();
    }
  }
}
