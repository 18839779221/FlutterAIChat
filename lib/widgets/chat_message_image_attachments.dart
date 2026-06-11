import 'dart:io';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';

import '../models/chat/chat_attachment.dart';
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
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(14),
                  child: _buildAttachmentPreview(context, attachment),
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
    final dataUrl = attachment.providerFileRefJson?['data_url'];
    if (dataUrl is String && dataUrl.trim().isNotEmpty) {
      final match = RegExp(
        r'^data:(image\/[a-zA-Z0-9.+-]+);base64,(.+)$',
      ).firstMatch(dataUrl.trim());
      if (match != null) {
        final bytes = base64Decode(match.group(2)!);
        return Image.memory(
          bytes,
          width: 168,
          height: 168,
          fit: BoxFit.cover,
        );
      }
    }
    final localPath = attachment.localPath;
    if (!kIsWeb &&
        localPath != null &&
        localPath.trim().isNotEmpty &&
        !localPath.startsWith('/attachments/')) {
      return Image.file(
        File(localPath),
        width: 168,
        height: 168,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => _fallbackPreview(context),
      );
    }
    return _fallbackPreview(context);
  }

  Widget _fallbackPreview(BuildContext context) {
    return Container(
      width: 168,
      height: 168,
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      alignment: Alignment.center,
      child: const Icon(Icons.image_outlined, size: 28),
    );
  }
}
