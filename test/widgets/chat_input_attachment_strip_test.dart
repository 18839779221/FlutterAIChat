import 'package:ai_chat/models/chat/chat_attachment.dart';
import 'package:ai_chat/widgets/chat_input_attachment_strip.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('attachment strip shows compact selected image previews', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
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
    );

    expect(find.byKey(const ValueKey('chat-input-attachment-strip')), findsOneWidget);
    expect(find.text('demo.png'), findsNothing);
    expect(find.byIcon(Icons.image_outlined), findsWidgets);
  });

  testWidgets('attachment strip supports tap to preview', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
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
    );

    await tester.tap(find.byKey(const ValueKey('chat-input-attachment-preview-att-1')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('chat-attachment-preview-fallback')), findsOneWidget);
    expect(find.byKey(const ValueKey('chat-attachment-preview-close')), findsOneWidget);
  });
}
