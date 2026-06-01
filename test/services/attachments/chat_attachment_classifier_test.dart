import 'package:ai_chat/services/attachments/chat_attachment_classifier.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('classifier accepts supported image mime types', () {
    expect(
      ChatAttachmentClassifier.isSupportedImageMimeType('image/png'),
      isTrue,
    );
    expect(
      ChatAttachmentClassifier.isSupportedImageMimeType('application/pdf'),
      isFalse,
    );
  });
}
