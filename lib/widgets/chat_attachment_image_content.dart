import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../models/chat/chat_attachment.dart';
import '../utils/logger.dart';

class ChatAttachmentImageContent extends StatelessWidget {
  const ChatAttachmentImageContent({
    super.key,
    required this.attachment,
    required this.fit,
    this.width,
    this.height,
    this.invalidPlaceholder,
  });

  final ChatAttachment attachment;
  final BoxFit fit;
  final double? width;
  final double? height;
  final Widget? invalidPlaceholder;

  @override
  Widget build(BuildContext context) {
    final dataUrl = attachment.providerFileRefJson?['data_url'];
    if (dataUrl is String && dataUrl.trim().isNotEmpty) {
      final bytes = _tryDecodeDataUrl(dataUrl.trim());
      if (bytes != null) {
        return Image.memory(
          bytes,
          width: width,
          height: height,
          fit: fit,
          errorBuilder: (_, error, __) {
            _logInvalidImage('failed to render inline attachment image', error);
            return _buildInvalidPlaceholder(context);
          },
        );
      }
      _logInvalidImage('failed to decode inline attachment image');
    }

    final localPath = attachment.localPath;
    if (_isHostFilePath(localPath)) {
      final file = File(localPath!);
      if (!file.existsSync()) {
        _logInvalidImage('attachment image file missing path=$localPath');
        return _buildInvalidPlaceholder(context);
      }
      return Image.file(
        file,
        width: width,
        height: height,
        fit: fit,
        errorBuilder: (_, error, __) {
          _logInvalidImage(
            'failed to render attachment image path=$localPath',
            error,
          );
          return _buildInvalidPlaceholder(context);
        },
      );
    }

    return _buildInvalidPlaceholder(context);
  }

  Uint8List? _tryDecodeDataUrl(String dataUrl) {
    final match = RegExp(
      r'^data:(image\/[a-zA-Z0-9.+-]+);base64,(.+)$',
    ).firstMatch(dataUrl);
    if (match == null) {
      return null;
    }
    try {
      return base64Decode(match.group(2)!);
    } on FormatException catch (error) {
      _logInvalidImage('attachment image data_url base64 is invalid', error);
      return null;
    }
  }

  bool _isHostFilePath(String? localPath) {
    return !kIsWeb &&
        localPath != null &&
        localPath.trim().isNotEmpty &&
        !localPath.startsWith('/attachments/');
  }

  Widget _buildInvalidPlaceholder(BuildContext context) {
    return invalidPlaceholder ?? const InvalidImagePlaceholder();
  }

  void _logInvalidImage(String message, [Object? error]) {
    Logger.w(
      'ChatAttachmentImageContent',
      error == null ? message : '$message error=$error',
    );
  }
}

class InvalidImagePlaceholder extends StatelessWidget {
  const InvalidImagePlaceholder({
    super.key,
    this.width,
    this.height,
    this.backgroundColor,
    this.iconColor,
    this.labelColor,
    this.iconSize = 24,
    this.label = '图片已失效',
  });

  final double? width;
  final double? height;
  final Color? backgroundColor;
  final Color? iconColor;
  final Color? labelColor;
  final double iconSize;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      key: const ValueKey('invalid-image-placeholder'),
      width: width,
      height: height,
      color:
          backgroundColor ?? theme.colorScheme.surfaceContainerHighest,
      alignment: Alignment.center,
      padding: const EdgeInsets.all(12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.broken_image_outlined,
            size: iconSize,
            color: iconColor ?? theme.colorScheme.onSurfaceVariant,
          ),
          const SizedBox(height: 6),
          Text(
            label,
            textAlign: TextAlign.center,
            style: theme.textTheme.labelMedium?.copyWith(
              color: labelColor ?? theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}
