import 'dart:async';

import 'package:ai_chat/models/chat/chat_timeline_projection.dart';
import 'package:ai_chat/models/chat/runtime_assistant_draft.dart';
import 'package:ai_chat/models/chat/runtime_streaming_preview_state.dart';
import 'package:ai_chat/models/chat_message.dart';
import 'package:ai_chat/models/session/context_window_snapshot.dart';
import 'package:ai_chat/models/debug/debug_test_case.dart';
import 'package:ai_chat/models/llm/streaming_message_event.dart';
import 'package:ai_chat/utils/logger.dart';
import 'package:ai_chat/models/tool/tool_invocation.dart';
import 'package:ai_chat/controllers/voice_input_controller.dart';
import 'package:ai_chat/providers/chat_collection_providers.dart';
import 'package:ai_chat/providers/chat_dependency_providers.dart';
import 'package:ai_chat/services/chat_service.dart';
import 'package:ai_chat/services/debug_test_case_loader.dart';
import 'package:ai_chat/services/latest_message_running_status_resolver.dart';
import 'package:ai_chat/services/runtime_streaming_preview_projector.dart';
import 'package:ai_chat/services/turn_projection_dispatcher.dart';
import 'package:ai_chat/providers/streaming_trace_providers.dart';
import 'package:ai_chat/models/debug/streaming_trace_snapshot.dart';
import 'package:ai_chat/providers/chat_send_state_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

// 正在自动摘要状态提供者
final isAutoSummarizingProvider = StateProvider<bool>((ref) => false);

// 加载更多状态提供者
final isLoadingMoreProvider = StateProvider<bool>((ref) => false);

// 是否有更多消息提供者
final hasMoreMessagesProvider = StateProvider<bool>((ref) => true);

// 初始化状态提供者
final isInitializingProvider = StateProvider<bool>((ref) => true);

// 控制器提供者
final scrollControllerProvider = Provider<ScrollController>((ref) {
  final controller = ScrollController();
  ref.onDispose(() => controller.dispose());
  return controller;
});

// 文本控制器提供者
final textControllerProvider = Provider<TextEditingController>((ref) {
  final controller = TextEditingController();
  ref.onDispose(() => controller.dispose());
  return controller;
});

// 焦点提供者
final focusNodeProvider = Provider<FocusNode>((ref) {
  final focusNode = FocusNode();
  ref.onDispose(() => focusNode.dispose());
  return focusNode;
});

final voiceInputControllerProvider = Provider<VoiceInputController?>((ref) {
  final speechInputConfig = ref.watch(speechInputConfigProvider).valueOrNull;
  final speechToTextService = ref.watch(speechToTextServiceProvider);
  final audioCaptureService = ref.watch(audioCaptureServiceProvider);
  if (speechInputConfig == null ||
      speechToTextService == null ||
      audioCaptureService == null) {
    return null;
  }

  final controller = VoiceInputController(
    textController: ref.watch(textControllerProvider),
    speechInputConfig: speechInputConfig,
    speechToTextService: speechToTextService,
    audioCaptureService: audioCaptureService,
  );
  ref.onDispose(controller.dispose);
  ref.onDispose(() {
    unawaited(controller.close());
  });
  return controller;
});

final debugTestCaseLoaderProvider = Provider<DebugTestCaseLoader>((ref) {
  return AssetDebugTestCaseLoader();
});

final debugTestCaseLibraryProvider =
    FutureProvider<DebugTestCaseLibrary>((ref) {
  return ref.watch(debugTestCaseLoaderProvider).load();
});

final enabledDebugTestCasesProvider = Provider<List<DebugTestCase>>((ref) {
  return ref.watch(debugTestCaseLibraryProvider).maybeWhen(
        data: (library) => library.allCases,
        orElse: () => const <DebugTestCase>[],
      );
});

final featuredDebugTestCasesProvider = Provider<List<DebugTestCase>>((ref) {
  return ref.watch(debugTestCaseLibraryProvider).maybeWhen(
        data: (library) => library.featuredCases,
        orElse: () => const <DebugTestCase>[],
      );
});

final contextWindowSnapshotProvider =
    FutureProvider<ContextWindowSnapshot?>((ref) async {
  final group = ref.watch(currentGroupProvider);
  // Recompute the inspector snapshot whenever the visible conversation
  // timeline changes. Without this dependency, a newly created group can
  // cache an initial null snapshot forever because the group id stays stable
  // after later turns/events are persisted.
  ref.watch(messagesProvider);
  final groupId = group?.id;
  if (groupId == null) {
    return null;
  }
  final config = ChatConfig(
    systemPrompt: '',
    userSystemPrompt: ref.watch(systemPromptProvider) ?? '',
  );
  return ref
      .watch(sessionContextInspectorServiceProvider)
      .buildLatestWindowSnapshotForGroup(
        groupId: groupId,
        config: config,
      );
});

// 流订阅提供者
final streamSubscriptionProvider =
    StateProvider<StreamSubscription?>((ref) => null);

/// Async cancellation hook for the currently running send transaction.
final activeSendCancellationProvider =
    StateProvider<Future<void> Function()?>((ref) => null);

