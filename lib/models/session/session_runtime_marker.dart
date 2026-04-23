/// Stores the latest runtime-only date injected into a session/group context.
class SessionRuntimeMarker {
  final int? id;

  /// Session/group this runtime marker belongs to.
  final int groupId;

  /// Latest injected date in yyyy-MM-dd form for cross-day comparison.
  final String lastInjectedDate;

  final DateTime updatedAt;

  SessionRuntimeMarker({
    this.id,
    required this.groupId,
    required this.lastInjectedDate,
    DateTime? updatedAt,
  }) : updatedAt = updatedAt ?? DateTime.now();

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'group_id': groupId,
      'last_injected_date': lastInjectedDate,
      'updated_at': updatedAt.millisecondsSinceEpoch,
    };
  }

  factory SessionRuntimeMarker.fromMap(Map<String, dynamic> map) {
    return SessionRuntimeMarker(
      id: map['id'] as int?,
      groupId: map['group_id'] as int,
      lastInjectedDate: map['last_injected_date'] as String? ?? '',
      updatedAt: DateTime.fromMillisecondsSinceEpoch(map['updated_at'] as int),
    );
  }

  SessionRuntimeMarker copyWith({
    int? id,
    int? groupId,
    String? lastInjectedDate,
    DateTime? updatedAt,
  }) {
    return SessionRuntimeMarker(
      id: id ?? this.id,
      groupId: groupId ?? this.groupId,
      lastInjectedDate: lastInjectedDate ?? this.lastInjectedDate,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
