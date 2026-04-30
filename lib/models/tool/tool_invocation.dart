enum ToolInvocationStatus {
  proposed,
  awaitingConfirmation,
  running,
  cancelled,
}

class ToolInvocation {
  /// Registered tool name used to route execution on the client.
  final String toolName;

  /// Structured arguments prepared for this specific tool execution.
  final Map<String, dynamic> arguments;

  /// Current lifecycle state of the invocation card.
  final ToolInvocationStatus status;

  /// User-facing summary shown in tool cards and confirmation prompts.
  final String summary;

  /// Whether the invocation still requires an explicit user confirmation.
  final bool requiresConfirmation;

  /// Optional explanation describing why the tool was selected.
  final String? decisionReason;

  /// Persistent turn step id used to resume and close the same step after
  /// confirmation.
  final int? stepId;

  /// Provider-native tool call id used to correlate proposed/running/result
  /// events for one logical tool step across transcript and continuation.
  final String? providerCallId;

  const ToolInvocation({
    required this.toolName,
    required this.arguments,
    required this.status,
    required this.summary,
    required this.requiresConfirmation,
    this.decisionReason,
    this.stepId,
    this.providerCallId,
  });

  factory ToolInvocation.fromJson(Map<String, dynamic> json) {
    final toolName = (json['toolName'] as String? ?? '').trim();
    if (toolName.isEmpty) {
      throw const FormatException('toolName is required');
    }

    final rawArguments = json['arguments'];
    if (rawArguments != null && rawArguments is! Map) {
      throw const FormatException('arguments must be a json object');
    }

    final statusName = (json['status'] as String? ?? '').trim();
    final status = ToolInvocationStatus.values.where(
      (value) => value.name == statusName,
    );
    if (status.isEmpty) {
      throw FormatException('invalid tool invocation status: $statusName');
    }

    return ToolInvocation(
      toolName: toolName,
      arguments: rawArguments == null
          ? const {}
          : Map<String, dynamic>.from(rawArguments as Map<dynamic, dynamic>),
      status: status.first,
      summary: json['summary'] as String? ?? '',
      requiresConfirmation: json['requiresConfirmation'] as bool? ?? false,
      decisionReason: json['decisionReason'] as String?,
      stepId: json['stepId'] as int?,
      providerCallId: (json['providerCallId'] as String?)?.trim(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'toolName': toolName,
      'arguments': arguments,
      'status': status.name,
      'summary': summary,
      'requiresConfirmation': requiresConfirmation,
      if (decisionReason != null) 'decisionReason': decisionReason,
      if (stepId != null) 'stepId': stepId,
      if ((providerCallId ?? '').trim().isNotEmpty)
        'providerCallId': providerCallId!.trim(),
    };
  }

  ToolInvocation copyWith({
    String? toolName,
    Map<String, dynamic>? arguments,
    ToolInvocationStatus? status,
    String? summary,
    bool? requiresConfirmation,
    String? decisionReason,
    int? stepId,
    String? providerCallId,
  }) {
    return ToolInvocation(
      toolName: toolName ?? this.toolName,
      arguments: arguments ?? this.arguments,
      status: status ?? this.status,
      summary: summary ?? this.summary,
      requiresConfirmation: requiresConfirmation ?? this.requiresConfirmation,
      decisionReason: decisionReason ?? this.decisionReason,
      stepId: stepId ?? this.stepId,
      providerCallId: providerCallId ?? this.providerCallId,
    );
  }
}
