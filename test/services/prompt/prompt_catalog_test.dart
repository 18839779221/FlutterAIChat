import 'package:ai_chat/services/prompt/prompt_catalog.dart';
import 'package:ai_chat/services/prompt/prompt_locale.dart';
import 'package:ai_chat/services/prompt/prompt_stage.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('PromptCatalog', () {
    const catalog = PromptCatalog();

    test(
        'identity and faithful-reporting sections keep critical constraints in both locales',
        () {
      expect(
        catalog.identityAndCoreRules(PromptLocale.english),
        contains('Do not fabricate'),
      );
      expect(
        catalog.identityAndCoreRules(PromptLocale.chinese),
        contains('不要伪造'),
      );
      expect(
        catalog.faithfulReporting(PromptLocale.english),
        contains('Report outcomes faithfully'),
      );
      expect(
        catalog.faithfulReporting(PromptLocale.chinese),
        contains('忠实汇报结果'),
      );
    });

    test('planner delta prioritizes direct answers before tools', () {
      final plannerEn = catalog.stageDelta(
        PromptStage.planner,
        PromptLocale.english,
      );

      expect(plannerEn, contains('Answer directly'));
      expect(plannerEn, contains('Use a tool only'));
      expect(plannerEn, contains('Do not confuse a plan with completed work'));
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

    test('tool-use section prefers dedicated file tools', () {
      final tools = catalog.usingTools(PromptLocale.english);

      expect(tools, contains('To read files use Read'));
      expect(tools, contains('To edit existing files use Edit'));
      expect(tools,
          contains('To create files or rewrite an entire file use Write'));
    });
  });
}
