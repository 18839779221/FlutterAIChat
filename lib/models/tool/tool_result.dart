enum ToolExecutionStatus {
  success,
  failure,
}

class ToolResult {
  final String toolName;
  final ToolExecutionStatus status;
  final String displayText;
  final Map<String, dynamic> payload;

  const ToolResult({
    required this.toolName,
    required this.status,
    required this.displayText,
    this.payload = const {},
  });

  Map<String, dynamic> toJson() {
    return {
      'toolName': toolName,
      'status': status.name,
      'displayText': displayText,
      'payload': payload,
    };
  }

  factory ToolResult.fromJson(Map<String, dynamic> json) {
    final statusName =
        json['status'] as String? ?? ToolExecutionStatus.success.name;
    final matchedStatus =
        ToolExecutionStatus.values.where((value) => value.name == statusName);

    return ToolResult(
      toolName: json['toolName'] as String? ?? '',
      status: matchedStatus.isEmpty
          ? ToolExecutionStatus.success
          : matchedStatus.first,
      displayText: json['displayText'] as String? ?? '',
      payload: json['payload'] is Map<String, dynamic>
          ? json['payload'] as Map<String, dynamic>
          : json['payload'] is Map
              ? Map<String, dynamic>.from(
                  json['payload'] as Map<dynamic, dynamic>)
              : const {},
    );
  }
}
