import 'package:ai_chat/models/response/message_content_type.dart';

/// Standardized phase consumed by presentation-layer renderers.
enum ToolPresentationEventPhase {
  proposed,
  awaitingConfirmation,
  running,
  result,
}

/// Stable UI-facing event emitted from tool transcript facts.
///
/// This model deliberately lives between execution facts and concrete widgets:
/// renderers may consume all phases or only a subset without rescanning raw
/// message payloads.
class ToolPresentationEvent {
  /// Registered tool name that owns this event.
  final String toolName;

  /// Coarse presentation phase for renderer-side selection logic.
  final ToolPresentationEventPhase phase;

  /// Turn identity that groups related events in one assistant turn.
  final String turnId;

  /// Stable execution step identity when available.
  final String? stepId;

  /// Provider/runtime call identity when available.
  final String? providerCallId;

  /// Timeline message content type that produced this event.
  final MessageContentType sourceContentType;

  /// Source assistant message id when the event was reconstructed from one.
  final int? sourceMessageId;

  /// When the event became visible in the transcript timeline.
  final DateTime timestamp;

  /// Structured phase payload copied from the underlying transcript fact.
  final Map<String, dynamic> data;

  const ToolPresentationEvent({
    required this.toolName,
    required this.phase,
    required this.turnId,
    required this.sourceContentType,
    required this.timestamp,
    this.stepId,
    this.providerCallId,
    this.sourceMessageId,
    this.data = const <String, dynamic>{},
  });
}
