import 'package:ai_chat/models/chat/active_turn_status_presentation.dart';
import 'package:ai_chat/widgets/chat_blocks/unified_turn_status_bar.dart';
import 'package:flutter/material.dart';

class LatestMessageRunningStatusTail extends StatelessWidget {
  const LatestMessageRunningStatusTail({
    super.key,
    required this.statusText,
  });

  final String statusText;

  @override
  Widget build(BuildContext context) {
    return UnifiedTurnStatusBar(
      status: ActiveTurnStatusPresentation(
        phase: ActiveTurnStatusPhase.planning,
        text: statusText,
        turnId: 'legacy-running-tail',
        sourceKind: ActiveTurnStatusSourceKind.sendPhaseFallback,
        allowFloating: true,
      ),
    );
  }
}
