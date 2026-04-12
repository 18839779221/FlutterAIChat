enum ChatTurnStatus {
  running,
  awaitingToolConfirmation,
  completed,
  failed,
  cancelled,
  maxIterationsReached,
}

class ChatTurn {
  final int? id;
  final int groupId;
  final ChatTurnStatus status;
  final String userInput;
  final int iterationCount;
  final int toolCallCount;
  final String? stopReason;
  final String? errorMessage;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? completedAt;

  ChatTurn({
    this.id,
    required this.groupId,
    required this.status,
    required this.userInput,
    this.iterationCount = 0,
    this.toolCallCount = 0,
    this.stopReason,
    this.errorMessage,
    DateTime? createdAt,
    DateTime? updatedAt,
    this.completedAt,
  }) : createdAt = createdAt ?? DateTime.now(),
       updatedAt = updatedAt ?? DateTime.now();

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'group_id': groupId,
      'status': status.name,
      'user_input': userInput,
      'iteration_count': iterationCount,
      'tool_call_count': toolCallCount,
      'stop_reason': stopReason,
      'error_message': errorMessage,
      'created_at': createdAt.millisecondsSinceEpoch,
      'updated_at': updatedAt.millisecondsSinceEpoch,
      'completed_at': completedAt?.millisecondsSinceEpoch,
    };
  }

  factory ChatTurn.fromMap(Map<String, dynamic> map) {
    return ChatTurn(
      id: map['id'] as int?,
      groupId: map['group_id'] as int,
      status: ChatTurnStatus.values.firstWhere(
        (value) => value.name == map['status'],
        orElse: () => ChatTurnStatus.running,
      ),
      userInput: map['user_input'] as String,
      iterationCount: map['iteration_count'] as int? ?? 0,
      toolCallCount: map['tool_call_count'] as int? ?? 0,
      stopReason: map['stop_reason'] as String?,
      errorMessage: map['error_message'] as String?,
      createdAt: DateTime.fromMillisecondsSinceEpoch(map['created_at'] as int),
      updatedAt: DateTime.fromMillisecondsSinceEpoch(map['updated_at'] as int),
      completedAt: map['completed_at'] == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(map['completed_at'] as int),
    );
  }

  ChatTurn copyWith({
    int? id,
    int? groupId,
    ChatTurnStatus? status,
    String? userInput,
    int? iterationCount,
    int? toolCallCount,
    String? stopReason,
    String? errorMessage,
    DateTime? createdAt,
    DateTime? updatedAt,
    DateTime? completedAt,
  }) {
    return ChatTurn(
      id: id ?? this.id,
      groupId: groupId ?? this.groupId,
      status: status ?? this.status,
      userInput: userInput ?? this.userInput,
      iterationCount: iterationCount ?? this.iterationCount,
      toolCallCount: toolCallCount ?? this.toolCallCount,
      stopReason: stopReason ?? this.stopReason,
      errorMessage: errorMessage ?? this.errorMessage,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      completedAt: completedAt ?? this.completedAt,
    );
  }
}
