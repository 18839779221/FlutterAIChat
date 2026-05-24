import 'package:flutter_test/flutter_test.dart';

import 'headless_live_provider_matrix.dart';
import 'local_test_provider_selector.dart';

void main() {
  test('matrix explicitly includes default responses provider profile', () {
    final profile = headlessLiveProviderMatrix['aigocode'];
    expect(profile, isNotNull);
    expect(
      profile!.askUserInteraction,
      StructuredCheckpointExpectation.required,
    );
    expect(
      profile.toolConfirmation,
      StructuredCheckpointExpectation.required,
    );
  });

  test('matrix explicitly includes preferred chat completions provider profile',
      () {
    final profile = headlessLiveProviderMatrix['minimax-openai'];
    expect(profile, isNotNull);
    expect(
      profile!.askUserInteraction,
      StructuredCheckpointExpectation.required,
    );
    expect(
      profile.toolConfirmation,
      StructuredCheckpointExpectation.required,
    );
  });

  test('matrix marks deepseek anthropic as required ask-user provider', () {
    final profile = headlessLiveProviderMatrix['deepseek-anthropic'];
    expect(profile, isNotNull);
    expect(
      profile!.askUserInteraction,
      StructuredCheckpointExpectation.required,
    );
    expect(
      profile.toolConfirmation,
      StructuredCheckpointExpectation.opportunistic,
    );
  });

  test('matrix marks minimax anthropic checkpoints as opportunistic', () {
    final profile = headlessLiveProviderMatrix['minimax-anthropic'];
    expect(profile, isNotNull);
    expect(
      profile!.askUserInteraction,
      StructuredCheckpointExpectation.opportunistic,
    );
    expect(
      profile.toolConfirmation,
      StructuredCheckpointExpectation.opportunistic,
    );
  });
}
