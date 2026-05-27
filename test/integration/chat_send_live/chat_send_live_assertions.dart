import 'package:ai_chat/models/agent/chat_turn_step.dart';
import 'package:ai_chat/models/chat_event.dart';
import 'package:ai_chat/models/chat_message.dart';
import 'package:ai_chat/models/chat_turn.dart';
import 'package:ai_chat/models/response/message_content_type.dart';
import 'package:flutter_test/flutter_test.dart';

void expectAtLeastOneTurn(List<ChatTurn> turns) {
  expect(turns, isNotEmpty);
}

class ChatSendLiveStateSnapshot {
  final int? groupId;
  final List<ChatMessage> messages;
  final List<ChatTurn> turns;
  final List<ChatTurnStep> steps;
  final List<ChatEvent> events;

  const ChatSendLiveStateSnapshot({
    required this.groupId,
    required this.messages,
    required this.turns,
    required this.steps,
    required this.events,
  });

  ChatTurn? get latestTurn => turns.isEmpty ? null : turns.last;
}

void expectTurnState(
  ChatSendLiveStateSnapshot state, {
  required ChatTurnStatus expectedStatus,
}) {
  final turn = state.latestTurn;
  expect(turn, isNotNull, reason: 'Expected at least one persisted turn.');
  expect(
    turn!.status,
    expectedStatus,
    reason:
        'Expected latest turn status to be $expectedStatus but got ${turn.status}.',
  );
}

void expectEventTypes(
  ChatSendLiveStateSnapshot state, {
  List<ChatEventType> includes = const [],
  List<ChatEventType> includesInOrder = const [],
}) {
  final eventTypes = state.events.map((event) => event.eventType).toList();
  for (final expectedType in includes) {
    expect(
      eventTypes,
      contains(expectedType),
      reason: 'Expected event list to contain $expectedType.',
    );
  }

  if (includesInOrder.isEmpty) {
    return;
  }

  var cursor = 0;
  for (final actualType in eventTypes) {
    if (actualType == includesInOrder[cursor]) {
      cursor += 1;
      if (cursor == includesInOrder.length) {
        break;
      }
    }
  }
  expect(
    cursor,
    includesInOrder.length,
    reason:
        'Expected event types to include ${includesInOrder.join(' -> ')} in order, got $eventTypes.',
  );
}

void expectStepSequence(
  ChatSendLiveStateSnapshot state, {
  int minimumCount = 1,
}) {
  expect(
    state.steps.length,
    greaterThanOrEqualTo(minimumCount),
    reason: 'Expected at least $minimumCount persisted steps.',
  );
  if (state.steps.isEmpty) {
    return;
  }
  final firstStepIndex = state.steps.first.stepIndex;
  for (var index = 0; index < state.steps.length; index += 1) {
    expect(
      state.steps[index].stepIndex,
      firstStepIndex + index,
      reason: 'Expected stepIndex to stay contiguous.',
    );
  }
}

void expectProviderIdsAligned(ChatSendLiveStateSnapshot state) {
  final turn = state.latestTurn;
  expect(turn, isNotNull, reason: 'Expected at least one persisted turn.');
  final providerState = turn!.providerStateJson ?? const <String, dynamic>{};
  final turnResponseId = providerState['response_id'];
  if (turnResponseId == null) {
    return;
  }
  for (final step in state.steps) {
    expect(
      step.providerResponseId,
      isNotEmpty,
      reason: 'Expected persisted step to retain providerResponseId.',
    );
  }
}

void expectNoPlannerRequestFailure(ChatSendLiveStateSnapshot state) {
  final turn = state.latestTurn;
  expect(turn, isNotNull, reason: 'Expected at least one persisted turn.');
  expect(
    turn!.status,
    isNot(ChatTurnStatus.failed),
    reason: 'Expected planner/provider request not to fail.',
  );
  final errorEvents = state.events.where(
    (event) =>
        event.eventType == ChatEventType.error ||
        (event.eventType == ChatEventType.turnStatus &&
            (event.content ?? '').contains('planner_request_failed')),
  );
  expect(
    errorEvents,
    isEmpty,
    reason: 'Expected no planner request failure events in ledger.',
  );
}

