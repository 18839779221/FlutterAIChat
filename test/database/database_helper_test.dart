import 'dart:io';

import 'package:ai_chat/database/database_helper.dart';
import 'package:ai_chat/models/chat_group.dart';
import 'package:ai_chat/models/chat_message.dart';
import 'package:ai_chat/models/response/message_content_type.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  test('DatabaseHelper schema includes typed message columns and v6 upgrade path', () {
    final source = File('lib/database/database_helper.dart').readAsStringSync();

    expect(source, contains('version: 6'));
    expect(
      source,
      contains(RegExp(r"content_type\s+TEXT\s+NOT\s+NULL\s+DEFAULT\s+'plainText'")),
    );
    expect(source, contains(RegExp(r'payload_json\s+TEXT')));
    expect(source, contains(RegExp(r'reference_json\s+TEXT')));
    expect(source, contains('if (oldVersion < 6)'));
    expect(
      source,
      contains(
        RegExp(
          r"ALTER\s+TABLE\s+messages\s+ADD\s+COLUMN\s+content_type\s+TEXT\s+NOT\s+NULL\s+DEFAULT\s+'plainText'",
        ),
      ),
    );
    expect(
      source,
      contains(
        RegExp(
          r'ALTER\s+TABLE\s+messages\s+ADD\s+COLUMN\s+payload_json\s+TEXT',
        ),
      ),
    );
    expect(
      source,
      contains(
        RegExp(
          r'ALTER\s+TABLE\s+messages\s+ADD\s+COLUMN\s+reference_json\s+TEXT',
        ),
      ),
    );
  });

  test('DatabaseHelper can persist structured message completion updates', () async {
    final helper = DatabaseHelper();
    final groupId = await helper.insertGroup(
      ChatGroup(title: 'structured output test group'),
    );

    final message = ChatMessage(
      text: 'placeholder',
      role: MessageRole.assistant,
      status: MessageStatus.generating,
    );
    final messageId = await helper.insertMessage(message, groupId);

    await helper.updateStructuredMessage(
      messageId,
      text: 'Structured fallback text',
      status: MessageStatus.completed,
      contentType: MessageContentType.structuredCard,
      payloadJson: '{"title":"Weekly Summary","summary":"A short summary","keyPoints":["A"],"actionItems":["B"],"risks":["C"]}',
    );

    final messages = await helper.getMessagesByGroup(groupId);
    final persisted = messages.singleWhere((item) => item.id == messageId);

    expect(persisted.text, 'Structured fallback text');
    expect(persisted.status, MessageStatus.completed);
    expect(persisted.contentType, MessageContentType.structuredCard);
    expect(persisted.payloadJson, {
      'title': 'Weekly Summary',
      'summary': 'A short summary',
      'keyPoints': ['A'],
      'actionItems': ['B'],
      'risks': ['C'],
    });

    await helper.deleteGroup(groupId);
  });
}
