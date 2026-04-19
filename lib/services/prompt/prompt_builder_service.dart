import 'prompt_catalog.dart';
import 'prompt_locale.dart';
import 'prompt_runtime_context_builder.dart';
import 'prompt_stage.dart';

class PromptBuilderService {
  const PromptBuilderService({
    PromptCatalog catalog = const PromptCatalog(),
    PromptRuntimeContextBuilder runtimeContextBuilder =
        const PromptRuntimeContextBuilder(),
  })  : _catalog = catalog,
        _runtimeContextBuilder = runtimeContextBuilder;

  final PromptCatalog _catalog;
  final PromptRuntimeContextBuilder _runtimeContextBuilder;

  String buildSystemPrompt({
    required PromptStage stage,
    PromptLocale locale = PromptLocale.english,
    String? userSystemPrompt,
    List<String> runtimeSections = const [],
  }) {
    final sections = <String>[];
    if (stage != PromptStage.summary) {
      sections.add(_catalog.base(locale));
    }
    sections.add(_catalog.stageDelta(stage, locale));
    sections.addAll(
      _runtimeContextBuilder.buildRuntimeSections(
        locale: locale,
        userSystemPrompt: userSystemPrompt,
        runtimeSections: runtimeSections,
      ),
    );
    return sections.map((section) => section.trim()).where((s) => s.isNotEmpty).join('\n\n');
  }
}
