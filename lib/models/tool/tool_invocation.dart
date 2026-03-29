enum ToolInvocationStatus {
  proposed,
  awaitingConfirmation,
  running,
  cancelled,
}

class ToolInvocation {
  final String toolName;
  final Map<String, dynamic> arguments;
  final ToolInvocationStatus status;
  final String summary;
  final bool requiresConfirmation;
  final String? decisionReason;

  const ToolInvocation({
    required this.toolName,
    required this.arguments,
    required this.status,
    required this.summary,
    required this.requiresConfirmation,
    this.decisionReason,
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
    };
  }
}
