import 'package:ai_chat/models/chat_message.dart';
import 'package:ai_chat/models/prompt/runtime_user_context_snapshot.dart';
import 'package:ai_chat/services/prompt/user_context_message_builder.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('UserContextMessageBuilder', () {
    test('renders snapshot into synthetic user reminder message', () {
      const builder = UserContextMessageBuilder();
      final message = builder.buildMessage(
        snapshot: const RuntimeUserContextSnapshot(
          currentDateText: "Today's date is 2026-04-24.",
          agentsMdText: 'Project instructions here.',
          additionalSections: [
            '# runtimePlatform\nCurrent runtime platform: Android phone app.'
          ],
        ),
      );

      expect(message.role, MessageRole.user);
      expect(message.text, contains('<system-reminder>'));
      expect(message.text, contains('# currentDate'));
      expect(message.text, contains('# agentsMd'));
      expect(message.text, contains('# runtimePlatform'));
    });

    test('omits empty sections from reminder body', () {
      const builder = UserContextMessageBuilder();
      final message = builder.buildMessage(
        snapshot: const RuntimeUserContextSnapshot(
          currentDateText: "Today's date is 2026-04-24.",
          agentsMdText: '',
        ),
      );

      expect(message.text, isNot(contains('# agentsMd')));
      expect(message.text, contains('# currentDate'));
    });
  });
}
