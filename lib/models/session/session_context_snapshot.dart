/// Persisted summary snapshot for one session/group context window.
class SessionContextSnapshot {
  final int? id;

  /// Session/group this snapshot belongs to.
  final int groupId;

  /// Summary text that replaces older history in model-visible context.
  final String summaryText;

  /// Last turn already covered by this snapshot summary.
  final int coveredUntilTurnId;

  /// Estimated token cost of the snapshot text itself.
  final int estimatedTokens;
  final DateTime createdAt;
  final DateTime updatedAt;

  SessionContextSnapshot({
    this.id,
    required this.groupId,
    required this.summaryText,
    required this.coveredUntilTurnId,
    this.estimatedTokens = 0,
    DateTime? createdAt,
    DateTime? updatedAt,
  })  : createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now();

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'group_id': groupId,
      'summary_text': summaryText,
      'covered_until_turn_id': coveredUntilTurnId,
      'estimated_tokens': estimatedTokens,
      'created_at': createdAt.millisecondsSinceEpoch,
      'updated_at': updatedAt.millisecondsSinceEpoch,
    };
  }

  factory SessionContextSnapshot.fromMap(Map<String, dynamic> map) {
    return SessionContextSnapshot(
      id: map['id'] as int?,
      groupId: map['group_id'] as int,
      summaryText: map['summary_text'] as String? ?? '',
      coveredUntilTurnId: map['covered_until_turn_id'] as int? ?? 0,
      estimatedTokens: map['estimated_tokens'] as int? ?? 0,
      createdAt: DateTime.fromMillisecondsSinceEpoch(map['created_at'] as int),
      updatedAt: DateTime.fromMillisecondsSinceEpoch(map['updated_at'] as int),
    );
  }

  SessionContextSnapshot copyWith({
    int? id,
    int? groupId,
    String? summaryText,
    int? coveredUntilTurnId,
    int? estimatedTokens,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return SessionContextSnapshot(
      id: id ?? this.id,
      groupId: groupId ?? this.groupId,
      summaryText: summaryText ?? this.summaryText,
      coveredUntilTurnId: coveredUntilTurnId ?? this.coveredUntilTurnId,
      estimatedTokens: estimatedTokens ?? this.estimatedTokens,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
