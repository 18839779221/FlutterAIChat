import 'package:ai_chat/services/prompt/prompt_builder_service.dart';
import 'package:ai_chat/services/prompt/prompt_locale.dart';
import 'package:ai_chat/services/prompt/prompt_stage.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('PromptBuilderService', () {
    const service = PromptBuilderService();

    test('defaults to english chat prompt with base constraints', () {
      final result = service.buildSystemPrompt(
        stage: PromptStage.chat,
      );

      expect(result, contains("solve the user's problem"));
      expect(result, contains('Do not fabricate'));
      expect(
        result,
        contains(
          'When given an instruction that requires creating or modifying external artifacts',
        ),
      );
      expect(result, contains('Report outcomes faithfully'));
      expect(
          result, contains('Do not imply that an external action succeeded'));
      expect(result, isNot(contains('run the test')));
    });

    test('planner prompt is action-selection oriented instead of tool-first',
        () {
      final result = service.buildSystemPrompt(
        stage: PromptStage.planner,
      );

      expect(result, contains('selecting the next best action'));
      expect(result, contains('Answer directly'));
      expect(result, contains('Use a tool only'));
      expect(
        result,
        contains(
          'If the user request requires a real external action, do not end the turn with text that merely sounds like the action already happened.',
        ),
      );
    });

    test('summary prompt stays lightweight and omits the main base block', () {
      final result = service.buildSystemPrompt(
        stage: PromptStage.summary,
        locale: PromptLocale.english,
      );

      expect(result, contains('Summarize and compress'));
      expect(result, isNot(contains("solve the user's problem")));
      expect(result, isNot(contains('Report outcomes faithfully')));
      expect(result, isNot(contains('To edit existing files use Edit')));
    });

    test('final answer prompt keeps faithful reporting constraints', () {
      final result = service.buildSystemPrompt(
        stage: PromptStage.finalAnswer,
      );

      expect(result, contains('Report outcomes faithfully'));
      expect(
        result,
        contains(
            'Do not imply that unexecuted or unverified work has already been completed.'),
      );
      expect(result, isNot(contains('execute the script')));
    });

    test('user system prompt is wrapped as runtime constraints', () {
      final result = service.buildSystemPrompt(
        stage: PromptStage.chat,
        userSystemPrompt: 'Use bullet points when helpful.',
      );

      expect(result, contains('Additional user preferences'));
      expect(result, contains('Use bullet points when helpful.'));
    });
  });
}
