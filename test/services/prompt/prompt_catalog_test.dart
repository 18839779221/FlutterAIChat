import 'package:ai_chat/services/prompt/prompt_catalog.dart';
import 'package:ai_chat/services/prompt/prompt_locale.dart';
import 'package:ai_chat/services/prompt/prompt_stage.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('PromptCatalog', () {
    const catalog = PromptCatalog();

    test('base prompt keeps critical constraints in both locales', () {
      expect(catalog.base(PromptLocale.english), contains('Do not fabricate'));
      expect(catalog.base(PromptLocale.chinese), contains('不要伪造'));
    });

    test('planner delta prioritizes direct answers before tools', () {
      final plannerEn = catalog.stageDelta(
        PromptStage.planner,
        PromptLocale.english,
      );

      expect(plannerEn, contains('Answer directly'));
      expect(plannerEn, contains('Use a tool only'));
    });

    test('user prompt wrapper keeps user text as additional constraints', () {
      final wrapped = catalog.wrapUserPrompt(
        PromptLocale.english,
        'Answer like a database expert.',
      );

      expect(wrapped, contains('Additional user preferences'));
      expect(wrapped, contains('database expert'));
      expect(wrapped, contains('do not conflict'));
    });
  });
}
