import 'dart:io';

import 'package:ai_chat/models/chat/chat_attachment.dart';
import 'package:ai_chat/services/attachments/chat_attachment_gallery_save_service.dart';
import 'package:ai_chat/services/attachments/chat_attachment_host_file_resolver.dart';
import 'package:ai_chat/services/default_tool_adapters.dart';
import 'package:ai_chat/services/file_tools/file_tool_root_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ChatAttachmentGallerySaveService', () {
    late Directory tempDirectory;
    late FileToolRootService rootService;
    late ChatAttachmentHostFileResolver resolver;

    setUp(() async {
      tempDirectory = await Directory.systemTemp.createTemp(
        'chat-attachment-gallery-save-',
      );
      rootService = FileToolRootService(
        rootDirectory: Directory('${tempDirectory.path}/agent'),
      );
      await rootService.ensureReady();
      resolver = ChatAttachmentHostFileResolver(rootService: rootService);
    });

    tearDown(() async {
      if (tempDirectory.existsSync()) {
        await tempDirectory.delete(recursive: true);
      }
    });

    test('saves workspace attachment to gallery through host intent', () async {
      final persistedFile = File(
        '${rootService.rootPath}/workspaces/.default/attachments/generated/demo.png',
      );
      await persistedFile.parent.create(recursive: true);
      await persistedFile.writeAsBytes([1, 2, 3, 4], flush: true);

      late HostIntentRequest capturedRequest;
      final service = ChatAttachmentGallerySaveService(
        hostFileResolver: resolver,
        platformOverride: TargetPlatform.android,
        launchIntent: (request) async {
          capturedRequest = request;
          return const HostIntentResult(
            status: HostIntentStatus.launched,
            message: 'saved',
          );
        },
      );

      final result = await service.saveToGallery(
        ChatAttachment.image(
          localId: 'att-1',
          fileName: 'demo.png',
          mimeType: 'image/png',
          localPath: '/workspaces/.default/attachments/generated/demo.png',
          status: ChatAttachmentStatus.ready,
        ),
      );

      expect(result.isSuccess, isTrue);
      expect(result.message, '已保存到系统相册');
      expect(capturedRequest.action, 'save_image_to_gallery');
      expect(capturedRequest.arguments['sourcePath'], persistedFile.path);
      expect(capturedRequest.arguments['fileName'], 'demo.png');
    });

    test('returns missing file failure when attachment file is absent', () async {
      final service = ChatAttachmentGallerySaveService(
        hostFileResolver: resolver,
        platformOverride: TargetPlatform.android,
        launchIntent: (request) async => throw UnimplementedError(),
      );

      final result = await service.saveToGallery(
        ChatAttachment.image(
          localId: 'att-1',
          fileName: 'demo.png',
          mimeType: 'image/png',
          localPath: '/workspaces/.default/attachments/generated/demo.png',
          status: ChatAttachmentStatus.ready,
        ),
      );

      expect(result.isSuccess, isFalse);
      expect(result.errorCode, 'missing_file');
    });
  });
}
