import 'package:flutter/material.dart';

import '../models/chat/chat_attachment.dart';
import 'chat_attachment_image_content.dart';
import 'chat_attachment_image_preview_dialog.dart';

class ChatMessageImageAttachments extends StatelessWidget {
  const ChatMessageImageAttachments({
    super.key,
    required this.attachments,
    this.alignment = Alignment.centerRight,
  });

  final List<ChatAttachment> attachments;
  final Alignment alignment;

  @override
  Widget build(BuildContext context) {
    return Align(
      key: const ValueKey('chat-message-image-attachments-align'),
      alignment: alignment,
      child: Column(
        key: const ValueKey('chat-message-image-attachments'),
        crossAxisAlignment: CrossAxisAlignment.end,
        children: attachments.map((attachment) {
          return Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                key: ValueKey(
                  'chat-message-attachment-preview-${attachment.localId}',
                ),
                borderRadius: BorderRadius.circular(14),
                onTap: () => showChatAttachmentImagePreview(
                  context,
                  attachment,
                  heroTag: _heroTagFor(attachment),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(14),
                  child: Hero(
                    tag: _heroTagFor(attachment),
                    child: _buildAttachmentPreview(context, attachment),
                  ),
                ),
              ),
            ),
          );
        }).toList(growable: false),
      ),
    );
  }

  Widget _buildAttachmentPreview(
    BuildContext context,
    ChatAttachment attachment,
  ) {
    return ChatAttachmentImageContent(
      attachment: attachment,
      width: 168,
      height: 168,
      fit: BoxFit.cover,
      invalidPlaceholder: _fallbackPreview(context),
    );
  }

  Widget _fallbackPreview(BuildContext context) {
    return const InvalidImagePlaceholder(
      width: 168,
      height: 168,
      iconSize: 28,
    );
  }

  String _heroTagFor(ChatAttachment attachment) {
    return 'chat-attachment-hero-${attachment.localId}';
  }
}
