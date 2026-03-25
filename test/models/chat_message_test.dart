import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:ai_chat/models/chat_message.dart';
import 'package:ai_chat/models/response/message_content_type.dart';

void main() {
  group('ChatMessage contentType contract', () {
    test('defaults to MessageContentType.plainText when omitted', () {
      final message = _buildMessage();

      expect(message.contentType, MessageContentType.plainText);
    });

    test('contentType can be explicitly set via constructor', () {
      final message = _buildMessage(
        contentType: MessageContentType.structuredCard,
        role: MessageRole.assistant,
      );

      expect(message.contentType, MessageContentType.structuredCard);
    });
  });

  group('ChatMessage serialization', () {
    test('toMap exposes content type and json payloads', () {
      final payload = {'card': 'data'};
      final reference = {'source': 'tool'};
      final message = _buildMessage(
        contentType: MessageContentType.toolResult,
        payloadJson: payload,
        referenceJson: reference,
      );

      final serialized = message.toMap();

      expect(serialized['content_type'], 'toolResult');
      expect(serialized['payload_json'], jsonEncode(payload));
      expect(jsonDecode(serialized['payload_json'] as String), payload);
      expect(serialized['reference_json'], jsonEncode(reference));
      expect(jsonDecode(serialized['reference_json'] as String), reference);
    });

    test('fromMap restores typed fields and falls back on unknown content type', () {
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final payload = {'card': 'value'};
      final reference = {'source': 'tool'};
      final map = {
        'text': 'hi',
        'role': 'assistant',
        'timestamp': timestamp,
        'status': 'completed',
        'content_type': 'structuredCard',
        'payload_json': jsonEncode(payload),
        'reference_json': jsonEncode(reference),
      };

      final message = ChatMessage.fromMap(map);

      expect(message.contentType, MessageContentType.structuredCard);
      expect(message.payloadJson, payload);
      expect(message.referenceJson, reference);

      final unknown = ChatMessage.fromMap({...map, 'content_type': 'unexpected'});
      expect(unknown.contentType, MessageContentType.plainText);
    });

    test('fromMap tolerates empty payload and reference json without crashing', () {
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final map = {
        'text': 'hi again',
        'role': 'user',
        'timestamp': timestamp,
        'status': 'initial',
        'content_type': 'plainText',
        'payload_json': '',
        'reference_json': null,
      };

      final message = ChatMessage.fromMap(map);

      expect(message.payloadJson, isNull);
      expect(message.referenceJson, isNull);
    });

    test('copyWith preserves content type and json payloads', () {
      final payload = {'card': 'data'};
      final reference = {'source': 'tool'};
      final original = _buildMessage(
        contentType: MessageContentType.structuredCard,
        payloadJson: payload,
        referenceJson: reference,
      );

      final updated = original.copyWith(text: 'updated');

      expect(updated.contentType, original.contentType);
      expect(updated.payloadJson, payload);
      expect(updated.referenceJson, reference);
    });
  });
}

ChatMessage _buildMessage({
  MessageContentType? contentType,
  Map<String, dynamic>? payloadJson,
  Map<String, dynamic>? referenceJson,
  MessageRole role = MessageRole.user,
}) {
  final args = <Symbol, dynamic>{
    #text: 'Hello',
    #role: role,
    if (contentType != null) #contentType: contentType,
    if (payloadJson != null) #payloadJson: payloadJson,
    if (referenceJson != null) #referenceJson: referenceJson,
  };

  return Function.apply(ChatMessage.new, [], args);
}
