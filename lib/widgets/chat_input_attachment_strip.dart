import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../models/chat/chat_attachment.dart';
import '../utils/logger.dart';
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
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: _buildAttachmentPreview(context, attachment),
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
    final localPath = attachment.localPath;
    if (!kIsWeb && localPath != null && localPath.trim().isNotEmpty) {
      return Image.file(
        File(localPath),
        fit: BoxFit.cover,
        errorBuilder: (_, error, stackTrace) {
          Logger.e(
            'ChatInputAttachmentStrip',
            'failed to render attachment preview path=$localPath',
            error,
          );
          return _fallbackPreview(context);
        },
      );
    }
    return _fallbackPreview(context);
  }

  Widget _fallbackPreview(BuildContext context) {
    return Container(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      alignment: Alignment.center,
      child: const Icon(Icons.image_outlined, size: 20),
    );
  }
}
