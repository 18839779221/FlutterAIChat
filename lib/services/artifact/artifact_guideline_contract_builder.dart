import '../../models/artifact/artifact_guideline_contract.dart';
import '../../theme/app_theme_spec.dart';
import 'artifact_host_style_builder.dart';
import 'artifact_theme_token_mapper.dart';

/// Builds the model-facing guideline contract for explanatory artifacts.
class ArtifactGuidelineContractBuilder {
  const ArtifactGuidelineContractBuilder();

  ArtifactGuidelineContract build({
    required AppThemeSpec spec,
  }) {
    final variables = ArtifactThemeTokenMapper.fromSpec(spec);
    final hostStyles = const ArtifactHostStyleBuilder().buildStyleBlock(
      variables,
    );

    return ArtifactGuidelineContract(
      usage:
          'This result is the required authoring contract for the next explanatory create_artifact call. Apply it directly in the generated source. Your source is authored for placement inside #artifact-root. Before writing source, verify all of the following: author only content for #artifact-root; do not generate a full page document structure; do not use html or body as the primary authored surface; do not declare a replacement root theme token set.',
      hostMarkupContract: '''
<!--
This is the host wrapper environment your artifact will run inside.
The app runtime provides this outer structure automatically.
You should author only the content that goes inside #artifact-root.
Do not generate a full page document structure yourself.
-->
<html>
  <head>
${_indentBlock(hostStyles, spaces: 4)}
  </head>
  <body>
    <div id="artifact-root">
      <!-- model-authored artifact content goes here -->
    </div>
  </body>
</html>
''',
      layoutConstraints: const <String>[
        'Keep the artifact flow-driven and avoid giant fixed-height outer wrappers.',
        'Prefer one-screen inline content and avoid exceeding two screens unless the user explicitly asks for more.',
        'For charts, keep the height within one screen to ensure good display quality. Avoid excessively tall charts that require excessive scrolling.',
        'Avoid horizontal scrolling on phone-sized layouts.',
        'Use the host-provided background and surface token references instead of assuming white or transparent backgrounds.',
        'Use host spacing tokens for consistent layout: var(--app-artifact-space-4) for section gaps, var(--app-artifact-space-5) for horizontal padding, var(--app-artifact-space-2) for tight spacing.',
        'Ensure adequate content density: avoid cramming elements too closely together.',
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

String _indentBlock(String value, {required int spaces}) {
  final prefix = ' ' * spaces;
  return value.split('\n').map((line) => '$prefix$line').join('\n');
}
