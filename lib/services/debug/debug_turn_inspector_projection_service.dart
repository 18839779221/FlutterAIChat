import 'package:ai_chat/models/chat/runtime_assistant_draft.dart';
import 'package:ai_chat/models/chat/runtime_stream_entry.dart';
import 'package:ai_chat/models/chat/tool_presentation_event.dart';
import 'package:ai_chat/models/chat_event.dart';
import 'package:ai_chat/models/chat_group.dart';
import 'package:ai_chat/models/chat_message.dart';
import 'package:ai_chat/models/chat_turn.dart';
import 'package:ai_chat/models/trace/chat_trace_event.dart';
import 'package:ai_chat/models/debug/debug_turn_inspector_context_section.dart';
import 'package:ai_chat/models/debug/debug_turn_inspector_projection.dart';
import 'package:ai_chat/models/debug/debug_turn_inspector_timeline_entry.dart';
import 'package:ai_chat/models/debug/debug_turn_option.dart';
import 'package:ai_chat/providers/chat_send_state_providers.dart';
import 'package:ai_chat/repositories/chat_event_repository.dart';
import 'package:ai_chat/repositories/chat_turn_repository.dart';
import 'package:ai_chat/services/chat_service.dart';
import 'package:ai_chat/services/prompt/prompt_builder_service.dart';
import 'package:ai_chat/services/prompt/prompt_stage.dart';
import 'package:ai_chat/services/chat_trace_recorder.dart';
import 'package:ai_chat/services/session_context_service.dart';
import 'package:ai_chat/services/tool_result_context_projector.dart';
import 'package:ai_chat/models/tool/tool_result.dart';

class DebugTurnInspectorProjectionService {
  DebugTurnInspectorProjectionService({
    required ChatTurnRepository chatTurnRepository,
    required ChatEventRepository chatEventRepository,
    required SessionContextService sessionContextService,
    required ChatTraceRecorder traceRecorder,
    RuntimeAssistantDraft? runtimeAssistantDraft,
    List<RuntimeStreamEntry> runtimeStreamEntries =
        const <RuntimeStreamEntry>[],
    List<ToolPresentationEvent> toolPresentationEvents =
        const <ToolPresentationEvent>[],
    ChatSendPhase? sendPhase,
    String? sendStatusText,
    ChatMessage? activeAskUserQuestionMessage,
    ChatGroup? currentGroup,
    String? systemPromptOverride,
    PromptBuilderService? promptBuilder,
  })  : _chatTurnRepository = chatTurnRepository,
        _chatEventRepository = chatEventRepository,
        _sessionContextService = sessionContextService,
        _traceRecorder = traceRecorder,
        _runtimeAssistantDraft = runtimeAssistantDraft,
        _runtimeStreamEntries = runtimeStreamEntries,
        _toolPresentationEvents = toolPresentationEvents,
        _sendPhase = sendPhase,
        _sendStatusText = sendStatusText,
        _activeAskUserQuestionMessage = activeAskUserQuestionMessage,
        _currentGroup = currentGroup,
        _systemPromptOverride = systemPromptOverride,
        _promptBuilder = promptBuilder ?? const PromptBuilderService();

  final ChatTurnRepository _chatTurnRepository;
  final ChatEventRepository _chatEventRepository;
  final SessionContextService _sessionContextService;
  final ChatTraceRecorder _traceRecorder;
  final RuntimeAssistantDraft? _runtimeAssistantDraft;
  final List<RuntimeStreamEntry> _runtimeStreamEntries;
  final List<ToolPresentationEvent> _toolPresentationEvents;
  final ChatSendPhase? _sendPhase;
  final String? _sendStatusText;
  final ChatMessage? _activeAskUserQuestionMessage;
  final ChatGroup? _currentGroup;
  final String? _systemPromptOverride;
  final PromptBuilderService _promptBuilder;

