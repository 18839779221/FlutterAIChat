enum ToolExecutionStatus {
  success,
  failure,
}

class ToolResult {
  final String toolName;
  final ToolExecutionStatus status;
  final String summary;
  final Map<String, dynamic> data;
  final String? executionPolicy;
  final Map<String, dynamic>? toolAccess;
  final String? errorMessage;

  const ToolResult({
    required this.toolName,
    required this.status,
    String? summary,
    Map<String, dynamic>? data,
    this.executionPolicy,
    this.toolAccess,
    this.errorMessage,
    String? displayText,
    Map<String, dynamic>? payload,
  })  : summary = summary ?? displayText ?? '',
        data = data ?? payload ?? const {};

  String get displayText => summary;

  Map<String, dynamic> get payload => data;

  /// Whether this result belongs to an external-action tool family.
  bool get isOutcomeTool {
    switch (toolName.trim()) {
      case 'create_reminder':
      case 'create_calendar_event':
      case 'share_result':
      case 'save_note':
      case 'Write':
      case 'Edit':
        return true;
      default:
        return false;
    }
  }

  /// Whether the failure should be promoted to a richer exception card.
  bool get shouldShowExceptionCard {
    if (status != ToolExecutionStatus.failure) {
      return false;
    }

    if (isOutcomeTool) {
      return true;
    }

    switch ((errorMessage ?? '').trim()) {
      case 'missing_api_key':
      case 'invalid_due_at':
      case 'invalid_start_at':
      case 'invalid_end_at':
      case 'share_unavailable':
      case 'share_failed':
      case 'unsupported_tool':
      case 'tool_blocked':
        return true;
      default:
        return false;
    }
  }

  /// Compact localized status label for tool result surfaces.
  String get statusLabel {
    return status == ToolExecutionStatus.success ? '完成' : '失败';
  }

  String? get resolvedExecutionPolicy {
    final snapshotPolicy = toolAccess?['executionPolicy'];
    if (snapshotPolicy is String && snapshotPolicy.trim().isNotEmpty) {
      return snapshotPolicy.trim();
    }
    if (executionPolicy == null || executionPolicy!.trim().isEmpty) {
      return null;
    }
    return executionPolicy!.trim();
  }

  Map<String, dynamic> toJson() {
    return {
      'toolName': toolName,
      'status': status.name,
      'summary': summary,
      'data': data,
      if (resolvedExecutionPolicy != null && toolAccess == null)
        'executionPolicy': resolvedExecutionPolicy,
      if (toolAccess != null) 'toolAccess': toolAccess,
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
      executionPolicy: json['executionPolicy'] as String? ??
          (json['toolAccess'] is Map
              ? (Map<String, dynamic>.from(
                  json['toolAccess'] as Map<dynamic, dynamic>))['executionPolicy']
                  as String?
              : null),
      toolAccess: json['toolAccess'] is Map<String, dynamic>
          ? json['toolAccess'] as Map<String, dynamic>
          : json['toolAccess'] is Map
              ? Map<String, dynamic>.from(
                  json['toolAccess'] as Map<dynamic, dynamic>)
              : null,
      errorMessage: json['errorMessage'] as String?,
    );
  }
}
