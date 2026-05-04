/// Kind of runtime-only streamed content exposed to the UI.
enum RuntimeStreamEntryKind {
  assistantText,
  reasoning,
  toolCallArguments,
}

/// Runtime-only streamed entry used by projection layers.
///
/// This model carries transient streaming snapshots only. It is not persisted
/// and does not represent transcript truth.
class RuntimeStreamEntry {
  /// Assistant turn or runtime turn that owns this entry.
  final String turnId;

  /// Stable runtime entry identity within one turn.
  final String entryId;

  /// Stream kind used by projection consumers to route the entry.
  final RuntimeStreamEntryKind kind;

  /// Provider call identity when the stream originated from a tool call.
  final String? providerCallId;

  /// Tool name for tool-call argument streams.
  final String? toolName;

  /// When this entry first became visible.
  final DateTime createdAt;

  /// When this entry was last updated.
  final DateTime updatedAt;

  /// Current accumulated streamed text snapshot.
  final String text;

  /// Optional runtime metadata preserved for renderer-specific consumers.
  final Map<String, dynamic>? payload;

  const RuntimeStreamEntry({
    required this.turnId,
    required this.entryId,
    required this.kind,
    required this.createdAt,
    required this.updatedAt,
    this.providerCallId,
    this.toolName,
    this.text = '',
    this.payload,
  });

  RuntimeStreamEntry copyWith({
    String? turnId,
    String? entryId,
    RuntimeStreamEntryKind? kind,
    String? providerCallId,
    String? toolName,
    DateTime? createdAt,
    DateTime? updatedAt,
    String? text,
    Map<String, dynamic>? payload,
  }) {
    return RuntimeStreamEntry(
      turnId: turnId ?? this.turnId,
      entryId: entryId ?? this.entryId,
      kind: kind ?? this.kind,
      providerCallId: providerCallId ?? this.providerCallId,
      toolName: toolName ?? this.toolName,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      text: text ?? this.text,
      payload: payload ?? this.payload,
    );
  }
}
