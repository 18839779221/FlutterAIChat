import 'package:ai_chat/models/chat/chat_attachment.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('chat attachment serializes image metadata and provider refs', () {
    final attachment = ChatAttachment.image(
      localId: 'att-1',
      fileName: 'demo.png',
      mimeType: 'image/png',
      byteSize: 128,
      localPath: '/tmp/demo.png',
      status: ChatAttachmentStatus.selected,
      providerFileRefJson: const {'file_id': 'provider-file-1'},
    );

    final encoded = attachment.toJson();
    final decoded = ChatAttachment.fromJson(encoded);

    expect(decoded.kind, ChatAttachmentKind.image);
    expect(decoded.fileName, 'demo.png');
    expect(decoded.mimeType, 'image/png');
    expect(decoded.providerFileRefJson?['file_id'], 'provider-file-1');
  });
}