  Future<DebugTurnInspectorProjection> build({
    required int groupId,
    int? selectedTurnId,
  }) async {
    final turns = await _chatTurnRepository.getTurnsByGroup(groupId);
    final sortedTurns = [...turns]..sort((left, right) {
        final leftUpdated = left.updatedAt;
        final rightUpdated = right.updatedAt;
        final updatedOrder = rightUpdated.compareTo(leftUpdated);
        if (updatedOrder != 0) {
          return updatedOrder;
        }
        return (right.id ?? 0).compareTo(left.id ?? 0);
      });
    final turnOptions = sortedTurns
        .where((turn) => turn.id != null)
        .take(10)
        .map(
          (turn) => DebugTurnOption(
            turnId: turn.id!,
            status: turn.status.name,
            updatedAt: turn.updatedAt,
            userInputPreview: _preview(turn.userInput),
          ),
        )
        .toList(growable: false);

    final effectiveSelectedTurnId = selectedTurnId ??
        (turnOptions.isEmpty ? null : turnOptions.first.turnId);
    final activeTurn = effectiveSelectedTurnId == null
        ? null
        : turns
            .where((turn) => turn.id == effectiveSelectedTurnId)
            .toList(
              growable: false,
            )
            .firstOrNull;
    final transcript = effectiveSelectedTurnId == null
        ? const <ChatEvent>[]
        : await _chatEventRepository.listEventsByTurn(effectiveSelectedTurnId);
    final userSystemPrompt =
        (_systemPromptOverride ?? _currentGroup?.systemPrompt ?? '').trim();
    final config = ChatConfig(
      systemPrompt: _promptBuilder.buildSystemPrompt(
        stage: PromptStage.planner,
        userSystemPrompt: userSystemPrompt,
      ),
      userSystemPrompt: userSystemPrompt,
    );
    final plannerState = effectiveSelectedTurnId == null
        ? null
        : await _sessionContextService.buildPlannerContextState(
            groupId: groupId,
            currentTurnId: effectiveSelectedTurnId,
            currentTurnTranscript: transcript,
            config: config,
          );
    final plannerMessages =
        plannerState?.plannerMessages ?? const <ChatMessage>[];

    return DebugTurnInspectorProjection(
      turnOptions: turnOptions,
      selectedTurnId: effectiveSelectedTurnId,
      activeTurnOverview: activeTurn == null
          ? null
          : _buildOverview(
              turn: activeTurn,
              runtimeStreamEntries: _runtimeStreamEntries,
              runtimeAssistantDraft: _runtimeAssistantDraft,
            ),
      timelineEntries: _buildTimelineEntries(
        turnId: effectiveSelectedTurnId,
        transcript: transcript,
        plannerMessages: plannerMessages,
      ),
      contextSections: _buildContextSections(
        resolvedSystemPrompt: plannerState?.resolvedSystemPrompt,
        plannerMessages: plannerMessages,
        transcript: transcript,
        turn: activeTurn,
      ),
    );
  }

  Future<DebugTurnInspectorProjection> buildForTurn({
    required int groupId,
    required int selectedTurnId,
  }) {
    return build(
      groupId: groupId,
      selectedTurnId: selectedTurnId,
    );
  }

  DebugTurnOverview _buildOverview({
    required ChatTurn turn,
    required List<RuntimeStreamEntry> runtimeStreamEntries,
    required RuntimeAssistantDraft? runtimeAssistantDraft,
  }) {
    final durationMs = turn.completedAt == null
        ? DateTime.now().difference(turn.createdAt).inMilliseconds
        : turn.completedAt!.difference(turn.createdAt).inMilliseconds;
    return DebugTurnOverview(
      turnId: turn.id ?? -1,
      groupId: turn.groupId,
      status: turn.status,
      sendPhase: _sendPhase?.name,
      sendStatusText: _sendStatusText,
      iterationCount: turn.iterationCount,
      toolCallCount: turn.toolCallCount,
      providerStyle: turn.providerStyle?.name,
      modelName: turn.modelName,
      diagnosticCode: turn.stopReason,
      errorMessage: turn.errorMessage,
      hasRuntimeDraft: runtimeAssistantDraft != null,
      runtimeStreamEntryCount: runtimeStreamEntries.length,
      hasPendingConfirmation: false,
      hasActiveQuestion: _activeAskUserQuestionMessage != null,
      startedAt: turn.createdAt,
      updatedAt: turn.updatedAt,
      durationMs: durationMs,
    );
  }

