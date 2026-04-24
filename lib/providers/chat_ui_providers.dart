import 'dart:async';

import 'package:ai_chat/models/chat_message.dart';
import 'package:ai_chat/models/debug/debug_test_case.dart';
import 'package:ai_chat/models/response/message_content_type.dart';
import 'package:ai_chat/models/tool/tool_invocation.dart';
import 'package:ai_chat/providers/chat_collection_providers.dart';
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

final debugTestCaseLibraryProvider = FutureProvider<DebugTestCaseLibrary>((ref) {
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

// 流订阅提供者
final streamSubscriptionProvider =
    StateProvider<StreamSubscription?>((ref) => null);

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

/// Returns the latest unresolved ask-user-question prompt so the timeline can
/// render it as the active interactive card while older/resolved prompts stay
/// compact.
final activeAskUserQuestionMessageProvider = Provider<ChatMessage?>((ref) {
  final messages = ref.watch(messagesProvider);
  final resolvedTurnIds = <int>{};

  for (final message in messages) {
    if (message.contentType != MessageContentType.askUserQuestionResult) {
      continue;
    }
    final turnId = message.payloadJson?['agentTurnId'];
    if (turnId is int) {
      resolvedTurnIds.add(turnId);
    }
  }

  for (final message in messages.reversed) {
    if (message.contentType != MessageContentType.askUserQuestionPrompt) {
      continue;
    }
    final payload = message.payloadJson;
    final turnId = payload?['agentTurnId'];
    final status = payload?['status'];
    if (turnId is! int || resolvedTurnIds.contains(turnId)) {
      continue;
    }
    if (status is String && status.isNotEmpty && status != 'awaitingResponse') {
      continue;
    }
    return message;
  }

  return null;
});

/// Returns the latest unresolved tool confirmation so the page can render a
/// single bottom confirmation bar outside the timeline cards.
final activePendingToolConfirmationProvider =
    Provider<PendingToolConfirmation?>((ref) {
  final messages = ref.watch(messagesProvider);

  for (final message in messages.reversed) {
    final contentType = message.contentType;
    if (contentType != MessageContentType.actionConfirmation &&
        contentType != MessageContentType.toolInvocation) {
      continue;
    }

    final payload = message.payloadJson;
    if (payload == null) {
      continue;
    }

    final invocation = ToolInvocation.fromJson(payload);
    if (invocation.status != ToolInvocationStatus.awaitingConfirmation ||
        !invocation.requiresConfirmation) {
      continue;
    }

    return PendingToolConfirmation(
      message: message,
      invocation: invocation,
    );
  }

  return null;
});