/// Runtime-only assistant draft that belongs to the active turn/stage.
final runtimeAssistantDraftProvider =
    StateProvider<RuntimeAssistantDraft?>((ref) => null);

/// Runtime-only structured preview state used by projection/UI consumers.
final runtimeStreamingPreviewStateProvider = StateNotifierProvider<
    RuntimeStreamingPreviewController, RuntimeStreamingPreviewState>((ref) {
  return RuntimeStreamingPreviewController(ref);
});

/// Shared serialized commit pipeline for runtime preview and truth events.
final turnProjectionDispatcherProvider = Provider<TurnProjectionDispatcher>((ref) {
  return TurnProjectionDispatcher(ref);
});

/// Pair of the message that currently owns the confirmation step and the
/// parsed invocation payload used by the bottom confirmation bar.
class PendingToolConfirmation {
  const PendingToolConfirmation({
    required this.message,
    required this.invocation,
  });

  final ChatMessage message;
  final ToolInvocation invocation;
}

/// Single projection snapshot used by timeline widgets and waiting-state
/// providers so they consume one consistent derived view.
final chatTimelineProjectionProvider = Provider<ChatTimelineProjection>((ref) {
  final groupId = ref.watch(currentGroupProvider)?.id;
  final messages = ref.watch(messagesProvider);
  final runtimeDraft = ref.watch(runtimeAssistantDraftProvider);
  final runtimePreviewState = ref.watch(runtimeStreamingPreviewStateProvider);
  return ref.watch(chatTimelineProjectionServiceProvider).build(
    messages: messages,
    groupId: groupId,
    runtimeDraft: runtimeDraft,
    runtimePreviewState: runtimePreviewState,
  );
});

/// Returns the latest unresolved ask-user-question prompt so the timeline can
/// render it as the active interactive card while older/resolved prompts stay
/// compact.
final activeAskUserQuestionMessageProvider = Provider<ChatMessage?>((ref) {
  return ref.watch(chatTimelineProjectionProvider).activeAskUserQuestionMessage;
});

/// Returns the latest unresolved tool confirmation so the page can render a
/// single bottom confirmation bar outside the timeline cards.
final activePendingToolConfirmationProvider =
    Provider<PendingToolConfirmation?>((ref) {
  final projected =
      ref.watch(chatTimelineProjectionProvider).pendingToolConfirmation;
  if (projected == null) {
    return null;
  }
  return PendingToolConfirmation(
    message: projected.message,
    invocation: projected.invocation,
  );
});

/// Shared latest-running-tail projection so page-level overlay logic and
/// timeline rows observe the same running-status truth.
final latestMessageRunningStatusProvider =
    Provider<LatestMessageRunningStatusPresentation?>((ref) {
  final messages = ref.watch(messagesProvider);
  final sendState = ref.watch(chatSendStateProvider);
  return ref.read(latestMessageRunningStatusResolverProvider).resolve(
        messages: [...messages]..sort(compareChatMessagesForTimeline),
        sendPhase: sendState.phase,
        statusTextOverride: sendState.statusText,
      );
});

