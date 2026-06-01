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
      return localPath.trim();
    }
    return null;
  }
}
