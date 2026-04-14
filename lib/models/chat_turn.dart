import 'dart:convert';

/// Runtime provider style used for native tool-loop continuation payloads.
enum ChatTurnProviderStyle {
  openaiChatCompletions,
  openaiResponses,
}

enum ChatTurnStatus {
  running,
  awaitingToolConfirmation,
  awaitingUserInteraction,
  completed,
  failed,
  cancelled,
  maxIterationsReached,
}

class ChatTurn {
  final int? id;
  final int groupId;
  final ChatTurnStatus status;

  /// Raw user request that started this turn.
  final String userInput;

  /// Compact turn goal summary used by the planner and final responder.
  final String? goalSummary;
  final int iterationCount;
  final int toolCallCount;

  /// Provider-native API style used for this turn.
  final ChatTurnProviderStyle? providerStyle;

  /// Runtime model name used to create provider requests for this turn.
  final String? modelName;

  /// Provider continuation state such as response ids or message linkage.
  final Map<String, dynamic>? providerStateJson;

  /// Final assistant response persisted after all planned steps finish.
  final String? finalResponseText;
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
    this.goalSummary,
    this.iterationCount = 0,
    this.toolCallCount = 0,
    this.providerStyle,
    this.modelName,
    this.providerStateJson,
    this.finalResponseText,
    this.stopReason,
    this.errorMessage,
    DateTime? createdAt,
    DateTime? updatedAt,
    this.completedAt,
  })  : createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now();

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'group_id': groupId,
      'status': status.name,
      'user_input': userInput,
      'goal_summary': goalSummary,
      'iteration_count': iterationCount,
      'tool_call_count': toolCallCount,
      'provider_style': providerStyle?.name,
      'model_name': modelName,
      'provider_state_json': providerStateJson,
      'final_response_text': finalResponseText,
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
      goalSummary: map['goal_summary'] as String?,
      iterationCount: map['iteration_count'] as int? ?? 0,
      toolCallCount: map['tool_call_count'] as int? ?? 0,
      providerStyle: _parseProviderStyle(map['provider_style']),
      modelName: map['model_name'] as String?,
      providerStateJson: _parseProviderState(map['provider_state_json']),
      finalResponseText: map['final_response_text'] as String?,
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
    String? goalSummary,
    int? iterationCount,
    int? toolCallCount,
    ChatTurnProviderStyle? providerStyle,
    String? modelName,
    Map<String, dynamic>? providerStateJson,
    String? finalResponseText,
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
      goalSummary: goalSummary ?? this.goalSummary,
      iterationCount: iterationCount ?? this.iterationCount,
      toolCallCount: toolCallCount ?? this.toolCallCount,
      providerStyle: providerStyle ?? this.providerStyle,
      modelName: modelName ?? this.modelName,
      providerStateJson: providerStateJson ?? this.providerStateJson,
      finalResponseText: finalResponseText ?? this.finalResponseText,
      stopReason: stopReason ?? this.stopReason,
      errorMessage: errorMessage ?? this.errorMessage,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      completedAt: completedAt ?? this.completedAt,
    );
  }

  static ChatTurnProviderStyle? _parseProviderStyle(dynamic value) {
    if (value is! String || value.trim().isEmpty) {
      return null;
    }
    return ChatTurnProviderStyle.values.firstWhere(
      (item) => item.name == value,
      orElse: () => ChatTurnProviderStyle.openaiResponses,
    );
  }

  static Map<String, dynamic>? _parseProviderState(dynamic value) {
    if (value == null) {
      return null;
    }
    if (value is Map<String, dynamic>) {
      return value;
    }
    if (value is Map) {
      return value.cast<String, dynamic>();
    }
    if (value is String && value.trim().isNotEmpty) {
      final decoded = jsonDecode(value);
      if (decoded is Map<String, dynamic>) {
        return decoded;
      }
      if (decoded is Map) {
        return decoded.cast<String, dynamic>();
      }
    }
    return null;
  }
}
