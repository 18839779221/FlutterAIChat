import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/chat/chat_attachment.dart';
import '../providers/chat_dependency_providers.dart';
import '../services/attachments/chat_attachment_gallery_save_service.dart';
import 'chat_attachment_image_content.dart';

Future<void> showChatAttachmentImagePreview(
  BuildContext context,
  ChatAttachment attachment,
  {
    String? heroTag,
  }
) {
  return Navigator.of(context).push<void>(
    PageRouteBuilder<void>(
      opaque: false,
      barrierColor: Colors.black.withValues(alpha: 0.9),
      pageBuilder: (context, animation, secondaryAnimation) {
        return _ChatAttachmentImagePreviewPage(
          attachment: attachment,
          heroTag: heroTag,
        );
      },
      transitionsBuilder: (context, animation, secondaryAnimation, child) {
        return FadeTransition(opacity: animation, child: child);
      },
    ),
  );
}

class _ChatAttachmentImagePreviewPage extends ConsumerWidget {
  const _ChatAttachmentImagePreviewPage({
    required this.attachment,
    required this.heroTag,
  });

  final ChatAttachment attachment;
  final String? heroTag;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ChatAttachmentGallerySaveService? saveService;
    try {
      saveService = ref.watch(chatAttachmentGallerySaveServiceProvider);
    } on UnimplementedError {
      saveService = null;
    }
    return Material(
      color: Colors.black,
      child: Stack(
        children: [
          Positioned.fill(
            child: InteractiveViewer(
              minScale: 0.8,
              maxScale: 4,
              child: Center(
                child: heroTag == null
                    ? _PreviewImage(
                        key: const ValueKey('chat-attachment-preview-image'),
                        attachment: attachment,
                      )
                    : Hero(
                        tag: heroTag!,
                        child: _PreviewImage(
                          key: const ValueKey('chat-attachment-preview-image'),
                          attachment: attachment,
                        ),
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
          Positioned(
            right: 20,
            bottom: 28,
            child: FilledButton.icon(
              key: const ValueKey('chat-attachment-preview-save'),
              onPressed: saveService == null
                  ? null
                  : () async {
                      final gallerySaveService = saveService!;
                      final messenger = ScaffoldMessenger.of(context);
                      final result =
                          await gallerySaveService.saveToGallery(attachment);
                      messenger
                        ..hideCurrentSnackBar()
                        ..showSnackBar(
                          SnackBar(
                            content: Text(result.message),
                            behavior: SnackBarBehavior.floating,
                          ),
                        );
                    },
              icon: const Icon(Icons.download_rounded),
              label: const Text('保存到相册'),
            ),
          ),
        ],
      ),
    );
  }
}

class _PreviewImage extends StatelessWidget {
  const _PreviewImage({
    super.key,
    required this.attachment,
  });

  final ChatAttachment attachment;

  @override
  Widget build(BuildContext context) {
    return ChatAttachmentImageContent(
      attachment: attachment,
      fit: BoxFit.contain,
      invalidPlaceholder: const _PreviewFallback(),
    );
  }
}

class _PreviewFallback extends StatelessWidget {
  const _PreviewFallback();

  @override
  Widget build(BuildContext context) {
    return const InvalidImagePlaceholder(
      key: ValueKey('chat-attachment-preview-fallback'),
      backgroundColor: Colors.transparent,
      iconColor: Colors.white70,
      labelColor: Colors.white70,
      iconSize: 56,
    );
  }
}
