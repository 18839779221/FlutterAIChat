import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../models/chat/chat_attachment.dart';

Future<void> showChatAttachmentImagePreview(
  BuildContext context,
  ChatAttachment attachment,
) {
  return showDialog<void>(
    context: context,
    barrierColor: Colors.black.withValues(alpha: 0.9),
    builder: (context) {
      return Dialog.fullscreen(
        backgroundColor: Colors.black,
        child: Stack(
          children: [
            Positioned.fill(
              child: InteractiveViewer(
                minScale: 0.8,
                maxScale: 4,
                child: Center(
                  child: _PreviewImage(
                    key: const ValueKey('chat-attachment-preview-image'),
                    attachment: attachment,
                  ),
                ),
              ),
            ),
            Positioned(
              top: 16,
              right: 16,
              child: IconButton(
                key: const ValueKey('chat-attachment-preview-close'),
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.close_rounded),
                color: Colors.white,
                style: IconButton.styleFrom(
                  backgroundColor: Colors.black.withValues(alpha: 0.42),
                ),
              ),
            ),
          ],
        ),
      );
    },
  );
}

class _PreviewImage extends StatelessWidget {
  const _PreviewImage({
    super.key,
    required this.attachment,
  });

  final ChatAttachment attachment;

  @override
  Widget build(BuildContext context) {
    final localPath = attachment.localPath;
    if (!kIsWeb && localPath != null && localPath.trim().isNotEmpty) {
      return Image.file(
        File(localPath),
        fit: BoxFit.contain,
        errorBuilder: (_, __, ___) => const _PreviewFallback(),
      );
    }
    return const _PreviewFallback();
  }
}

class _PreviewFallback extends StatelessWidget {
  const _PreviewFallback();

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const ValueKey('chat-attachment-preview-fallback'),
      color: Colors.transparent,
      alignment: Alignment.center,
      child: const Icon(
        Icons.image_outlined,
        size: 56,
        color: Colors.white70,
      ),
    );
  }
}
