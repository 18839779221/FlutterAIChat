import 'package:flutter_riverpod/flutter_riverpod.dart';

enum ChatSendPhase {
  idle,
  preparing,
  awaitingConfirmation,
  executingTool,
  streamingResponse,
}

class ChatSendState {
  /// Current lifecycle phase of the active send transaction.
  final ChatSendPhase phase;

  /// Whether the assistant is actively generating a streamed response.
  final bool isGenerating;

  const ChatSendState({
    required this.phase,
    required this.isGenerating,
  });

  const ChatSendState.idle()
      : phase = ChatSendPhase.idle,
        isGenerating = false;

  ChatSendState copyWith({
    ChatSendPhase? phase,
    bool? isGenerating,
  }) {
    return ChatSendState(
      phase: phase ?? this.phase,
      isGenerating: isGenerating ?? this.isGenerating,
    );
  }
}

class ChatSendStateNotifier extends StateNotifier<ChatSendState> {
  ChatSendStateNotifier() : super(const ChatSendState.idle());

  void setPhase(ChatSendPhase phase) {
    state = state.copyWith(phase: phase);
  }

  void setGenerating(bool isGenerating) {
    state = state.copyWith(isGenerating: isGenerating);
  }

  void update({
    ChatSendPhase? phase,
    bool? isGenerating,
  }) {
    state = state.copyWith(
      phase: phase,
      isGenerating: isGenerating,
    );
  }
}

final chatSendStateProvider =
    StateNotifierProvider<ChatSendStateNotifier, ChatSendState>((ref) {
  return ChatSendStateNotifier();
});

final isGeneratingProvider = Provider<bool>((ref) {
  return ref.watch(chatSendStateProvider.select((state) => state.isGenerating));
});

final sendPhaseProvider = Provider<ChatSendPhase>((ref) {
  return ref.watch(chatSendStateProvider.select((state) => state.phase));
});
