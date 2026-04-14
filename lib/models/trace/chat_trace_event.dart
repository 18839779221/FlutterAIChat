/// Enumerates the explicit lifecycle stages described in the send trace design.
enum ChatTraceStage {
  /// The client just started the send request.
  sendStart,
  /// The send pipeline ended successfully.
  sendDone,
  /// The send pipeline explicitly failed.
  sendFailed,
  /// Context selection completed ahead of the LLM call.
  contextSelected,
  /// The LLM request was sent.
  llmRequestStart,
  /// The LLM emitted the first token.
  llmFirstToken,
  /// The LLM request completed (success or failure).
  llmDone,
  /// The tool execution phase finished.
  toolExecuteDone,
  /// The tool context builder completed.
  toolContextBuilt,
  /// The user explicitly confirmed or cancelled a pending tool invocation.
  toolConfirmationAction,
}

/// Represents the structured status of each stage for logging and observability.
enum ChatTraceStatus {
  /// Stage was just created and will soon run.
  started,
  /// Stage is actively running but not yet resolved.
  inProgress,
  /// Stage finished with a success outcome.
  success,
  /// Stage finished because of a failure.
  failure,
}

/// Data vertex describing a single trace record generated while processing a turn.
class ChatTraceEvent {
  /// The chat turn identifier owning this event.
  final String turnId;

  /// Stage or milestone inside the send trace lifecycle.
  final ChatTraceStage stage;

  /// Success/failure semantics for the current stage.
  final ChatTraceStatus status;

  /// Optional developer-facing summary describing why the event was emitted.
  final String? summary;

  /// Optional structured payload captured during tracing.
  /// Sensitive values are redacted when emitting logs, but the raw map is
  /// retained for diagnostics so callers can inspect fields safely.
  final Map<String, dynamic>? data;

  /// When the event was recorded.
  final DateTime timestamp;

  ChatTraceEvent({
    required this.turnId,
    required this.stage,
    required this.status,
    this.summary,
    Map<String, dynamic>? data,
    DateTime? timestamp,
  })  : data = data == null ? null : Map.unmodifiable(data),
        timestamp = timestamp ?? DateTime.now();
}
