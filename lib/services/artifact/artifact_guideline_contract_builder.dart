import '../../models/artifact/artifact_guideline_contract.dart';
import '../../theme/app_theme_spec.dart';
import 'artifact_theme_token_mapper.dart';

/// Builds the model-facing guideline contract for explanatory artifacts.
class ArtifactGuidelineContractBuilder {
  const ArtifactGuidelineContractBuilder();

  ArtifactGuidelineContract build({
    required AppThemeSpec spec,
  }) {
    final variables = ArtifactThemeTokenMapper.fromSpec(spec);
    final rootLines = variables.entries
        .map((entry) => '        ${entry.key}: ${entry.value};')
        .join('\n');

    return ArtifactGuidelineContract(
      usage:
          'This result is the required authoring contract for the next explanatory create_artifact call. Apply it directly in the generated source. Your source is authored for placement inside #artifact-root. Before writing source, verify all of the following: author only content for #artifact-root; do not generate a full page document structure; do not use html or body as the primary authored surface; do not declare a replacement root theme token set.',
      hostMarkupContract: '''
<!--
The app runtime already provides the outer host wrapper.
Do not generate a full page document structure.
Author only the content rendered inside #artifact-root.
-->
<style>
  :root {
$rootLines
  }

  * {
    box-sizing: border-box;
  }

  #artifact-root {
    width: 100%;
    background: var(--app-artifact-page-bg);
    color: var(--app-artifact-text-primary);
    font-family: var(--app-artifact-font-ui);
  }
</style>
<div id="artifact-root">
  <!-- model-authored artifact content goes here -->
</div>
''',
      layoutConstraints: const <String>[
        'Keep the artifact flow-driven and avoid giant fixed-height outer wrappers.',
        'Prefer one-screen inline content and avoid exceeding two screens unless the user explicitly asks for more.',
        'Avoid horizontal scrolling on phone-sized layouts.',
        'Use the host-provided background and surface token references instead of assuming white or transparent backgrounds.',
      ],
      renderingRules: const <String>[
        'Use the provided token references when theme-aware values are needed.',
        'Do not hardcode theme-specific colors, spacing scales, or border colors when a host token exists.',
        'Use chart token references for data series, axis, grid, and highlight treatments.',
        'Keep the artifact as an explanation-enhancement surface inside the reply rather than a standalone product page.',
        'Do not rely on remote CSS, external scripts, or network requests.',
      ],
    );
  }
}
