import 'prompt_catalog.dart';
import 'prompt_locale.dart';

class PromptRuntimeContextBuilder {
  const PromptRuntimeContextBuilder({
    PromptCatalog catalog = const PromptCatalog(),
  }) : _catalog = catalog;

  final PromptCatalog _catalog;

  List<String> buildRuntimeSections({
    required PromptLocale locale,
    String? userSystemPrompt,
    List<String> runtimeSections = const [],
  }) {
    final sections = <String>[];
    final wrappedUserPrompt = _catalog.wrapUserPrompt(
      locale,
      userSystemPrompt ?? '',
    );
    if (wrappedUserPrompt.isNotEmpty) {
      sections.add(wrappedUserPrompt);
    }
    for (final section in runtimeSections) {
      final trimmed = section.trim();
      if (trimmed.isNotEmpty) {
        sections.add(trimmed);
      }
    }
    return sections;
  }
}
