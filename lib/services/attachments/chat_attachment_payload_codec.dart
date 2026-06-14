import 'dart:convert';
import 'dart:io';

import '../../models/chat/chat_attachment.dart';

/// Shared image attachment helpers for provider payload assembly.
class ChatAttachmentPayloadCodec {
  static List<ChatAttachment> imageAttachments(
    List<ChatAttachment> attachments,
  ) {
    return attachments
        .where((attachment) => attachment.kind == ChatAttachmentKind.image)
        .toList(growable: false);
  }

  static String? resolveImageReference(ChatAttachment attachment) {
    final providerRef = attachment.providerFileRefJson;
    final dataUrl = providerRef?['data_url'];
    if (dataUrl is String && dataUrl.trim().isNotEmpty) {
      return dataUrl.trim();
    }
    final remoteUrl = providerRef?['url'] ?? providerRef?['image_url'];
    if (remoteUrl is String && remoteUrl.trim().isNotEmpty) {
      return remoteUrl.trim();
    }
    final localPath = attachment.localPath;
    if (localPath != null && localPath.trim().isNotEmpty) {
      final trimmed = localPath.trim();
      if (trimmed.startsWith('http://') ||
          trimmed.startsWith('https://') ||
          trimmed.startsWith('file://')) {
        return trimmed;
      }
    }
    return null;
  }

  static String? resolveImageReferenceForRuntime(ChatAttachment attachment) {
    final providerRef = attachment.providerFileRefJson;
    final dataUrl = providerRef?['data_url'];
    if (dataUrl is String && dataUrl.trim().isNotEmpty) {
      return dataUrl.trim();
    }

    final localPath = attachment.localPath;
    if (localPath != null && localPath.trim().isNotEmpty) {
      final trimmed = localPath.trim();
      if (trimmed.startsWith('/workspaces/')) {
        return null;
      }
      if (trimmed.startsWith('file://')) {
        final file = File(Uri.parse(trimmed).toFilePath());
        if (file.existsSync()) {
          final bytes = file.readAsBytesSync();
          return 'data:${attachment.mimeType};base64,${base64Encode(bytes)}';
        }
      }
      if (!trimmed.startsWith('http://') && !trimmed.startsWith('https://')) {
        final file = File(trimmed);
        if (file.existsSync()) {
          final bytes = file.readAsBytesSync();
          return 'data:${attachment.mimeType};base64,${base64Encode(bytes)}';
        }
      }
    }

    return resolveImageReference(attachment);
  }
}
