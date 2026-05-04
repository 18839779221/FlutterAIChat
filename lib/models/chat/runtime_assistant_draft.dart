import 'package:ai_chat/models/chat/assistant_turn_block.dart';

/// Runtime-only assistant draft used for stage-scoped streaming UI.
///
/// Drafts never represent persisted transcript truth. They are ephemeral
/// per-turn projections that allow streaming or reasoning stages to render in
/// the timeline without creating premature persisted assistant messages.
class RuntimeAssistantDraft {
  /// Stable turn owner id for timeline grouping.
  final String turnId;

  /// Stage-local draft identity used as the block key.
  final String draftId;

  /// Semantic block type exposed to the timeline.
  final AssistantTurnBlockType blockType;

  /// First visible timestamp for this draft.
  final DateTime createdAt;

  /// Last update timestamp for this draft.
  final DateTime updatedAt;

  /// Optional main text emitted by the stage.
  final String text;

  /// Optional reasoning text emitted by the stage.
  final String? reasoningText;

  /// Optional lightweight payload for stage hints such as reasoning scope.
  final Map<String, dynamic>? payload;

  const RuntimeAssistantDraft({
    required this.turnId,
    required this.draftId,
    required this.blockType,
    required this.createdAt,
    required this.updatedAt,
    this.text = '',
    this.reasoningText,
    this.payload,
  });

  RuntimeAssistantDraft copyWith({
    String? turnId,
    String? draftId,
    AssistantTurnBlockType? blockType,
    DateTime? createdAt,
    DateTime? updatedAt,
    String? text,
    String? reasoningText,
    Map<String, dynamic>? payload,
  }) {
    return RuntimeAssistantDraft(
      turnId: turnId ?? this.turnId,
      draftId: draftId ?? this.draftId,
      blockType: blockType ?? this.blockType,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      text: text ?? this.text,
      reasoningText: reasoningText ?? this.reasoningText,
      payload: payload ?? this.payload,
    );
  }
}
