import 'package:image_picker/image_picker.dart';

import '../../models/chat/chat_attachment.dart';
import '../../utils/logger.dart';
import 'chat_attachment_classifier.dart';
import 'chat_attachment_picker_service.dart';

/// `image_picker` backed implementation for selecting local image files.
class ImagePickerChatAttachmentPickerService
    implements ChatAttachmentPickerService {
  ImagePickerChatAttachmentPickerService({
    ImagePicker? picker,
  }) : _picker = picker ?? ImagePicker();

  final ImagePicker _picker;

  @override
  Future<List<ChatAttachment>> pickImages() async {
    final files = await _picker.pickMultiImage();
    Logger.runtime(
      'ImagePickerAttachmentPicker',
      'pickMultiImage completed',
      data: {
        'pickedFileCount': files.length,
      },
    );
    if (files.isEmpty) {
      return const <ChatAttachment>[];
    }

    final attachments = <ChatAttachment>[];
    for (final file in files) {
      final mimeType = _resolveMimeType(file);
      Logger.runtime(
        'ImagePickerAttachmentPicker',
        'processing picked file',
        data: {
          'name': file.name,
          'path': file.path,
          'mimeType': mimeType,
        },
      );
      if (!ChatAttachmentClassifier.isSupportedImageMimeType(mimeType)) {
        Logger.w(
          'ImagePickerAttachmentPicker',
          'skip unsupported picked image mime type: $mimeType',
        );
        continue;
      }
      final bytes = await file.length();
      attachments.add(
        ChatAttachment.image(
          localId: _buildLocalId(file),
          fileName: file.name,
          mimeType: mimeType,
          byteSize: bytes,
          localPath: file.path,
          status: ChatAttachmentStatus.selected,
        ),
      );
    }
    return attachments;
  }

  String _buildLocalId(XFile file) {
    return '${DateTime.now().microsecondsSinceEpoch}_${file.name}';
  }

  String _resolveMimeType(XFile file) {
    final lower = file.name.toLowerCase();
    if (lower.endsWith('.png')) {
      return 'image/png';
    }
    if (lower.endsWith('.webp')) {
      return 'image/webp';
    }
    if (lower.endsWith('.jpg') || lower.endsWith('.jpeg')) {
      return 'image/jpeg';
    }
    return 'application/octet-stream';
  }
}
