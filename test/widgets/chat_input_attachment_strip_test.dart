import 'dart:io';

import 'package:ai_chat/models/chat/chat_attachment.dart';
import 'package:ai_chat/providers/chat_dependency_providers.dart';
import 'package:ai_chat/services/attachments/chat_attachment_gallery_save_service.dart';
import 'package:ai_chat/services/attachments/chat_attachment_host_file_resolver.dart';
import 'package:ai_chat/services/file_tools/file_tool_root_service.dart';
import 'package:ai_chat/widgets/chat_input_attachment_strip.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

void main() {
  testWidgets('attachment strip shows compact selected image previews', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: ChatInputAttachmentStrip(
              attachments: [
                ChatAttachment.image(
                  localId: 'att-1',
                  fileName: 'demo.png',
                  mimeType: 'image/png',
                  byteSize: 128,
                  status: ChatAttachmentStatus.selected,
                ),
              ],
              onRemove: (_) {},
            ),
          ),
        ),
      ),
    );

    expect(find.byKey(const ValueKey('chat-input-attachment-strip')), findsOneWidget);
    expect(find.text('demo.png'), findsNothing);
    expect(find.byKey(const ValueKey('invalid-image-placeholder')), findsOneWidget);
    expect(find.text('图片已失效'), findsOneWidget);
  });

  testWidgets('attachment strip supports tap to preview', (tester) async {
    var saveInvoked = false;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          chatAttachmentGallerySaveServiceProvider.overrideWithValue(
            _FakeGallerySaveService(
              onSave: () {
                saveInvoked = true;
              },
            ),
          ),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: ChatInputAttachmentStrip(
              attachments: [
                ChatAttachment.image(
                  localId: 'att-1',
                  fileName: 'demo.png',
                  mimeType: 'image/png',
                  byteSize: 128,
                  status: ChatAttachmentStatus.selected,
                ),
              ],
              onRemove: (_) {},
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.byKey(const ValueKey('chat-input-attachment-preview-att-1')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('chat-attachment-preview-fallback')), findsOneWidget);
    expect(find.text('图片已失效'), findsAtLeastNWidgets(1));
    expect(find.byKey(const ValueKey('chat-attachment-preview-close')), findsOneWidget);
    expect(find.byKey(const ValueKey('chat-attachment-preview-save')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('chat-attachment-preview-save')));
    await tester.pumpAndSettle();

    expect(saveInvoked, isTrue);
    expect(find.text('已保存到系统相册'), findsOneWidget);
  });
}

class _FakeGallerySaveService extends ChatAttachmentGallerySaveService {
  _FakeGallerySaveService({
    required VoidCallback onSave,
  })  : _onSave = onSave,
        super(
          hostFileResolver: ChatAttachmentHostFileResolver(
            rootService: FileToolRootService(
              rootDirectory: Directory.systemTemp,
            ),
          ),
        );

  final VoidCallback _onSave;

  @override
  Future<AttachmentGallerySaveResult> saveToGallery(
    ChatAttachment attachment,
  ) async {
    _onSave();
    return const AttachmentGallerySaveResult(
      isSuccess: true,
      message: '已保存到系统相册',
    );
  }
}