void expectAskUserContinuationCoverage(
  ChatSendLiveStateSnapshot waitingState,
  ChatSendLiveStateSnapshot resumedState,
) {
  final promptEvent = waitingState.events.lastWhere(
    (event) => event.eventType == ChatEventType.assistantQuestionPrompt,
    orElse: () => throw TestFailure(
      'Expected assistantQuestionPrompt event in live state.',
    ),
  );
  final promptPayload = promptEvent.payloadJson ?? const <String, dynamic>{};
  final providerCallId =
      (promptPayload['providerCallId'] ?? '').toString().trim();
  final stepId = promptPayload['stepId'];

  expect(
    providerCallId,
    isNotEmpty,
    reason:
        'Expected assistantQuestionPrompt payload to retain providerCallId.',
  );
  expect(
    stepId,
    isNotNull,
    reason: 'Expected assistantQuestionPrompt payload to retain stepId.',
  );

  final promptMessage = waitingState.messages.lastWhere(
    (message) =>
        message.contentType == MessageContentType.askUserQuestionPrompt,
    orElse: () => throw TestFailure(
      'Expected askUserQuestionPrompt message in persisted messages.',
    ),
  );
  expect(
    promptMessage.payloadJson?['providerCallId'],
    providerCallId,
    reason: 'Expected prompt message payload to keep providerCallId aligned.',
  );

  final interactionEvent = resumedState.events.lastWhere(
    (event) => event.eventType == ChatEventType.userInteractionResult,
    orElse: () => throw TestFailure(
      'Expected userInteractionResult event after submitting answers.',
    ),
  );
  expect(
    interactionEvent.payloadJson?['providerCallId'],
    providerCallId,
    reason:
        'Expected userInteractionResult payload to keep providerCallId aligned.',
  );

  final resultMessage = resumedState.messages.lastWhere(
    (message) =>
        message.contentType == MessageContentType.askUserQuestionResult,
    orElse: () => throw TestFailure(
      'Expected askUserQuestionResult message after resume.',
    ),
  );
  expect(
    resultMessage.payloadJson?['providerCallId'],
    providerCallId,
    reason: 'Expected ask-user result message to keep providerCallId aligned.',
  );

  final persistedStep = resumedState.steps.firstWhere(
    (step) => step.providerCallId == providerCallId,
    orElse: () => throw TestFailure(
      'Expected persisted step for providerCallId $providerCallId.',
    ),
  );
  expect(
    persistedStep.id,
    stepId,
    reason:
        'Expected ask-user step id to match assistantQuestionPrompt payload.',
  );
  expect(
    persistedStep.status,
    ChatTurnStepStatus.completed,
    reason: 'Expected ask-user step to be completed after resume.',
  );
}

bool expectOptionalStructuredAskUserFlow(
  ChatSendLiveStateSnapshot? waitingState,
  ChatSendLiveStateSnapshot finalState, {
  required bool supportsStructuredInteraction,
}) {
  if (supportsStructuredInteraction || waitingState != null) {
    return true;
  }
  expectNoPlannerRequestFailure(finalState);
  expectTurnState(
    finalState,
    expectedStatus: ChatTurnStatus.completed,
  );
  expectEventTypes(
    finalState,
    includesInOrder: const [
      ChatEventType.userMessage,
      ChatEventType.finalAnswer,
    ],
  );
  return false;
}

bool expectOptionalStructuredToolConfirmationFlow(
  ChatSendLiveStateSnapshot? waitingState,
  ChatSendLiveStateSnapshot finalState, {
  required bool supportsStructuredInteraction,
}) {
  if (supportsStructuredInteraction || waitingState != null) {
    return true;
  }
  expectNoPlannerRequestFailure(finalState);
  expectTurnState(
    finalState,
    expectedStatus: ChatTurnStatus.completed,
  );
  expectEventTypes(
    finalState,
    includes: const [
      ChatEventType.finalAnswer,
    ],
  );
  return false;
}

