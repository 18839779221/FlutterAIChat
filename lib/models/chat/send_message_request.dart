import 'chat_attachment.dart';

/// Stable input object for one outbound user send action.
class SendMessageRequest {
  const SendMessageRequest({
    required this.text,
    this.attachments = const <ChatAttachment>[],
    this.allowUnsupportedImageInputAttempt = false,
  });

  final String text;
  final List<ChatAttachment> attachments;
  final bool allowUnsupportedImageInputAttempt;
}
