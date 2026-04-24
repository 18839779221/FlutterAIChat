import 'package:ai_chat/providers/chat_collection_providers.dart';
import 'package:ai_chat/providers/chat_dependency_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

abstract class ChatPreferencesController {
  Future<void> setSystemPrompt(String? prompt);
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
}