  List<DebugTurnTimelineEntry> _buildTimelineEntries({
    required int? turnId,
    required List<ChatEvent> transcript,
    required List<ChatMessage> plannerMessages,
  }) {
    final entries = <DebugTurnTimelineEntry>[];
    for (final event in transcript) {
      entries.add(
        DebugTurnTimelineEntry(
          id: 'event-${event.id ?? event.sequence}',
          timestamp: event.createdAt,
          kind: event.eventType.name,
          title: event.eventType.name,
          summary: event.content ?? '',
          source: DebugTurnTimelineSource.persisted,
          severity: _severityForEvent(event),
          payloadJson: event.payloadJson,
        ),
      );
    }
    for (final message in plannerMessages) {
      entries.add(
        DebugTurnTimelineEntry(
          id: 'planner-${message.id ?? message.timestamp.microsecondsSinceEpoch}',
          timestamp: message.timestamp,
          kind: 'plannerMessage',
          title: message.role.name,
          summary: message.text,
          source: DebugTurnTimelineSource.runtime,
          severity: DebugTimelineSeverity.info,
          payloadJson: {
            'role': message.role.name,
            'status': message.status.name,
            if (message.payloadJson != null) 'payloadJson': message.payloadJson,
            if (message.reasoningContent != null)
              'reasoningContent': message.reasoningContent,
          },
        ),
      );
    }
    for (final traceTurnId in _resolveTraceTurnIds(
      turnId: turnId,
      transcript: transcript,
      plannerMessages: plannerMessages,
    )) {
      for (final event in _traceRecorder.eventsForTurn(traceTurnId)) {
        entries.add(
          DebugTurnTimelineEntry(
            id: 'trace-$traceTurnId-${event.timestamp.microsecondsSinceEpoch}-${event.stage.name}',
            timestamp: event.timestamp,
            kind: 'trace.${event.stage.name}.${event.status.name}',
            title: event.stage.name,
            summary: event.summary ?? '',
            source: DebugTurnTimelineSource.trace,
            severity: _severityForTrace(event),
            payloadJson: event.data,
          ),
        );
      }
    }
    entries.sort((left, right) => left.timestamp.compareTo(right.timestamp));
    return entries;
  }

