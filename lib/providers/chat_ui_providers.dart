import 'dart:async';

import 'package:ai_chat/models/chat_message.dart';
import 'package:ai_chat/models/debug/debug_test_case.dart';
import 'package:ai_chat/models/response/message_content_type.dart';
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

// 是否允许视口继续跟随最新消息锚点
final autoScrollToBottomProvider = StateProvider<bool>((ref) => true);

// 推理模式提供者
final useReasoningProvider = StateProvider<bool>((ref) => false);

// 简洁模式提供者
final useConciseModeProvider = StateProvider<bool>((ref) => false);

// 暂存的系统提示词提供者
final cachedSystemPromptProvider = StateProvider<String?>((ref) => null);

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
