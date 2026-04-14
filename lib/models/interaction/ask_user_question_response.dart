/// Structured answers submitted from an AskUserQuestion card.
class AskUserQuestionResponse {
  /// Flattened final answer text keyed by stable question id.
  final Map<String, String> answersByQuestionId;

  /// Selected option labels keyed by question id for richer replay.
  final Map<String, List<String>> selectedOptionLabelsByQuestionId;

  /// Free-text answers collected from "Other" inputs keyed by question id.
  final Map<String, String> freeTextAnswersByQuestionId;

  const AskUserQuestionResponse({
    this.answersByQuestionId = const {},
    this.selectedOptionLabelsByQuestionId = const {},
    this.freeTextAnswersByQuestionId = const {},
  });

  factory AskUserQuestionResponse.fromJson(Map<String, dynamic> json) {
    return AskUserQuestionResponse(
      answersByQuestionId: _readStringMap(json['answersByQuestionId']),
      selectedOptionLabelsByQuestionId: _readStringListMap(
        json['selectedOptionLabelsByQuestionId'],
      ),
      freeTextAnswersByQuestionId: _readStringMap(
        json['freeTextAnswersByQuestionId'],
      ),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'answersByQuestionId': answersByQuestionId,
      'selectedOptionLabelsByQuestionId': selectedOptionLabelsByQuestionId,
      'freeTextAnswersByQuestionId': freeTextAnswersByQuestionId,
    };
  }

  static Map<String, String> _readStringMap(dynamic value) {
    if (value is! Map) {
      return const {};
    }
    return Map<String, String>.fromEntries(
      value.entries.map(
        (entry) => MapEntry(
          entry.key.toString(),
          (entry.value as String? ?? '').trim(),
        ),
      ),
    );
  }

  static Map<String, List<String>> _readStringListMap(dynamic value) {
    if (value is! Map) {
      return const {};
    }
    return Map<String, List<String>>.fromEntries(
      value.entries.map((entry) {
        final rawList = entry.value is List ? entry.value as List : const [];
        return MapEntry(
          entry.key.toString(),
          rawList.map((item) => item.toString()).toList(growable: false),
        );
      }),
    );
  }
}
