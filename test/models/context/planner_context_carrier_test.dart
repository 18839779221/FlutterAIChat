import 'package:ai_chat/models/chat_turn.dart';
import 'package:ai_chat/models/context/planner_context_carrier.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('SyntheticCarrier', () {
    test('system role 不带 toolCallId', () {
      const c = SyntheticCarrier.system('You are an agent.');
      expect(c.role, SyntheticRole.system);
      expect(c.content, 'You are an agent.');
      expect(c.toolCallId, isNull);
    });

    test('user role 不带 toolCallId', () {
      const c = SyntheticCarrier.user('hi');
      expect(c.role, SyntheticRole.user);
      expect(c.content, 'hi');
      expect(c.toolCallId, isNull);
    });

    test('toolResult 必须带 toolCallId', () {
      const c = SyntheticCarrier.toolResult(
        toolCallId: 'call_1',
        content: 'OK',
      );
      expect(c.role, SyntheticRole.toolResult);
      expect(c.toolCallId, 'call_1');
      expect(c.content, 'OK');
    });

    test('estimatedTokens 是 content 字符数 / 4 取整', () {
      const c = SyntheticCarrier.user('hello world');
      expect(c.estimatedTokens, 'hello world'.length ~/ 4);
    });
  });

  group('RawAssistantCarrier', () {
    test('保留 apiStyle + rawJson', () {
      const c = RawAssistantCarrier(
        apiStyle: ChatTurnProviderStyle.openaiChatCompletions,
        rawJson: {'role': 'assistant', 'content': 'hi'},
      );
      expect(c.apiStyle, ChatTurnProviderStyle.openaiChatCompletions);
      expect(c.rawJson['content'], 'hi');
    });

    test('estimatedTokens 大于 0（占位估算）', () {
      const c = RawAssistantCarrier(
        apiStyle: ChatTurnProviderStyle.openaiChatCompletions,
        rawJson: {'role': 'assistant', 'content': 'some content here'},
      );
      expect(c.estimatedTokens, greaterThan(0));
    });
  });
}