bool expectOptionalMultiToolContinuation(
  ChatSendLiveStateSnapshot state, {
  required String toolName,
  required int minimumDistinctCallCount,
  required bool supportsStructuredContinuation,
}) {
  final toolCallEvents = state.events.where((event) {
    if (event.eventType != ChatEventType.assistantToolCall) {
      return false;
    }
    final payload = event.payloadJson ?? const <String, dynamic>{};
    return payload['toolName'] == toolName;
  }).toList(growable: false);

  if (supportsStructuredContinuation ||
      toolCallEvents.length >= minimumDistinctCallCount) {
    return true;
  }

  expectNoPlannerRequestFailure(state);
  expectTurnState(
    state,
    expectedStatus: ChatTurnStatus.completed,
  );
  expectEventTypes(
    state,
    includes: const [
      ChatEventType.finalAnswer,
    ],
  );
  return false;
}

void expectToolBatchWithDistinctCalls(
  ChatSendLiveStateSnapshot state, {
  required String toolName,
  required int minimumDistinctCallCount,
}) {
  final toolCallEvents = state.events.where((event) {
    if (event.eventType != ChatEventType.assistantToolCall) {
      return false;
    }
    final payload = event.payloadJson ?? const <String, dynamic>{};
    return payload['toolName'] == toolName;
  }).toList(growable: false);

  expect(
    toolCallEvents,
    isNotEmpty,
    reason: 'Expected at least one assistantToolCall event for $toolName.',
  );

  final providerCallsByBatch = <String, Set<String>>{};
  for (final event in toolCallEvents) {
    final payload = event.payloadJson ?? const <String, dynamic>{};
    final providerResponseId =
        (payload['providerResponseId'] ?? '').toString().trim();
    final providerCallId = (payload['providerCallId'] ?? '').toString().trim();
    if (providerResponseId.isEmpty || providerCallId.isEmpty) {
      continue;
    }
    providerCallsByBatch
        .putIfAbsent(providerResponseId, () => <String>{})
        .add(providerCallId);
  }

  expect(
    providerCallsByBatch.isNotEmpty,
    isTrue,
    reason:
        'Expected $toolName assistantToolCall events to retain providerResponseId/providerCallId.',
  );

  final matchedEntry = providerCallsByBatch.entries.firstWhere(
    (entry) => entry.value.length >= minimumDistinctCallCount,
    orElse: () => const MapEntry<String, Set<String>>('', <String>{}),
  );

  expect(
    matchedEntry.key,
    isNotEmpty,
    reason: 'Expected at least one $toolName decision batch with '
        '$minimumDistinctCallCount distinct providerCallId values, got $providerCallsByBatch.',
  );

  final matchedCallIds = matchedEntry.value;
  final stepCallIds = state.steps
      .where((step) => step.providerResponseId == matchedEntry.key)
      .map((step) => step.providerCallId)
      .whereType<String>()
      .toSet();
  expect(
    stepCallIds.containsAll(matchedCallIds),
    isTrue,
    reason: 'Expected persisted steps in batch ${matchedEntry.key} to retain '
        'providerCallId values $matchedCallIds, got $stepCallIds.',
  );

  final resultCallIds = state.events
      .where((event) => event.eventType == ChatEventType.toolResult)
      .map((event) => event.payloadJson?['providerCallId'])
      .whereType<String>()
      .toSet();
  expect(
    resultCallIds.containsAll(matchedCallIds),
    isTrue,
    reason: 'Expected toolResult events to cover providerCallId values '
        '$matchedCallIds, got $resultCallIds.',
  );
}

