import 'package:ai_chat/models/chat/tool_workflow_step.dart';
import 'package:ai_chat/models/chat_group.dart';
import 'package:ai_chat/models/chat_message.dart';
import 'package:ai_chat/providers/chat_dependency_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

// 消息列表提供者
final messagesProvider =
    StateNotifierProvider<MessagesNotifier, List<ChatMessage>>((ref) {
  return MessagesNotifier(ref);
});

class MessagesNotifier extends StateNotifier<List<ChatMessage>> {
  final Ref _ref;

  MessagesNotifier(this._ref) : super([]);

  void setMessages(List<ChatMessage> messages) {
    final sortedMessages = [...messages]..sort(compareChatMessagesForTimeline);
    state = sortedMessages;
  }

  void addMessage(ChatMessage message) {
    state = [...state, message];
  }

  void insertMessages(int index, List<ChatMessage> messages) {
    final newList = [...state];
    newList.insertAll(index, messages);
    state = newList;
  }

  void updateMessage(int id, String text) {
    final index = state.indexWhere((message) => message.id == id);
    if (index != -1) {
      final message = state[index];
      message.text = text;
      state = [...state];
    }
  }

  void appendToMessage(int id, String text) {
    final index = state.indexWhere((message) => message.id == id);
    if (index != -1) {
      final message = state[index];
      message.appendText(text);
      state = [...state];
    }
  }

  void appendReasoningToMessage(int id, String reasoning) {
    final index = state.indexWhere((message) => message.id == id);
    if (index != -1) {
      final message = state[index];
      message.appendReasoning(reasoning);
      state = [...state];
    }
  }

  void updateMessageStatus(int id, MessageStatus status) {
    final index = state.indexWhere((message) => message.id == id);
    if (index != -1) {
      final message = state[index].copyWith(status: status);
      final newList = [...state];
      newList[index] = message;
      state = newList;
    }
  }

  void replaceMessage(ChatMessage updatedMessage) {
    final index =
        state.indexWhere((message) => message.id == updatedMessage.id);
    if (index == -1) {
      return;
    }

    final newList = [...state];
    newList[index] = updatedMessage;
    state = newList;
  }

  void deleteMessageById(int id) {
    state = state.where((message) => message.id != id).toList();
  }

  void deleteMessagePair(int index) {
    final newList = [...state];
    final indexMessage = newList[index];
    ChatMessage? userMessage, aiMessage;

    if (indexMessage.isUser) {
      userMessage = newList[index];
      if (index < newList.length - 1) {
        aiMessage = newList[index + 1];
      }
    } else {
      aiMessage = newList[index];
      if (index > 0) {
        userMessage = newList[index - 1];
      }
    }

    if (userMessage != null && aiMessage != null) {
      newList.remove(aiMessage);
      newList.remove(userMessage);
      state = newList;

      final dbHelper = _ref.read(databaseProvider);
      if (userMessage.id != null) {
        dbHelper.deleteMessage(userMessage.id!);
      }
      if (aiMessage.id != null) {
        dbHelper.deleteMessage(aiMessage.id!);
      }
    }
  }

  void clearMessages() {
    state = [];
  }
}

// 聊天分组提供者
final groupsProvider =
    StateNotifierProvider<GroupsNotifier, List<ChatGroup>>((ref) {
  return GroupsNotifier();
});

class GroupsNotifier extends StateNotifier<List<ChatGroup>> {
  GroupsNotifier() : super([]);

  void setGroups(List<ChatGroup> groups) {
    state = groups;
  }

  void addGroup(ChatGroup group) {
    state = [...state, group];
  }
}

// 当前分组提供者
final currentGroupProvider = StateProvider<ChatGroup?>((ref) => null);

// 系统提示词提供者
final systemPromptProvider = StateProvider<String?>((ref) => null);

final toolWorkflowExpansionProvider =
    StateNotifierProvider<ToolWorkflowExpansionNotifier, Map<String, String>>(
        (ref) {
  return ToolWorkflowExpansionNotifier();
});

class ToolWorkflowExpansionNotifier extends StateNotifier<Map<String, String>> {
  ToolWorkflowExpansionNotifier() : super(const {});

  void toggleExpandedStep({
    required String turnId,
    required String stepId,
  }) {
    final currentStepId = state[turnId];
    if (currentStepId == stepId) {
      final nextState = Map<String, String>.from(state)..remove(turnId);
      state = nextState;
      return;
    }

    state = {
      ...state,
      turnId: stepId,
    };
  }

  void clearTurn(String turnId) {
    if (!state.containsKey(turnId)) {
      return;
    }
    final nextState = Map<String, String>.from(state)..remove(turnId);
    state = nextState;
  }
}

String? resolveWorkflowExpandedStepId({
  required String turnId,
  required List<ToolWorkflowStep> steps,
  required String? manualExpandedStepId,
}) {
  for (final step in steps) {
    if (step.status == ToolWorkflowStepStatus.failed) {
      return step.stepId;
    }
  }

  for (final step in steps) {
    if (step.status == ToolWorkflowStepStatus.awaitingConfirmation ||
        step.status == ToolWorkflowStepStatus.running) {
      return step.stepId;
    }
  }

  if (manualExpandedStepId == null) {
    return null;
  }

  final matched = steps.where((step) => step.stepId == manualExpandedStepId);
  if (matched.isEmpty) {
    return null;
  }

  return manualExpandedStepId;
}
