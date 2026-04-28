import 'package:ai_chat/models/chat/assistant_turn_block.dart';
import 'package:ai_chat/models/chat_message.dart';
import 'package:ai_chat/models/tool/tool_invocation.dart';

/// Projection snapshot used by UI and tests to consume one consistent
/// waiting/workflow/timeline view without re-scanning raw messages.
class ChatTimelineProjection {
  const ChatTimelineProjection({
    this.activeAskUserQuestionMessage,
    this.pendingToolConfirmation,
    this.assistantBlocks = const <AssistantTurnBlock>[],
  });

  /// Latest unresolved ask-user-question prompt, when present.
  final ChatMessage? activeAskUserQuestionMessage;

  /// Latest unresolved confirmation request, when present.
  final ProjectedPendingToolConfirmation? pendingToolConfirmation;

  /// Current assistant blocks built for the visible timeline snapshot.
  final List<AssistantTurnBlock> assistantBlocks;
}

/// Stable pending-confirmation projection exposed outside provider-specific
/// state so UI/tests can consume it directly.
class ProjectedPendingToolConfirmation {
  const ProjectedPendingToolConfirmation({
    required this.message,
    required this.invocation,
  });

  /// Source assistant message that owns the confirmation request.
  final ChatMessage message;

  /// Parsed tool invocation payload used by shared confirmation UI.
  final ToolInvocation invocation;
}
