import 'dart:io';

import 'package:ai_chat/models/chat/chat_attachment.dart';
import 'package:ai_chat/services/attachments/chat_attachment_storage_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  test('storage service persists selected image into managed directory',
      () async {
    final tempRoot = await Directory.systemTemp.createTemp(
      'chat_attachment_storage_test',
    );
    addTearDown(() async {
      if (await tempRoot.exists()) {
        await tempRoot.delete(recursive: true);
      }
    });

    final sourceFile = File(p.join(tempRoot.path, 'source.png'));
    await sourceFile.writeAsBytes(const <int>[1, 2, 3, 4]);

    final service = ChatAttachmentStorageService(
      resolveRootDirectory: () async => tempRoot,
    );
    final stored = await service.persistSelectedImage(
      attachment: ChatAttachment.image(
        localId: 'att-1',
        fileName: 'demo.png',
        mimeType: 'image/png',
        byteSize: 4,
        localPath: sourceFile.path,
        status: ChatAttachmentStatus.selected,
      ),
    );

    expect(stored.localPath, '/attachments/persisted/att-1_demo.png');
    expect(
      await File(
        p.join(tempRoot.path, 'attachments', 'persisted', 'att-1_demo.png'),
      ).exists(),
      isTrue,
    );
    expect(stored.status, ChatAttachmentStatus.ready);
    expect(
      stored.providerFileRefJson?['data_url'],
      startsWith('data:image/png;base64,'),
    );
  });

  test('storage service records send-ready payload metadata', () async {
    final tempRoot = await Directory.systemTemp.createTemp(
      'chat_attachment_storage_test_meta',
    );
    addTearDown(() async {
      if (await tempRoot.exists()) {
        await tempRoot.delete(recursive: true);
      }
    });

    final sourceFile = File(p.join(tempRoot.path, 'source.jpg'));
    await sourceFile.writeAsBytes(List<int>.generate(2048, (index) => index % 255));

    final service = ChatAttachmentStorageService(
      resolveRootDirectory: () async => tempRoot,
    );
    final stored = await service.persistSelectedImage(
      attachment: ChatAttachment.image(
        localId: 'att-2',
        fileName: 'camera.jpg',
        mimeType: 'image/jpeg',
        byteSize: 2048,
        localPath: sourceFile.path,
        status: ChatAttachmentStatus.selected,
      ),
    );

    expect(stored.providerFileRefJson?['data_url'], isA<String>());
    expect(stored.providerFileRefJson?['data_url_length'], greaterThan(0));
    expect(stored.providerFileRefJson?['send_mime_type'], isNotEmpty);
  });
}
