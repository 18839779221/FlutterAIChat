import 'package:ai_chat/models/interaction/ask_user_question_request.dart';
import 'package:ai_chat/models/interaction/question_card_payload.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AskUserQuestionRequest', () {
    test('can parse questions, multiSelect, and recommended options', () {
      final request = AskUserQuestionRequest.fromJson({
        'questions': [
          {
            'id': 'storage_layer',
            'question': 'Which storage layer should we use?',
            'header': 'Storage',
            'multiSelect': false,
            'options': [
              {
                'label': 'SQLite',
                'description': 'Local relational store',
              },
              {
                'label': 'Isar (Recommended)',
                'description': 'Fast object store',
              },
            ],
          },
        ],
        'agentTurnId': 42,
        'stepId': 7,
        'providerCallId': 'call_123',
      });

      expect(request.agentTurnId, 42);
      expect(request.stepId, 7);
      expect(request.providerCallId, 'call_123');
      expect(request.questions, hasLength(1));
      expect(request.questions.single.id, 'storage_layer');
      expect(request.questions.single.multiSelect, isFalse);
      expect(request.questions.single.options[1].isRecommended, isTrue);
    });
  });

  group('QuestionCardPayload', () {
    test('round-trips prompt payload without losing question metadata', () {
      final payload = QuestionCardPayload(
        type: QuestionCardPayloadType.prompt,
        agentTurnId: 42,
        stepId: 7,
        traceTurnId: 'trace_123',
        status: QuestionCardPayloadStatus.awaitingResponse,
        questions: [
          AskUserQuestionRequest.fromJson({
            'questions': [
              {
                'id': 'storage_layer',
                'question': 'Which storage layer should we use?',
                'header': 'Storage',
                'multiSelect': false,
                'options': [
                  {
                    'label': 'SQLite',
                    'description': 'Local relational store',
                  },
                ],
              },
            ],
            'agentTurnId': 42,
          }).questions.single,
        ],
      );

      final restored = QuestionCardPayload.fromJson(payload.toJson());

      expect(restored.type, QuestionCardPayloadType.prompt);
      expect(restored.agentTurnId, 42);
      expect(restored.stepId, 7);
      expect(restored.traceTurnId, 'trace_123');
      expect(restored.status, QuestionCardPayloadStatus.awaitingResponse);
      expect(restored.questions.single.id, 'storage_layer');
      expect(restored.questions.single.question, 'Which storage layer should we use?');
    });
  });
}
