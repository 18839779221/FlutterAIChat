import 'package:ai_chat/models/chat/active_turn_status_presentation.dart';
import 'package:ai_chat/models/chat/assistant_turn_block.dart';
import 'package:ai_chat/models/chat_message.dart';
import 'package:flutter/widgets.dart';

/// Stable description for a single rendered timeline row.
enum ChatTimelineItemType {
  userBubble,
  assistantBlock,
}

/// UI-facing item model used to decouple timeline structure from widget instances.
class ChatTimelineItem {
  /// Stable row identity used to preserve row state across parent rebuilds.
  final String stableKey;

  /// Determines which row renderer path is used.
  final ChatTimelineItemType type;

  /// User message for anchor bubble rows.
  final ChatMessage? userMessage;

  /// Source assistant message that produced the current block when available.
  final ChatMessage? sourceMessage;

  /// All messages from the current segment so tool previews can resolve context.
  final List<ChatMessage> sourceMessages;

  /// Assistant block payload for assistant rows.
  final AssistantTurnBlock? block;

  /// Optional unified running status appended under the active anchor row.
  final ActiveTurnStatusPresentation? activeStatus;

  /// Stable anchor key used to measure inline status visibility in the viewport.
  final Key? statusAnchorKey;

  /// Whether the inline status should stay laid out but visually hidden because
  /// the floating host is currently active.
  final bool hideInlineStatus;

  const ChatTimelineItem({
    required this.stableKey,
    required this.type,
    this.userMessage,
    this.sourceMessage,
    this.sourceMessages = const [],
    this.block,
    this.activeStatus,
    this.statusAnchorKey,
    this.hideInlineStatus = false,
  });
}