void expectToolCallContinuationCoverage(
  ChatSendLiveStateSnapshot state, {
  required String toolName,
  required int minimumDistinctCallCount,
}) {
  final toolCallEvents = state.events.where((event) {
    if (event.eventType != ChatEventType.assistantToolCall) {
      return false;
    }
    final payload = event.payloadJson ?? const <String, dynamic>{};
    return payload['toolName'] == toolName;
  }).toList(growable: false);

  expect(
    toolCallEvents.length,
    greaterThanOrEqualTo(minimumDistinctCallCount),
    reason:
        'Expected at least $minimumDistinctCallCount assistantToolCall events for $toolName.',
  );

  final providerCallIds = <String>{};
  final providerResponseIds = <String>{};
  for (final event in toolCallEvents) {
    final payload = event.payloadJson ?? const <String, dynamic>{};
    final providerCallId = (payload['providerCallId'] ?? '').toString().trim();
    final providerResponseId =
        (payload['providerResponseId'] ?? '').toString().trim();
    expect(
      providerCallId,
      isNotEmpty,
      reason: 'Expected $toolName assistantToolCall to retain providerCallId.',
    );
    expect(
      providerResponseId,
      isNotEmpty,
      reason:
          'Expected $toolName assistantToolCall to retain providerResponseId.',
    );
    providerCallIds.add(providerCallId);
    providerResponseIds.add(providerResponseId);
  }

  expect(
    providerCallIds.length,
    greaterThanOrEqualTo(minimumDistinctCallCount),
    reason:
        'Expected at least $minimumDistinctCallCount distinct providerCallId values for $toolName, got $providerCallIds.',
  );

  final stepCallIds = state.steps
      .map((step) => step.providerCallId)
      .whereType<String>()
      .toSet();
  expect(
    stepCallIds.containsAll(providerCallIds),
    isTrue,
    reason:
        'Expected persisted steps to cover providerCallId values $providerCallIds, got $stepCallIds.',
  );

  final resultOrErrorCallIds = state.events
      .where(
        (event) =>
            event.eventType == ChatEventType.toolResult ||
            event.eventType == ChatEventType.toolError,
      )
      .map((event) => event.payloadJson?['providerCallId'])
      .whereType<String>()
      .toSet();
  expect(
    resultOrErrorCallIds.containsAll(providerCallIds),
    isTrue,
    reason:
        'Expected toolResult/toolError events to cover providerCallId values '
        '$providerCallIds, got $resultOrErrorCallIds.',
  );

  expect(
    providerResponseIds,
    isNotEmpty,
    reason:
        'Expected $toolName tool calls to retain providerResponseId values.',
  );
}

void expectAnyToolErrorWithProviderCallId(
  ChatSendLiveStateSnapshot state, {
  String? toolName,
}) {
  final toolErrorEvent = state.events.lastWhere(
    (event) {
      if (event.eventType != ChatEventType.toolError) {
        return false;
      }
      if (toolName == null) {
        return true;
      }
      return event.payloadJson?['toolName'] == toolName;
    },
    orElse: () => throw TestFailure(
      toolName == null
          ? 'Expected at least one toolError event.'
          : 'Expected at least one toolError event for $toolName.',
    ),
  );

  final providerCallId =
      (toolErrorEvent.payloadJson?['providerCallId'] ?? '').toString().trim();
  expect(
    providerCallId,
    isNotEmpty,
    reason: 'Expected toolError event to retain providerCallId.',
  );

  final persistedStep = state.steps.firstWhere(
    (step) => step.providerCallId == providerCallId,
    orElse: () => throw TestFailure(
      'Expected persisted step for failed providerCallId $providerCallId.',
    ),
  );
  expect(
    persistedStep.status,
    ChatTurnStepStatus.failed,
    reason: 'Expected failed step to remain marked as failed.',
  );
}

void expectCompletedAssistantAnswerPersisted(
  ChatSendLiveStateSnapshot state,
) {
  final answerMessage = state.messages.lastWhere(
    (message) =>
        message.isAssistant &&
        message.contentType == MessageContentType.plainText &&
        message.status == MessageStatus.completed &&
        message.text.trim().isNotEmpty,
    orElse: () => throw TestFailure(
      'Expected a completed assistant plain-text answer message.',
    ),
  );

  expect(
    answerMessage.text.trim(),
    isNotEmpty,
    reason: 'Expected final assistant answer text to be persisted.',
  );
}
