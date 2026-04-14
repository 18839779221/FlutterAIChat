import 'ask_user_question_item.dart';
import 'ask_user_question_response.dart';

enum QuestionCardPayloadType {
  prompt,
  result,
}

enum QuestionCardPayloadStatus {
  awaitingResponse,
  submitted,
  cancelled,
}

/// Stable chat-message payload used by AskUserQuestion prompt/result cards.
class QuestionCardPayload {
  /// Whether this payload represents the prompt card or the submitted result.
  final QuestionCardPayloadType type;

  /// Owning turn id used to resume and replay the interaction.
  final int agentTurnId;

  /// Optional step id for step-ledger updates.
  final int? stepId;

  /// UI trace id used to reconnect resumed events to the original send.
  final String? traceTurnId;

  /// Current interaction lifecycle state rendered in the chat timeline.
  final QuestionCardPayloadStatus status;

  /// Original structured questions shown in the prompt card.
  final List<AskUserQuestionItem> questions;

  /// Final submitted answers for result playback.
  final AskUserQuestionResponse? submittedAnswers;

  /// Optional in-card index used only when replaying wizard state.
  final int? currentQuestionIndex;

  const QuestionCardPayload({
    required this.type,
    required this.agentTurnId,
    required this.status,
    this.stepId,
    this.traceTurnId,
    this.questions = const [],
    this.submittedAnswers,
    this.currentQuestionIndex,
  });

  factory QuestionCardPayload.fromJson(Map<String, dynamic> json) {
    return QuestionCardPayload(
      type: QuestionCardPayloadType.values.firstWhere(
        (item) => item.name == json['type'],
        orElse: () => QuestionCardPayloadType.prompt,
      ),
      agentTurnId: json['agentTurnId'] as int? ?? 0,
      stepId: json['stepId'] as int?,
      traceTurnId: (json['traceTurnId'] as String?)?.trim(),
      status: QuestionCardPayloadStatus.values.firstWhere(
        (item) => item.name == json['status'],
        orElse: () => QuestionCardPayloadStatus.awaitingResponse,
      ),
      questions: json['questions'] is List
          ? (json['questions'] as List)
              .map(
                (item) => AskUserQuestionItem.fromJson(
                  Map<String, dynamic>.from(item as Map<dynamic, dynamic>),
                ),
              )
              .toList(growable: false)
          : const [],
      submittedAnswers: json['submittedAnswers'] is Map
          ? AskUserQuestionResponse.fromJson(
              Map<String, dynamic>.from(
                json['submittedAnswers'] as Map<dynamic, dynamic>,
              ),
            )
          : null,
      currentQuestionIndex: json['currentQuestionIndex'] as int?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'type': type.name,
      'agentTurnId': agentTurnId,
      if (stepId != null) 'stepId': stepId,
      if ((traceTurnId ?? '').isNotEmpty) 'traceTurnId': traceTurnId,
      'status': status.name,
      'questions': questions.map((item) => item.toJson()).toList(growable: false),
      if (submittedAnswers != null) 'submittedAnswers': submittedAnswers!.toJson(),
      if (currentQuestionIndex != null) 'currentQuestionIndex': currentQuestionIndex,
    };
  }
}
