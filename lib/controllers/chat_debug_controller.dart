import 'dart:convert';

import 'package:ai_chat/models/chat_message.dart';
import 'package:ai_chat/models/response/message_content_type.dart';
import 'package:ai_chat/providers/chat_collection_providers.dart';
import 'package:ai_chat/providers/chat_dependency_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

abstract class ChatDebugController {
  Future<void> structureMessageForDebug(ChatMessage message);
}

class DefaultChatDebugController implements ChatDebugController {
  final Ref _ref;

  DefaultChatDebugController(this._ref);

  @override
  Future<void> structureMessageForDebug(ChatMessage message) async {
    final currentGroup = _ref.read(currentGroupProvider);
    if (currentGroup?.id == null) {
      return;
    }

    final isSupportedMessage = message.isAssistant &&
        message.status == MessageStatus.completed &&
        message.contentType == MessageContentType.plainText;
    if (!isSupportedMessage) {
      return;
    }

    final dbHelper = _ref.read(databaseProvider);
    final placeholderMessage = ChatMessage(
      text: '',
      role: MessageRole.assistant,
      status: MessageStatus.generating,
    );

    final placeholderId =
        await dbHelper.insertMessage(placeholderMessage, currentGroup!.id!);
    placeholderMessage.id = placeholderId;
    _ref.read(messagesProvider.notifier).addMessage(placeholderMessage);

    final result = await _ref
        .read(chatServiceProvider)
        .structureMessageForDebug(message.text);
    final completedMessage = result.isStructuredCard
        ? placeholderMessage.copyWith(
            text: result.card!.summary,
            status: MessageStatus.completed,
            contentType: MessageContentType.structuredCard,
            payloadJson: result.card!.toJson(),
          )
        : placeholderMessage.copyWith(
            text: result.fallbackText!,
            status: MessageStatus.completed,
            contentType: MessageContentType.plainText,
            payloadJson: null,
          );

    await dbHelper.updateStructuredMessage(
      placeholderId,
      text: completedMessage.text,
      status: completedMessage.status,
      contentType: completedMessage.contentType,
      payloadJson: completedMessage.payloadJson == null
          ? null
          : jsonEncode(completedMessage.payloadJson),
    );
    _ref.read(messagesProvider.notifier).replaceMessage(completedMessage);
  }
}
