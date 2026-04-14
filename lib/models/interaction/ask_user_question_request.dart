import 'ask_user_question_item.dart';

/// Runtime payload for one AskUserQuestion checkpoint inside a turn.
class AskUserQuestionRequest {
  /// Questions to be answered before the turn can continue.
  final List<AskUserQuestionItem> questions;

  /// Owning turn id used to resume the same agent loop.
  final int agentTurnId;

  /// Optional persisted step id for provider continuation and ledger updates.
  final int? stepId;

  /// Provider-native call id for this interaction tool step.
  final String? providerCallId;

  /// UI trace id used to reconnect the resumed stream with the original send.
  final String? traceTurnId;

  const AskUserQuestionRequest({
    required this.questions,
    required this.agentTurnId,
    this.stepId,
    this.providerCallId,
    this.traceTurnId,
  });

  factory AskUserQuestionRequest.fromJson(Map<String, dynamic> json) {
    final rawQuestions = json['questions'];
    if (rawQuestions is! List || rawQuestions.isEmpty) {
      throw const FormatException('questions is required');
    }
    final agentTurnId = json['agentTurnId'];
    if (agentTurnId is! int) {
      throw const FormatException('agentTurnId is required');
    }
    return AskUserQuestionRequest(
      questions: rawQuestions
          .map(
            (item) => AskUserQuestionItem.fromJson(
              Map<String, dynamic>.from(item as Map<dynamic, dynamic>),
            ),
          )
          .toList(growable: false),
      agentTurnId: agentTurnId,
      stepId: json['stepId'] as int?,
      providerCallId: (json['providerCallId'] as String?)?.trim(),
      traceTurnId: (json['traceTurnId'] as String?)?.trim(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'questions': questions.map((item) => item.toJson()).toList(growable: false),
      'agentTurnId': agentTurnId,
      if (stepId != null) 'stepId': stepId,
      if ((providerCallId ?? '').isNotEmpty) 'providerCallId': providerCallId,
      if ((traceTurnId ?? '').isNotEmpty) 'traceTurnId': traceTurnId,
    };
  }
}