  List<DebugTurnInspectorContextSection> _buildContextSections({
    required String? resolvedSystemPrompt,
    required List<ChatMessage> plannerMessages,
    required List<ChatEvent> transcript,
    required ChatTurn? turn,
  }) {
    return [
      DebugTurnInspectorContextSection(
        id: 'resolved-system-prompt',
        title: 'Resolved System Prompt',
        summary: (resolvedSystemPrompt == null || resolvedSystemPrompt.isEmpty)
            ? 'empty'
            : _preview(resolvedSystemPrompt),
        defaultExpanded: true,
        rawText: resolvedSystemPrompt ?? '',
      ),
      DebugTurnInspectorContextSection(
        id: 'planner-messages',
        title: 'Planner Messages',
        summary: '${plannerMessages.length} items',
        defaultExpanded: false,
        rawJson: {
          'messages': plannerMessages
              .map(
                (message) => {
                  'id': message.id,
                  'role': message.role.name,
                  'status': message.status.name,
                  'text': message.text,
                  'timestamp': message.timestamp.toIso8601String(),
                  if (message.reasoningContent != null)
                    'reasoningContent': message.reasoningContent,
                  if (message.payloadJson != null)
                    'payloadJson': message.payloadJson,
                  if (message.referenceJson != null)
                    'referenceJson': message.referenceJson,
                },
              )
              .toList(growable: false),
        },
      ),
      _buildSkillsSection(
        plannerMessages: plannerMessages,
        transcript: transcript,
      ),
      DebugTurnInspectorContextSection(
        id: 'transcript-events',
        title: 'Transcript Events',
        summary: '${transcript.length} items',
        defaultExpanded: false,
        rawJson: {
          'events': transcript
              .map(
                (event) => {
                  'id': event.id,
                  'turnId': event.turnId,
                  'sequence': event.sequence,
                  'eventType': event.eventType.name,
                  'role': event.role?.name,
                  'status': event.status,
                  'content': event.content,
                  if (event.payloadJson != null)
                    'payloadJson': event.payloadJson,
                  'createdAt': event.createdAt.toIso8601String(),
                },
              )
              .toList(growable: false),
        },
      ),
      DebugTurnInspectorContextSection(
        id: 'turn-steps',
        title: 'Turn Steps',
        summary: turn == null ? '0 items' : 'turn ${turn.id}',
        defaultExpanded: false,
        rawJson: {
          'turn': turn == null
              ? null
              : {
                  'id': turn.id,
                  'status': turn.status.name,
                  'providerStyle': turn.providerStyle?.name,
                  'modelName': turn.modelName,
                  'providerStateJson': turn.providerStateJson,
                },
        },
      ),
      DebugTurnInspectorContextSection(
        id: 'provider-state',
        title: 'Provider State',
        summary: 'raw turn provider state',
        defaultExpanded: false,
        rawJson: turn?.providerStateJson,
      ),
      DebugTurnInspectorContextSection(
        id: 'runtime-stream',
        title: 'Runtime Stream Entries',
        summary: '${_runtimeStreamEntries.length} items',
        defaultExpanded: false,
        rawJson: {
          'entries': _runtimeStreamEntries
              .map(
                (entry) => {
                  'turnId': entry.turnId,
                  'entryId': entry.entryId,
                  'kind': entry.kind.name,
                  'providerCallId': entry.providerCallId,
                  'toolName': entry.toolName,
                  'text': entry.text,
                  'payload': entry.payload,
                  'createdAt': entry.createdAt.toIso8601String(),
                  'updatedAt': entry.updatedAt.toIso8601String(),
                },
              )
              .toList(growable: false),
        },
      ),
      DebugTurnInspectorContextSection(
        id: 'runtime-draft',
        title: 'Runtime Assistant Draft',
        summary: _runtimeAssistantDraft == null ? 'none' : 'present',
        defaultExpanded: false,
        rawJson: _runtimeAssistantDraft == null
            ? null
            : {
                'turnId': _runtimeAssistantDraft!.turnId,
                'draftId': _runtimeAssistantDraft!.draftId,
                'blockType': _runtimeAssistantDraft!.blockType.name,
                'text': _runtimeAssistantDraft!.text,
                'reasoningText': _runtimeAssistantDraft!.reasoningText,
                'payload': _runtimeAssistantDraft!.payload,
              },
      ),
      DebugTurnInspectorContextSection(
        id: 'latest-decision',
        title: 'Latest Decision Snapshot',
        summary: 'runtime snapshot',
        defaultExpanded: false,
        rawJson: {
          'toolPresentationEvents': _toolPresentationEvents
              .map(
                (event) => {
                  'toolName': event.toolName,
                  'phase': event.phase.name,
                  'turnId': event.turnId,
                  'stepId': event.stepId,
                  'providerCallId': event.providerCallId,
                  'sourceContentType': event.sourceContentType.name,
                  'sourceMessageId': event.sourceMessageId,
                  'timestamp': event.timestamp.toIso8601String(),
                  'data': event.data,
                },
              )
              .toList(growable: false),
        },
      ),
    ];
  }

