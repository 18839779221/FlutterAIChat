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

  test('generated image attachment carries provider data url metadata', () {
    final attachment = ChatAttachment.generatedImage(
      localId: 'generated-1',
      fileName: 'generated.png',
      mimeType: 'image/png',
      dataUrl: 'data:image/png;base64,AAAA',
      providerFileRefJson: const {'model': 'gpt-image-2'},
    );

    expect(attachment.kind, ChatAttachmentKind.image);
    expect(attachment.source, ChatAttachmentSource.providerFile);
    expect(attachment.status, ChatAttachmentStatus.ready);
    expect(
      attachment.providerFileRefJson?['data_url'],
      'data:image/png;base64,AAAA',
    );
    expect(attachment.providerFileRefJson?['model'], 'gpt-image-2');
  });
}
