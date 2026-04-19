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
      expect(result, contains('speaking directly to the user'));
    });

    test('planner prompt is action-selection oriented instead of tool-first', () {
      final result = service.buildSystemPrompt(
        stage: PromptStage.planner,
      );

      expect(result, contains('selecting the next best action'));
      expect(result, contains('Answer directly'));
      expect(result, contains('Use a tool only'));
    });

    test('summary prompt stays lightweight and omits the main base block', () {
      final result = service.buildSystemPrompt(
        stage: PromptStage.summary,
        locale: PromptLocale.english,
      );

      expect(result, contains('Summarize and compress'));
      expect(result, isNot(contains("solve the user's problem")));
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