class RuntimeStreamingPreviewController
    extends StateNotifier<RuntimeStreamingPreviewState> {
  RuntimeStreamingPreviewController(this._ref)
      : _projector = RuntimeStreamingPreviewProjector(
          onEventConsumed: (message, event, timestamp) {
            final traceId = message.streamTraceId?.trim();
            final turnId = message.streamTurnId?.trim();
            if (traceId == null ||
                traceId.isEmpty ||
                turnId == null ||
                turnId.isEmpty) {
              return;
            }
            _ref.read(streamingTraceRecorderProvider.notifier).recordStage(
              traceId: traceId,
              turnId: turnId,
              stage: StreamingTraceStage.previewEventConsumed,
              timestamp: timestamp,
              details: {
                'messageId': event.messageId,
                'eventType': event.runtimeType.toString(),
              },
            );
          },
        ),
        super(const RuntimeStreamingPreviewState());

  static const Duration _minPublishInterval = Duration(milliseconds: 16);

  final Ref _ref;
  final RuntimeStreamingPreviewProjector _projector;
  Timer? _flushTimer;
  DateTime? _lastPublishedAt;
  int _pendingPublishedEventCount = 0;

  void publish(StreamingMessageEvent event) {
    if (!mounted) {
      return;
    }

    // Log tool_use events for artifact diagnosis
    if (event is StreamingContentBlockStartEvent &&
        event.blockType == StreamingContentBlockType.toolUse) {
      Logger.temp(
        'RuntimeStreamingPreviewController',
        'tool_use block started',
        reason: 'diagnose streaming performance',
        data: {
          'messageId': event.messageId,
          'contentBlockId': event.contentBlockId,
          'toolName': event.toolName,
        },
      );
    }
    if (event is StreamingContentBlockDeltaEvent &&
        event.deltaType == StreamingContentDeltaType.inputJson) {
      Logger.temp(
        'RuntimeStreamingPreviewController',
        'inputJson delta received',
        reason: 'diagnose streaming performance',
        data: {
          'messageId': event.messageId,
          'contentBlockId': event.contentBlockId,
          'valueLength': event.value.length,
        },
      );
    }

    final now = DateTime.now();
    _recordToolUseTraceStage(event, now: now);
    _projector.consume(event, now: now);
    _pendingPublishedEventCount += 1;
    final lastPublishedAt = _lastPublishedAt;
    if (lastPublishedAt == null ||
        now.difference(lastPublishedAt) >= _minPublishInterval) {
      _publishState(now);
      return;
    }

    _flushTimer ??= Timer(
      _minPublishInterval - now.difference(lastPublishedAt),
      () => _publishState(DateTime.now()),
    );
  }

  void _recordToolUseTraceStage(
    StreamingMessageEvent event, {
    required DateTime now,
  }) {
    final traceId = _readRuntimeMetadataValue(
      event.runtimeMetadata,
      key: 'streamTraceId',
    );
    final turnId = _readRuntimeMetadataValue(
      event.runtimeMetadata,
      key: 'streamTurnId',
    );
    if (traceId == null ||
        traceId.isEmpty ||
        turnId == null ||
        turnId.isEmpty) {
      return;
    }

    final recorder = _ref.read(streamingTraceRecorderProvider.notifier);
    if (event is StreamingContentBlockStartEvent &&
        event.blockType == StreamingContentBlockType.toolUse) {
      final toolName = event.toolName?.trim();
      if (toolName == null || toolName.isEmpty) {
        return;
      }
      recorder.recordStage(
        traceId: traceId,
        turnId: turnId,
        stage: StreamingTraceStage.toolCallStreamStarted,
        timestamp: now,
        details: {
          'messageId': event.messageId,
          'contentBlockId': event.contentBlockId,
          'toolName': toolName,
        },
      );
      return;
    }

    if (event is! StreamingContentBlockStopEvent) {
      return;
    }

    final currentState = _projector.currentState();
    final message = currentState.messages
        .where((candidate) => candidate.messageId == event.messageId)
        .lastOrNull;
    final block = message?.blocks
        .where((candidate) => candidate.contentBlockId == event.contentBlockId)
        .lastOrNull;
    final toolName = block?.toolName?.trim();
    if (block == null ||
        block.blockType != StreamingContentBlockType.toolUse ||
        toolName == null ||
        toolName.isEmpty) {
      return;
    }
    recorder.recordStage(
      traceId: traceId,
      turnId: turnId,
      stage: StreamingTraceStage.toolCallStreamCompleted,
      timestamp: now,
      details: {
        'messageId': event.messageId,
        'contentBlockId': event.contentBlockId,
        'toolName': toolName,
      },
    );
  }

  String? _readRuntimeMetadataValue(
    Map<String, dynamic>? metadata, {
    required String key,
  }) {
    final value = metadata?[key];
    if (value is! String) {
      return null;
    }
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  void clear() {
    _flushTimer?.cancel();
    _flushTimer = null;
    _pendingPublishedEventCount = 0;
    _lastPublishedAt = null;
    _projector.clear();
    if (mounted && !state.isEmpty) {
      state = const RuntimeStreamingPreviewState();
    }
  }

  void _publishState(DateTime now) {
    _flushTimer?.cancel();
    _flushTimer = null;
    if (!mounted || _pendingPublishedEventCount == 0) {
      return;
    }
    _lastPublishedAt = now;
    final newState = _projector.currentState();
    final eventCount = _pendingPublishedEventCount;
    _pendingPublishedEventCount = 0;

    Logger.temp(
      'RuntimeStreamingPreviewController',
      'state flushed',
      reason: 'diagnose streaming performance',
      data: {
        'eventCount': eventCount,
        'messageCount': newState.messages.length,
        'totalBlocks': newState.messages.fold<int>(
          0,
          (sum, msg) => sum + msg.blocks.length,
        ),
      },
    );

    state = newState;

    final tracedMessage = newState.messages
        .where(
          (message) =>
              (message.streamTraceId ?? '').trim().isNotEmpty &&
              (message.streamTurnId ?? '').trim().isNotEmpty,
        )
        .lastOrNull;
    final traceId = tracedMessage?.streamTraceId?.trim();
    final turnId = tracedMessage?.streamTurnId?.trim();
    if (traceId != null &&
        traceId.isNotEmpty &&
        turnId != null &&
        turnId.isNotEmpty) {
      _ref.read(streamingTraceRecorderProvider.notifier).recordStage(
        traceId: traceId,
        turnId: turnId,
        stage: StreamingTraceStage.previewStateCommitted,
        timestamp: now,
        details: {
          'eventCount': eventCount,
          'messageCount': newState.messages.length,
          'totalBlocks': newState.messages.fold<int>(
            0,
            (sum, msg) => sum + msg.blocks.length,
          ),
        },
      );
    }
  }

  @override
  void dispose() {
    _flushTimer?.cancel();
    _flushTimer = null;
    _pendingPublishedEventCount = 0;
    super.dispose();
  }
}
