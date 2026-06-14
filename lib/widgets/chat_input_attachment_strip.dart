import 'package:flutter/material.dart';

import '../models/chat/chat_attachment.dart';
import 'chat_attachment_image_content.dart';
import 'chat_attachment_image_preview_dialog.dart';

class ChatInputAttachmentStrip extends StatelessWidget {
  const ChatInputAttachmentStrip({
    super.key,
    required this.attachments,
    required this.onRemove,
  });

  final List<ChatAttachment> attachments;
  final ValueChanged<ChatAttachment> onRemove;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      key: const ValueKey('chat-input-attachment-strip'),
      height: 92,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: attachments.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final attachment = attachments[index];
          return Container(
            width: 84,
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Theme.of(context).dividerColor),
            ),
            child: Stack(
              children: [
                Positioned.fill(
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      key: ValueKey(
                        'chat-input-attachment-preview-${attachment.localId}',
                      ),
                      borderRadius: BorderRadius.circular(8),
                      onTap: () => showChatAttachmentImagePreview(
                        context,
                        attachment,
                        heroTag: _heroTagFor(attachment),
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Hero(
                          tag: _heroTagFor(attachment),
                          child: _buildAttachmentPreview(context, attachment),
                        ),
                      ),
                    ),
                  ),
                ),
                Positioned(
                  top: 2,
                  right: 2,
                  child: IconButton(
                    visualDensity: VisualDensity.compact,
                    constraints: const BoxConstraints.tightFor(
                      width: 22,
                      height: 22,
                    ),
                    padding: EdgeInsets.zero,
                    splashRadius: 10,
                    style: IconButton.styleFrom(
                      backgroundColor: Colors.black.withValues(alpha: 0.42),
                      foregroundColor: Colors.white,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    onPressed: () => onRemove(attachment),
                    icon: const Icon(Icons.close_rounded, size: 11),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildAttachmentPreview(
    BuildContext context,
    ChatAttachment attachment,
  ) {
    return ChatAttachmentImageContent(
      attachment: attachment,
      fit: BoxFit.cover,
      invalidPlaceholder: _fallbackPreview(context),
    );
  }

  Widget _fallbackPreview(BuildContext context) {
    return const InvalidImagePlaceholder(
      iconSize: 20,
    );
  }

  String _heroTagFor(ChatAttachment attachment) {
    return 'chat-attachment-hero-${attachment.localId}';
  }
}
