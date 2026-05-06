enum ToolExecutionStatus {
  success,
  failure,
}

/// Tool results carry one compact UI summary plus structured result data.
/// Planner-visible semantics must be projected from `data` via transcript
/// replay instead of reading summary text directly.
class ToolResult {
  /// Stable runtime tool name, used for UI rendering, analytics, and
  /// downstream routing decisions after execution completes.
  final String toolName;

  /// Coarse execution outcome consumed by orchestration and presentation
  /// layers to distinguish success paths from failure paths.
  final ToolExecutionStatus status;

  /// Compact user-facing summary shown in the transcript timeline and cards.
  /// This field is only for UI/presentation surfaces.
  final String summary;

  /// Structured tool payload for machine consumption, such as file metadata,
  /// search hits, identifiers, or other typed execution details.
  final Map<String, dynamic> data;

  /// Optional execution policy label captured at execution time when the tool
  /// result needs to remember whether it was auto-run, confirmed, or blocked.
  final String? executionPolicy;

  /// Snapshotted access decision and related policy metadata used by UI and
  /// debugging surfaces to explain why a tool was or was not allowed to run.
  final Map<String, dynamic>? toolAccess;

  /// Stable machine-readable failure code. This should be short and suitable
  /// for retries, branching logic, and error presentation decisions.
  final String? errorMessage;

  const ToolResult({
    required this.toolName,
    required this.status,
    String? summary,
    Map<String, dynamic>? data,
    this.executionPolicy,
    this.toolAccess,
    this.errorMessage,
  })  : summary = summary ?? '',
        data = data ?? const {};

  /// Whether this result belongs to an external-action tool family.
  bool get isOutcomeTool {
    switch (toolName.trim()) {
      case 'create_reminder':
      case 'create_calendar_event':
      case 'share_result':
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

  /// Backward-compatible alias for callers that still expect legacy naming.
  String get displayText => summary;

  /// Backward-compatible alias for callers that still refer to structured
  /// result data as `payload`.
  Map<String, dynamic> get payload => data;

  /// Resolves the effective execution policy, preferring the runtime snapshot
  /// because it reflects the final policy state visible to the user.
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
      summary: json['summary'] as String? ?? '',
      data: json['data'] is Map<String, dynamic>
          ? json['data'] as Map<String, dynamic>
          : json['data'] is Map
              ? Map<String, dynamic>.from(json['data'] as Map<dynamic, dynamic>)
              : const {},
      executionPolicy: json['executionPolicy'] as String? ??
          (json['toolAccess'] is Map
              ? (Map<String, dynamic>.from(json['toolAccess']
                  as Map<dynamic, dynamic>))['executionPolicy'] as String?
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