  DebugTurnInspectorContextSection _buildSkillsSection({
    required List<ChatMessage> plannerMessages,
    required List<ChatEvent> transcript,
  }) {
    final availableSkillLines = <String>[];
    for (final message in plannerMessages) {
      final text = message.text;
      if (!text.contains(
        'The following skills are available for use with the Skill tool:',
      )) {
        continue;
      }
      availableSkillLines.addAll(
        text
            .split('\n')
            .map((line) => line.trim())
            .where((line) => line.startsWith('- '))
            .toList(growable: false),
      );
    }

    const projector = ToolResultContextProjector();
    final invokedSkills = <Map<String, dynamic>>[];
    for (final event in transcript) {
      if (event.eventType != ChatEventType.toolResult) {
        continue;
      }
      final payload = event.payloadJson;
      if (payload == null ||
          payload['toolName']?.toString().trim() != 'skill') {
        continue;
      }
      final data = payload['data'] is Map
          ? Map<String, dynamic>.from(payload['data'] as Map<dynamic, dynamic>)
          : <String, dynamic>{};
      final result = ToolResult.fromJson(payload);
      final projectedText = projector.projectToContextText(result);
      invokedSkills.add({
        'skillId': data['skillId'],
        'name': data['name'],
        'status': payload['status'],
        'qualifiedPath': data['qualifiedPath'],
        'baseDirectory': data['baseDirectory'],
        'instructionBodyTruncated': data['instructionBodyTruncated'] == true,
        'originalInstructionLength': data['originalInstructionLength'],
        'projected': projectedText != null && projectedText.trim().isNotEmpty,
        if (payload['errorMessage'] != null)
          'errorMessage': payload['errorMessage'],
      });
    }

    return DebugTurnInspectorContextSection(
      id: 'skills',
      title: 'Skills',
      summary:
          '${availableSkillLines.length} available, ${invokedSkills.length} invoked',
      defaultExpanded: false,
      rawJson: {
        'availableSkills': availableSkillLines,
        'invokedSkills': invokedSkills,
      },
    );
  }

  DebugTimelineSeverity _severityForEvent(ChatEvent event) {
    switch (event.eventType) {
      case ChatEventType.error:
      case ChatEventType.toolError:
        return DebugTimelineSeverity.error;
      case ChatEventType.finalAnswer:
      case ChatEventType.turnStatus:
        return DebugTimelineSeverity.info;
      default:
        return DebugTimelineSeverity.info;
    }
  }

  DebugTimelineSeverity _severityForTrace(ChatTraceEvent event) {
    switch (event.status) {
      case ChatTraceStatus.failure:
        return DebugTimelineSeverity.error;
      case ChatTraceStatus.inProgress:
        return DebugTimelineSeverity.warning;
      case ChatTraceStatus.started:
      case ChatTraceStatus.success:
        return DebugTimelineSeverity.info;
    }
  }

  String _preview(String value) {
    final normalized = value.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (normalized.length <= 80) {
      return normalized;
    }
    return '${normalized.substring(0, 80)}...';
  }

  List<String> _resolveTraceTurnIds({
    required int? turnId,
    required List<ChatEvent> transcript,
    required List<ChatMessage> plannerMessages,
  }) {
    final ids = <String>[];

    void addCandidate(Object? rawValue) {
      final value = rawValue?.toString().trim();
      if (value == null || value.isEmpty) {
        return;
      }
      if (!ids.contains(value)) {
        ids.add(value);
      }
    }

    for (final event in transcript) {
      addCandidate(event.payloadJson?['traceTurnId']);
    }
    for (final message in plannerMessages) {
      addCandidate(message.payloadJson?['traceTurnId']);
      addCandidate(message.payloadJson?['payloadJson']?['traceTurnId']);
    }
    if (ids.isEmpty && turnId != null) {
      addCandidate('turn_$turnId');
    }
    return ids;
  }
}
