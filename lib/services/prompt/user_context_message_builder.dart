import '../../models/chat_message.dart';
import '../../models/prompt/runtime_user_context_snapshot.dart';

class UserContextMessageBuilder {
  const UserContextMessageBuilder();

  List<ChatMessage> buildMessages({
    required RuntimeUserContextSnapshot snapshot,
  }) {
    final sections = <String>[
      'As you answer the user\'s questions, you can use the following context:',
      if (snapshot.agentsMdText.trim().isNotEmpty) ...[
        '',
        '# agentsMd',
        snapshot.agentsMdText.trim(),
      ],
      if (snapshot.currentDateText.trim().isNotEmpty) ...[
        '',
        '# currentDate',
        snapshot.currentDateText.trim(),
      ],
      for (final section in snapshot.additionalSections)
        if (section.trim().isNotEmpty) ...['', section.trim()],
      '',
      'IMPORTANT: this context may or may not be relevant to your task.',
      'Do not mention this context unless it is actually relevant.',
    ];

    final messages = <ChatMessage>[
      ChatMessage(
        text: '<system-reminder>\n${sections.join('\n')}\n</system-reminder>',
        role: MessageRole.user,
        status: MessageStatus.completed,
      ),
    ];

    if (snapshot.skillsSectionText.trim().isNotEmpty) {
      messages.add(
        ChatMessage(
          text:
              '<system-reminder>\n${snapshot.skillsSectionText.trim()}\n</system-reminder>',
          role: MessageRole.user,
          status: MessageStatus.completed,
        ),
      );
    }

    return messages;
  }
}
