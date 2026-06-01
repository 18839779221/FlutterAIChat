import 'package:ai_chat/models/chat/chat_attachment.dart';
import 'package:ai_chat/widgets/chat_message_image_attachments.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('user message renders compact right-aligned image attachments', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
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
    );

    expect(find.byKey(const ValueKey('chat-message-image-attachments')), findsOneWidget);
    expect(find.byIcon(Icons.image_outlined), findsWidgets);
    expect(find.text('demo.png'), findsNothing);

    final align = tester.widget<Align>(
      find.byKey(const ValueKey('chat-message-image-attachments-align')),
    );
    expect(align.alignment, Alignment.centerRight);
  });

  testWidgets('user message attachments support tap to preview', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
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
    );

    await tester.tap(find.byKey(const ValueKey('chat-message-attachment-preview-att-1')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('chat-attachment-preview-fallback')), findsOneWidget);
    expect(find.byKey(const ValueKey('chat-attachment-preview-close')), findsOneWidget);
  });
}
