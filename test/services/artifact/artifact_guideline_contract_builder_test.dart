import 'package:ai_chat/services/artifact/artifact_guideline_contract_builder.dart';
import 'package:ai_chat/services/artifact/artifact_theme_token_mapper.dart';
import 'package:ai_chat/theme/app_theme_spec.dart';
import 'package:ai_chat/widgets/chat_blocks/artifact_preview_surface.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ArtifactGuidelineContractBuilder', () {
    test('builds JSON-friendly contract with host markup contract', () {
      final contract = const ArtifactGuidelineContractBuilder().build(
        spec: AppThemeSpec.claude(),
      );

      expect(contract.usage, isNotEmpty);
      expect(contract.hostMarkupContract, contains(':root'));
      expect(contract.hostMarkupContract, contains('html, body'));
      expect(contract.hostMarkupContract, contains('#artifact-root'));
      expect(contract.hostMarkupContract, contains('--app-artifact-chart-1'));
      expect(contract.layoutConstraints, isNotEmpty);
      expect(contract.renderingRules, isNotEmpty);
      expect(contract.hostMarkupContract, isNot(contains('/private/var')));
    });

    test('reuses the same host base styles as the preview wrapper', () {
      final spec = AppThemeSpec.claude();
      final contract = const ArtifactGuidelineContractBuilder().build(
        spec: spec,
      );

      final previewStyles = buildArtifactPreviewHostStyles(
        ArtifactThemeTokenMapper.fromSpec(spec),
      );

      expect(
        _normalizeWhitespace(contract.hostMarkupContract),
        contains(_normalizeWhitespace(_extractStyleBody(previewStyles))),
      );
    });
  });
}

String _extractStyleBody(String styleBlock) {
  return styleBlock
      .replaceFirst('<style>', '')
      .replaceFirst('</style>', '')
      .trim();
}

String _normalizeWhitespace(String value) {
  return value.replaceAll(RegExp(r'\s+'), ' ').trim();
}
