import 'package:ai_chat/models/chat/assistant_turn_block.dart';
import 'package:ai_chat/models/chat_message.dart';

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

  /// Optional latest-running tail text appended under the last row.
  final String? runningTailText;

  const ChatTimelineItem({
    required this.stableKey,
    required this.type,
    this.userMessage,
    this.sourceMessage,
    this.sourceMessages = const [],
    this.block,
    this.runningTailText,
  });
}
