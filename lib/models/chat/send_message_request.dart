import 'chat_attachment.dart';

enum SendMessageDispatchMode {
  steer,
  queue,
}

/// Stable input object for one outbound user send action.
class SendMessageRequest {
  const SendMessageRequest({
    required this.text,
    this.attachments = const <ChatAttachment>[],
    this.allowUnsupportedImageInputAttempt = false,
    this.dispatchMode = SendMessageDispatchMode.steer,
    this.additionalStartMessages = const <SendMessageRequest>[],
  });

  final String text;
  final List<ChatAttachment> attachments;
  final bool allowUnsupportedImageInputAttempt;
  final SendMessageDispatchMode dispatchMode;
  final List<SendMessageRequest> additionalStartMessages;
}
