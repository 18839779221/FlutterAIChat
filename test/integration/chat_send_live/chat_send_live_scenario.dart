import 'package:ai_chat/models/chat_turn.dart';

class ProviderMatrixTarget {
  /// Protocol style expected for this matrix target.
  final ChatTurnProviderStyle style;
  final bool enabledByDefault;

  const ProviderMatrixTarget({
    required this.style,
    this.enabledByDefault = true,
  });
}

class ScenarioCase {
  final String id;
  final String title;
  final String userMessage;
  final List<ProviderMatrixTarget> providerTargets;

  const ScenarioCase({
    required this.id,
    required this.title,
    required this.userMessage,
    this.providerTargets = const [],
  });
}
