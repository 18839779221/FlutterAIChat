enum ToolExecutionStatus {
  success,
  failure,
}

class ToolResult {
  final String toolName;
  final ToolExecutionStatus status;
  final String summary;
  final Map<String, dynamic> data;
  final String? errorMessage;

  const ToolResult({
    required this.toolName,
    required this.status,
    String? summary,
    Map<String, dynamic>? data,
    this.errorMessage,
    String? displayText,
    Map<String, dynamic>? payload,
  })  : summary = summary ?? displayText ?? '',
        data = data ?? payload ?? const {};

  String get displayText => summary;

  Map<String, dynamic> get payload => data;

  Map<String, dynamic> toJson() {
    return {
      'toolName': toolName,
      'status': status.name,
      'summary': summary,
      'data': data,
      'errorMessage': errorMessage,
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
      summary: (json['summary'] ?? json['displayText']) as String? ?? '',
      data: json['data'] is Map<String, dynamic>
          ? json['data'] as Map<String, dynamic>
          : json['data'] is Map
              ? Map<String, dynamic>.from(
                  json['data'] as Map<dynamic, dynamic>)
              : json['payload'] is Map<String, dynamic>
                  ? json['payload'] as Map<String, dynamic>
                  : json['payload'] is Map
              ? Map<String, dynamic>.from(
                  json['payload'] as Map<dynamic, dynamic>)
              : const {},
      errorMessage: json['errorMessage'] as String?,
    );
  }
}
