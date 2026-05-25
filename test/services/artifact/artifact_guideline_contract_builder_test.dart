import 'package:ai_chat/services/artifact/artifact_guideline_contract_builder.dart';
import 'package:ai_chat/theme/app_theme_spec.dart';
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
  });
}
