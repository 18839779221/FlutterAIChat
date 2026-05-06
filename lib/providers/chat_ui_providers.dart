import 'dart:async';

import 'package:ai_chat/models/chat/chat_timeline_projection.dart';
import 'package:ai_chat/models/chat/runtime_assistant_draft.dart';
import 'package:ai_chat/models/chat/runtime_stream_entry.dart';
import 'package:ai_chat/models/chat_message.dart';
import 'package:ai_chat/models/session/context_window_snapshot.dart';
import 'package:ai_chat/models/debug/debug_test_case.dart';
import 'package:ai_chat/models/tool/tool_invocation.dart';
import 'package:ai_chat/providers/chat_collection_providers.dart';
import 'package:ai_chat/providers/chat_dependency_providers.dart';
import 'package:ai_chat/services/chat_service.dart';
import 'package:ai_chat/services/debug_test_case_loader.dart';
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
    systemPrompt: ref.watch(systemPromptProvider) ?? '',
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

/// Runtime-only generic stream entries used by projection/UI consumers.
final runtimeStreamEntriesProvider = StateNotifierProvider<
    RuntimeStreamEntriesController, List<RuntimeStreamEntry>>((ref) {
  return RuntimeStreamEntriesController();
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
  final runtimeStreamEntries = ref.watch(runtimeStreamEntriesProvider);
  return ref.watch(chatTimelineProjectionServiceProvider).build(
        messages: messages,
        groupId: groupId,
        runtimeDraft: runtimeDraft,
        runtimeStreamEntries: runtimeStreamEntries,
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

class RuntimeStreamEntriesController
    extends StateNotifier<List<RuntimeStreamEntry>> {
  RuntimeStreamEntriesController() : super(const <RuntimeStreamEntry>[]);

  static const Duration _minPublishInterval = Duration(milliseconds: 120);

  Timer? _flushTimer;
  DateTime? _lastPublishedAt;
  List<RuntimeStreamEntry>? _pendingEntries;

  void publish(List<RuntimeStreamEntry> entries) {
    if (!mounted) {
      return;
    }
    if (entries.isEmpty) {
      clear();
      return;
    }

    _pendingEntries = List<RuntimeStreamEntry>.from(entries);
    final now = DateTime.now();
    final lastPublishedAt = _lastPublishedAt;
    if (lastPublishedAt == null ||
        now.difference(lastPublishedAt) >= _minPublishInterval) {
      _flushPending(now);
      return;
    }

    _flushTimer ??= Timer(
      _minPublishInterval - now.difference(lastPublishedAt),
      () => _flushPending(DateTime.now()),
    );
  }

  void clear() {
    _flushTimer?.cancel();
    _flushTimer = null;
    _pendingEntries = null;
    if (mounted && state.isNotEmpty) {
      state = const <RuntimeStreamEntry>[];
    }
  }

  void _flushPending(DateTime now) {
    _flushTimer?.cancel();
    _flushTimer = null;
    final pendingEntries = _pendingEntries;
    _pendingEntries = null;
    if (!mounted || pendingEntries == null) {
      return;
    }
    _lastPublishedAt = now;
    state = pendingEntries;
  }

  @override
  void dispose() {
    _flushTimer?.cancel();
    super.dispose();
  }
}
