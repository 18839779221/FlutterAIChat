import 'package:ai_chat/providers/chat_collection_providers.dart';
import 'package:ai_chat/providers/chat_dependency_providers.dart';
import 'package:ai_chat/providers/chat_ui_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

abstract class ChatPreferencesController {
  Future<void> setSystemPrompt(String? prompt);

  void setUseReasoning(bool value);

  void setUseConciseMode(bool value);
}

class DefaultChatPreferencesController implements ChatPreferencesController {
  final Ref _ref;

  DefaultChatPreferencesController(this._ref);

  @override
  Future<void> setSystemPrompt(String? prompt) async {
    _ref.read(systemPromptProvider.notifier).state = prompt;

    final currentGroup = _ref.read(currentGroupProvider);
    if (currentGroup != null && currentGroup.id != null) {
      final dbHelper = _ref.read(databaseProvider);
      await dbHelper.updateGroupSystemPrompt(currentGroup.id!, prompt);
    }
  }

  @override
  void setUseReasoning(bool value) {
    _ref.read(useReasoningProvider.notifier).state = value;
  }

  @override
  void setUseConciseMode(bool value) {
    final currentPrompt = _ref.read(systemPromptProvider);
    final cachedPrompt = _ref.read(cachedSystemPromptProvider);

    if (value) {
      if (cachedPrompt == null) {
        _ref.read(cachedSystemPromptProvider.notifier).state = currentPrompt;
      }
      setSystemPrompt("极简模式，只回答问题本身，无需任何解释背景和扩展，尽量控制在30字之内(特殊情况下允许超出)");
    } else {
      setSystemPrompt(cachedPrompt);
      _ref.read(cachedSystemPromptProvider.notifier).state = null;
    }

    _ref.read(useConciseModeProvider.notifier).state = value;
  }
}
