import 'ask_user_question_option.dart';

/// One structured question emitted by the AskUserQuestion tool.
class AskUserQuestionItem {
  /// Stable identifier used when saving structured answers.
  final String id;

  /// Short title shown above the question body.
  final String header;

  /// Main question text displayed to the user.
  final String question;

  /// Whether the card should allow multiple selections.
  final bool multiSelect;

  /// Selectable options defined by the model for this question.
  final List<AskUserQuestionOption> options;

  const AskUserQuestionItem({
    required this.id,
    required this.header,
    required this.question,
    required this.multiSelect,
    required this.options,
  });

  factory AskUserQuestionItem.fromJson(Map<String, dynamic> json) {
    final id = (json['id'] as String? ?? '').trim();
    if (id.isEmpty) {
      throw const FormatException('question id is required');
    }
    final question = (json['question'] as String? ?? '').trim();
    if (question.isEmpty) {
      throw const FormatException('question is required');
    }
    final rawOptions = json['options'];
    return AskUserQuestionItem(
      id: id,
      header: (json['header'] as String? ?? '').trim(),
      question: question,
      multiSelect: json['multiSelect'] as bool? ?? false,
      options: rawOptions is List
          ? rawOptions
              .map(
                (item) => AskUserQuestionOption.fromJson(
                  Map<String, dynamic>.from(item as Map<dynamic, dynamic>),
                ),
              )
              .toList(growable: false)
          : const [],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'header': header,
      'question': question,
      'multiSelect': multiSelect,
      'options': options.map((item) => item.toJson()).toList(growable: false),
    };
  }
}
