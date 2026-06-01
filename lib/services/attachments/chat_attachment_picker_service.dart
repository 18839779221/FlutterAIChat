import '../../models/chat/chat_attachment.dart';

/// Abstraction over platform image picking so widgets stay testable.
abstract class ChatAttachmentPickerService {
  Future<List<ChatAttachment>> pickImages();
}
