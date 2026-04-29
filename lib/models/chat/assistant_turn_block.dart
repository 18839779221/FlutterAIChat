import 'package:ai_chat/models/interaction/ask_user_question_request.dart';
import 'package:ai_chat/models/interaction/ask_user_question_response.dart';
import 'package:ai_chat/models/artifact/artifact_turn_projection.dart';
import 'package:ai_chat/models/chat/tool_workflow_step.dart';
import 'package:ai_chat/models/tool/tool_result.dart';

/// Supported block types rendered inside one assistant turn.
enum AssistantTurnBlockType {
  analysis,
  toolWorkflow,
  toolResultSummary,
  artifact,
  structuredOutput,
  finalResponse,
}

/// UI-facing block model used to render one assistant turn in document style.
class AssistantTurnBlock {
  /// Stable block id in the current runtime timeline.
  final String id;

  /// Assistant turn owner id.
  final String turnId;

  /// Semantic block type, never inferred at render time from free text.
  final AssistantTurnBlockType type;

  /// Order within the current assistant turn.
  final int sequence;

  /// When the block first became visible.
  final DateTime createdAt;

  /// Last update time for streaming or workflow refresh.
  final DateTime updatedAt;

  /// Optional status, mainly for workflow-like blocks.
  final String? status;

  /// Optional user-facing title.
  final String? title;

  /// Main body text.
  final String? text;

  /// Provider-returned reasoning/thinking text shown as secondary UI content.
  final String? reasoningText;

  /// Structured block payload for future renderers.
  final Map<String, dynamic>? payload;

  /// Typed workflow projection for tool workflow rendering.
  final List<ToolWorkflowStep>? workflowSteps;

  /// Typed tool result projection for result rendering.
  final ToolResult? toolResult;

  /// Typed artifact projection for inline artifact rendering.
  final ArtifactTurnProjection? artifactProjection;

  /// Typed ask-user-question request projection for active prompt rendering.
  final AskUserQuestionRequest? askUserQuestionRequest;

  /// Typed ask-user-question result projection for submitted answers.
  final AskUserQuestionResponse? askUserQuestionResponse;

  const AssistantTurnBlock({
    required this.id,
    required this.turnId,
    required this.type,
    required this.sequence,
    required this.createdAt,
    required this.updatedAt,
    this.status,
    this.title,
    this.text,
    this.reasoningText,
    this.payload,
    this.workflowSteps,
    this.toolResult,
    this.artifactProjection,
    this.askUserQuestionRequest,
    this.askUserQuestionResponse,
  });

  AssistantTurnBlock copyWith({
    String? id,
    String? turnId,
    AssistantTurnBlockType? type,
    int? sequence,
    DateTime? createdAt,
    DateTime? updatedAt,
    String? status,
    String? title,
    String? text,
    String? reasoningText,
    Map<String, dynamic>? payload,
    List<ToolWorkflowStep>? workflowSteps,
    ToolResult? toolResult,
    ArtifactTurnProjection? artifactProjection,
    AskUserQuestionRequest? askUserQuestionRequest,
    AskUserQuestionResponse? askUserQuestionResponse,
  }) {
    return AssistantTurnBlock(
      id: id ?? this.id,
      turnId: turnId ?? this.turnId,
      type: type ?? this.type,
      sequence: sequence ?? this.sequence,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      status: status ?? this.status,
      title: title ?? this.title,
      text: text ?? this.text,
      reasoningText: reasoningText ?? this.reasoningText,
      payload: payload ?? this.payload,
      workflowSteps: workflowSteps ?? this.workflowSteps,
      toolResult: toolResult ?? this.toolResult,
      artifactProjection: artifactProjection ?? this.artifactProjection,
      askUserQuestionRequest:
          askUserQuestionRequest ?? this.askUserQuestionRequest,
      askUserQuestionResponse:
          askUserQuestionResponse ?? this.askUserQuestionResponse,
    );
  }
}
