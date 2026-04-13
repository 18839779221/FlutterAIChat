import 'dart:convert';

/// Persistent execution status for one tool step inside a turn ledger.
enum ChatTurnStepStatus {
  planned,
  running,
  completed,
  failed,
  skipped,
}

class ChatTurnStep {
  final int? id;
  final int turnId;

  /// Stable order inside the turn ledger.
  final int stepIndex;

  /// Provider-native response id that produced this step batch.
  final String? providerResponseId;

  /// Provider-native call id such as OpenAI tool call ids.
  final String? providerCallId;

  /// Tool name chosen for this step.
  final String toolName;

  /// Normalized tool arguments stored for replay and continuation.
  final Map<String, dynamic> toolArgsJson;
  final ChatTurnStepStatus status;

  /// User-visible and model-facing short summary of the finished step.
  final String? resultSummary;

  /// Structured tool result persisted for later planner/final-answer use.
  final Map<String, dynamic>? resultJson;
  final String? errorCode;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? completedAt;

  ChatTurnStep({
    this.id,
    required this.turnId,
    required this.stepIndex,
    this.providerResponseId,
    this.providerCallId,
    required this.toolName,
    required this.toolArgsJson,
    required this.status,
    this.resultSummary,
    this.resultJson,
    this.errorCode,
    DateTime? createdAt,
    DateTime? updatedAt,
    this.completedAt,
  })  : createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now();

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'turn_id': turnId,
      'step_index': stepIndex,
      'provider_response_id': providerResponseId,
      'provider_call_id': providerCallId,
      'tool_name': toolName,
      'tool_args_json': jsonEncode(toolArgsJson),
      'status': status.name,
      'result_summary': resultSummary,
      'result_json': resultJson == null ? null : jsonEncode(resultJson),
      'error_code': errorCode,
      'created_at': createdAt.millisecondsSinceEpoch,
      'updated_at': updatedAt.millisecondsSinceEpoch,
      'completed_at': completedAt?.millisecondsSinceEpoch,
    };
  }

  factory ChatTurnStep.fromMap(Map<String, dynamic> map) {
    return ChatTurnStep(
      id: map['id'] as int?,
      turnId: map['turn_id'] as int,
      stepIndex: map['step_index'] as int,
      providerResponseId: map['provider_response_id'] as String?,
      providerCallId: map['provider_call_id'] as String?,
      toolName: map['tool_name'] as String? ?? '',
      toolArgsJson: _parseJsonMap(map['tool_args_json']) ?? const {},
      status: ChatTurnStepStatus.values.firstWhere(
        (item) => item.name == map['status'],
        orElse: () => ChatTurnStepStatus.planned,
      ),
      resultSummary: map['result_summary'] as String?,
      resultJson: _parseJsonMap(map['result_json']),
      errorCode: map['error_code'] as String?,
      createdAt: DateTime.fromMillisecondsSinceEpoch(map['created_at'] as int),
      updatedAt: DateTime.fromMillisecondsSinceEpoch(map['updated_at'] as int),
      completedAt: map['completed_at'] == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(map['completed_at'] as int),
    );
  }

  ChatTurnStep copyWith({
    int? id,
    int? turnId,
    int? stepIndex,
    String? providerResponseId,
    String? providerCallId,
    String? toolName,
    Map<String, dynamic>? toolArgsJson,
    ChatTurnStepStatus? status,
    String? resultSummary,
    Map<String, dynamic>? resultJson,
    String? errorCode,
    DateTime? createdAt,
    DateTime? updatedAt,
    DateTime? completedAt,
  }) {
    return ChatTurnStep(
      id: id ?? this.id,
      turnId: turnId ?? this.turnId,
      stepIndex: stepIndex ?? this.stepIndex,
      providerResponseId: providerResponseId ?? this.providerResponseId,
      providerCallId: providerCallId ?? this.providerCallId,
      toolName: toolName ?? this.toolName,
      toolArgsJson: toolArgsJson ?? this.toolArgsJson,
      status: status ?? this.status,
      resultSummary: resultSummary ?? this.resultSummary,
      resultJson: resultJson ?? this.resultJson,
      errorCode: errorCode ?? this.errorCode,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      completedAt: completedAt ?? this.completedAt,
    );
  }

  static Map<String, dynamic>? _parseJsonMap(dynamic value) {
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
