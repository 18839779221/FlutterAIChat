import 'local_test_provider_selector.dart';

/// Explicit live-test capability matrix for concrete upstream providers.
///
/// Keep this separate from provider selection so adding a new provider mostly
/// becomes "fill one row" instead of editing selector control flow.
const Map<String, HeadlessLiveProviderProfile> headlessLiveProviderMatrix = {
  'aigocode': HeadlessLiveProviderProfile(
    askUserInteraction: StructuredCheckpointExpectation.required,
    toolConfirmation: StructuredCheckpointExpectation.required,
  ),
  'minimax-openai': HeadlessLiveProviderProfile(
    askUserInteraction: StructuredCheckpointExpectation.required,
    toolConfirmation: StructuredCheckpointExpectation.required,
  ),
  'deepseek-openai': HeadlessLiveProviderProfile(
    askUserInteraction: StructuredCheckpointExpectation.required,
    toolConfirmation: StructuredCheckpointExpectation.required,
  ),
  'minimax-anthropic': HeadlessLiveProviderProfile(
    askUserInteraction: StructuredCheckpointExpectation.opportunistic,
    toolConfirmation: StructuredCheckpointExpectation.opportunistic,
  ),
  'deepseek-anthropic': HeadlessLiveProviderProfile(
    askUserInteraction: StructuredCheckpointExpectation.required,
    toolConfirmation: StructuredCheckpointExpectation.opportunistic,
  ),
};
