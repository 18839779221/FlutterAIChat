import 'dart:io';

import 'package:ai_chat/models/chat/chat_attachment.dart';
import 'package:ai_chat/providers/chat_dependency_providers.dart';
import 'package:ai_chat/services/attachments/chat_attachment_gallery_save_service.dart';
import 'package:ai_chat/services/attachments/chat_attachment_host_file_resolver.dart';
import 'package:ai_chat/services/file_tools/file_tool_root_service.dart';
import 'package:ai_chat/widgets/chat_message_image_attachments.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

void main() {
  const transparentPngDataUrl =
      'data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJ'
      'AAAADUlEQVR42mP8z8BQDwAFgwJ/lXc1PwAAAABJRU5ErkJggg==';

  testWidgets('user message renders compact right-aligned image attachments',
      (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: ChatMessageImageAttachments(
              attachments: [
                ChatAttachment.image(
                  localId: 'att-1',
                  fileName: 'demo.png',
                  mimeType: 'image/png',
                  status: ChatAttachmentStatus.ready,
                ),
              ],
            ),
          ),
        ),
      ),
    );

    expect(find.byKey(const ValueKey('chat-message-image-attachments')),
        findsOneWidget);
    expect(find.byKey(const ValueKey('invalid-image-placeholder')), findsOneWidget);
    expect(find.text('图片已失效'), findsOneWidget);
    expect(find.text('demo.png'), findsNothing);

    final align = tester.widget<Align>(
      find.byKey(const ValueKey('chat-message-image-attachments-align')),
    );
    expect(align.alignment, Alignment.centerRight);
  });

  testWidgets('generated image attachments can render inline data urls',
      (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: ChatMessageImageAttachments(
              alignment: Alignment.centerLeft,
              attachments: [
                ChatAttachment.generatedImage(
                  localId: 'generated-1',
                  fileName: 'generated.png',
                  mimeType: 'image/png',
                  dataUrl: transparentPngDataUrl,
                ),
              ],
            ),
          ),
        ),
      ),
    );

    final align = tester.widget<Align>(
      find.byKey(const ValueKey('chat-message-image-attachments-align')),
    );
    expect(align.alignment, Alignment.centerLeft);
    expect(find.byType(Image), findsOneWidget);
    expect(find.byIcon(Icons.image_outlined), findsNothing);
  });

  testWidgets('user message attachments support tap to preview',
      (tester) async {
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
            body: ChatMessageImageAttachments(
              attachments: [
                ChatAttachment.image(
                  localId: 'att-1',
                  fileName: 'demo.png',
                  mimeType: 'image/png',
                  status: ChatAttachmentStatus.ready,
                ),
              ],
            ),
          ),
        ),
      ),
    );

    await tester.tap(
        find.byKey(const ValueKey('chat-message-attachment-preview-att-1')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('chat-attachment-preview-fallback')),
        findsOneWidget);
    expect(find.text('图片已失效'), findsAtLeastNWidgets(1));
    expect(find.byKey(const ValueKey('chat-attachment-preview-close')),
        findsOneWidget);
    expect(find.byKey(const ValueKey('chat-attachment-preview-save')),
        findsOneWidget);

    final heroFinder = find.byType(Hero);
    expect(heroFinder, findsAtLeastNWidgets(2));

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
