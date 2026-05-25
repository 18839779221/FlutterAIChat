import 'package:ai_chat/services/artifact/artifact_theme_token_mapper.dart';
import 'package:ai_chat/theme/app_theme_spec.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ArtifactThemeTokenMapper', () {
    test('maps app theme spec to stable artifact css variables', () {
      final variables = ArtifactThemeTokenMapper.fromSpec(
        AppThemeSpec.claude(),
      );

      expect(variables['--app-artifact-page-bg'], isNotEmpty);
      expect(variables['--app-artifact-surface'], isNotEmpty);
      expect(variables['--app-artifact-surface-muted'], isNotEmpty);
      expect(variables['--app-artifact-text-primary'], isNotEmpty);
      expect(variables['--app-artifact-text-secondary'], isNotEmpty);
      expect(variables['--app-artifact-border-subtle'], isNotEmpty);
      expect(variables['--app-artifact-accent'], isNotEmpty);
      expect(variables['--app-artifact-chart-1'], isNotEmpty);
      expect(variables['--app-artifact-chart-grid'], isNotEmpty);
      expect(variables['--app-artifact-space-4'], '12px');
      expect(variables['--app-artifact-radius-md'], '12px');
      expect(variables['--app-artifact-font-ui'], isNotEmpty);
      expect(variables['--app-artifact-font-code'], isNotEmpty);
      expect(variables['--app-artifact-shadow-soft'], isNotEmpty);
      expect(
        variables.containsKey('--semantic.surfaces.pageBackground'),
        isFalse,
      );
    });
  });
}
